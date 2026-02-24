#!/usr/bin/env python3
"""
Kea DHCP Lease Dashboard
Combines: nmap scan + ARP table + Kea CSV + known reservations
"""
import csv, datetime, http.server, json, os, re, socketserver, subprocess, time
from threading import Thread, Lock

PORT = 9090
LEASES_FILE = "/var/lib/kea/kea-leases4.csv"
SUBNETS = ["10.40.10.0/24", "10.40.30.0/24", "10.40.40.0/24", "10.40.50.0/24"]
NMAP_BIN = "/run/current-system/sw/bin/nmap"
SCAN_INTERVAL = 120  # seconds between nmap scans

VLAN_MAP = {
    "10.40.10.": ("10", "LAN",        "#22d3ee"),
    "10.40.20.": ("20", "Guest",      "#f59e0b"),
    "10.40.30.": ("30", "Management", "#a78bfa"),
    "10.40.40.": ("40", "Servers",    "#34d399"),
    "10.40.50.": ("50", "IoT",        "#fb923c"),
}

# Known reservations from Kea config
RESERVATIONS = {
    "f4:e2:c6:20:08:d6": ("10.40.30.120", "unifi-ap"),
    "e8:ff:1e:d2:b0:2f": ("10.40.40.104", "andromeda"),
    "7c:83:34:b9:7c:04": ("10.40.40.101", "caelum"),
    "7c:83:34:b9:b8:51": ("10.40.40.117", "eridanus"),
}
# Reverse map: ip -> hostname for reserved IPs
RESERVED_IPS = {ip: (mac, name) for mac, (ip, name) in RESERVATIONS.items()}

def get_vlan(ip):
    for prefix, info in VLAN_MAP.items():
        if ip.startswith(prefix):
            return info
    return ("?", "Unknown", "#6b7280")

def read_csv_leases():
    """Read dynamic leases from Kea CSV."""
    leases = {}
    try:
        with open(LEASES_FILE, newline="") as f:
            for row in csv.DictReader(f):
                ip = row.get("address", "").strip()
                if ip and not ip.startswith("#"):
                    leases[ip] = {
                        "mac":      row.get("hwaddr", "").strip(),
                        "hostname": row.get("hostname", "").strip(),
                        "expire":   row.get("expire", "0").strip(),
                        "state":    row.get("state", "0").strip(),
                    }
    except FileNotFoundError:
        pass
    return leases

def read_arp():
    """Parse `ip neigh show` into {ip: {mac, state}}."""
    arp = {}
    try:
        out = subprocess.check_output(["ip", "neigh", "show"], text=True)
        for line in out.splitlines():
            parts = line.split()
            if len(parts) < 2:
                continue
            ip = parts[0]
            if ":" not in ip:  # skip IPv6
                mac = ""
                state = parts[-1].upper()
                if "lladdr" in parts:
                    idx = parts.index("lladdr")
                    mac = parts[idx + 1]
                arp[ip] = {"mac": mac, "state": state}
    except Exception:
        pass
    return arp

def run_nmap():
    """Run nmap ping scan, return {ip: mac}."""
    result = {}
    try:
        out = subprocess.check_output(
            [NMAP_BIN, "-sn"] + SUBNETS,
            text=True, stderr=subprocess.DEVNULL, timeout=60
        )
        current_ip = None
        for line in out.splitlines():
            m = re.search(r"Nmap scan report for (?:[\w.-]+ \()?(\d+\.\d+\.\d+\.\d+)", line)
            if m:
                current_ip = m.group(1)
                result[current_ip] = ""
            m = re.search(r"MAC Address: ([0-9A-Fa-f:]{17})", line)
            if m and current_ip:
                result[current_ip] = m.group(1).lower()
    except Exception:
        pass
    return result

# Shared state updated by background scanner
_scan_lock = Lock()
_scan_data = {"nmap": {}, "last_scan": None}

def background_scanner():
    while True:
        nmap = run_nmap()
        with _scan_lock:
            _scan_data["nmap"] = nmap
            _scan_data["last_scan"] = datetime.datetime.now().strftime("%H:%M:%S")
        time.sleep(SCAN_INTERVAL)

def build_device_list():
    """Merge all sources into a unified device list."""
    with _scan_lock:
        nmap = dict(_scan_data["nmap"])
        last_scan = _scan_data["last_scan"]

    arp  = read_arp()
    csv_leases = read_csv_leases()

    # Collect all known IPs
    all_ips = set(nmap.keys()) | set(arp.keys()) | set(csv_leases.keys()) | set(RESERVED_IPS.keys())
    # Remove gateway IPs
    all_ips = {ip for ip in all_ips if not ip.endswith(".1") and not ip.startswith("192.168.")}

    devices = []
    for ip in all_ips:
        vid, vname, vcolor = get_vlan(ip)

        # Determine MAC
        mac = (nmap.get(ip) or
               arp.get(ip, {}).get("mac") or
               csv_leases.get(ip, {}).get("mac") or
               (RESERVED_IPS.get(ip, ("", ""))[0]) or
               "—")

        # Determine hostname
        hostname = (csv_leases.get(ip, {}).get("hostname") or
                    RESERVED_IPS.get(ip, ("", ""))[1] or
                    "")

        # Online status: in nmap results or ARP REACHABLE
        arp_state = arp.get(ip, {}).get("state", "")
        online = ip in nmap or arp_state in ("REACHABLE", "DELAY", "PROBE")

        # Source tag
        sources = []
        if ip in RESERVED_IPS:   sources.append("reserved")
        if ip in csv_leases:      sources.append("lease")
        if ip in nmap:            sources.append("nmap")
        if ip in arp:             sources.append("arp")

        # Expiry from CSV
        expiry = "—"
        expiry_pct = 0
        if ip in csv_leases:
            try:
                ts = int(csv_leases[ip]["expire"])
                if ts == 0:
                    expiry = "permanent"
                    expiry_pct = 100
                else:
                    now = int(time.time())
                    remaining = ts - now
                    expiry = datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
                    expiry_pct = max(0, min(100, int((remaining / 86400) * 100)))
            except:
                pass
        elif ip in RESERVED_IPS:
            expiry = "static"
            expiry_pct = 100

        devices.append({
            "ip": ip, "mac": mac, "hostname": hostname or "—",
            "vlan_id": vid, "vlan_name": vname, "vlan_color": vcolor,
            "online": online, "sources": sources,
            "expiry": expiry, "expiry_pct": expiry_pct,
        })

    devices.sort(key=lambda x: tuple(int(p) for p in x["ip"].split(".") if p.isdigit()))
    return devices, last_scan

def render_html(devices, last_scan):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    online_count = sum(1 for d in devices if d["online"])

    vlan_counts = {}
    for d in devices:
        k = (d["vlan_id"], d["vlan_name"], d["vlan_color"])
        vlan_counts[k] = vlan_counts.get(k, 0) + 1

    stat_cards = ""
    for (vid, vname, vc), count in sorted(vlan_counts.items()):
        stat_cards += f'<div class="stat-card"><div class="stat-n" style="color:{vc}">{count}</div><div class="stat-l">VLAN {vid} · {vname}</div></div>'

    rows = ""
    for d in devices:
        online_dot = '<span class="dot online" title="online"></span>' if d["online"] else '<span class="dot offline" title="offline"></span>'
        source_badges = " ".join(f'<span class="src-badge src-{s}">{s}</span>' for s in d["sources"])
        bar_html = ""
        if d["expiry"] not in ("—", "static", "permanent"):
            bar_color = "#f59e0b" if d["expiry_pct"] < 20 else "#22d3ee"
            bar_html = f'<div class="bar-track"><div class="bar" style="width:{d["expiry_pct"]}%;background:{bar_color}"></div></div>'
        expiry_display = f'<span class="mono muted small">{d["expiry"]}</span>{bar_html}'

        rows += f"""
        <tr class="{'offline-row' if not d['online'] else ''}">
          <td>{online_dot} <span class="mono accent">{d["ip"]}</span></td>
          <td><span class="hostname">{d["hostname"]}</span></td>
          <td><span class="mono muted">{d["mac"]}</span></td>
          <td><span class="vlan-badge" style="--vc:{d['vlan_color']}">VLAN {d['vlan_id']} <span class="vn">{d['vlan_name']}</span></span></td>
          <td>{source_badges}</td>
          <td>{expiry_display}</td>
        </tr>"""

    scan_note = f"last nmap scan: <span style='color:var(--accent)'>{last_scan}</span>" if last_scan else "nmap scan pending..."

    return f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="30">
<title>Kea DHCP · orion</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Syne:wght@400;700;800&display=swap');
*,*::before,*::after{{box-sizing:border-box;margin:0;padding:0}}
:root{{--bg:#0a0f1a;--surface:#111827;--border:#1f2d45;--text:#e2e8f0;--muted:#64748b;--accent:#22d3ee}}
body{{font-family:'Syne',sans-serif;background:var(--bg);color:var(--text);min-height:100vh;padding:2rem}}
body::before{{content:'';position:fixed;inset:0;background-image:linear-gradient(rgba(34,211,238,.03) 1px,transparent 1px),linear-gradient(90deg,rgba(34,211,238,.03) 1px,transparent 1px);background-size:40px 40px;pointer-events:none;z-index:0}}
.wrap{{position:relative;z-index:1;max-width:1300px;margin:0 auto}}
header{{display:flex;align-items:flex-end;justify-content:space-between;margin-bottom:2rem;padding-bottom:1.5rem;border-bottom:1px solid var(--border)}}
.logo{{display:flex;align-items:center;gap:1rem}}
.logo-icon{{width:44px;height:44px;border:2px solid var(--accent);border-radius:10px;display:grid;place-items:center;font-size:1.4rem}}
h1{{font-size:1.6rem;font-weight:800;letter-spacing:-.02em}}
h1 span{{color:var(--accent)}}
.meta{{text-align:right}}
.total{{font-size:2rem;font-weight:800;color:var(--accent);line-height:1}}
.total-label,.updated{{font-size:.7rem;color:var(--muted);letter-spacing:.1em;text-transform:uppercase;font-family:'JetBrains Mono',monospace}}
.stats{{display:flex;gap:1rem;flex-wrap:wrap;margin-bottom:2rem}}
.stat-card{{background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:.75rem 1.25rem;min-width:130px}}
.stat-n{{font-size:1.8rem;font-weight:800;line-height:1}}
.stat-l{{font-size:.7rem;color:var(--muted);letter-spacing:.05em;margin-top:.25rem}}
.table-wrap{{background:var(--surface);border:1px solid var(--border);border-radius:12px;overflow:hidden}}
table{{width:100%;border-collapse:collapse}}
thead tr{{background:rgba(34,211,238,.05);border-bottom:1px solid var(--border)}}
th{{padding:.75rem 1rem;font-size:.65rem;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);text-align:left;font-weight:600}}
td{{padding:.7rem 1rem;border-bottom:1px solid var(--border);font-size:.875rem;vertical-align:middle}}
tr:last-child td{{border-bottom:none}}
tr:hover td{{background:rgba(255,255,255,.02)}}
.offline-row td{{opacity:.4}}
.dot{{display:inline-block;width:7px;height:7px;border-radius:50%;margin-right:.4rem;vertical-align:middle}}
.dot.online{{background:#22d3ee;box-shadow:0 0 6px #22d3ee}}
.dot.offline{{background:#374151}}
.mono{{font-family:'JetBrains Mono',monospace;font-size:.8rem}}
.accent{{color:var(--accent)}}
.muted{{color:var(--muted)}}
.small{{font-size:.72rem}}
.hostname{{font-weight:600}}
.vlan-badge{{display:inline-flex;align-items:center;gap:.4rem;font-family:'JetBrains Mono',monospace;font-size:.72rem;font-weight:600;padding:.25rem .6rem;border-radius:6px;background:color-mix(in srgb,var(--vc) 12%,transparent);color:var(--vc);border:1px solid color-mix(in srgb,var(--vc) 30%,transparent)}}
.vn{{font-family:'Syne',sans-serif;font-size:.7rem;opacity:.8}}
.src-badge{{font-family:'JetBrains Mono',monospace;font-size:.62rem;padding:.15rem .4rem;border-radius:4px;margin-right:.2rem}}
.src-reserved{{background:rgba(167,139,250,.15);color:#a78bfa;border:1px solid rgba(167,139,250,.3)}}
.src-lease{{background:rgba(34,211,238,.1);color:#22d3ee;border:1px solid rgba(34,211,238,.25)}}
.src-nmap{{background:rgba(52,211,153,.1);color:#34d399;border:1px solid rgba(52,211,153,.25)}}
.src-arp{{background:rgba(251,146,60,.1);color:#fb923c;border:1px solid rgba(251,146,60,.25)}}
.bar-track{{height:3px;background:var(--border);border-radius:2px;overflow:hidden;margin-top:.3rem}}
.bar{{height:100%;border-radius:2px}}
.footer{{text-align:center;margin-top:1.5rem;font-size:.7rem;color:var(--muted);letter-spacing:.05em}}
.footer a{{color:var(--accent);text-decoration:none}}
</style></head>
<body><div class="wrap">
  <header>
    <div class="logo">
      <div class="logo-icon">🛰</div>
      <div><h1>orion · <span>DHCP</span></h1><div style="font-size:.8rem;color:var(--muted)">Kea lease dashboard</div></div>
    </div>
    <div class="meta">
      <div class="total">{online_count}<span style="font-size:1rem;color:var(--muted)">/{len(devices)}</span></div>
      <div class="total-label">online / known</div>
      <div class="updated">updated {now}</div>
    </div>
  </header>
  <div class="stats">{stat_cards}</div>
  <div class="table-wrap"><table>
    <thead><tr><th>IP Address</th><th>Hostname</th><th>MAC Address</th><th>VLAN</th><th>Source</th><th>Lease Expiry</th></tr></thead>
    <tbody>{rows}</tbody>
  </table></div>
  <div class="footer">{scan_note} · auto-refresh every <span style="color:var(--accent)">30s</span> · <a href="/">refresh now</a></div>
</div></body></html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        devices, last_scan = build_device_list()
        html = render_html(devices, last_scan).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)
    def log_message(self, *a): pass

# Start background nmap scanner
Thread(target=background_scanner, daemon=True).start()

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()


#!/usr/bin/env python3
import csv, datetime, http.server, socketserver, time

LEASES_FILE = "/var/lib/kea/kea-leases4.csv"
PORT = 9090

VLAN_MAP = {
    "10.40.10.": ("10", "LAN",        "#22d3ee"),
    "10.40.20.": ("20", "Guest",      "#f59e0b"),
    "10.40.30.": ("30", "Management", "#a78bfa"),
    "10.40.40.": ("40", "Servers",    "#34d399"),
    "10.40.50.": ("50", "IoT",        "#fb923c"),
}

def get_vlan(ip):
    for prefix, info in VLAN_MAP.items():
        if ip.startswith(prefix):
            return info
    return ("?", "Unknown", "#6b7280")

def format_expiry(expire_ts):
    try:
        ts = int(expire_ts)
        if ts == 0:
            return "permanent", "ok", 100
        now = int(time.time())
        remaining = ts - now
        label = datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
        if remaining < 0:
            return label, "expired", 0
        pct = min(100, int((remaining / 86400) * 100))
        return label, ("warning" if pct < 20 else "ok"), pct
    except:
        return expire_ts, "ok", 50

def read_leases():
    leases = []
    try:
        with open(LEASES_FILE, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                ip = row.get("address", "")
                if not ip or ip.startswith("#"):
                    continue
                vid, vname, vcolor = get_vlan(ip)
                expiry_label, expiry_status, expiry_pct = format_expiry(row.get("expire", "0"))
                leases.append({
                    "ip": ip,
                    "hostname": row.get("hostname", "") or "—",
                    "mac": row.get("hwaddr", "") or "—",
                    "vlan_id": vid, "vlan_name": vname, "vlan_color": vcolor,
                    "expiry": expiry_label, "expiry_status": expiry_status, "expiry_pct": expiry_pct,
                })
    except FileNotFoundError:
        pass
    leases.sort(key=lambda x: tuple(int(p) for p in x["ip"].split(".") if p.isdigit()))
    return leases

def render_html(leases):
    now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    rows = ""
    for l in leases:
        expired_class = " class=\"expired-row\"" if l["expiry_status"] == "expired" else ""
        bar_color = "#ef4444" if l["expiry_status"] == "expired" else ("#f59e0b" if l["expiry_status"] == "warning" else "#22d3ee")
        rows += f"""
        <tr{expired_class}>
          <td><span class="mono accent">{l["ip"]}</span></td>
          <td><span class="hostname">{l["hostname"]}</span></td>
          <td><span class="mono muted">{l["mac"]}</span></td>
          <td><span class="vlan-badge" style="--vc:{l["vlan_color"]}">VLAN {l["vlan_id"]} <span class="vn">{l["vlan_name"]}</span></span></td>
          <td>
            <span class="mono muted small">{l["expiry"]}</span>
            <div class="bar-track"><div class="bar" style="width:{l["expiry_pct"]}%;background:{bar_color}"></div></div>
          </td>
        </tr>"""

    vlan_counts = {}
    for l in leases:
        k = (l["vlan_id"], l["vlan_name"], l["vlan_color"])
        vlan_counts[k] = vlan_counts.get(k, 0) + 1

    stat_cards = ""
    for (vid, vname, vc), count in sorted(vlan_counts.items()):
        stat_cards += f"<div class=\"stat-card\"><div class=\"stat-n\" style=\"color:{vc}\">{count}</div><div class=\"stat-l\">VLAN {vid} · {vname}</div></div>"

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
.wrap{{position:relative;z-index:1;max-width:1200px;margin:0 auto}}
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
td{{padding:.75rem 1rem;border-bottom:1px solid var(--border);font-size:.875rem;vertical-align:middle}}
tr:last-child td{{border-bottom:none}}
tr:hover td{{background:rgba(255,255,255,.02)}}
.expired-row td{{opacity:.4}}
.mono{{font-family:'JetBrains Mono',monospace;font-size:.8rem}}
.accent{{color:var(--accent)}}
.muted{{color:var(--muted)}}
.small{{font-size:.72rem}}
.hostname{{font-weight:600}}
.vlan-badge{{display:inline-flex;align-items:center;gap:.4rem;font-family:'JetBrains Mono',monospace;font-size:.72rem;font-weight:600;padding:.25rem .6rem;border-radius:6px;background:color-mix(in srgb,var(--vc) 12%,transparent);color:var(--vc);border:1px solid color-mix(in srgb,var(--vc) 30%,transparent)}}
.vn{{font-family:'Syne',sans-serif;font-size:.7rem;opacity:.8}}
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
      <div class="total">{len(leases)}</div>
      <div class="total-label">active leases</div>
      <div class="updated">updated {now}</div>
    </div>
  </header>
  <div class="stats">{stat_cards}</div>
  <div class="table-wrap"><table>
    <thead><tr><th>IP Address</th><th>Hostname</th><th>MAC Address</th><th>VLAN</th><th>Lease Expiry</th></tr></thead>
    <tbody>{rows}</tbody>
  </table></div>
  <div class="footer">auto-refresh every <span style="color:var(--accent)">30s</span> · <a href="/">refresh now</a></div>
</div></body></html>"""

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        html = render_html(read_leases()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html)))
        self.end_headers()
        self.wfile.write(html)
    def log_message(self, *a): pass

with socketserver.TCPServer(("", PORT), Handler) as httpd:
    httpd.serve_forever()


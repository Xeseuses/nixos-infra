#!/usr/bin/env python3
# hosts/eridanus/generate-security-dashboard.py
#
# Generates a static HTML security dashboard by:
#   - SSHing to each monitored host and running aureport
#   - Reading local auditd + aide logs on eridanus itself
#   - Rendering a unified HTML page at /var/lib/security-dashboard/index.html
#
# Runs every 15 minutes via systemd timer (security-dashboard.service).

import subprocess
import json
import re
import os
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict

OUTPUT_DIR  = Path("/var/lib/security-dashboard")
OUTPUT_FILE = OUTPUT_DIR / "index.html"
STATE_FILE  = OUTPUT_DIR / "state.json"

# ── Host definitions ──────────────────────────────────────────────────────────
HOSTS = [
    {"name": "eridanus",   "ip": "localhost",    "port": 22,    "local": True  },
    {"name": "orion",      "ip": "10.40.10.1",   "port": 22,    "local": False },
    {"name": "caelum",     "ip": "10.40.40.101", "port": 22,    "local": False },
    {"name": "andromeda",  "ip": "10.40.40.104", "port": 22,    "local": False },
    {"name": "horologium", "ip": "10.40.40.106", "port": 22,    "local": False },
    {"name": "lyra",       "ip": "77.42.83.12",  "port": 22022, "local": False },
]

SSH_KEY  = "/persist/etc/ssh/monitor_key"
SSH_OPTS = [
    "-o", "StrictHostKeyChecking=no",
    "-o", "ConnectTimeout=5",
    "-o", "BatchMode=yes",
    "-o", "LogLevel=ERROR",
]

# ── State ─────────────────────────────────────────────────────────────────────

def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {}

def save_state(state):
    try:
        STATE_FILE.write_text(json.dumps(state, indent=2))
    except Exception:
        pass

# ── Remote command execution ───────────────────────────────────────────────────

def run_remote(host, cmd, timeout=15):
    """Run a command on a remote host via SSH. Returns (stdout, error)."""
    if host["local"]:
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=timeout
            )
            return result.stdout, None
        except Exception as e:
            return "", str(e)
    else:
        ssh_cmd = [
            "ssh",
            "-i", SSH_KEY,
            *SSH_OPTS,
            "-p", str(host["port"]),
            f"root@{host['ip']}",
            " ".join(cmd) if isinstance(cmd, list) else cmd,
        ]
        try:
            result = subprocess.run(
                ssh_cmd, capture_output=True, text=True, timeout=timeout
            )
            if result.returncode != 0 and not result.stdout:
                return "", result.stderr.strip()
            return result.stdout, None
        except subprocess.TimeoutExpired:
            return "", "timeout"
        except Exception as e:
            return "", str(e)

# ── Data collection ────────────────────────────────────────────────────────────

def get_failed_logins(host):
    """Get failed login attempts in the last 24h."""
    out, err = run_remote(host, [
        "aureport", "--auth", "--failed",
        "--start", "yesterday", "--end", "now", "-i"
    ])
    if err:
        return [], err
    lines = []
    for line in out.splitlines():
        # Skip header lines
        if re.match(r'^\d+\.', line.strip()):
            parts = line.strip().split()
            if len(parts) >= 6:
                lines.append({
                    "time":    f"{parts[1]} {parts[2]}",
                    "user":    parts[3],
                    "host":    parts[4],
                    "exe":     parts[5],
                    "result":  parts[6] if len(parts) > 6 else "failed",
                })
    return lines, None

def get_sudo_usage(host):
    """Get sudo/privilege escalation events in the last 24h."""
    out, err = run_remote(host, [
        "ausearch", "--start", "yesterday",
        "-m", "USER_AUTH,USER_CMD,CRED_ACQ",
        "--key", "root-exec",
        "-i", "--format", "text"
    ])
    if err:
        return [], err
    events = []
    for line in out.splitlines():
        if "sudo" in line.lower() or "su" in line.lower():
            events.append(line.strip())
    return events[:20], None  # cap at 20

def get_audit_summary(host):
    """Get aureport summary stats."""
    out, err = run_remote(host, ["aureport", "--summary", "-i"])
    if err:
        return {}, err
    summary = {}
    for line in out.splitlines():
        if "Number of" in line:
            m = re.match(r'Number of (\w[\w ]+?):\s+(\d+)', line)
            if m:
                summary[m.group(1).strip()] = int(m.group(2))
    return summary, None

def get_config_changes(host):
    """Get system config changes in the last 24h."""
    out, err = run_remote(host, [
        "aureport", "--config",
        "--start", "yesterday", "--end", "now", "-i"
    ])
    if err:
        return [], err
    lines = []
    for line in out.splitlines():
        if re.match(r'^\d+\.', line.strip()):
            lines.append(line.strip())
    return lines[:10], None

def get_aide_status(host):
    """Get AIDE log summary."""
    out, err = run_remote(host, ["tail", "-n", "50", "/var/log/aide/aide.log"])
    if err or not out.strip():
        return {"status": "unknown", "last_check": "never", "changes": []}

    lines = out.strip().splitlines()
    last_check = "unknown"
    changes = []
    status = "ok"

    for line in lines:
        if "AIDE check passed" in line or "no unexpected changes" in line:
            last_check = line[:10] if len(line) > 10 else "recent"
            status = "ok"
        elif "AIDE found" in line:
            m = re.search(r'found (\d+) change', line)
            count = int(m.group(1)) if m else 1
            last_check = line[:10] if len(line) > 10 else "recent"
            status = "alert" if count > 0 else "ok"
        elif re.match(r'^[A-Z] /', line):
            changes.append(line.strip())

    return {
        "status":     status,
        "last_check": last_check,
        "changes":    changes[:10],
    }

def get_host_uptime(host):
    """Get host uptime."""
    out, err = run_remote(host, ["uptime", "-p"])
    return out.strip() if not err else "unknown"

def collect_host_data(host):
    """Collect all data for a single host."""
    name = host["name"]
    print(f"Collecting data from {name}...")

    failed_logins, fl_err = get_failed_logins(host)
    config_changes, cc_err = get_config_changes(host)
    audit_summary, as_err = get_audit_summary(host)
    aide = get_aide_status(host)
    uptime = get_host_uptime(host)

    reachable = fl_err != "timeout" and as_err != "timeout"

    return {
        "name":           name,
        "ip":             host["ip"],
        "reachable":      reachable,
        "uptime":         uptime,
        "failed_logins":  failed_logins,
        "config_changes": config_changes,
        "audit_summary":  audit_summary,
        "aide":           aide,
        "errors": {
            "logins":  fl_err,
            "config":  cc_err,
            "summary": as_err,
        },
    }

# ── HTML generation ────────────────────────────────────────────────────────────

def severity_color(count, warn=1, crit=5):
    if count == 0:
        return "var(--green)"
    elif count < crit:
        return "var(--yellow)"
    else:
        return "var(--red)"

def render_host_card(data):
    name      = data["name"]
    reachable = data["reachable"]
    uptime    = data["uptime"]
    logins    = data["failed_logins"]
    changes   = data["config_changes"]
    aide      = data["aide"]
    summary   = data["audit_summary"]

    if not reachable:
        return f'''
        <div class="host-card unreachable">
          <div class="host-header">
            <span class="host-name">⚠ {name}</span>
            <span class="host-status" style="color:var(--red)">unreachable</span>
          </div>
          <p style="color:var(--muted);font-size:.875rem;margin-top:.5rem">
            Could not connect to {data["ip"]}
          </p>
        </div>'''

    login_count  = len(logins)
    change_count = len(changes)
    aide_status  = aide.get("status", "unknown")
    aide_color   = "var(--green)" if aide_status == "ok" else (
                   "var(--red)" if aide_status == "alert" else "var(--muted)")

    login_rows = ""
    for l in logins[:5]:
        login_rows += f'''
        <tr>
          <td>{l.get("time","")}</td>
          <td><code>{l.get("user","")}</code></td>
          <td>{l.get("host","")}</td>
          <td style="color:var(--red)">{l.get("result","failed")}</td>
        </tr>'''

    aide_changes = ""
    for c in aide.get("changes", []):
        aide_changes += f'<div style="color:var(--yellow);font-size:.8rem;font-family:monospace">{c}</div>'

    return f'''
    <div class="host-card">
      <div class="host-header">
        <span class="host-name">🖥 {name}</span>
        <span class="host-status" style="color:var(--green)">● online</span>
      </div>
      <div style="color:var(--muted);font-size:.75rem;margin-bottom:1rem">{uptime}</div>

      <div class="metric-row">
        <div class="metric">
          <div class="metric-label">Failed logins (24h)</div>
          <div class="metric-value" style="color:{severity_color(login_count)}">{login_count}</div>
        </div>
        <div class="metric">
          <div class="metric-label">Config changes (24h)</div>
          <div class="metric-value" style="color:{severity_color(change_count)}">{change_count}</div>
        </div>
        <div class="metric">
          <div class="metric-label">AIDE integrity</div>
          <div class="metric-value" style="color:{aide_color};font-size:1rem">
            {"✓ clean" if aide_status == "ok" else ("⚠ changes" if aide_status == "alert" else "?")}
          </div>
        </div>
      </div>

      {f"""
      <div style="margin-top:1rem">
        <div class="section-label">Failed logins</div>
        <table style="width:100%">
          <tr><th>Time</th><th>User</th><th>From</th><th>Result</th></tr>
          {login_rows}
        </table>
      </div>""" if logins else ""}

      {f"""
      <div style="margin-top:1rem">
        <div class="section-label">AIDE changes detected</div>
        {aide_changes}
      </div>""" if aide.get("changes") else ""}
    </div>'''

def render_html(host_data):
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    total_failed_logins = sum(len(h["failed_logins"]) for h in host_data)
    total_aide_alerts   = sum(1 for h in host_data if h["aide"]["status"] == "alert")
    unreachable         = sum(1 for h in host_data if not h["reachable"])
    total_hosts         = len(host_data)

    host_cards = "\n".join(render_host_card(h) for h in host_data)

    overall_status = "NORMAL"
    status_color   = "var(--green)"
    if unreachable > 0 or total_aide_alerts > 0:
        overall_status = "WARNING"
        status_color   = "var(--yellow)"
    if total_failed_logins > 20 or total_aide_alerts > 2:
        overall_status = "ALERT"
        status_color   = "var(--red)"

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="900">
<title>constellation — security dashboard</title>
<style>
:root{{
  --bg:#0d1117;--bg2:#161b22;--bg3:#21262d;
  --border:#30363d;--text:#c9d1d9;--muted:#8b949e;
  --green:#3fb950;--red:#f85149;--yellow:#d29922;
  --blue:#58a6ff;--purple:#bc8cff;
}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;padding:2rem;max-width:1400px;margin:0 auto}}
h1{{color:var(--blue);font-size:1.5rem;margin-bottom:.25rem}}
.subtitle{{color:var(--muted);font-size:.875rem;margin-bottom:2rem}}
.summary-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:1rem;margin-bottom:2rem}}
.card{{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:1.25rem}}
.card .label{{color:var(--muted);font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;margin-bottom:.5rem}}
.card .value{{font-size:2rem;font-weight:700}}
.host-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(400px,1fr));gap:1.5rem}}
.host-card{{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:1.5rem}}
.host-card.unreachable{{border-color:var(--red);opacity:.7}}
.host-header{{display:flex;justify-content:space-between;align-items:center;margin-bottom:.25rem}}
.host-name{{font-weight:700;font-size:1rem}}
.host-status{{font-size:.8rem}}
.metric-row{{display:grid;grid-template-columns:repeat(3,1fr);gap:1rem;margin-top:.75rem}}
.metric{{background:var(--bg3);border-radius:6px;padding:.75rem;text-align:center}}
.metric-label{{color:var(--muted);font-size:.65rem;text-transform:uppercase;letter-spacing:.05em;margin-bottom:.4rem}}
.metric-value{{font-size:1.5rem;font-weight:700}}
.section-label{{color:var(--muted);font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;margin-bottom:.5rem}}
table{{width:100%;border-collapse:collapse;font-size:.8rem}}
th{{color:var(--muted);font-size:.65rem;text-transform:uppercase;padding:.4rem .5rem;text-align:left;border-bottom:1px solid var(--border)}}
td{{padding:.4rem .5rem;border-bottom:1px solid var(--border)}}
code{{color:var(--blue);background:var(--bg3);padding:.1em .3em;border-radius:3px;font-size:.85em}}
.status-banner{{background:var(--bg2);border:1px solid {status_color};border-radius:8px;padding:1rem;margin-bottom:2rem;display:flex;align-items:center;gap:1rem}}
.footer{{color:var(--muted);font-size:.75rem;margin-top:2rem;border-top:1px solid var(--border);padding-top:1rem}}
</style>
</head>
<body>
<h1>🔐 constellation — security dashboard</h1>
<p class="subtitle">Updated: {now} · Auto-refreshes every 15 min · {total_hosts} hosts monitored</p>

<div class="status-banner">
  <span style="font-size:1.5rem">{"✓" if overall_status == "NORMAL" else "⚠"}</span>
  <div>
    <div style="font-weight:700;color:{status_color}">{overall_status}</div>
    <div style="font-size:.875rem;color:var(--muted)">
      {total_failed_logins} failed logins · {total_aide_alerts} integrity alerts · {unreachable} unreachable hosts
    </div>
  </div>
</div>

<div class="summary-grid">
  <div class="card">
    <div class="label">Hosts online</div>
    <div class="value" style="color:{'var(--green)' if unreachable == 0 else 'var(--yellow)'}">{total_hosts - unreachable}/{total_hosts}</div>
  </div>
  <div class="card">
    <div class="label">Failed logins (24h)</div>
    <div class="value" style="color:{severity_color(total_failed_logins)}">{total_failed_logins}</div>
  </div>
  <div class="card">
    <div class="label">AIDE alerts</div>
    <div class="value" style="color:{severity_color(total_aide_alerts)}">{total_aide_alerts}</div>
  </div>
  <div class="card">
    <div class="label">Unreachable</div>
    <div class="value" style="color:{severity_color(unreachable)}">{unreachable}</div>
  </div>
</div>

<div class="host-grid">
  {host_cards}
</div>

<p class="footer">
  constellation · {now} · auditd + aide · eridanus security monitor
</p>
</body>
</html>"""

# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    host_data = []
    for host in HOSTS:
        data = collect_host_data(host)
        host_data.append(data)

    html = render_html(host_data)
    OUTPUT_FILE.write_text(html)

    reachable = sum(1 for h in host_data if h["reachable"])
    alerts    = sum(1 for h in host_data if h["aide"]["status"] == "alert")
    logins    = sum(len(h["failed_logins"]) for h in host_data)
    print(f"Dashboard written — {reachable}/{len(HOSTS)} hosts, {logins} failed logins, {alerts} AIDE alerts")


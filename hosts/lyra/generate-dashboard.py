#!/usr/bin/env python3
# /var/lib/honeypot-dashboard/generate.py
#
# Generates a static HTML dashboard from:
#   - endlessh-go journal logs (SSH tarpit)
#   - /var/log/honeypot/*.log (fake service hits)
#   - cscli decisions (CrowdSec bans)
#
# Run by a systemd timer every 5 minutes.
# Output: /var/lib/honeypot-dashboard/index.html
# Served by Caddy on threats.xesh.cc (WireGuard-only)

import subprocess
import json
import re
import os
from datetime import datetime, timezone
from collections import Counter
from pathlib import Path

OUTPUT_DIR = Path("/var/lib/honeypot-dashboard")
OUTPUT_FILE = OUTPUT_DIR / "index.html"
HONEYPOT_LOG_DIR = Path("/var/log/honeypot")

# ── Data collection ──────────────────────────────────────────────────────────

def get_endlessh_hits():
    """Parse endlessh-go from journald."""
    hits = []
    try:
        result = subprocess.run(
            ["journalctl", "-u", "endlessh-go", "--no-pager", "-o", "short-iso"],
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.splitlines():
            m = re.search(r'ACCEPT host=(\S+) port=(\d+)', line)
            if m:
                # Extract timestamp from journald line
                ts_m = re.match(r'(\S+)', line)
                hits.append({
                    "time": ts_m.group(1) if ts_m else "unknown",
                    "ip": m.group(1),
                    "port": m.group(2),
                    "service": "SSH tarpit"
                })
    except Exception:
        pass
    return hits

def get_honeypot_hits():
    """Parse fake service log files."""
    hits = []
    services = {"ftp": 21, "telnet": 23, "mysql": 3306}
    for svc, port in services.items():
        log = HONEYPOT_LOG_DIR / f"{svc}.log"
        if not log.exists():
            continue
        try:
            for line in log.read_text().splitlines():
                m = re.search(r'(\S+) honeypot_\w+ src_ip=(\S+)', line)
                if m:
                    hits.append({
                        "time": m.group(1),
                        "ip": m.group(2),
                        "port": port,
                        "service": f"Fake {svc.upper()}"
                    })
        except Exception:
            pass
    return hits

def get_crowdsec_decisions():
    """Get active CrowdSec bans."""
    decisions = []
    try:
        result = subprocess.run(
            ["cscli", "decisions", "list", "-o", "json"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
            if data:
                for d in data:
                    decisions.append({
                        "ip":      d.get("value", ""),
                        "reason":  d.get("reason", ""),
                        "country": d.get("country", ""),
                        "as":      d.get("as", ""),
                        "expires": d.get("expiration", ""),
                    })
    except Exception:
        pass
    return decisions

def get_crowdsec_metrics():
    """Get CrowdSec alert counts."""
    try:
        result = subprocess.run(
            ["cscli", "alerts", "list", "-o", "json", "--limit", "1000"],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0 and result.stdout.strip():
            data = json.loads(result.stdout)
            return len(data) if data else 0
    except Exception:
        pass
    return 0

# ── HTML generation ──────────────────────────────────────────────────────────

def render_html(endlessh, honeypot, decisions):
    all_hits = endlessh + honeypot
    all_hits.sort(key=lambda x: x["time"], reverse=True)

    # Stats
    total_tarpit    = len(endlessh)
    total_honeypot  = len(honeypot)
    total_banned    = len(decisions)

    # Top attackers across all sources
    all_ips = [h["ip"] for h in all_hits]
    top_ips = Counter(all_ips).most_common(10)

    # Service breakdown
    service_counts = Counter(h["service"] for h in all_hits)

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def rows(items, limit=50):
        html = ""
        for item in items[:limit]:
            html += f"""
            <tr>
              <td>{item.get('time','')[:19]}</td>
              <td><code>{item.get('ip','')}</code></td>
              <td>{item.get('service','')}</td>
            </tr>"""
        return html

    def decision_rows(items):
        html = ""
        for d in items:
            html += f"""
            <tr>
              <td><code>{d.get('ip','')}</code></td>
              <td>{d.get('country','')}</td>
              <td>{d.get('as','')[:40]}</td>
              <td>{d.get('reason','')}</td>
              <td>{d.get('expires','')}</td>
            </tr>"""
        return html

    def top_ip_rows(items):
        html = ""
        for ip, count in items:
            html += f"<tr><td><code>{ip}</code></td><td>{count}</td></tr>"
        return html

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>lyra — threat dashboard</title>
<style>
  :root {{
    --bg: #0d1117; --bg2: #161b22; --bg3: #21262d;
    --border: #30363d; --text: #c9d1d9; --muted: #8b949e;
    --green: #3fb950; --red: #f85149; --yellow: #d29922;
    --blue: #58a6ff; --purple: #bc8cff;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: var(--bg); color: var(--text); font-family: 'Segoe UI', system-ui, sans-serif; padding: 2rem; }}
  h1 {{ color: var(--blue); font-size: 1.5rem; margin-bottom: 0.25rem; }}
  .subtitle {{ color: var(--muted); font-size: 0.875rem; margin-bottom: 2rem; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
  .card {{ background: var(--bg2); border: 1px solid var(--border); border-radius: 8px; padding: 1.25rem; }}
  .card .label {{ color: var(--muted); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.5rem; }}
  .card .value {{ font-size: 2rem; font-weight: 700; }}
  .card.red .value {{ color: var(--red); }}
  .card.yellow .value {{ color: var(--yellow); }}
  .card.green .value {{ color: var(--green); }}
  .card.blue .value {{ color: var(--blue); }}
  section {{ margin-bottom: 2rem; }}
  section h2 {{ font-size: 1rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 0.75rem; border-bottom: 1px solid var(--border); padding-bottom: 0.5rem; }}
  table {{ width: 100%; border-collapse: collapse; background: var(--bg2); border-radius: 8px; overflow: hidden; }}
  th {{ background: var(--bg3); color: var(--muted); font-size: 0.75rem; text-transform: uppercase; padding: 0.75rem 1rem; text-align: left; }}
  td {{ padding: 0.6rem 1rem; border-top: 1px solid var(--border); font-size: 0.875rem; }}
  tr:hover td {{ background: var(--bg3); }}
  code {{ color: var(--blue); background: var(--bg3); padding: 0.1em 0.4em; border-radius: 3px; font-size: 0.85em; }}
  .footer {{ color: var(--muted); font-size: 0.75rem; margin-top: 2rem; }}
</style>
</head>
<body>

<h1>🛡 lyra — threat dashboard</h1>
<p class="subtitle">Updated: {now} · Auto-refreshes every 5 minutes</p>

<div class="grid">
  <div class="card red">
    <div class="label">SSH tarpit catches</div>
    <div class="value">{total_tarpit}</div>
  </div>
  <div class="card yellow">
    <div class="label">Honeypot hits</div>
    <div class="value">{total_honeypot}</div>
  </div>
  <div class="card green">
    <div class="label">Active bans</div>
    <div class="value">{total_banned}</div>
  </div>
  <div class="card blue">
    <div class="label">Unique attackers</div>
    <div class="value">{len(set(all_ips))}</div>
  </div>
</div>

<section>
  <h2>Active CrowdSec bans</h2>
  <table>
    <tr><th>IP</th><th>Country</th><th>AS</th><th>Reason</th><th>Expires</th></tr>
    {decision_rows(decisions) or '<tr><td colspan="5" style="color:var(--muted);text-align:center">No active bans</td></tr>'}
  </table>
</section>

<section>
  <h2>Top attackers (all time)</h2>
  <table>
    <tr><th>IP</th><th>Hits</th></tr>
    {top_ip_rows(top_ips) or '<tr><td colspan="2" style="color:var(--muted);text-align:center">No data</td></tr>'}
  </table>
</section>

<section>
  <h2>Recent hits (last 50)</h2>
  <table>
    <tr><th>Time</th><th>IP</th><th>Service</th></tr>
    {rows(all_hits) or '<tr><td colspan="3" style="color:var(--muted);text-align:center">No hits yet</td></tr>'}
  </table>
</section>

<p class="footer">lyra · {now} · endlessh-go + honeypot + crowdsec</p>
</body>
</html>"""

# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    endlessh  = get_endlessh_hits()
    honeypot  = get_honeypot_hits()
    decisions = get_crowdsec_decisions()

    html = render_html(endlessh, honeypot, decisions)
    OUTPUT_FILE.write_text(html)
    print(f"Dashboard written to {OUTPUT_FILE} — {len(endlessh)} tarpit, {len(honeypot)} honeypot, {len(decisions)} bans")


#!/usr/bin/env python3
# /var/lib/honeypot-dashboard/generate.py
#
# Generates a static HTML dashboard from:
#   - endlessh-go journal logs (SSH tarpit)
#   - /var/log/honeypot/*.log (fake service hits)
#   - cscli decisions (CrowdSec bans)
#
# Also auto-bans repeat honeypot offenders:
#   - Any IP hitting fake services 3+ times in 24h → 7 day ban
#   - endlessh hits excluded (too noisy)
#
# Run by a systemd timer every 5 minutes.
# Output: /var/lib/honeypot-dashboard/index.html

import subprocess
import json
import re
import os
from datetime import datetime, timezone, timedelta
from collections import Counter
from pathlib import Path

OUTPUT_DIR = Path("/var/lib/honeypot-dashboard")
OUTPUT_FILE = OUTPUT_DIR / "index.html"
HONEYPOT_LOG_DIR = Path("/var/log/honeypot")

# ── Auto-ban config ──────────────────────────────────────────────────────────
BAN_THRESHOLD = 3        # hits within window to trigger ban
BAN_WINDOW_HOURS = 24    # look-back window in hours
BAN_DURATION = "168h"    # 7 days
BAN_REASON = "honeypot-repeat-offender"

# ── Data collection ──────────────────────────────────────────────────────────

def get_endlessh_hits():
    hits = []
    try:
        result = subprocess.run(
            ["journalctl", "-u", "endlessh-go", "--no-pager", "-o", "short-iso"],
            capture_output=True, text=True, timeout=10
        )
        for line in result.stdout.splitlines():
            m = re.search(r'ACCEPT host=(\S+) port=(\d+)', line)
            if m:
                ts_m = re.match(r'(\S+)', line)
                hits.append({
                    "time": ts_m.group(1) if ts_m else "unknown",
                    "ip": m.group(1),
                    "service": "SSH tarpit"
                })
    except Exception:
        pass
    return hits

def get_honeypot_hits():
    hits = []
    services = {"ftp": 21, "telnet": 23, "mysql": 3306}
    for svc in services:
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
                        "service": f"Fake {svc.upper()}"
                    })
        except Exception:
            pass
    return hits

def get_crowdsec_decisions():
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
                        "origin":  d.get("origin", ""),
                    })
    except Exception:
        pass
    return decisions

def get_already_banned_ips(decisions):
    return {d["ip"] for d in decisions}

# ── Auto-ban logic ────────────────────────────────────────────────────────────

def auto_ban_repeat_offenders(honeypot_hits, already_banned):
    """Ban IPs that hit fake services BAN_THRESHOLD+ times in BAN_WINDOW_HOURS."""
    now = datetime.now()
    window_start = now - timedelta(hours=BAN_WINDOW_HOURS)
    recent_hits = []

    for hit in honeypot_hits:
        try:
            # Parse ISO timestamp
            ts_str = hit["time"][:19].replace("T", " ")
            ts = datetime.fromisoformat(ts_str)
            if ts > window_start:
                recent_hits.append(hit["ip"])
        except Exception:
            pass

    ip_counts = Counter(recent_hits)
    new_bans = []

    for ip, count in ip_counts.items():
        if count >= BAN_THRESHOLD and ip not in already_banned:
            try:
                result = subprocess.run(
                    ["cscli", "decisions", "add",
                     "--ip", ip,
                     "--duration", BAN_DURATION,
                     "--reason", BAN_REASON],
                    capture_output=True, text=True, timeout=10
                )
                if result.returncode == 0:
                    new_bans.append((ip, count))
                    print(f"Auto-banned {ip} ({count} honeypot hits in {BAN_WINDOW_HOURS}h)")
            except Exception as e:
                print(f"Failed to ban {ip}: {e}")

    return new_bans

# ── HTML generation ───────────────────────────────────────────────────────────

def render_html(endlessh, honeypot, decisions, new_bans):
    all_hits = endlessh + honeypot
    all_hits.sort(key=lambda x: x["time"], reverse=True)

    total_tarpit   = len(endlessh)
    total_honeypot = len(honeypot)
    total_banned   = len(decisions)
    total_auto_banned = len([d for d in decisions if d.get("reason") == "honeypot-repeat-offender"])
    all_ips        = [h["ip"] for h in all_hits]
    top_ips        = Counter(all_ips).most_common(10)
    now            = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def rows(items, limit=50):
        html = ""
        for item in items[:limit]:
            svc = item.get("service", "")
            color = "var(--red)" if "tarpit" in svc.lower() else "var(--yellow)"
            html += f"""
            <tr>
              <td>{item.get('time','')[:19]}</td>
              <td><code>{item.get('ip','')}</code></td>
              <td style="color:{color}">{svc}</td>
            </tr>"""
        return html

    def decision_rows(items):
        html = ""
        for d in items:
            is_autoban = d.get("reason") == "honeypot-repeat-offender"
            is_manual  = d.get("origin") == "cscli" and not is_autoban
            origin_color = "var(--red)" if is_autoban else ("var(--purple)" if is_manual else "var(--yellow)")
            origin_label = "⚡ auto-ban" if is_autoban else ("manual" if is_manual else "crowdsec")
            row_style = ' style="background:rgba(248,81,73,0.06)"' if is_autoban else ""
            html += f"""
            <tr{row_style}>
              <td><code>{d.get('ip','')}</code></td>
              <td>{d.get('country','')}</td>
              <td>{d.get('as','')[:35]}</td>
              <td>{d.get('reason','')}</td>
              <td style="color:{origin_color};font-weight:{'700' if is_autoban else '400'}">{origin_label}</td>
              <td>{d.get('expires','')}</td>
            </tr>"""
        return html

    def top_ip_rows(items):
        html = ""
        for ip, count in items:
            bar_width = min(100, int(count / max(c for _, c in items) * 100))
            html += f"""<tr>
              <td><code>{ip}</code></td>
              <td>
                <div style="display:flex;align-items:center;gap:8px">
                  <div style="background:var(--red);height:8px;width:{bar_width}%;border-radius:4px;min-width:4px"></div>
                  <span>{count}</span>
                </div>
              </td>
            </tr>"""
        return html

    new_ban_notice = ""
    if new_bans:
        ban_list = " &nbsp;·&nbsp; ".join(f"<code>{ip}</code> <span style=\'color:var(--muted)\'>{c} hits</span>" for ip, c in new_bans)
        new_ban_notice = f"""
        <div style="background:rgba(248,81,73,0.12);border:2px solid var(--red);border-radius:8px;padding:1.25rem;margin-bottom:1.5rem;display:flex;align-items:center;gap:1rem">
          <span style="font-size:1.5rem">⚡</span>
          <div>
            <div style="color:var(--red);font-weight:700;font-size:0.9rem;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:0.25rem">Auto-banned this run</div>
            <div style="font-size:0.875rem">{ban_list}</div>
          </div>
        </div>"""

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
<p class="subtitle">Updated: {now} · Auto-refreshes every 5 minutes · Auto-bans at {BAN_THRESHOLD}+ honeypot hits/{BAN_WINDOW_HOURS}h</p>

{new_ban_notice}

<div class="grid">
  <div class="card red"><div class="label">SSH tarpit catches</div><div class="value">{total_tarpit}</div></div>
  <div class="card yellow"><div class="label">Honeypot hits</div><div class="value">{total_honeypot}</div></div>
  <div class="card green"><div class="label">Active bans</div><div class="value">{total_banned}</div></div>
  <div class="card blue"><div class="label">Unique attackers</div><div class="value">{len(set(all_ips))}</div></div>
  <div class="card" style="border-color:var(--red);background:rgba(248,81,73,0.08)"><div class="label" style="color:var(--red)">⚡ Auto-banned today</div><div class="value" style="color:var(--red)">{total_auto_banned}</div></div>
</div>

<section>
  <h2>Active CrowdSec bans</h2>
  <table>
    <tr><th>IP</th><th>Country</th><th>AS</th><th>Reason</th><th>Origin</th><th>Expires</th></tr>
    {decision_rows(decisions) or '<tr><td colspan="6" style="color:var(--muted);text-align:center">No active bans</td></tr>'}
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

<p class="footer">lyra · {now} · endlessh-go + honeypot + crowdsec · auto-ban threshold: {BAN_THRESHOLD} hits/{BAN_WINDOW_HOURS}h → {BAN_DURATION} ban</p>
</body>
</html>"""

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    endlessh  = get_endlessh_hits()
    honeypot  = get_honeypot_hits()
    decisions = get_crowdsec_decisions()

    # Auto-ban repeat offenders from fake services only
    already_banned = get_already_banned_ips(decisions)
    new_bans = auto_ban_repeat_offenders(honeypot, already_banned)

    # Refresh decisions after banning
    if new_bans:
        decisions = get_crowdsec_decisions()

    html = render_html(endlessh, honeypot, decisions, new_bans)
    OUTPUT_FILE.write_text(html)
    print(f"Dashboard written — {len(endlessh)} tarpit, {len(honeypot)} honeypot, {len(decisions)} bans, {len(new_bans)} new auto-bans")


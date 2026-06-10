#!/usr/bin/env python3
# hosts/lyra/generate-dashboard.py
#
# Generates static HTML dashboard + auto-bans repeat honeypot offenders.
# Run every 5 minutes via systemd timer (honeypot-dashboard.service).
# Output: /var/lib/honeypot-dashboard/index.html

import subprocess
import json
import re
import glob
from datetime import datetime, timedelta
from collections import Counter
from pathlib import Path

OUTPUT_DIR     = Path("/var/lib/honeypot-dashboard")
OUTPUT_FILE    = OUTPUT_DIR / "index.html"
STATE_FILE     = OUTPUT_DIR / "state.json"
HONEYPOT_LOGS  = Path("/var/log/honeypot")

# ── Tunable config ────────────────────────────────────────────────────────────
BAN_THRESHOLD    = 3
BAN_WINDOW_HOURS = 24
BAN_DURATION     = "168h"
BAN_REASON       = "honeypot-repeat-offender"

# ── CrowdSec helpers ──────────────────────────────────────────────────────────

def get_cscli_config():
    """Find CrowdSec config in Nix store — path changes on every rebuild."""
    matches = glob.glob("/nix/store/*-crowdsec.yaml")
    if matches:
        return matches[0]
    return None

def run_cscli(*args):
    """Run cscli with the correct NixOS config path."""
    config = get_cscli_config()
    if not config:
        raise FileNotFoundError("Could not find crowdsec.yaml in /nix/store")
    return subprocess.run(
        ["cscli", "-c", config] + list(args),
        capture_output=True, text=True, timeout=15
    )

# ── State persistence ─────────────────────────────────────────────────────────

def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except Exception:
        return {"last_ban_time": None, "total_ever_banned": 0}

def save_state(state):
    try:
        STATE_FILE.write_text(json.dumps(state, indent=2))
    except Exception:
        pass

# ── Data collection ───────────────────────────────────────────────────────────

def get_endlessh_hits():
    """Read endlessh-go ACCEPT events from journald (last 7 days only)."""
    hits = []
    try:
        result = subprocess.run(
            ["journalctl", "-u", "endlessh-go", "--no-pager",
             "-o", "short-iso", "--since", "7 days ago"],
            capture_output=True, text=True, timeout=30
        )
        for line in result.stdout.splitlines():
            m = re.search(r'ACCEPT host=(\S+)', line)
            if m:
                ts_m = re.match(r'(\S+)', line)
                hits.append({
                    "time":    ts_m.group(1) if ts_m else "",
                    "ip":      m.group(1),
                    "service": "SSH tarpit",
                })
    except Exception as e:
        print(f"Warning: could not read endlessh journal: {e}")
    return hits

def get_honeypot_hits():
    """Read fake service log files."""
    hits = []
    for svc in ("ftp", "telnet", "mysql"):
        log = HONEYPOT_LOGS / f"{svc}.log"
        if not log.exists():
            continue
        try:
            for line in log.read_text().splitlines():
                m = re.search(r'(\S+) honeypot_\w+ src_ip=(\S+)', line)
                if m:
                    hits.append({
                        "time":    m.group(1),
                        "ip":      m.group(2),
                        "service": f"Fake {svc.upper()}",
                    })
        except Exception as e:
            print(f"Warning: could not read {log}: {e}")
    return hits

def get_crowdsec_decisions():
    try:
        result = run_cscli("decisions", "list", "-o", "json")
        if result.returncode != 0:
            print(f"Warning: cscli decisions list failed: {result.stderr.strip()}")
            return []
        if not result.stdout.strip() or result.stdout.strip() == "null":
            return []
        data = json.loads(result.stdout)
        decisions = []
        for alert in (data or []):
            for d in alert.get("decisions", []):
                decisions.append({
                    "ip":      d.get("value", ""),
                    "reason":  d.get("scenario", ""),
                    "country": alert.get("source", {}).get("cn", ""),
                    "as":      alert.get("source", {}).get("as_name", ""),
                    "expires": d.get("duration", ""),
                    "origin":  d.get("origin", ""),
                })
        return decisions
    except Exception as e:
        print(f"Warning: could not get CrowdSec decisions: {e}")
        return []


# ── Auto-ban logic ────────────────────────────────────────────────────────────

def auto_ban_repeat_offenders(honeypot_hits, already_banned):
    """Ban IPs with BAN_THRESHOLD+ fake-service hits in BAN_WINDOW_HOURS."""
    window_start = datetime.now() - timedelta(hours=BAN_WINDOW_HOURS)
    recent = []

    for hit in honeypot_hits:
        try:
            ts = datetime.fromisoformat(hit["time"][:19].replace("T", " "))
            if ts > window_start:
                recent.append(hit["ip"])
        except Exception:
            pass

    new_bans = []
    for ip, count in Counter(recent).items():
        if count < BAN_THRESHOLD or ip in already_banned:
            continue
        try:
            result = run_cscli(
                "decisions", "add",
                "--ip", ip,
                "--duration", BAN_DURATION,
                "--reason", BAN_REASON
            )
            if result.returncode == 0:
                new_bans.append((ip, count))
                print(f"Auto-banned {ip} ({count} hits in {BAN_WINDOW_HOURS}h)")
            else:
                print(f"Failed to ban {ip}: {result.stderr.strip()}")
        except Exception as e:
            print(f"Failed to ban {ip}: {e}")

    return new_bans

# ── HTML generation ───────────────────────────────────────────────────────────

def render_html(endlessh, honeypot, decisions, new_bans, state):
    all_hits  = sorted(endlessh + honeypot, key=lambda x: x["time"], reverse=True)
    all_ips   = [h["ip"] for h in all_hits]
    top_ips   = Counter(all_ips).most_common(10)

    total_tarpit      = len(endlessh)
    total_honeypot    = len(honeypot)
    total_banned      = len(decisions)
    total_auto_banned = len([d for d in decisions if d.get("reason") == BAN_REASON])
    total_ever_banned = state.get("total_ever_banned", 0)
    last_ban_time     = state.get("last_ban_time") or "never"
    now_str           = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def hit_rows(items, limit=100):
        html = ""
        for item in items[:limit]:
            svc   = item.get("service", "")
            color = "var(--red)" if "tarpit" in svc.lower() else "var(--yellow)"
            html += (
                f'<tr>'
                f'<td>{item.get("time","")[:19]}</td>'
                f'<td><code>{item.get("ip","")}</code></td>'
                f'<td style="color:{color}">{svc}</td>'
                f'</tr>'
            )
        return html

    def decision_rows(items):
        html = ""
        for d in items:
            autoban = d.get("reason") == BAN_REASON
            manual  = d.get("origin") == "cscli" and not autoban
            clr     = "var(--red)" if autoban else ("var(--purple)" if manual else "var(--yellow)")
            lbl     = "⚡ auto-ban" if autoban else ("manual" if manual else "crowdsec")
            fw      = "700" if autoban else "400"
            row_bg  = ' style="background:rgba(248,81,73,0.07)"' if autoban else ""
            html += (
                f'<tr{row_bg}>'
                f'<td><code>{d.get("ip","")}</code></td>'
                f'<td>{d.get("country","")}</td>'
                f'<td>{d.get("as","")[:35]}</td>'
                f'<td>{d.get("reason","")}</td>'
                f'<td style="color:{clr};font-weight:{fw}">{lbl}</td>'
                f'<td>{d.get("expires","")}</td>'
                f'</tr>'
            )
        return html

    def top_rows(items):
        if not items:
            return ""
        max_c = max(c for _, c in items)
        html  = ""
        for ip, count in items:
            w = min(100, int(count / max_c * 100))
            html += (
                f'<tr>'
                f'<td><code>{ip}</code></td>'
                f'<td>'
                f'<div style="display:flex;align-items:center;gap:8px">'
                f'<div style="background:var(--red);height:8px;width:{w}%;'
                f'border-radius:4px;min-width:4px"></div>'
                f'<span>{count}</span>'
                f'</div>'
                f'</td>'
                f'</tr>'
            )
        return html

    ban_notice = ""
    if new_bans:
        items = " &nbsp;·&nbsp; ".join(
            f'<code>{ip}</code> <span style="color:var(--muted)">({c} hits)</span>'
            for ip, c in new_bans
        )
        ban_notice = f'''
        <div style="background:rgba(248,81,73,0.12);border:2px solid var(--red);
                    border-radius:8px;padding:1.25rem;margin-bottom:1.5rem;
                    display:flex;align-items:center;gap:1rem">
          <span style="font-size:1.75rem">⚡</span>
          <div>
            <div style="color:var(--red);font-weight:700;font-size:0.9rem;
                        text-transform:uppercase;letter-spacing:.05em;
                        margin-bottom:.3rem">Auto-banned this run</div>
            <div style="font-size:.875rem">{items}</div>
          </div>
        </div>'''

    no_bans = '<tr><td colspan="6" style="color:var(--muted);text-align:center;padding:1.5rem">No active bans</td></tr>'
    no_hits = '<tr><td colspan="3" style="color:var(--muted);text-align:center;padding:1.5rem">No hits yet</td></tr>'
    no_top  = '<tr><td colspan="2" style="color:var(--muted);text-align:center;padding:1.5rem">No data</td></tr>'

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>lyra — threat dashboard</title>
<style>
:root{{
  --bg:#0d1117;--bg2:#161b22;--bg3:#21262d;
  --border:#30363d;--text:#c9d1d9;--muted:#8b949e;
  --green:#3fb950;--red:#f85149;--yellow:#d29922;
  --blue:#58a6ff;--purple:#bc8cff;
}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:var(--bg);color:var(--text);font-family:'Segoe UI',system-ui,sans-serif;padding:2rem;max-width:1200px;margin:0 auto}}
h1{{color:var(--blue);font-size:1.5rem;margin-bottom:.25rem}}
.subtitle{{color:var(--muted);font-size:.875rem;margin-bottom:2rem}}
.grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:1rem;margin-bottom:2rem}}
.card{{background:var(--bg2);border:1px solid var(--border);border-radius:8px;padding:1.25rem}}
.card .label{{color:var(--muted);font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;margin-bottom:.5rem}}
.card .value{{font-size:2rem;font-weight:700}}
.card.red .value{{color:var(--red)}}
.card.yellow .value{{color:var(--yellow)}}
.card.green .value{{color:var(--green)}}
.card.blue .value{{color:var(--blue)}}
.card.purple .value{{color:var(--purple)}}
section{{margin-bottom:2rem}}
section h2{{font-size:.9rem;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;margin-bottom:.75rem;border-bottom:1px solid var(--border);padding-bottom:.5rem}}
table{{width:100%;border-collapse:collapse;background:var(--bg2);border-radius:8px;overflow:hidden}}
th{{background:var(--bg3);color:var(--muted);font-size:.7rem;text-transform:uppercase;padding:.75rem 1rem;text-align:left}}
td{{padding:.6rem 1rem;border-top:1px solid var(--border);font-size:.875rem}}
tr:hover td{{background:var(--bg3)}}
code{{color:var(--blue);background:var(--bg3);padding:.1em .4em;border-radius:3px;font-size:.85em}}
.footer{{color:var(--muted);font-size:.75rem;margin-top:2rem;border-top:1px solid var(--border);padding-top:1rem}}
</style>
</head>
<body>
<h1>🛡 lyra — threat dashboard</h1>
<p class="subtitle">
  Updated: {now_str} &nbsp;·&nbsp;
  Auto-refreshes every 5 min &nbsp;·&nbsp;
  Auto-bans at {BAN_THRESHOLD}+ hits/{BAN_WINDOW_HOURS}h &nbsp;·&nbsp;
  Last ban: {last_ban_time}
</p>

{ban_notice}

<div class="grid">
  <div class="card red">
    <div class="label">SSH tarpit (7d)</div>
    <div class="value">{total_tarpit}</div>
  </div>
  <div class="card yellow">
    <div class="label">Honeypot hits</div>
    <div class="value">{total_honeypot}</div>
  </div>
  <div class="card blue">
    <div class="label">Unique attackers</div>
    <div class="value">{len(set(all_ips))}</div>
  </div>
  <div class="card green">
    <div class="label">Active bans</div>
    <div class="value">{total_banned}</div>
  </div>
  <div class="card" style="border-color:var(--red);background:rgba(248,81,73,0.08)">
    <div class="label" style="color:var(--red)">⚡ Auto-banned (active)</div>
    <div class="value" style="color:var(--red)">{total_auto_banned}</div>
  </div>
  <div class="card purple">
    <div class="label">Total ever banned</div>
    <div class="value">{total_ever_banned}</div>
  </div>
</div>

<section>
  <h2>Active CrowdSec bans</h2>
  <table>
    <tr><th>IP</th><th>Country</th><th>AS</th><th>Reason</th><th>Origin</th><th>Expires</th></tr>
    {decision_rows(decisions) or no_bans}
  </table>
</section>

<section>
  <h2>Top attackers (all time)</h2>
  <table>
    <tr><th>IP</th><th>Hits</th></tr>
    {top_rows(top_ips) or no_top}
  </table>
</section>

<section>
  <h2>Recent hits (last 100)</h2>
  <table>
    <tr><th>Time</th><th>IP</th><th>Service</th></tr>
    {hit_rows(all_hits) or no_hits}
  </table>
</section>

<p class="footer">
  lyra &nbsp;·&nbsp; {now_str} &nbsp;·&nbsp;
  endlessh-go + honeypot (FTP/telnet/MySQL) + CrowdSec &nbsp;·&nbsp;
  threshold: {BAN_THRESHOLD} hits/{BAN_WINDOW_HOURS}h → {BAN_DURATION} ban
</p>
</body>
</html>"""

# ── Main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    state = load_state()

    endlessh  = get_endlessh_hits()
    honeypot  = get_honeypot_hits()
    decisions = get_crowdsec_decisions()

    already_banned = {d["ip"] for d in decisions}
    new_bans = auto_ban_repeat_offenders(honeypot, already_banned)

    if new_bans:
        state["last_ban_time"]     = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        state["total_ever_banned"] = state.get("total_ever_banned", 0) + len(new_bans)
        save_state(state)
        decisions = get_crowdsec_decisions()

    html = render_html(endlessh, honeypot, decisions, new_bans, state)
    OUTPUT_FILE.write_text(html)
    print(
        f"Dashboard written — "
        f"{len(endlessh)} tarpit, {len(honeypot)} honeypot, "
        f"{len(decisions)} active bans, {len(new_bans)} new auto-bans"
    )


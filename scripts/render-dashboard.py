#!/usr/bin/env python3
"""Builds the public dashboard page from the verified reports.

Usage: python3 render-dashboard.py <folder of verified JSON files> <output index.html>
Each verified/<sha>.json is written by the correlation Lambda and looks like
{"sha": ..., "createdAt": ..., "confirmed": [...], "suspected": [...]}.
"""

import html
import json
import os
import sys
from datetime import datetime, timezone


def load_reports(folder):
    reports = []
    for name in os.listdir(folder):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(folder, name)) as f:
                data = json.load(f)
        except (OSError, ValueError):
            continue
        data["file"] = name
        reports.append(data)
    reports.sort(key=lambda r: r.get("createdAt", ""), reverse=True)
    return reports


def when(ts):
    """Turns 2026-11-26T21:00:12.000Z into 2026-11-26 21:00 UTC."""
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M UTC")
    except (AttributeError, ValueError):
        return ts or ""


def chips(items, kind):
    if not items:
        return '<span class="none">none</span>'
    return " ".join(f'<span class="chip {kind}">{html.escape(i)}</span>' for i in items)


def render(reports):
    e = html.escape
    updated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    if reports:
        latest = reports[0]
        summary = f"""
  <section class="card">
    <h2>Latest scan</h2>
    <p class="meta">Commit <code>{e(latest.get("sha", "")[:7])}</code> &middot; {e(when(latest.get("createdAt", "")))}</p>
    <div class="counts">
      <div><span class="big confirmed-text">{len(latest.get("confirmed", []))}</span>Confirmed</div>
      <div><span class="big suspected-text">{len(latest.get("suspected", []))}</span>Suspected</div>
    </div>
    <p><b>Confirmed:</b> {chips(latest.get("confirmed", []), "confirmed")}</p>
    <p><b>Suspected:</b> {chips(latest.get("suspected", []), "suspected")}</p>
  </section>"""
    else:
        summary = '<section class="card"><h2>Latest scan</h2><p>No verified scans yet. The first one appears after the next hourly run.</p></section>'

    rows = "\n".join(
        f"""      <tr>
        <td><code>{e(r.get("sha", "")[:7])}</code></td>
        <td>{e(when(r.get("createdAt", "")))}</td>
        <td>{chips(r.get("confirmed", []), "confirmed")}</td>
        <td>{chips(r.get("suspected", []), "suspected")}</td>
        <td><a href="data/{e(r["file"])}">JSON</a></td>
      </tr>"""
        for r in reports
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="300">
<title>Team 13 Verified Security Pipeline</title>
<style>
  body {{ font-family: system-ui, sans-serif; margin: 0; background: #f5f6f8; color: #1f2328; }}
  header {{ background: #1f2a44; color: #fff; padding: 20px 32px; }}
  header h1 {{ margin: 0; font-size: 22px; }}
  header p {{ margin: 6px 0 0; opacity: .8; font-size: 14px; }}
  main {{ max-width: 1000px; margin: 24px auto; padding: 0 16px; }}
  .card {{ background: #fff; border-radius: 8px; padding: 20px 24px; margin-bottom: 20px; box-shadow: 0 1px 3px rgba(0,0,0,.08); }}
  h2 {{ margin: 0 0 8px; font-size: 18px; }}
  .meta {{ color: #57606a; margin: 0 0 12px; }}
  .counts {{ display: flex; gap: 40px; margin: 12px 0; }}
  .counts div {{ display: flex; flex-direction: column; color: #57606a; }}
  .big {{ font-size: 36px; font-weight: 700; }}
  .confirmed-text {{ color: #b42318; }}
  .suspected-text {{ color: #b54708; }}
  .chip {{ display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 13px; margin: 2px 0; }}
  .chip.confirmed {{ background: #fde8e7; color: #b42318; }}
  .chip.suspected {{ background: #fef0c7; color: #93370d; }}
  .none {{ color: #8c959f; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 14px; }}
  th, td {{ text-align: left; padding: 8px; border-bottom: 1px solid #eaecef; vertical-align: top; }}
  th {{ color: #57606a; font-weight: 600; }}
  footer {{ color: #8c959f; font-size: 13px; text-align: center; margin: 24px 0; }}
</style>
</head>
<body>
<header>
  <h1>Team 13 Verified Security Pipeline</h1>
  <p>Confirmed = found by SAST in the code <b>and</b> exploited by the pentest on the running app. Suspected = found by only one of them.</p>
</header>
<main>
{summary}
  <section class="card">
    <h2>Scan history</h2>
    <table>
      <tr><th>Commit</th><th>Scanned at</th><th>Confirmed</th><th>Suspected</th><th>Report</th></tr>
{rows}
    </table>
  </section>
</main>
<footer>{len(reports)} verified scan(s) &middot; page built {updated} &middot; refreshes every 5 minutes</footer>
</body>
</html>
"""


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: render-dashboard.py <reports folder> <output html>")
    folder, out = sys.argv[1], sys.argv[2]
    page = render(load_reports(folder))
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        f.write(page)
    os.replace(tmp, out)  # swap in one step so visitors never see a half-written page

#!/usr/bin/env python3
"""Merge every data/<account>.json into docs/data.json and the README stats block."""
import json
import re
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
START, END = "<!-- stats:start -->", "<!-- stats:end -->"


def streaks(active_days, today):
    """(current, longest). Current still counts if today has no activity yet but yesterday did."""
    ds = sorted(date.fromisoformat(d) for d in active_days)
    longest = run = 0
    prev = None
    for d in ds:
        run = run + 1 if prev and (d - prev).days == 1 else 1
        longest = max(longest, run)
        prev = d
    current = 0
    if ds and (today - ds[-1]).days <= 1:
        s = set(ds)
        d = ds[-1]
        while d in s:
            current += 1
            d -= timedelta(days=1)
    return current, longest


def build():
    accounts = {p.stem: json.loads(p.read_text()) for p in sorted((REPO / "data").glob("*.json"))}
    today = datetime.now(timezone.utc).date()

    combined = {}
    for name, a in accounts.items():
        for day, v in a.get("days", {}).items():
            c = combined.setdefault(day, {"messages": 0, "sessions": 0, "toolCalls": 0, "tokens": 0, "byAccount": {}})
            tokens = sum(v.get("tokensByModel", {}).values())
            for k in ("messages", "sessions", "toolCalls"):
                c[k] += v.get(k, 0)
            c["tokens"] += tokens
            c["byAccount"][name] = v.get("messages", 0)
    combined = dict(sorted(combined.items()))

    def active(days):
        return [d for d, v in days.items() if v.get("messages", 0) > 0]

    cur, best = streaks(active(combined), today)
    per_account = {}
    for name, a in accounts.items():
        c, b = streaks(active(a.get("days", {})), today)
        per_account[name] = {
            "currentStreak": c,
            "longestStreak": b,
            "activeDays": len(active(a.get("days", {}))),
            "messages": sum(v.get("messages", 0) for v in a.get("days", {}).values()),
            "sessions": sum(v.get("sessions", 0) for v in a.get("days", {}).values()),
            "tokens": sum(sum(v.get("tokensByModel", {}).values()) for v in a.get("days", {}).values()),
            "updatedAt": a.get("updatedAt"),
        }

    models, hours = {}, {str(h): 0 for h in range(24)}
    for a in accounts.values():
        for m, u in a.get("models", {}).items():
            models[m] = models.get(m, 0) + u.get("inputTokens", 0) + u.get("outputTokens", 0) \
                + u.get("cacheReadInputTokens", 0) + u.get("cacheCreationInputTokens", 0)
        for h, n in a.get("hourCounts", {}).items():
            hours[h] = hours.get(h, 0) + n

    summary = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "currentStreak": cur,
        "longestStreak": best,
        "activeDays": len(active(combined)),
        "messages": sum(v["messages"] for v in combined.values()),
        "sessions": sum(v["sessions"] for v in combined.values()),
        "toolCalls": sum(v["toolCalls"] for v in combined.values()),
        "tokens": sum(v["tokens"] for v in combined.values()),
        "accounts": per_account,
        "models": dict(sorted(models.items(), key=lambda kv: -kv[1])),
        "hourCounts": hours,
        "days": combined,
    }
    (REPO / "docs" / "data.json").write_text(json.dumps(summary, indent=2) + "\n")
    write_readme(summary)
    return summary


def fmt(n):
    for unit, size in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if n >= size:
            return f"{n / size:.1f}{unit}"
    return str(n)


def write_readme(s):
    rows = "\n".join(
        f"| {name} | {a['currentStreak']} | {a['longestStreak']} | {a['activeDays']} | {a['messages']:,} "
        f"| {a['sessions']:,} | {fmt(a['tokens'])} | {(a['updatedAt'] or '')[:10]} |"
        for name, a in s["accounts"].items()
    )
    block = f"""{START}
| | Combined |
|---|---|
| 🔥 Current streak | **{s['currentStreak']} days** |
| 🏆 Longest streak | {s['longestStreak']} days |
| Active days | {s['activeDays']} |
| Messages | {s['messages']:,} |
| Sessions | {s['sessions']:,} |
| Tool calls | {s['toolCalls']:,} |
| Tokens | {fmt(s['tokens'])} |

| Account | Current streak | Longest | Active days | Messages | Sessions | Tokens | Last sync |
|---|---|---|---|---|---|---|---|
{rows}

_Updated {s['generatedAt'][:16].replace('T', ' ')} UTC_
{END}"""
    readme = REPO / "README.md"
    text = readme.read_text()
    text = re.sub(re.escape(START) + ".*?" + re.escape(END), lambda _: block, text, flags=re.S)
    readme.write_text(text)


if __name__ == "__main__":
    s = build()
    print(f"streak {s['currentStreak']} (best {s['longestStreak']}), {len(s['accounts'])} accounts")

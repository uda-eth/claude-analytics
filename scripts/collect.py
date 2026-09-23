#!/usr/bin/env python3
"""Snapshot this machine's Claude Code stats into data/<account>.json.

Reads ~/.claude/stats-cache.json (or $CLAUDE_CONFIG_DIR/stats-cache.json),
keeps only aggregate counts (no session ids, prompts or project names), and
merges with the snapshot already in the repo so days are never lost when
Claude Code prunes or resets its cache.

Usage: collect.py <account-label> [--push]
"""
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def config_dir():
    return Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))


def load_cache():
    path = config_dir() / "stats-cache.json"
    if not path.exists():
        sys.exit(f"no stats cache at {path} (run /stats in Claude Code once)")
    return json.loads(path.read_text())


def sanitize(cache):
    days = {}
    for d in cache.get("dailyActivity", []):
        days[d["date"]] = {
            "messages": d.get("messageCount", 0),
            "sessions": d.get("sessionCount", 0),
            "toolCalls": d.get("toolCallCount", 0),
        }
    for d in cache.get("dailyModelTokens", []):
        days.setdefault(d["date"], {"messages": 0, "sessions": 0, "toolCalls": 0})
        days[d["date"]]["tokensByModel"] = d.get("tokensByModel", {})
    models = {
        name: {k: u.get(k, 0) for k in
               ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens")}
        for name, u in cache.get("modelUsage", {}).items()
    }
    days.update(transcript_days(config_dir(), cache.get("lastComputedDate", "")))
    longest = cache.get("longestSession") or {}
    return {
        "days": days,
        "models": models,
        "hourCounts": cache.get("hourCounts", {}),
        "totalSessions": cache.get("totalSessions", 0),
        "totalMessages": cache.get("totalMessages", 0),
        "longestSession": {k: longest.get(k) for k in ("duration", "messageCount", "timestamp")},
    }


def transcript_days(config, after):
    """Count days the cache hasn't computed yet (it only refreshes on /stats) from the raw transcripts."""
    days, sessions = {}, {}
    for f in (config / "projects").glob("**/*.jsonl"):
        if datetime.fromtimestamp(f.stat().st_mtime).strftime("%Y-%m-%d") <= after:
            continue
        for line in f.open(errors="ignore"):
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get("type") not in ("user", "assistant") or "timestamp" not in e:
                continue
            ts = datetime.fromisoformat(e["timestamp"].replace("Z", "+00:00")).astimezone()
            date = ts.strftime("%Y-%m-%d")
            if date <= after:
                continue
            d = days.setdefault(date, {"messages": 0, "sessions": 0, "toolCalls": 0})
            d["messages"] += 1
            sessions.setdefault(date, set()).add(e.get("sessionId"))
            content = (e.get("message") or {}).get("content")
            if isinstance(content, list):
                d["toolCalls"] += sum(1 for c in content if isinstance(c, dict) and c.get("type") == "tool_use")
    for date, ids in sessions.items():
        days[date]["sessions"] = len(ids)
    return days


def merge(old, new):
    """Union of days (newer value wins per day); totals take the max so a cache reset can't shrink them."""
    days = dict(old.get("days", {}))
    days.update(new["days"])
    models = dict(old.get("models", {}))
    for name, u in new["models"].items():
        prev = models.get(name, {})
        models[name] = {k: max(v, prev.get(k, 0)) for k, v in u.items()}
    new["days"] = dict(sorted(days.items()))
    new["models"] = models
    new["totalSessions"] = max(new["totalSessions"], old.get("totalSessions", 0))
    new["totalMessages"] = max(new["totalMessages"], old.get("totalMessages", 0))
    return new


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        sys.exit(__doc__)
    account = args[0]
    push = "--push" in sys.argv

    if push:
        subprocess.run(["git", "-C", str(REPO), "pull", "--rebase", "--quiet"], check=True)

    out = REPO / "data" / f"{account}.json"
    old = json.loads(out.read_text()) if out.exists() else {}
    snap = merge(old, sanitize(load_cache()))
    snap["account"] = account
    snap["updatedAt"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(snap, indent=2) + "\n")
    print(f"{account}: {len(snap['days'])} days -> {out.relative_to(REPO)}")

    if push:
        git = ["git", "-C", str(REPO)]
        subprocess.run(git + ["add", str(out)], check=True)
        if subprocess.run(git + ["diff", "--cached", "--quiet"]).returncode == 0:
            print("no change")
            return
        subprocess.run(git + ["commit", "--quiet", "-m", f"data: {account} snapshot"], check=True)
        subprocess.run(git + ["push", "--quiet"], check=True)
        print("pushed")


if __name__ == "__main__":
    main()

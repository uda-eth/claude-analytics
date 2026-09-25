# claude-analytics

Combined Claude Code usage across two Claude accounts: one streak and one set of totals, plus a per-account split.

**Dashboard:** https://uda-eth.github.io/claude-analytics/

<!-- stats:start -->
| | Combined |
|---|---|
| 🔥 Current streak | **37 days** |
| 🏆 Longest streak | 37 days |
| Active days | 92 |
| Messages | 272,548 |
| Sessions | 1,470 |
| Tool calls | 90,215 |
| Tokens | 15.4B |

| Account | Current streak | Longest | Active days | Messages | Sessions | Tokens | Last sync |
|---|---|---|---|---|---|---|---|
| personal | 7 | 9 | 79 | 116,698 | 922 | 4.3B | 2026-09-25 |
| work | 37 | 37 | 38 | 155,850 | 548 | 11.1B | 2026-09-25 |

_Updated 2026-09-25 19:23 UTC_
<!-- stats:end -->

## How it works

1. Each laptop runs `scripts/collect.py <account>` once an hour, using launchd. It reads `~/.claude/stats-cache.json`, keeps only aggregate counts, merges them into `data/<account>.json` and pushes.
2. Each push to `data/` triggers the `build` workflow. It runs `scripts/build.py`, which combines every account, rewrites the stats block above and `docs/data.json`, and commits the result.
3. GitHub Pages serves `docs/` as the dashboard.

A day counts toward the combined streak if **either** account sent a message that day.

**What's published:** daily message, session and tool-call counts, tokens by model, and the hour-of-day histogram. **What's never published:** prompts, project names, session ids, and file paths.

## Setting up a laptop

**The easy way:** open Claude Code on the new laptop and say:

> Set up https://github.com/uda-eth/claude-analytics on this machine as the `personal` account

Claude clones the repo, reads [`CLAUDE.md`](CLAUDE.md), installs the collector and checks the dashboard picked it up.

**By hand:**

```bash
git clone https://github.com/uda-eth/claude-analytics ~/dev/claude-analytics
cd ~/dev/claude-analytics
./scripts/install.sh work        # or: personal
```

`install.sh` runs one collection right away, then installs the hourly launchd job `com.uda-eth.claude-analytics`. The machine needs push access to this repo (`gh auth login`). If the stats cache is missing, run `/stats` in Claude Code once.

Remove it with `./scripts/install.sh --uninstall`.

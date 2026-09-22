# Setting up a machine (for Claude Code)

When someone points you at this repo and asks you to set it up, connect it or track this account, follow these steps in order. Each one is safe to re-run.

1. **Pick the account label.** Look at the labels already in `data/*.json` (`work` is the CRS Mac). A new laptop is usually `personal`. If it's unclear, ask. Reusing an existing label would merge two accounts into one row.
2. **Clone to the standard path** (skip this if it's already cloned):
   ```bash
   git clone https://github.com/uda-eth/claude-analytics ~/dev/claude-analytics
   ```
3. **Check the prerequisites.**
   - `python3 --version` works (only the standard library is used).
   - `gh auth status` shows the account `uda-eth` and git uses https. If git isn't wired to gh, run `gh auth setup-git`. The collector pushes over git, so this machine needs write access to the repo.
   - `~/.claude/stats-cache.json` exists. If it's missing, ask the user to run `/stats` in Claude Code once, which creates it. If this account uses `CLAUDE_CONFIG_DIR`, the file is in that directory instead.
4. **Install the collector:**
   ```bash
   cd ~/dev/claude-analytics && ./scripts/install.sh <label>
   ```
   This takes a snapshot, pushes it and installs the hourly launchd job `com.uda-eth.claude-analytics`. It's macOS only. On Linux, add a cron line instead: `0 * * * * python3 ~/dev/claude-analytics/scripts/collect.py <label> --push`.
5. **Verify the outcome, not just the exit code.**
   - `launchctl list | grep claude-analytics` shows the job.
   - `git log origin/main --oneline -3` shows `data: <label> snapshot`.
   - Within about 2 minutes, `gh run list -R uda-eth/claude-analytics -L 1` shows a green `build` run, and https://uda-eth.github.io/claude-analytics/data.json lists `<label>` under `accounts`.
6. Report the combined streak and each account's streak from that `data.json`.

## Menu bar streak (optional)
`./menubar/install.sh` builds `~/Applications/StreakBar.app` (a flame + combined streak in the menu bar) and starts it at login via launchd `com.uda-eth.streakbar`. It reads the Pages `data.json`, falls back to the local `docs/data.json`, and recounts the streak on the local calendar. Check it with `~/Applications/StreakBar.app/Contents/MacOS/StreakBar --print`. Remove it with `./menubar/install.sh --uninstall`.

## Rules
- The repo is **public**. Never commit anything beyond what `collect.py` writes: no prompts, project names, session ids or paths.
- Don't edit `README.md`'s stats block or `docs/data.json` by hand. The `build` workflow owns them.
- Logs are in `~/Library/Logs/claude-analytics.log`. To remove the job, run `./scripts/install.sh --uninstall`.

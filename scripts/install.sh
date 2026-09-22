#!/bin/bash
# Install (or remove) the hourly launchd job that snapshots this machine's Claude stats.
set -euo pipefail

LABEL=com.uda-eth.claude-analytics
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${1:-}" == "--uninstall" ]]; then
  launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "removed $LABEL"
  exit 0
fi

ACCOUNT="${1:?usage: install.sh <account-label> | --uninstall}"
PY="$(command -v python3)"
mkdir -p "$HOME/Library/Logs"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>$REPO/scripts/collect.py</string>
    <string>$ACCOUNT</string>
    <string>--push</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StartInterval</key><integer>3600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/claude-analytics.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/claude-analytics.log</string>
</dict>
</plist>
EOF

"$PY" "$REPO/scripts/collect.py" "$ACCOUNT" --push
launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $LABEL for '$ACCOUNT' (hourly; log: ~/Library/Logs/claude-analytics.log)"

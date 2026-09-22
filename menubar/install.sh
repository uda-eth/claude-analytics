#!/bin/bash
# Build StreakBar.app into ~/Applications and start it at login (or remove it).
set -euo pipefail

LABEL=com.uda-eth.streakbar
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP="$HOME/Applications/StreakBar.app"
SRC="$(cd "$(dirname "$0")" && pwd)/StreakBar.swift"

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
pkill -x StreakBar 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
  rm -rf "$PLIST" "$APP"
  echo "removed StreakBar"
  exit 0
fi

mkdir -p "$APP/Contents/MacOS"
swiftc -O "$SRC" -o "$APP/Contents/MacOS/StreakBar"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$LABEL</string>
  <key>CFBundleName</key><string>StreakBar</string>
  <key>CFBundleExecutable</key><string>StreakBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP" >/dev/null
# Pin the item near the right edge (points from the right) so a crowded menu bar
# pushes other icons under the notch instead of this one. Cmd-drag overrides it.
defaults read "$LABEL" "NSStatusItem Preferred Position StreakBar" >/dev/null 2>&1 ||
  defaults write "$LABEL" "NSStatusItem Preferred Position StreakBar" -float 600

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/StreakBar</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/streakbar.log</string>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed StreakBar (starts at login). Log: ~/Library/Logs/streakbar.log"

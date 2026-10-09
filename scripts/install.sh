#!/usr/bin/env bash
# Build daylog and install it to run at login (both pieces restart if they crash).
#   server: launchd agent com.rithvik.daylog.server  -> http://127.0.0.1:7878
#   app:    ~/Applications/Daylog.app via launchd agent com.rithvik.daylog.app
# Re-run any time to rebuild and restart. Undo with scripts/uninstall.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UV="$(command -v uv)"
APP="$HOME/Applications/Daylog.app"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/daylog"
DOMAIN="gui/$(id -u)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"  # CLT SwiftPM can't link manifests here

mkdir -p "$AGENTS" "$LOGS" "$HOME/Applications"

echo "→ server deps"
"$UV" sync --project "$ROOT/server" -q

echo "→ building app"
(cd "$ROOT/app" && swift build -c release 2>&1 | tail -1)

echo "→ bundling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/app/.build/release/DaylogBar" "$APP/Contents/MacOS/Daylog"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Daylog</string>
  <key>CFBundleIdentifier</key><string>com.rithvik.daylog</string>
  <key>CFBundleExecutable</key><string>Daylog</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1

write_agent() {  # label, program args (xml), extra keys
  cat > "$AGENTS/$1.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$1</string>
  <key>ProgramArguments</key><array>$2</array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$LOGS/$3.log</string>
  <key>StandardErrorPath</key><string>$LOGS/$3.log</string>
  $4
</dict></plist>
PLIST
  launchctl bootout "$DOMAIN/$1" 2>/dev/null || true
  # bootout is asynchronous; bootstrapping before it finishes fails with error 5.
  for _ in $(seq 1 50); do launchctl print "$DOMAIN/$1" >/dev/null 2>&1 || break; sleep 0.2; done
  launchctl bootstrap "$DOMAIN" "$AGENTS/$1.plist"
}

echo "→ launchd agents"
write_agent com.rithvik.daylog.server \
  "<string>$UV</string><string>run</string><string>--project</string><string>$ROOT/server</string><string>uvicorn</string><string>daylog.api:app</string><string>--host</string><string>127.0.0.1</string><string>--port</string><string>7878</string>" \
  server "<key>WorkingDirectory</key><string>$ROOT/server</string>"
write_agent com.rithvik.daylog.app \
  "<string>$APP/Contents/MacOS/Daylog</string>" \
  app "<key>LimitLoadToSessionType</key><string>Aqua</string>"

echo -n "→ waiting for server"
for _ in $(seq 1 30); do
  if curl -fs http://127.0.0.1:7878/health >/dev/null; then echo " up"; break; fi
  echo -n "."; sleep 1
done
curl -fs http://127.0.0.1:7878/health && echo
echo "✓ daylog installed. Pill on the right edge of your screen; ⌥+fn (or ⌃⌥D) toggles the panel."
echo "  Logs: $LOGS"

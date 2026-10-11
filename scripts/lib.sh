# Shared by release.sh and dev.sh. Source it; don't run it.
UV="$(command -v uv)"
AGENTS="$HOME/Library/LaunchAgents"
LOGS="$HOME/Library/Logs/daylog"
DATA="$HOME/Library/Application Support/daylog"
DOMAIN="gui/$(id -u)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"  # CLT SwiftPM can't link manifests here
mkdir -p "$AGENTS" "$LOGS" "$DATA" "$HOME/Applications"

# build_app <source-root> <app-path> <bundle-id> <display-name>
build_app() {
  local src="$1" app="$2" id="$3" name="$4"
  (cd "$src/app" && swift build -c release 2>&1 | tail -1)
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  cp "$src/app/.build/release/DaylogBar" "$app/Contents/MacOS/Daylog"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleExecutable</key><string>Daylog</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-dev}</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
  # Stable local signing identity so macOS keeps permissions across rebuilds (ad-hoc fallback).
  local identity; identity="$(security find-identity -p codesigning 2>/dev/null | awk '/"daylog-local"/{print $2; exit}')"
  codesign --force --sign "${identity:--}" "$app" >/dev/null 2>&1
}

# write_agent <label> <program-args-xml> <log-name> [extra-plist-keys]
write_agent() {
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
  ${4:-}
</dict></plist>
PLIST
  launchctl bootout "$DOMAIN/$1" 2>/dev/null || true
  # bootout is asynchronous; bootstrapping before it finishes fails with error 5.
  for _ in $(seq 1 50); do launchctl print "$DOMAIN/$1" >/dev/null 2>&1 || break; sleep 0.2; done
  launchctl bootstrap "$DOMAIN" "$AGENTS/$1.plist"
}

# server_args <server-dir> <port>
server_args() {
  echo "<string>$UV</string><string>run</string><string>--project</string><string>$1</string><string>uvicorn</string><string>daylog.api:app</string><string>--host</string><string>127.0.0.1</string><string>--port</string><string>$2</string>"
}

wait_health() {  # wait_health <port>
  curl -fs --retry 15 --retry-connrefused --retry-delay 1 "http://127.0.0.1:$1/health"; echo
}

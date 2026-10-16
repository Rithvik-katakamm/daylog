#!/usr/bin/env bash
# The TEST COPY, for agent tests only (his call, Oct 15: one Day Log on his Mac, "prototype").
# Builds the working tree into .build/Daylog Test.app (never ~/Applications) and writes its server job
# (:7879, a throwaway database, importers off) into .build/ (never ~/Library/LaunchAgents, so it can't
# start at login). Nothing runs after this script: `.build/devctl start` runs both headless and silent,
# `.build/devctl stop` ends them. It never appears on his screens and never touches his real log.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
BUILD="$ROOT/.build"; mkdir -p "$BUILD"

echo "→ test server deps"
"$UV" sync --project "$ROOT/server" -q

echo "→ test server job (.build/, starts only with devctl start)"
cat > "$BUILD/com.rithvik.daylog.dev.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.rithvik.daylog.dev</string>
  <key>ProgramArguments</key><array>$(server_args "$ROOT/server" 7879)</array>
  <key>WorkingDirectory</key><string>$ROOT/server</string>
  <key>EnvironmentVariables</key><dict>
    <key>DAYLOG_DEV</key><string>1</string>
    <key>DAYLOG_DB</key><string>$DATA/daylog-dev.sqlite</string>
    <key>DAYLOG_IMPORTERS</key><string>0</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOGS/server-dev.log</string>
  <key>StandardErrorPath</key><string>$LOGS/server-dev.log</string>
</dict></plist>
PLIST

echo "→ building .build/Daylog Test.app"
pkill -f "Daylog Test.app/Contents/MacOS/Daylog" 2>/dev/null || true
build_app "$ROOT" "$BUILD/Daylog Test.app" com.rithvik.daylog.dev "Daylog Test"

echo "→ devctl"
swiftc -O "$ROOT/tools/devctl.swift" -o "$BUILD/devctl"
echo "✓ test copy built in .build/ (not running). Tests: .build/devctl start … stop."

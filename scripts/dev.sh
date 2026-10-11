#!/usr/bin/env bash
# DEV channel: build the working tree into "Daylog Dev.app" and (re)start the dev server.
# Never touches the stable app, the real server, or the real log.
#   Daylog Dev.app (com.rithvik.daylog.dev) · server :7879 · daylog-dev.sqlite · importers off
# Open it with ⌥D (from the stable app). Drive it in tests with .build/devctl (no keyboard, no focus).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"

echo "→ dev server deps"
"$UV" sync --project "$ROOT/server" -q

echo "→ dev server (working tree, :7879)"
write_agent com.rithvik.daylog.dev "$(server_args "$ROOT/server" 7879)" server-dev \
  "<key>WorkingDirectory</key><string>$ROOT/server</string><key>EnvironmentVariables</key><dict><key>DAYLOG_DEV</key><string>1</string><key>DAYLOG_DB</key><string>$DATA/daylog-dev.sqlite</string><key>DAYLOG_IMPORTERS</key><string>0</string></dict>"

echo "→ building Daylog Dev.app"
pkill -f "Daylog Dev.app/Contents/MacOS/Daylog" 2>/dev/null || true  # relaunch on next ⌥D with the new build
build_app "$ROOT" "$HOME/Applications/Daylog Dev.app" com.rithvik.daylog.dev "Daylog Dev"

echo "→ devctl"
mkdir -p "$ROOT/.build" && swiftc -O "$ROOT/tools/devctl.swift" -o "$ROOT/.build/devctl"

wait_health 7879 >/dev/null && echo "✓ dev ready. ⌥D opens it; stable (⌥L) untouched."

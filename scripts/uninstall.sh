#!/usr/bin/env bash
# Stop and remove the launchd agents and the app bundle. Your data stays at
# ~/Library/Application Support/daylog/daylog.sqlite.
set -uo pipefail
for label in com.rithvik.daylog.app com.rithvik.daylog.server com.rithvik.daylog.dev; do
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
  rm -f "$HOME/Library/LaunchAgents/$label.plist"
done
rm -rf "$HOME/Applications/Daylog.app"
echo "daylog uninstalled (data kept)."

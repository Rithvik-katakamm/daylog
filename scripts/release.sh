#!/usr/bin/env bash
# STABLE channel: ship a tagged version to the app you actually use.
#   scripts/release.sh v0.2
# Freezes the tag into ~/Library/Application Support/daylog/releases/<tag>, builds Daylog.app
# from that frozen copy, and points the real server at it. Editing the repo afterwards can't
# affect stable. Roll back by releasing an older tag.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/lib.sh"
VERSION="${1:?usage: scripts/release.sh <tag, e.g. v0.2>}"

cd "$ROOT"
if ! git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
  [ -z "$(git status --porcelain)" ] || { echo "✗ working tree not clean; commit first"; exit 1; }
  git tag -a "$VERSION" -m "Day Log $VERSION"
  echo "→ tagged $VERSION at $(git rev-parse --short HEAD)"
fi

REL="$DATA/releases/$VERSION"
echo "→ freezing $VERSION into $REL"
rm -rf "$REL"; mkdir -p "$REL"
git archive "$VERSION" | tar -x -C "$REL"
"$UV" sync --project "$REL/server" -q

echo "→ building Daylog.app from the frozen copy"
export VERSION
build_app "$REL" "$HOME/Applications/Daylog.app" com.rithvik.daylog "Daylog"
ln -sfn "$REL" "$DATA/releases/current"

echo "→ real server (frozen $VERSION, :7878)"
write_agent com.rithvik.daylog.server "$(server_args "$DATA/releases/current/server" 7878)" server \
  "<key>WorkingDirectory</key><string>$DATA/releases/current/server</string>"
echo "→ app"
write_agent com.rithvik.daylog.app "<string>$HOME/Applications/Daylog.app/Contents/MacOS/Daylog</string>" app \
  "<key>LimitLoadToSessionType</key><string>Aqua</string>"

wait_health 7878
git push -q origin "$VERSION" 2>/dev/null && echo "→ pushed tag $VERSION" || echo "  (tag not pushed)"
echo "✓ Day Log $VERSION is live. ⌥L opens it."

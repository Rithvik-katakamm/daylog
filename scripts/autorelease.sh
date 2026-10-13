#!/usr/bin/env bash
# CD (RIT-87): when he unlocks the Mac, bring the founder version up to date with main.
# Never on a timer (battery; a closed Mac runs nothing anyway). The stable app kicks this job on
# unlock/wake (launchctl kickstart); launchd also runs it once at login.
#   scripts/autorelease.sh            check and release if main moved
#   scripts/autorelease.sh --install  register the launchd job (on demand only, no schedule)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # launchd starts jobs with a bare PATH
source "$ROOT/scripts/lib.sh"
LABEL=com.rithvik.daylog.autorelease

if [ "${1:-}" = "--install" ]; then
  cat > "$AGENTS/$LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$ROOT/scripts/autorelease.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$LOGS/autorelease.log</string>
  <key>StandardErrorPath</key><string>$LOGS/autorelease.log</string>
</dict></plist>
PLIST
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  for _ in $(seq 1 50); do launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break; sleep 0.2; done
  launchctl bootstrap "$DOMAIN" "$AGENTS/$LABEL.plist"
  echo "✓ autorelease registered: runs at login and whenever the app kicks it (unlock/wake)"
  exit 0
fi

say() { echo "$(date '+%F %T') $*"; }
notify() { osascript -e "display notification \"$1\" with title \"Day Log\"" 2>/dev/null || true; }
LOCK="$DATA/autorelease.lock"
mkdir "$LOCK" 2>/dev/null || { say "already running"; exit 0; }
trap 'rmdir "$LOCK"' EXIT

cd "$ROOT"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = main ] || { say "skip: repo is on $BRANCH, not main"; exit 0; }
[ -z "$(git status --porcelain --untracked-files=no)" ] || { say "skip: uncommitted changes in the repo"; exit 0; }
git fetch -q origin main --tags 2>/dev/null || { say "skip: offline"; exit 0; }
if ! git merge -q --ff-only origin/main 2>/dev/null; then
  say "skip: local main and GitHub's main have diverged"; notify "Can't update: local main and GitHub's main diverged"; exit 0
fi
CUR="$(basename "$(readlink "$DATA/releases/current")")"
if git diff --quiet "$CUR" HEAD -- app server; then say "up to date ($CUR)"; exit 0; fi

say "main moved past $CUR; testing"
if ! (cd server && "$UV" run pytest -q >/dev/null); then
  say "tests failed; staying on $CUR"; notify "New code failed its tests; staying on $CUR"; exit 0
fi
LATEST="$(git tag --list 'v*' --sort=-v:refname | head -1)"
NEXT="v0.$(( ${LATEST#v0.} + 1 ))"
say "releasing $NEXT"
"$ROOT/scripts/release.sh" "$NEXT"
notify "Day Log $NEXT is live (from GitHub). ⌘K shows it."

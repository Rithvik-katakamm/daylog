#!/usr/bin/env bash
# CD: when he unlocks the Mac, bring the founder version up to date with main.
# Never on a timer (battery; a closed Mac runs nothing anyway). The stable app kicks this job when he's at the Mac:
# unlock, wake, opening the bar, or a push to main from this Mac (.githooks/pre-push); launchd also runs it at login. It releases only
# commits CI marked green on GitHub, and every skip says why (notification + a line in the pill).
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
  git -C "$ROOT" config core.hooksPath .githooks   # a push to main from this Mac starts CD (.githooks/pre-push)
  echo "✓ autorelease registered: runs at login and whenever the app kicks it (unlock/wake)"
  exit 0
fi

say() { echo "$(date '+%F %T') $*"; }
notify() { osascript -e "display notification \"$1\" with title \"Day Log\"" 2>/dev/null || true; }
STATUS="$DATA/cd-status.json"   # read by the server's /health; the pill shows a skip until the next good release
status() {  # status <state> [reason] [fix]
  STATE="$1" REASON="${2:-}" FIX="${3:-}" python3 -c 'import json,os,datetime
print(json.dumps({"state":os.environ["STATE"],"reason":os.environ["REASON"],"fix":os.environ["FIX"],
"at":datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}))' > "$STATUS"
}
# Every skip says why and how to fix it (his rule, Oct 13): a notification now, and a line in the pill.
skip() {
  say "skip: $1"
  local same=""; grep -qF "\"reason\": \"$1\"" "$STATUS" 2>/dev/null && same=1
  status skipped "$1" "$2"
  [ -n "$same" ] || notify "Stayed on ${CUR:-the current version}: $1. $2"   # once per new reason, not every bar open
  exit 0
}

LOCK="$DATA/autorelease.lock"
mkdir "$LOCK" 2>/dev/null || { say "already running"; exit 0; }
trap 'rmdir "$LOCK"' EXIT

# What ships is GitHub's main: the exact commit CI tested, frozen by tag. The working tree is never used, so
# edits in progress, another branch or unpushed commits on the Mac can't block a release or sneak into one.
cd "$ROOT"
CUR="$(basename "$(readlink "$DATA/releases/current")")"
git fetch -q origin main --tags 2>/dev/null || skip "GitHub is unreachable (offline?)" "it retries at the next unlock"
SHA="$(git rev-parse origin/main)"
if git diff --quiet "$CUR" "$SHA" -- app server; then say "up to date ($CUR)"; status ok; exit 0; fi

ci() { gh run list --commit "$SHA" --workflow CI --json status,conclusion -q '.[0] | .status+" "+(.conclusion // "")' 2>/dev/null; }
say "GitHub's main moved past $CUR; waiting for CI on ${SHA:0:7}"
for i in $(seq 1 40); do   # up to 10 minutes; the Mac is awake and he's at it
  s="$(ci)"
  case "$s" in
    "completed success") break ;;
    "completed cancelled")   # a newer push replaced this run: check the newer commit instead
      git fetch -q origin main 2>/dev/null || true
      if [ "$(git rev-parse origin/main)" != "$SHA" ]; then
        say "CI on ${SHA:0:7} was replaced by a newer push; rechecking"; rmdir "$LOCK"; trap - EXIT; exec "$0"
      fi
      skip "CI on ${SHA:0:7} was cancelled" "run: gh workflow run CI --ref main" ;;
    completed*) skip "CI failed on ${SHA:0:7} (${s#completed })" "see gh run list; a fix pushed to main re-runs it" ;;
    "") [ "$i" -ge 8 ] && skip "no CI run exists for ${SHA:0:7}" "run: gh workflow run CI --ref main" ;;
  esac
  sleep 15
done
[ "$s" = "completed success" ] || skip "CI is still running on ${SHA:0:7} after 10 minutes" "it retries at the next unlock or bar open"

LATEST="$(git tag --list 'v*' --sort=-v:refname | head -1)"
NEXT="v0.$(( ${LATEST#v0.} + 1 ))"
git tag -a "$NEXT" -m "Day Log $NEXT" "$SHA"   # tag the CI-green commit itself, never whatever HEAD is
say "CI green; releasing $NEXT (${SHA:0:7})"
"$ROOT/scripts/release.sh" "$NEXT"
status released "" ""
notify "Day Log $NEXT is live. ⌘K shows it."
# Best effort: if the Mac's repo is a clean main that's behind, catch it up (never blocks a release).
if [ "$(git rev-parse --abbrev-ref HEAD)" = main ] && [ -z "$(git status --porcelain --untracked-files=no)" ]; then
  git merge -q --ff-only origin/main 2>/dev/null || true
fi

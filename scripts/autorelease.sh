#!/usr/bin/env bash
# CD: when he unlocks the Mac, bring the founder version up to date with main.
# Never on a timer (battery; a closed Mac runs nothing anyway). The stable app kicks this job when he's at the Mac:
# unlock, wake, or opening the bar (launchctl kickstart); launchd also runs it once at login. It releases only
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

cd "$ROOT"
CUR="$(basename "$(readlink "$DATA/releases/current")")"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = main ] || skip "the repo is on branch $BRANCH, not main" "switch back to main"
[ -z "$(git status --porcelain --untracked-files=no)" ] || skip "uncommitted changes in the repo" "commit or stash them"
git fetch -q origin main --tags 2>/dev/null || skip "GitHub is unreachable (offline?)" "it retries at the next unlock"
git merge -q --ff-only origin/main 2>/dev/null || skip "local main and GitHub's main have diverged" "pull --rebase, then push"
[ -z "$(git log --oneline origin/main..HEAD)" ] || skip "local commits aren't on GitHub yet, so CI hasn't checked them" "push them"
if git diff --quiet "$CUR" HEAD -- app server; then say "up to date ($CUR)"; status ok; exit 0; fi

# CD releases only what CI marked green on GitHub (his call: CI always runs there, even when the Mac is on).
SHA="$(git rev-parse HEAD)"
ci() { gh run list --commit "$SHA" --workflow CI --json status,conclusion -q '.[0] | .status+" "+(.conclusion // "")' 2>/dev/null; }
say "main moved past $CUR; waiting for CI on ${SHA:0:7}"
for i in $(seq 1 40); do   # up to 10 minutes; the Mac is awake and he's at it
  s="$(ci)"
  case "$s" in
    "completed success") break ;;
    completed*) skip "CI failed on ${SHA:0:7} (${s#completed })" "see gh run list; a fix pushed to main re-runs it" ;;
    "") [ "$i" -ge 8 ] && skip "no CI run exists for ${SHA:0:7}" "run: gh workflow run CI --ref main" ;;
  esac
  sleep 15
done
[ "$s" = "completed success" ] || skip "CI is still running on ${SHA:0:7} after 10 minutes" "it retries at the next unlock or bar open"

if ! (cd server && "$UV" run pytest -q >/dev/null); then
  skip "tests passed on GitHub but fail on this Mac" "run cd server && uv run pytest"
fi
LATEST="$(git tag --list 'v*' --sort=-v:refname | head -1)"
NEXT="v0.$(( ${LATEST#v0.} + 1 ))"
say "CI green; releasing $NEXT"
"$ROOT/scripts/release.sh" "$NEXT"
status released "" ""
notify "Day Log $NEXT is live. ⌘K shows it."

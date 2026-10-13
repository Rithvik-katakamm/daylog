# Cloud loop: work from the phone

**Goal (his, Oct 13):** close the laptop and keep working without feeling the difference; open it and carry on.

```
phone ──▶ Claude cloud session (Linux VM, clone of GitHub repo)
             │ pushes claude/<branch>            (git goes through GitHub's proxy; no token lives in the VM)
             ▼
          GitHub Actions  .github/workflows/ci.yml
             ├─ server: uv run pytest            (ubuntu)
             ├─ app:    swift build -c release   (macos-15: a fresh Mac VM, compiles the pill, can't show it)
             └─ land:   both green → merge into main, re-test, delete the branch   (no PR to approve)
             ▼
          his Mac, whenever he's at it: unlock, wake, or opening the bar (at most every 5 min)
             app kicks com.rithvik.daylog.autorelease → scripts/autorelease.sh
               fetch GitHub's main → app/ or server/ changed since releases/current?
               → CI green on GitHub for that commit? (waits up to 10 min) → tag that commit → release.sh v0.N+1
               → notification; ⌘K shows the version
             any skip → a notification (once per new reason) + "update skipped · why · fix" in the pill
```

## Constraints (why it's shaped like this)

| Constraint | Consequence |
|---|---|
| A closed Mac is asleep and runs nothing | CI can't run on the Mac: it runs on GitHub's machines |
| The founder version lives on the Mac | CD has to run on the Mac, at the moment it's awake and his: unlock |
| Polling costs battery and does nothing while closed | No timer: the app kicks the job on unlock/wake; launchd also runs it at login |
| The cloud VM has no macOS screen | Cloud = backend, data, docs, logic tests; notch/UI work stays at the Mac |
| His database never leaves the Mac | Cloud sessions can't run evals on his real lines |
| He may be mid-work on the Mac when CD runs | CD ships GitHub's `main` (the CI-tested commit) from a frozen tag and never touches the working tree, so local edits, branches or unpushed commits neither block it nor ship |
| Coding on the Mac should ship right away | A push to main from the Mac starts CD at once (`.githooks/pre-push`); cloud work ships at the next unlock / wake / bar open |
| CI runs on GitHub even when the Mac is on (his call) | CD releases only a commit with a green CI run; a push from the Mac ships the same way as one from the phone |
| He wants to know every time CD doesn't ship (his call) | Each skip: a notification with the reason and the fix, and a line in the pill until the next good release |

## One-time setup (him)

1. claude.ai/code → connect GitHub → pick `Rithvik-katakamm/daylog`.
2. Cloud environment: default network access is enough (PyPI for `uv`). Setup script: `cd server && uv sync`.
3. From the phone: start a session on the repo with a card, e.g. "…".

## Knobs and logs

- `~/Library/Logs/daylog/autorelease.log`: every unlock check (up to date / skipped / released).
- Turn CD off: `launchctl bootout gui/$(id -u)/com.rithvik.daylog.autorelease`. Back on: `scripts/autorelease.sh --install`.

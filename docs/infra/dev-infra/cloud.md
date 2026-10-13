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
          his Mac, at the next unlock or wake
             app kicks com.rithvik.daylog.autorelease → scripts/autorelease.sh
               fetch main → fast-forward → app/ or server/ changed since releases/current?
               → pytest → release.sh v0.N+1 → notification; ⌘K shows the version
```

## Constraints (why it's shaped like this)

| Constraint | Consequence |
|---|---|
| A closed Mac is asleep and runs nothing | CI can't run on the Mac: it runs on GitHub's machines |
| The founder version lives on the Mac | CD has to run on the Mac, at the moment it's awake and his: unlock |
| Polling costs battery and does nothing while closed | No timer: the app kicks the job on unlock/wake; launchd also runs it at login |
| The cloud VM has no macOS screen | Cloud = backend, data, docs, logic tests; notch/UI work stays at the Mac |
| His database never leaves the Mac | Cloud sessions can't run evals on his real lines |
| He may be working in the repo when he unlocks | autorelease skips if the repo isn't on a clean `main`, or if main diverged |

## One-time setup (him)

1. claude.ai/code → connect GitHub → pick `Rithvik-katakamm/daylog`.
2. Cloud environment: default network access is enough (PyPI for `uv`). Setup script: `cd server && uv sync`.
3. From the phone: start a session on the repo with a card, e.g. "…".

## Knobs and logs

- `~/Library/Logs/daylog/autorelease.log`: every unlock check (up to date / skipped / released).
- Turn CD off: `launchctl bootout gui/$(id -u)/com.rithvik.daylog.autorelease`. Back on: `scripts/autorelease.sh --install`.

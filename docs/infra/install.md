# Install, run, test

## Two channels: stable and dev

Building and testing must never disturb the version he's using.

| | **Stable** (what he uses) | **Dev** (what gets built and tested) |
|---|---|---|
| App | `~/Applications/Daylog.app` (`com.rithvik.daylog`) | `~/Applications/Daylog Dev.app` (`com.rithvik.daylog.dev`) |
| Opened with | ⌥L | ⌥D (stable hands off to the Dev app) |
| Code | a **frozen copy of a git tag**: `~/Library/Application Support/daylog/releases/<tag>` (`current` symlink) | the working tree |
| Server | `com.rithvik.daylog.server` on `:7878` | `com.rithvik.daylog.dev` on `:7879` (`DAYLOG_DEV=1`) |
| Data | `daylog.sqlite` (the real log) | `daylog-dev.sqlite`; importers off; `POST /dev/reset` |
| Records Mac activity | yes | no |
| Looks | normal | identical, plus a `DEV` tag |
| Updated by | `scripts/release.sh <tag>`, only when he says ship | `scripts/dev.sh`, as often as needed |

```sh
scripts/dev.sh             # rebuild Dev app + restart dev server (stable untouched)
scripts/release.sh v0.2    # tag HEAD (clean tree required), freeze it, ship to stable
scripts/release.sh v0.1    # roll back = release an older tag
scripts/install.sh         # first-time: latest tag → stable, working tree → dev
scripts/uninstall.sh       # remove agents + app (data kept)
```

## Server tests

`cd server && uv run pytest` (temp DB, fake clock).

# Install, run, test

## One version: Day Log prototype

His call (Oct 15): "one version across the board … we're prototyping." One app, one server, his real
log. A dev/prod split comes back only when there are real users.

```
change → commit → push main → CI on GitHub (server tests + macOS build)
                                 │ green                         │ red
                                 ▼                               ▼
          CD (autorelease.sh, started by the push)        nothing ships; the pill says
          freezes the tag, rebuilds the app                "update skipped: why"
                                 ▼
          Day Log prototype vX · ⌥L · :7878 · his real database
```

| | |
|---|---|
| App | `~/Applications/Daylog.app` (`com.rithvik.daylog`), opened with ⌥L |
| Code | a **frozen copy of a git tag**: `~/Library/Application Support/daylog/releases/<tag>` (`current` symlink), so the running version is always known and rollback is one command |
| Server | `com.rithvik.daylog.server` on `:7878` |
| Data | `daylog.sqlite` (the real log). Backups: `daylog/backups/` |
| Updated by | CD after every green push (`scripts/autorelease.sh`); `release.sh` only by hand to roll back |

**The test copy** (agents only, never on his screens): `scripts/test-copy.sh` builds
`.build/Daylog Test.app` (`com.rithvik.daylog.dev`) and its server job (`:7879`, `daylog-dev.sqlite`,
importers off) into the repo's `.build/`, not ~/Applications or LaunchAgents. `devctl start` runs them
headless; `devctl stop` ends them. See `docs/testing/strategy.md`.

```sh
scripts/test-copy.sh       # build the hidden test copy (nothing starts)
scripts/release.sh v0.31   # roll back = release an older tag
scripts/install.sh         # first-time: latest tag → the app, working tree → the test copy
scripts/uninstall.sh       # remove agents + app (data kept)
```

## Server tests

`cd server && uv run pytest` (temp DB, fake clock).

## What's new after a release

`scripts/release.sh` writes `RELEASE.json` into the frozen release: the version, commit subjects since the
previous tag that touched `app/` or `server/` ("new"), and any `Try:` commit trailers ("try"). `/health` serves
the version to everyone and the notes only to the owner's install. The first time the bar opens after a release it
shows one line, "v0.13 · new: … · try: …", once; ⌘K → "What's new in this version" shows it again.

**Owner-only features** are on when the file `~/Library/Application Support/daylog/owner` exists. Nothing in the
repo creates it, so other people installing Day Log never see owner-only features. To get a "try" line in the
notes, add a trailer to the commit: `Try: open the bar right after a release`.

## Keeping private things out of git

Local code and data stay local. `.githooks/pre-commit` refuses a commit that stages databases, keys, `.env`, the owner flag, `RELEASE.json`, local tool folders (`.codex/`, `.learning/`), secret-looking strings or a home-folder path. Turn it on in each clone with `git config core.hooksPath .githooks`.

# Events and API

Everything Day Log knows is a row in one SQLite table, `events`. Code: `server/daylog/`.

## Invariants

- **Append-only.** Triggers reject UPDATE and DELETE (`db.py`). Edits and deletes are new
  events that point at old ones through `ref`.
- **Views are derived** at read time (`timeline.py`): fix the logic, and history is fixed too.
- **Source attribution:** every event has `kind` (claim / observation / prediction) and
  `source` (button, mcp, api, mac, wispr…).
- **Times** are stored in UTC as `YYYY-MM-DDTHH:MM:SSZ`, so string order = time order.

## Event types

| type | kind | What it means | `ref` points to |
|---|---|---|---|
| `timer.start` | claim | Started a task | — |
| `timer.stop` | claim | Ended a timer or ghost span | the start |
| `entry.log` | claim | A past block with start + end | — |
| `entry.delete` | claim | Tombstone: hide that entry/timer/note | the target |
| `entry.amend` | claim | Edit: new label/start/end (newest wins) | the target |
| `note` | claim | A thought at a moment | the running timer (if any) |
| `focus.set` | claim | Focus tier 0–3 from now on | the running timer |
| `ghost.start` | claim | Went offline, with a status | — |
| `app.focus` | observation | App in front (plus a heartbeat every 5 min) | — |
| `away.start` | observation | Locked, asleep, or idle for 5+ min | — |
| `meeting` | observation | Wispr Notetaker meeting (start, end) | — |
| `dictation` | observation | Wispr dictation (app, url, words) | — |

## API (`127.0.0.1:7878`, live docs at `/docs`)

| Method | Path | Does |
|---|---|---|
| GET | `/health` | Up check; `env` is `real` or `dev` |
| POST | `/dev/reset` | Wipe the dev database (dev server only; 404 on real) |
| GET | `/now` | Running timer (with focus), current app, meeting, ghost |
| POST | `/timer/start`, `/timer/stop` | Start (auto-stops the old timer, ends ghost) / stop |
| POST | `/log` | One line in: logs a past block if it has a time, else starts a timer |
| GET | `/parse` | What `/log` would do (live preview, no write) |
| POST | `/entries` | Log a past block (`minutes` or `start`+`end`) |
| POST | `/entries/{id}/amend` | Rename or move start/end |
| DELETE | `/entries/{id}` | Tombstone |
| POST | `/notes` | Note at this moment |
| POST | `/focus` | Set focus tier on the running task (409 if none) |
| POST / DELETE | `/ghost` | Go offline / come back (observations refused while ghost, except two bare facts: the Mac sleeping (`{reason}` only) and the first app switch after it (`{}`, a wake mark). A sleep that touches 12-7 AM local ends ghost when the Mac slept; knob `NIGHT_HOURS`) |
| POST | `/observations` | Mac recorder input (`app.focus`, `away.start`) |
| GET | `/timeline` | Claims, meetings, activity, dictations, notes for a day or range |
| GET | `/history` | Newest-first stops for scrolling back (entries, meetings, notes, gaps ≥10m) |
| GET | `/summary` | Minutes by label, app, focus tier; tracked vs. untracked |
| POST | `/import/wispr` | Run the Wispr import now (it also runs every 10 min) |

## MCP (`server/daylog/mcp_server.py`)

A thin client of the HTTP API: `what_is_rithvik_doing`, `timeline`, `day_summary`,
`log_activity`. It never touches the database directly.

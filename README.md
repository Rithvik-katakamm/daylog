# daylog

**What is Rithvik doing?** A local system of record for time: what you actually did,
not what you planned.

## Use it

- **The pill** on the right edge of your screen. Click it, or press **⌃⌥D**.
  Drag it up or down to move it.
- **Type what you're doing + ⏎** to start a timer. Typing something new switches
  (the old timer stops).
- **Already did it?** Type it, then hit 15m / 30m / 1h / 2h to log the time ending now.
- **The day view:** drag across any time range to say what you were doing then.
  Right-click a block to delete it. ‹ › moves between days.
  - Mint = what you logged. Violet = Wispr meetings (automatic).
  - The thin colored strip = which app was in front.
- **Agents:** any Claude Code session has the `daylog` MCP tools:
  `what_is_rithvik_doing`, `timeline`, `day_summary`, `log_activity`.

## Install / update / remove

```sh
scripts/install.sh     # build, install, and (re)start both pieces at login
scripts/uninstall.sh   # remove (your data stays)
```

Data: `~/Library/Application Support/daylog/daylog.sqlite` · Logs: `~/Library/Logs/daylog/`
API docs (live): http://127.0.0.1:7878/docs

## How it's built (and why)

```
 Daylog.app (Swift)                 server (Python)                     agents
 ┌──────────────────┐   HTTP     ┌──────────────────────────┐   HTTP   ┌──────────────┐
 │ pill + panel     │──POST────▶ │ FastAPI  :7878           │ ◀─────── │ MCP server   │◀── Claude, Muse…
 │ activity recorder│──POST────▶ │  rules: one timer, no    │          │ (thin client)│
 └──────────────────┘ ◀──JSON─── │  future entries, …       │          └──────────────┘
                                 │        │                 │
                Wispr flow.sqlite ──read──▶ importer (10 min)
                                 │        ▼                 │
                                 │  events (append-only)    │
                                 │  └▶ timeline / summary / now are DERIVED at read time
                                 └──────────────────────────┘
```

- **Why a server?** Many writers (button, recorder, importers, later the phone) and many
  readers (panel, agents) need one owner of the truth and one place where the rules live.
  The HTTP reply is the server confirming what it saved and what's true now.
- **Why append-only?** Nothing is ever edited or erased. Stopping a timer *adds* a stop
  event, and deleting adds a tombstone. Triggers in SQLite reject UPDATE/DELETE, so the
  rule is enforced by the database, not by remembering it. You get a full history, and
  derived views can be recomputed whenever the logic improves.
- **Observations vs. claims:** the recorder and importers write `observation`s (what a
  machine saw). You write `claim`s (what you did). They're stored separately and never
  merged, which is what makes a future "were you doing X?" model trainable.
- **Why MCP calls the HTTP API instead of the DB:** REST is the contract and MCP is an
  adapter for LLMs. One door means agents follow the same rules you do.
- **Why it feels fast:** the app is always running and the panel already exists (it's
  shown, not launched). The UI updates optimistically before the server replies, and
  the server is on localhost with an indexed SQLite file.

## Layout

```
server/daylog/db.py          the event store + append-only triggers
server/daylog/timeline.py    derived views: claims, meetings, activity, summary, now
server/daylog/api.py         HTTP routes + background Wispr import
server/daylog/wispr.py       Wispr Flow importer (read-only)
server/daylog/mcp_server.py  MCP tools for agents
app/Sources/DaylogBar/       Swift app: main (windows), Views, Store, API, ActivityRecorder, HotKey
docs/vision.md               where this is going
docs/specs/                  what each version commits to
```

Tests: `cd server && uv run pytest`

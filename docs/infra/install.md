# Install, run, test

## Install / update / remove

```sh
scripts/install.sh     # build both pieces, install, (re)start at login
scripts/uninstall.sh   # remove (data stays)
```

## What's running

| Piece | How | Where |
|---|---|---|
| Server | launchd agent `com.rithvik.daylog.server` (KeepAlive) | `127.0.0.1:7878` |
| App | launchd agent `com.rithvik.daylog.app` (KeepAlive, GUI session) | `~/Applications/Daylog.app` |
| MCP | started by each agent client over stdio | registered in Claude Code (user scope) as `daylog` |

## Files

| What | Path |
|---|---|
| Database | `~/Library/Application Support/daylog/daylog.sqlite` |
| Logs | `~/Library/Logs/daylog/server.log`, `app.log` (hotkey presses are logged) |
| Wispr source (read-only) | `~/Library/Application Support/Wispr Flow/flow.sqlite` |

## Build gotchas

- **Use Xcode's toolchain.** The Command Line Tools' SwiftPM can't link package manifests on
  this Mac. The install script sets `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Signing:** the app is signed with a self-signed local identity, **`daylog-local`** (login
  keychain), so macOS keeps permissions across rebuilds. The first build after creating it
  asks for the keychain password; choose **Always Allow**.
- **mcp SDK v2:** `FastMCP` was renamed `MCPServer` (`mcp.server.mcpserver`).

## Testing

- Server: `cd server && uv run pytest`. Tests use a temp DB and a fake clock.
- **App, without touching real data:** run a scratch server on another port, then point a
  copy of the app at it with `DAYLOG_API`:

  ```sh
  DAYLOG_DB=/tmp/scratch.sqlite DAYLOG_IMPORTERS=0 uv run uvicorn daylog.api:app --port 7879
  launchctl bootout gui/$(id -u)/com.rithvik.daylog.app      # pause the real app
  DAYLOG_API=http://127.0.0.1:7879 ~/Applications/Daylog.app/Contents/MacOS/Daylog
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.rithvik.daylog.app.plist
  ```

## Dev mode (⌥D)

Test features without polluting the real log.

| | Real (⌥L) | Dev (⌥D) |
|---|---|---|
| Server | `com.rithvik.daylog.server`, `:7878` | `com.rithvik.daylog.dev`, `:7879` (`DAYLOG_DEV=1`) |
| Database | `daylog.sqlite` | `daylog-dev.sqlite` |
| Importers (Wispr) | on | off |
| Looks | normal | **identical colors** + a `DEV · testing · nothing is logged` tag above the bar |

- The Mac activity recorder always posts to **real**, never to dev.
- ⌥L / ⌥D while the bar is open switches between them; the same key again closes it.
- Wipe dev data: `curl -X POST localhost:7879/dev/reset`. (This route is a 404 on the real
  server.) It'll move into the command menu (RIT-60).
- Agents testing UI changes should use ⌥D, never the real bar.

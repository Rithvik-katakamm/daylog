# Components

Every part of Day Log we work on, by **layer** (taste · ui · ux · product · backend · infra · ai,
defined in Notion "Product & design talk"). One row per component: what it is, where it lives,
its state, and what's still wrong. Update the row in the same commit that changes the component.
Technical work → Linear (team RIT). Product/design questions → Notion.

## UI / UX: the pill

| Component | Layer | What it is | Code | State (Oct 11) | Open problems |
|---|---|---|---|---|---|
| **Notch pill** | ui, ux, taste | The closed bar: a black body hugging the notch, task left, time right | `BarView.bar`, `restRow`, `NotchShape` | Shipped v0.2+. Height = full menu bar (38pt on 14" MBP; notch is 32×185) so it wraps the notch | Covers ~100pt of menu bar each side: hides menu items, feels bolted on. Needs to belong to the menu bar (see Linear) |
| **The drop** | ui, ux | How the pill opens and closes | `BarView.liquid` | v2: widen on the notch, fall down; close reverses | Not smooth yet: blurred glow re-drawn on the CPU each frame. Moving glow to Metal (`gpuLight`) to reach 120 Hz |
| **Neon tube** | ui, taste | The lit outline: bloom, glass, hot core. Says *what* + focus *heat* | `NeonTube` | Shipped v0.3 | Color-layer talk pending (Notion) |
| **Halo** | ui | Substances as one blended glow (high neon green, rose, aqua) | `OuterRings` | Shipped v0.2, green brightened v0.4 | Part of the color talk |
| **Breath** | ui | Slow pulse while closed when something is on | `Breathing` | Shipped | Watch whether it annoys over hours |
| **Text size** | ui, ux | ⌘= / ⌘− / ⌘0 | `fs()`, `Store.resizeText` | Shipped v0.3 | Closed pill ears don't grow with it well |
| **Side ring** | ui | Status ring on the right edge | `SideRing` | Off by default (in the way) | Keep or delete after the UX talk |
| **Monitor mode** | ux, ui | No notch → one row: full title, ▲s, time | `monitorRow`, `placePanel`, `PillScreen` | Shipped v0.6; ⌘K: pill on MacBook / monitor / follow cursor | Style it further (RIT-82) |

## UX: commands

| Component | Layer | What it is | Code | State | Open problems |
|---|---|---|---|---|---|
| **Key commands** | ux | ⌘F focus, ⌘B/⌘⇧B breaks, ⌘G/⌘I/⌘E substances, ⌘N, ⌘O, ⌘K | `handleKey`, `CommandMenu.swift`, `docs/ui/keys.md` | Shipped; now shortcuts, not the main way | — |
| **Typed commands** | ux, backend | Say it: "smoke break", "back", "deep focus", "coffee, high, deep focus" (also via Wispr dictation) | `server/daylog/intents.py`, `/parse`, `/log` | MVP shipped v0.6 (keyword rules, 50+ tests) | Rules miss anything unusual; "coffee" anywhere = caffeinated. Next: a model + eval vs these rules (RIT-78) |
| **Smart capture** | ux, ai | Model-backed: understand anything typed, clean titles, time fixes, juggling | not built (RIT-78, RIT-52) | After living with the MVP | Data shape decided at typing time (data talk, RIT-70) |

## Backend

| Component | Layer | What it is | Code | State | Open problems |
|---|---|---|---|---|---|
| **Event log** | backend | Append-only SQLite, edits as new events | `db.py` | Shipped | — |
| **Substances** | backend | `state.set` events, global | `api.py /state`, `timeline.active_states` | Shipped v0.2 | Old labels contain "high" (data talk, RIT-70) |
| **Breaks** | backend | `break.start`; resumes the task; smoke → high; >1h → ~15 min + ghost | `api.py /break`, `timeline.expire_break` | Shipped v0.2 | Learn real break lengths (Smart capture) |

## Infra

| Component | Layer | What it is | Code | State | Open problems |
|---|---|---|---|---|---|
| **Channels** | infra | Stable (frozen tag) + Dev; for now stable = dev | `scripts/release.sh`, `dev.sh` | Auto-ship each checked build | Building on the Mac he uses: one instance rule; maybe a test user/VM later |
| **Launch agents** | infra | launchd keeps server + app alive | `scripts/lib.sh write_agent` | Idempotent (no repeat "Background Items Added"). App runs as `ProcessType Interactive` (v0.7): unspecified = CPU-throttled, which made stable stutter while Dev was smooth | — |
| **Agent status** | backend, ai | Agents set his status in plain words via MCP `set_status` (source `agent:<name>`); the pill polls every 4s | `mcp_server.py`, `Store.startPolling` | MVP v0.7 | Push instead of poll; agent-set status is a claim *on his behalf*, show it differently? |

## Testing

| Component | Layer | What it is | Code | State | Open problems |
|---|---|---|---|---|---|
| **Server tests** | testing, backend | Unit + API tests for the server | `server/tests/` | 136 pass (Oct 13) | Some tests depend on the clock; two midnight bugs fixed Oct 13 |
| **devctl** | testing | Test remote for the Dev app (no keyboard, no focus) | `tools/devctl.swift`, `AppDelegate` test channel | Shipped; `start`/`stop`/`snap` added Oct 13 | — |
| **Headless Dev** | testing | Dev app off-screen and silent; snapshots of the bar | `Flavor.headless`, `snapshot(name:)`, `Sound.play` | Shipped Oct 13 (default for all tests) | Snapshot may differ from a real window (glow/blur) |
| **Lab VM** | testing, infra | Hidden macOS VM for real-window checks | — | Not set up (his call: when needed) | Costs Mac memory/CPU/disk; one-time setup needs him |
| **CI gate** | testing, infra | GitHub Actions on every push | — | Not set up (RIT-130) | Pain arrives when agents push (RIT-121) |

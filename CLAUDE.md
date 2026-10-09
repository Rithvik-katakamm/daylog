# daylog

A personal time-truth system: **what was Rithvik actually doing, and when?**
Built for Rithvik first. Possible portfolio piece later.

> Status: **v1 shipped 2026-10-09** (`docs/specs/2026-10-09-v1.md`), installed and
> running via launchd. Next: refine from real use. See `README.md` for how it's
> built. Ideation source: Notion → Journal → "2026-10-06 — Agentic Ideation Sticky Pad".
>
> Build note: build Swift with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
> (Command Line Tools SwiftPM can't link manifests on this Mac). `scripts/install.sh`
> sets it.

## The problem

He doesn't know where his time goes ("time is money right now"; 3h went into one
doc today, and nothing recorded it). A calendar is the *plan*; this records the
*actuals*: "what I actually did, not what I wanted to do." Seeing it should let him
build guilt-free ("I was building then, that time was well spent") and give his agents
real context about his day, so Muse stops repeating the same advice blind.

## Shape (agreed so far)

```
CAPTURE (surfaces)        BACKEND (deterministic, no AI)      CONSUMERS (read it)
side button / day view ─▶ local server                    ─▶ MCP server → any agent
phone action button    ─▶  └─ append-only event log        ─▶ Muse (push/pull)
importers (Wispr, Whoop,                                   ─▶ Notion dashboard (maybe)
  calls, Mac activity) ─▶
```

- **The backend is the project.** It starts as a local server plus an append-only
  event log. It's dumb on purpose at the entry point so it stays fast and trustworthy.
  Intelligence gets layered on top later; it never replaces the raw log.
- **Fast, clean, local, or he won't use it.** The bar is Wispr Flow-level latency.
  Dark, minimal, a button on the side of the screen. Clicking it opens a small panel
  with a scrollable day view (not a full window). He drags across a time range to
  say "this is what I was doing."
- **Greedy for ground truth.** If a system of record proves what he was doing, log it
  without asking: a Wispr Notetaker meeting, a phone call, a Whoop workout. Manual
  entries are also ground truth. Inferred activity is a *suggestion* until he
  confirms it.
- **Three kinds of record, never mixed:**
  - *observations*: machine-captured facts (app in front, meeting recorded, workout)
  - *claims*: what he says he did
  - *predictions*: model output with confidence, shown for him to confirm or reject

  His confirmations become labels, which makes the self-improving loop concrete.
- **Tool isolation: daylog never writes to his calendar.** Only Muse schedules,
  because Muse holds the running context of his life. daylog is a capture surface
  and a source of truth; it shows its own day view of actuals.
- **Raw logs stay local.** Notion is the refined, human-facing layer (maybe a life
  dashboard snapshot). Undecided.

## Evolution path (ideation, not a commitment)

1. Dumb log: manual timer, quick "did X for 40m" entry, day view, MCP read access.
2. Importers: Wispr meetings, calls, Whoop, passive Mac activity (apps, tabs).
3. ML: predict labels for unlabeled time from observations, trained on his own
   confirmations. That's a model, not an agent.
4. Agents stay consumers: Muse and others read through MCP and act with judgment.

## Related systems in this workspace

- `workshop/active/capture`: evidence capture (has Wispr/transcript adapters).
- The lake (its own product, multi-consumer, already ingests Whoop). daylog is a
  likely producer and consumer.
- `brain/`: system of record for AI conversations. daylog would be the system of
  record for *time*.

## Working rules

- Explain the *why* of every architectural choice. He wants to understand the build
  well enough to improve it himself (learning HTTP and backend craft through it).
- Commit each slice; push roughly every 2 commits.
- Nothing outward (posts, messages to humans) without his approval.

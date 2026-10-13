# daylog

A personal time-truth system: **what was Rithvik actually doing, and when?**
Built for Rithvik first. Possible portfolio piece later.

> **GOAL OF THIS REPO (his call, Oct 12): get Day Log into the hands of people other than him, and run a
> tight feedback loop.** First target: 5 free outside users for 3+ days, each giving feedback (RIT-109). The
> metric is outside users and feedback conversations per week, not features shipped. Distribution is part of
> the build: an install a stranger can do (RIT-44), the first 5 by hand and in person, build-in-public via Holland
> (nothing posted without his approval). Design means *how it works* (Tanay): judge every slice by whether it
> makes the experience better for someone using it. Ideas parked for later: task launcher (RIT-107).

> **Work is tracked in Linear** (team RIT, project "Day Log"): pick issues there, move
> status as you go. New ideas go to Linear Triage, not into the current issue.
> **Learning goes to Linear Triage too (his rule, Oct 11):** when he says he wants to *learn* or
> *deep dive* into something, file it in Triage with the `learn` flag (+ Type `Spike`, the right
> Area, `agent-filed`). Name the layer of the stack it belongs to, quote what was explained, and
> list a granular learning path. Triage is where he reviews and folds it into what he's learning.
> **Labels:** follow the Linear doc "How we use labels" (team RIT): one Type, at most one
> Area, plus flags, and **always `agent-filed`** on issues you create.
> **Vision lives in `docs/product/vision.md`** (public). Personal context and the original
> vision sources live outside the repo (in the brain: `docs/daylog-private/`).
> Notion is read-only context unless he says otherwise.
> **"Vision note: …"** = append a dated entry (his words) to the Linear document "Vision notes"
> on the Day Log project. Notes are thoughts, not work: promote to a Spike/issue only when
> he decides. Never put vision notes in the public repo verbatim.
> **Docs map: `docs/README.md`** (product / ui / backend / infra). Before adding a key, color
> or sound, update `docs/ui/keys.md`, `colors.md` or `sounds.md` in the same commit.
>
> Status: **first version shipped 2026-10-09**; now building milestone "v1 · Want to use it" (`docs/product/specs/2026-10-09-v1.md`), installed and
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
keyboard bar (⌥L)      ─▶ local server                    ─▶ MCP server → any agent
phone action button    ─▶  └─ append-only event log        ─▶ Muse (push/pull)
importers (Wispr, Whoop,                                   ─▶ Notion dashboard (maybe)
  calls, Mac activity) ─▶
```

- **The backend is the project.** It starts as a local server plus an append-only
  event log. It's dumb on purpose at the entry point so it stays fast and trustworthy.
  Intelligence gets layered on top later; it never replaces the raw log.
- **Fast, clean, local, keyboard-only, or he won't use it.** Wispr Flow-level latency.
  ⌥L drops a black capsule from the top of the screen: one input line whose ring color is
  the mode. No calendar view (dropped Oct 9). An always-on dimmed pill and/or side ring came
  back Oct 11 as a glance (no clicks), switchable in ⌘K. See
  `docs/ui/keys.md` and `docs/ui/colors.md`.
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

1. Dumb log: manual timer, quick "did X for 40m" entry, look back / edit, MCP read access.
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

- **Never disturb the stable app he's using.** Build with `scripts/dev.sh` and test the Dev app
  through `.build/devctl` (no keyboard, no focus). See `docs/infra/install.md`.
- **For now (his call, Oct 11): stable = dev, always.** After a change is built and checked in
  Dev, ship it with `scripts/release.sh <next tag>` without asking. He uses stable and wants its
  real data (messy data gets cleaned in the data talk, RIT-70). Dev is only for messing around.
  This lasts until he says otherwise.
- **Quit the Dev app after testing** (`pkill -f "Daylog Dev.app"`): only one Day Log should ever be
  running on his screen.

- Explain the *why* of every architectural choice. He wants to understand the build
  well enough to improve it himself (learning HTTP and backend craft through it).
- Commit each slice; push roughly every 2 commits.
- **Every commit ends with a `Layer:` trailer** (one or more of: taste, ui, ux, product, backend,
  infra, ai). At the end of the build we join commits with his Day Log blocks to measure hours and
  enjoyment (focus tier, notes) per layer. Layer definitions: Notion "Product & design talk".
- Nothing outward (posts, messages to humans) without his approval.

## Agent Context and Documentation

Handoff as of 2026-10-12, 8 PM. Start here in a fresh session.

- **What to work on:** Linear (team RIT), project Day Log. The order is the issue **priority**:
  In Progress first, then Todo from Urgent down. He keeps a Linear board view "what's next?"
  (Todo / In Progress / Done columns, priority rows). Pull the top card. Don't re-rank or reorganize Linear.
- **Right now (Oct 12 night):** working on branch **`experiment/auto-labeler`**, released to stable as **v0.12**
  (his OK). Main's hand-rolled checkpoint is tag `handrolled-2026-10-12`. Don't merge to main without asking.
  Shipped tonight: RIT-101 stale reset (v0.9), monitor pill (v0.10), RIT-39 cut offer (v0.11), RIT-120 auto-labeler
  v1 (v0.12: `server/daylog/autolabel.py`, knobs in `labels.json`, `/auto`, `/auto/score`, MCP `auto_labels`,
  window title + browser URL capture). First score: category 35%, task 4% (iTerm2 hides the activity).
- **Problem (RIT-116, his framing):** zero-input tracking of his whole day, accurate and reliable; time is the side
  benefit. Narrowed: every Mac minute gets the right label with zero input, scored against what he typed.
- **Next:** RIT-122 (the bar shows its guess; ⏎ confirms, typing corrects = labels: the data flywheel), then
  RIT-121 (Dev-mode feedback → headless Claude Code fixes small things on a branch). The model path (baseline lookup
  table → trees/logistic regression → embeddings → sequence model → active learning) is on RIT-118. He wants a real
  model, not just a lookup table; labels are the bottleneck. Ask him first: did he turn on Accessibility for
  Daylog (window titles)?
- **How he works now:** you write the code (no "core piece he writes" step); cards follow `issue-card/shape.md`
  (build cards short, think cards deep). Keep the Linear In Progress card live and open it on his MacBook. The
  Day Log Map artifact (https://claude.ai/artifact/TLCj9MQKgCzVWsDY2S7Qry) is the visual; update it as things
  ship. Setup feedback → Notion "Build setup feedback (live log)" under Agent Context.
- **Build-first commitment (his, Oct 12):** for 7 days, no system/meta work (no Linear reshuffles, views,
  workflows, skills or research runs). Start in the editor, not Linear. The week's number is *pieces someone
  other than him used*. Context: `~/workspace/brain/records/plans/2026-10-12-founder-pattern-plan.md`.
- **Build loop + learn slices are enforced by hooks** (`.claude/settings.json`, Oct 12):
  `hooks/build-loop.sh` (SessionStart) injects the loop: top Linear issue by priority → state what ships, the
  check that proves it's done, and the core piece *he* writes → ship → next. `hooks/learn-trigger.py`
  (UserPromptSubmit) spots concept gaps ("I don't understand…", "why does…") and attaches the learn-slice
  protocol: name the concept and its layer, teach it in ≤5 sentences from this repo's code, one check question,
  file a Linear Triage `learn` issue related to the build issue, then resume. Triggers are logged to
  `.learning/triggers.jsonl` (gitignored) so we can count learn slices per build slice.
- **Checks:** server tests run with `cd server && uv run pytest -q` (132 passing on Oct 12 night; plain
  `python -m pytest` uses the wrong env). Swift: see the Build note at the top.
- **Day Log data caveat:** label totals before Oct 12 are inflated by stale statuses (RIT-101 fixed it from v0.9).
  Prefer `/auto` (sleep and away are separated) or `computer_active_minutes`.

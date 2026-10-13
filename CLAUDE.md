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
> status as you go. **Don't create new Linear issues (his rule, Oct 13):** knock off the ones that exist and
> modify a card when his build direction changes it, when modification is needed try to fold in the new information into an existing card tastefully only if needed, if this is not possibl ask him how he wants tot handle it. When something isn't on the card, say so in one line
> ("this isn't on the card, and here's how it changes the build") and carry on. When a card is done, move it to
> Done, move the next one to In Progress, and open it in the Linear app on his MacBook.
> **Learning maps to existing learn cards (his rule, Oct 13; replaces Oct 11):** when a build hits a concept,
> use an existing card (Linear project "Learning", or the `learn` label) and comment "pulled by <build issue>".
> Always say "existing card RIT-x" vs "new card"; a new one only when he explicitly asks. Name the layer,
> teach briefly from this repo's code, ask a check question.
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

- **How this build runs (his rule, Oct 13): pain first, lesson second.** The order of work comes from real
  friction while he uses Day Log; each issue solved is a level-up. He's using this project to push what he can
  build and deploy (AI engineering, backend, security), learning by doing.
- **Name the fork in the road.** Whenever a slice reaches a real choice (rules vs model, local vs cloud, where a
  secret lives, data shape), stop and say so in two or three lines: the options, the tradeoff, your pick. Offer a
  short learn on it; he decides whether to stop and learn or keep building. Put the choice on the card.
- **Decide with numbers, not feel (his rule, Oct 13).** Every fork names the metric that settles it and the
  result that would change the decision, written before building (e.g. "LLM only if mode accuracy +X points at
  p95 ≤ Y ms"). Compare options on the same test set; the simple option may win. Day Log's metrics: RIT-131.
- **Check his foundation before moving on.** After a learn, ask one or two check questions in his own code's
  terms; move on when the answers hold.
- **Never disturb the stable app he's using.** Build with `scripts/dev.sh` and test the Dev app
  through `.build/devctl` (no keyboard, no focus). See `docs/infra/install.md`.
- **Test headless, always (his preference, Oct 13).** `devctl start` launches the Dev app off-screen and silent;
  check with the state line and `devctl snap <name>` (PNG in `~/Library/Logs/daylog/snapshots/`); `devctl stop`
  after. Test windows on his screen: target 0. On a real discrepancy (glow, focus, animation), escalate to a hidden
  local macOS VM: say so and ask before setting it up. CI later (RIT-130). See `docs/testing/strategy.md`.
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

Handoff as of 2026-10-13, 2:30 AM. Start here in a fresh session.

- **What to work on:** Linear (team RIT), project Day Log. The order is the issue **priority**:
  In Progress first, then Todo from Urgent down. He keeps a Linear board view "what's next?"
  (Todo / In Progress / Done columns, priority rows). Pull the top card. You may re-rank when a decision changes what's next (his call, Oct 12 night); say what you moved.
- **Right now (Oct 13):** `main` is what he runs (stable **v0.13**). The auto-labeler experiment was merged into
  main on his OK; the hand-rolled checkpoint stays as tag `handrolled-2026-10-12`. Shipped Oct 12–13: RIT-101 stale
  reset (v0.9), monitor pill (v0.10), RIT-39 cut offer (v0.11), RIT-120 auto-labeler v1 (v0.12), RIT-124 what's new
  after a release + owner-only feature flag (v0.13). First score: category 35%, task 4%.
- **Problem (RIT-116, his framing):** zero-input tracking of his whole day, accurate and reliable; time is the side
  benefit. Narrowed: every Mac minute gets the right label with zero input, scored against what he typed.
- **Next (agreed order, RIT-128):** RIT-122 (the bar shows its guess; ⏎ confirms, typing corrects = labels, incl.
  the label data shape) → RIT-125 (what may leave the Mac) → RIT-52 (one parser) → RIT-126 (agent labeler) →
  RIT-127 (sync, when cross-device pain is real). Also queued: RIT-121 (Dev-mode feedback → headless Claude Code fixes small things on a branch). The model path (baseline lookup
  table → trees/logistic regression → embeddings → sequence model → active learning) is on RIT-118. He wants a real
  model, not just a lookup table; labels are the bottleneck. Window titles are captured (Accessibility on since Oct 13).
- **How he works now:** you write the code (no "core piece he writes" step); cards follow `issue-card/shape.md`
  (build cards short, think cards deep). Keep the Linear In Progress card live and open it on his MacBook. The
  Day Log Map artifact (private link on Linear RIT-120) is the visual; update it as things
  ship. Setup feedback → Notion "Build setup feedback (live log)" under Agent Context.
- **Build-first commitment (his, Oct 12):** for 7 days, no system/meta work (no Linear reshuffles, views,
  workflows, skills or research runs). Start in the editor, not Linear. The week's number is *pieces someone
  other than him used*. Context: `~/workspace/brain/records/plans/2026-10-12-founder-pattern-plan.md`.
- **Build loop + learn slices are enforced by hooks** (`.claude/settings.json`, Oct 12):
  `hooks/build-loop.sh` (SessionStart) injects the loop: next Linear card (re-ranking allowed) → state what ships,
  the check that proves it's done, and the layer + components touched → ship → next. Claude writes the code. `hooks/learn-trigger.py`
  (UserPromptSubmit) spots concept gaps ("I don't understand…", "why does…") and attaches the learn-slice
  protocol: name the concept and its layer, teach it in ≤5 sentences from this repo's code, one check question,
  map it to an existing learn card (new only if he asks), then resume. Triggers are logged to
  `.learning/triggers.jsonl` (gitignored) so we can count learn slices per build slice.
- **Checks:** server tests run with `cd server && uv run pytest -q` (133 passing on Oct 13; plain
  `python -m pytest` uses the wrong env). Swift: see the Build note at the top.
- **Day Log data caveat:** label totals before Oct 12 are inflated by stale statuses (RIT-101 fixed it from v0.9).
  Prefer `/auto` (sleep and away are separated) or `computer_active_minutes`.

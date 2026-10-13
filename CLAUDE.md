# daylog

A personal time-truth system: **what was Rithvik actually doing, and when?** A calendar is the plan; this
records the actuals. Vision: `docs/product/vision.md`. How it's built: `README.md`. Docs map: `docs/README.md`.

**Goal of this repo (his call, Oct 12):** get Day Log into the hands of people other than him and run a tight
feedback loop. First target: 5 free outside users for 3+ days, each giving feedback (RIT-109). The metric is
outside users and feedback conversations per week, not features shipped. Judge every slice by whether it makes
the experience better for someone using it.

## Invariants (the build must keep these)

- **The backend is the project:** a local server plus an append-only event log, dumb on purpose at the entry
  point. Intelligence layers on top later; it never replaces the raw log.
- **Three kinds of record, never mixed:** *observations* (machine-captured), *claims* (what he says he did),
  *predictions* (model output with confidence, until he confirms). His confirmations become labels.
- **Greedy for ground truth:** a system of record (Wispr meeting, call, Whoop workout) is logged without asking.
- **Daylog never writes to his calendar.** Only Muse schedules.
- **Raw logs stay local.**
- **Fast, local, keyboard-only.** ⌥L capsule; ring color is the mode. Before adding a key, color or sound,
  update `docs/ui/keys.md`, `colors.md` or `sounds.md` in the same commit.

## Linear (team RIT, project "Day Log")

- **What's next = issue priority:** In Progress first, then Todo from Urgent down. You may re-rank when a
  decision changes what's next; say what you moved.
- **Keep status live:** current card In Progress; on ship move it to Done, the next one to In Progress, and open
  it in the Linear app on his MacBook (`open "linear://rithvik-katakam/issue/RIT-NN"`).
- **Don't create new issues (Oct 13).** Work existing cards; fold changes in his build direction into an
  existing card when needed; if that's not possible, ask him. Off-card work: say "this isn't on the card, and
  here's how it changes the build" in one line and carry on.
- **Learn cards:** map to an existing card (project "Learning" or `learn` label), comment "pulled by <issue>",
  always say "existing card RIT-x" vs "new card"; new only when he asks.
- **Cards follow `issue-card/shape.md`** (build cards short, think cards deep). **Labels:** the Linear doc "How
  we use labels": one Type, at most one Area, flags, and always `agent-filed` on issues you create.
- **"Vision note: …"** = append a dated entry (his words) to the Linear doc "Vision notes". Notes aren't work;
  never put them in the public repo verbatim. Notion is read-only unless he says otherwise.
- The visual is the Day Log Map artifact (private link on RIT-120); update it as things ship. Setup feedback
  goes to Notion "Build setup feedback (live log)" under Agent Context.
- **Full rules + his card feedback:** Notion "Linear Card Management (feedback + rules)" under Agent Context
  (https://app.notion.com/p/3f8a8f2071a581f382bed180b71a169f). Log new card feedback there.

## Working rules

- **Pain first, lesson second (Oct 13).** Work order comes from real friction while he uses Day Log. He's
  using this project to push what he can build and deploy; you write the code, he steers and reviews.
- **Name the fork in the road.** At a real choice (rules vs model, local vs cloud, secrets, data shape): the
  options, the tradeoff, your pick, in 2-3 lines. Offer a short learn; he decides. Put the choice on the card.
- **Decide with numbers (Oct 13).** Every fork names the metric that settles it and the result that would
  change the decision, written before building. Day Log's metrics: RIT-131.
- **Check his foundation:** after a learn, 1-2 check questions in his own code's terms.
- **Explain the why** of every architectural choice; he's learning backend craft through this.
- **Commits:** one per slice, push roughly every 2. Every commit ends with a `Layer:` trailer (taste, ui, ux,
  product, backend, infra, ai); commits get joined with his Day Log blocks to measure hours per layer. A `Try:` line (what to try, shown
  after a release) goes in that same last paragraph with `Layer:`: git only reads trailers from the last paragraph.
- **Nothing outward** (posts, messages to humans) without his approval.
- The build loop and learn-slice protocol are injected by hooks (`.claude/hooks/build-loop.sh`,
  `learn-trigger.py`); triggers log to `.learning/triggers.jsonl`.

## Build, test, ship

- **Swift:** build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Command Line Tools SwiftPM
  can't link manifests on this Mac). `scripts/install.sh` sets it.
- **Server tests:** `cd server && uv run pytest -q` (plain `python -m pytest` uses the wrong env).
- **Never disturb the stable app.** Build with `scripts/dev.sh`; test the Dev app headless through
  `.build/devctl`: `start` (off-screen, silent), state line, `snap <name>` (PNG in
  `~/Library/Logs/daylog/snapshots/`), `stop`. Test windows on his screen: 0. On a real window discrepancy
  (glow, focus, animation), ask before setting up a hidden local macOS VM. See `docs/testing/strategy.md`.
- **Stable = dev, for now (Oct 11):** after a change is checked in Dev, ship with `scripts/release.sh <next tag>`
  without asking. Then quit Dev (`pkill -f "Daylog Dev.app"`): only one Day Log on his screen.
- **Data caveat:** label totals before Oct 12 are inflated by stale statuses (fixed in v0.9). Prefer `/auto` or
  `computer_active_minutes`.

## Where we are

`main` is what he runs; the current stable is the latest `v*` tag. The problem framing is RIT-116: every Mac
minute gets the right label with zero input, scored against what he typed. The agreed order is on RIT-128, the
model path on RIT-118. Build-first week from Oct 12 (no system/meta work unless he asks):
`~/workspace/brain/records/plans/2026-10-12-founder-pattern-plan.md`.

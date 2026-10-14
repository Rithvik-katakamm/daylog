# build-learn (pilot, Day Log only)

Layer: infra → dev infra. How a question he asks mid-build becomes (or doesn't become) a learn, and
how a learn card only closes on proof. Vendored from the build-learn plugin v0.1.0 (Codex, Oct 14),
scoped to this repo for a pilot. If he likes it, it moves to the brain and other repos.

## What runs

| Piece | Where | Job |
|---|---|---|
| Skills | `.claude/skills/build-learn`, `.claude/skills/learning-card-development` | Decide inline / existing card / new card / later / nothing; write a card from the real gap |
| Hooks | `.claude/settings.json` → `runtime.py hook` | Capture prompts, nudge on a question, gate Linear writes, ask for an assessment before a turn ends |
| Ledger | `.learning/build-learn.sqlite3` (gitignored, local) | Append-only events: what he asked, what the agent judged, feedback, permits, outcomes |

**Who writes the ledger:** the hooks write on their own (each prompt, each Linear write). The agent
writes its judgments through `runtime.py` (`assess`, `evidence`, `permit`, `outcome`, `register`).
`status` and `export` read it.

## Day Log changes to the plugin (his calls, Oct 14)

1. **Detector = the old learn-trigger phrase list.** The plugin's bare "how"/"why" flagged 61% of his
   114 prompts (the old list: 51%). Every flag costs an assessment before the turn can end.
2. **Build cards move freely.** No permit for status, priority or text on a build card. Gated: a **new
   card**, and on a **registered learn card** its description or a close (any state outside
   Backlog/Todo/In Progress/Triage/Canceled).
3. **`register`** lists the learn cards the gate protects (seeded Oct 14 from the `learn` label and the
   Learning project). A card linked in an assessment counts too.

The old `.claude/hooks/learn-trigger.py` is gone; `.learning/triggers.jsonl` keeps its history.

## Knobs

| Knob | Default | Where |
|---|---|---|
| Question detector | old learn-trigger phrases | `SIGNAL` in `runtime.py` |
| States that don't count as closing | backlog, todo, in progress, triage, started, canceled | `ACTIVE_STATES` |
| Permit lifetime | 10 min, one use | `hook()` PreToolUse |
| Card review pass | 12/14, no zero, no veto | `act()` card_review |

## How we judge the pilot (written before using it)

Over the next 10 learn moments: at least 7 worth the interruption, at most 2 unwanted, 0 learn cards
closed without his explanation + prediction + a check. More than 2 unwanted → loosen the detector or
pull the Stop gate.

Tests: `cd .claude/build-learn && python3 -m unittest discover -s tests`.

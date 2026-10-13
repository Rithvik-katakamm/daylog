---
name: linear-management
description: Run a build as a loop of Linear build + learn cards for Rithvik. Use when picking the next card, starting or finishing a card, reshaping a card, re-ranking, handling a learn moment, or when he steps away and wants Linear cleaned up for his return.
status: PROPOSED (draft distilled from the Oct 12–13 Day Log sessions; not installed)
---

# Linear management

Linear is his build cockpit. MacBook to one side shows the card he's on; the monitor in front is for work. He
should be able to open his computer and see what he's doing next without asking (Oct 12).

## Config (per repo)

Team, project, Linear workspace slug, the learn project/label, the labels doc, the card-shape doc. For Day Log:
team RIT, project "Day Log", slug `rithvik-katakam`, learn project "Learning" / label `learn`, labels doc "How we
use labels", shape `issue-card/shape.md`.

## Pick the next card

1. In Progress first, then Todo by priority (Urgent down).
2. Re-ranking is allowed when a decision or new evidence changes what's next; say in one line what moved and why
   (Oct 12 night).
3. **Ordering is a real decision, not a list (Oct 12):** decisions branch the build, so order by what unblocks
   the rest. Ask: what can we get to today, what choice can be made today, what's the tomorrow decision, and what
   is actually bottlenecking the experience? Make one-way-ish decisions (data shapes, label formats) before data
   piles up on them; cheap reversible ones can wait (Oct 13).
4. Real friction from using the product outranks the plan: pain first, lesson second (Oct 13).

## Keep status live

- The card being worked is **In Progress**. Never leave a card stale (Oct 12).
- On ship, in one step: card → **Done**, next card → **In Progress**, open it on his MacBook:
  `open "linear://<slug>/issue/RIT-NN"`.
- **One Linear tab open at a time**: the card he's on (Oct 12).
- Before coding, state the slice in three lines: what ships, the check that proves it, the layer + components.

## Layer is first-class (Oct 13)

The layer tag matters to him: it's how he sees which part of the system he's in and how he'll measure hours and
enjoyment per layer (commits carry a `Layer:` trailer, joined with his Day Log blocks).
- Every card names its **Layer** (taste / ui / ux / product / backend / infra / ai, plus testing for docs).
- When telling him what's next, lead with the layer so he knows where in the system he is.
- **Open (data seasoning):** whether layer becomes a Linear label, a field, or stays a card line. Decide when
  there's enough history to see how he actually filters.

## Card hygiene

- **Don't create new issues (Oct 13).** Work existing cards. When his direction changes a card, fold the new
  information into the existing card tastefully, only if needed; if it doesn't fit anywhere, ask him how to
  handle it. Off-card work: "this isn't on the card, and here's how it changes the build", one line, carry on.
- **Shape:** follow the card-shape doc. Build cards stay short so card size never slows the build; they're
  things he and Claude think through together, not one-shot specs. Think cards are deep: principal components,
  real data, prior art, one informed choice, a learn (Oct 12).
- Cards keep him at the right altitude: name the layer, the data, the components (Oct 12).
- Make it visual where it helps: point the card at the system map / diagram for the part being touched (Oct 12).
- Labels: one Type, at most one Area, flags, and always `agent-filed` on anything you create.
- Ideas aren't work: "Vision note: …" goes to the Vision notes doc, promoted only when he decides.

## Learn cards

- Learn only when he asks or is stuck; otherwise keep plowing through build cards (Oct 12).
- Map to an **existing** learn card and comment "pulled by <build card>". Always say "existing card RIT-x" or
  "new card"; create new only when he explicitly asks. Those cards come from his own conversations, which is why
  the alignment holds (Oct 13).
- Teach briefly from the repo's code, then 1-2 check questions; close the learn card only when his answers hold.
- Vary the teaching; he noticed learn replies starting to sound the same (Oct 13).

## When he steps away

"I'm going out for a smoke break, clean this up on Linear" means: reshape and re-rank cards, fold the session's
feedback into existing cards, and have the next card In Progress and open when he's back (Oct 12).

## Eval cases (must pass before installing)

1. Card shipped → it's Done, the next card is In Progress, `open linear://…` ran, one tab.
2. He mentions a new idea mid-build → no new issue; folded into a card or flagged in one line.
3. He says "I don't understand X" → existing learn card named, "pulled by" comment, check question asked.
4. A decision changes the order → priorities moved, one-line reason given.
5. Asked "what's next?" → answer leads with card id, layer, and the three-line slice.
6. Change doesn't fit any card → he's asked; nothing filed.

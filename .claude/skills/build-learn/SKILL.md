---
name: build-learn
description: Use when building in a project with the build-learn ledger, when a question or correction changes a build decision, when choosing or reordering learning work, or when reviewing evidence for a learning card.
---

# Build and learn

Keep the real build and the user's next decision central. The agent writes code;
the user steers, explains, predicts, and tests the experience. Understanding is
specific to a concept and context, never a permanent score about the person.
An older assistant assigning coding homework is not evidence that the user wants
to write the implementation. Follow the current human's chosen role and energy;
do not predict an unannounced change of energy with high confidence.

Read ledger `status` at session start. Read the current build issue and the linked
Notion Linear Card Management rules before tracker changes. In Progress comes
first, then priority. Re-rank when new evidence changes what matters; name why.

For a question, correction, or consequential choice:

1. Start with the actual experience. Locate the relevant layer/component and trace
   one concrete path only as far as the decision needs.
2. Assess the consequence of not understanding, whether the gap is durable, and
   whether it blocks this decision. These are different questions. A definition
   can get a direct answer without a lesson or card. A nonblocking curiosity can wait.
3. Record an `assess` judgment with the exact observation/evidence IDs, build issue,
   concept, reason, worthiness, blocking, and route: `none`, `inline`, `existing`,
   `new`, or `deferred`. The regex flags candidates; you decide meaning. Assess
   consequential gaps even if the detector missed them. Reassess after corrections.
4. Search existing learning work before proposing a new card. Link build ↔ learn;
   say existing versus new. New cards require the user's request. Worthy blocking
   learning comes before the dependent decision; worthy nonblocking work stays
   deferred until chosen. Explain any change to the ranking.
   If a correction changes the concept, search again and check the card's actual
   topic; do not carry the old learning-card link into a different gap.
5. When useful, ask for an explanation or prediction in this code's terms, then
   check the actual running version and outcome. Adapt or skip steps that add no
   value. Stop repeating checks when the user identifies a different gap.

Record evidence, not an impression of mastery. Generated code, green tests,
shipping, agreement, and “got it” do not establish the user's understanding.
Learning completion needs the user's explanation and prediction plus an observed
check tied to this concept. The gate validates references; you must judge their
relevance and adequacy. Build completion is separate.
Resolving a build blocker is also separate from proving understanding. If a factual
check settles the immediate choice, mark blocking false and resume the build even
while the deeper learning card remains open. Do not require mastery just to proceed.

Before a Linear issue write, record a one-use `permit` for the exact tool and input.
For learning-card creation or content revision, use `learning-card-development`;
record the draft and rubric review before the permit. A well-timed bad card is a failure.
Use the appropriate action, not a build label to bypass learning checks. Record the
returned issue identifier in a new assessment after creating a card. See
[runtime reference](reference.md) for commands and coverage limits.

Honor ordinary feedback immediately and append a revised assessment. Explicit
`build-learn feedback ...` records direct feedback; `build-learn skip ...` dismisses
pending checks without claiming understanding. Never turn a skip into a success.
When a new observation corrects an earlier assessment, set `supersedes` to that
assessment ID so its decision and unused permits are retired, not erased.

After an intervention, record `outcome` only when there is subsequent evidence.
Did it improve a choice, prediction, or result? Was the interruption useful? Keep
unknown outcomes unknown. Review corrections and failures before changing policy;
never silently train on agent judgments as ground truth.

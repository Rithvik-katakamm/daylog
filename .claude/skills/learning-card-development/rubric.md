# Card review and tuning

Score each dimension 0 (missing/wrong), 1 (partly useful), 2 (clear and grounded).
Record a brief reason with each score in review artifacts. The ledger accepts the
seven scores plus an overall reason, reviewer identity, and explicit veto list.

| Ledger key | What earns 2 |
|---|---|
| source_fidelity | Quotes, current mechanism, paths/commands trace to supplied evidence; unknowns labeled |
| decision_value | A specific next choice or verification improves; learner's own gap anchors it |
| causal_path | One connected path explains the experience with the right boundary and layer |
| independent_check | Learner predicts/interprets/transfers; key separated; no syntax trivia as a proxy |
| scope | A useful entry is finishable without a whole curriculum; deeper map remains available |
| navigation | Easy to find the question, mechanism, action, check, and optional depth; avoids repetition |
| adaptation | Explicit response to build energy, too-easy/too-hard/wrong-gap feedback |

Initial mechanical publishing gate: at least 12/14, no zero dimension, no veto.
This threshold is a configurable policy hypothesis, not a validated educational scale.
Veto inaccurate mechanism or command, invented learner evidence, an unsafe/unrequested
mutation exercise, or claimed mastery without learner evidence. A numerical score
cannot cancel a veto. A review is an agent judgment and must stay labeled that way.

Compare blind drafts using the same source packet and rubric. Keep source-check
defects separate from style preference. Preserve baseline and failed revisions.
Hold out at least one scenario when tuning. Do not call a regression rerun a holdout.

For actual use, record: did the learner start; did the card address the intended
decision; was the interruption useful; could they explain/predict/check; did a later
decision improve; did a delayed variation transfer? Unknown stays unknown. Completion
and learner time are not automatically positive outcomes. Ask for feedback at a useful
stopping point, not after every tool call. Human feedback overrides an agent's rating.

## Ledger shape

`card_draft`: description (exact Markdown), evidence IDs, experience, decision, path,
exercise, prediction, success, adaptation. Drafting has no external side effect.
`card_review`: draft ID, reviewer, scores (seven keys above), vetoes (list), reason.
`permit`: for learning_create or a learning_update changing description, add the
card_review ID. Input description must exactly equal the reviewed draft. A changed
description requires a new draft and review. No automatic tracker writes.

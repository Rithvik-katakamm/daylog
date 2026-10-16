# Knobs: where to turn the product

His words (Oct 16): "UI is all about knobs … I want to know where my knobs are … turn them, see how it feels."

## The live knobs file

`server/daylog/knobs.json`, read on every pill decision, so a change takes effect on the next one: no
restart, no release. (Edit the copy the running server uses: `~/Library/Application Support/daylog/releases/current/server/daylog/knobs.json`,
or edit the repo's and ship.)

| Knob | Now | What it does | Turn it and you'll see |
|---|---|---|---|
| `word_model` | `qwen2.5-coder:7b` | The model that coins the pill's one word. Same as the look's model = no extra model | `null`: gemma's polished words ("Floating"); coder: playful ones ("DrunkWorkBee", "Geassed") |
| `word_temperature` | 1.0 | How adventurous the word is (0 = safest, ~1.5 = wild) | Higher: stranger, more invented words |
| `display_temperature` | 0.8 | How adventurous the color and reason are | Higher: bolder, more varied colors |
| `display_timeout_s` | 25 | How long a look may take before the pill keeps plain colors | Lower: faster fallbacks; the word model's swap needs ~20 s |

**The memory cost of `word_model`:** on 16 GB, gemma (8.3 GB) and the coder (4.7 GB) can't sit in GPU memory
together, so each look swaps them (8-19 s instead of ~7). Watch ⌘K → MODELS flip between them.

## Knobs in the code (need a release)

| Knob | Where |
|---|---|
| The model for both jobs | `harness.MODEL` (gemma4:12b) |
| The line reader's instructions and examples | `server/daylog/instructions.md`, `harness.EXAMPLES` |
| The display agent's instructions | `server/daylog/display_instructions.md` |
| Fallback colors when the model is off | `app/…/Views.swift` `Theme`, `docs/ui/colors.md` |
| Time rules (night ghost, smoke cap, stale reset) | `server/daylog/timeline.py` constants |

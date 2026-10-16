# The harness: a local model reads what he types

Layer: backend + ai. Code: `server/daylog/harness.py`, wired in `server/daylog/api.py` (`/read`,
`/log`, `/harness`). **Status: live in the bar (Oct 15).** The rules preview instantly; the model's
reading, with its reason, replaces the preview about a second after he pauses typing.

## The shape

```
 typed line ─▶ /read ─▶ "and …" while a task runs?  ──yes──▶ rename it (a rule; no model)
                 │ no
                 ▼
         harness.messages(): instructions + 11 worked examples + "Right now: <what's running>" + the line
                 │  POST Ollama /api/chat · format = the Reading shape (why first) · temperature 0
                 ▼
         Reading(why, mode, task, states, focus, ghost_status)      ← the model only fills this form
                 │
         harness.check(): keep only what the words and the moment support      ← code, not the model
                 │  fails / model down / no answer in time ──▶ the rules (intents.py), as before
                 ▼
         harness.plan() ─▶ the same command code the keys use ─▶ claims; the reading itself is
                                                                  kept as a `line.read` prediction
```

- **No tools, no memory.** The model can't look anything up or act. Each call starts blank: all it
  knows is the prompt (the instructions, the worked examples, what's running now, the line).
- **`why` comes first.** The model writes one sentence on what it understood before it picks a
  mode; the bar shows that sentence next to the preview ("the thinking").
- **The shape is the contract.** Ollama constrains the output to the `Reading` JSON schema and the
  code validates it. Anything outside it means "use the rules", never a crash.
- **Code checks the model (guardrails, `check`).** A substance needs a word for it in the line
  ("drinking coffee" is caffeinated, never intoxicated), and "drinking" with friends adds
  intoxicated even when the model forgets. A break needs a break word. "Back" needs a break or
  ghost to come back from. Rename and continue need something running.
- **Code does what's exact; the model does what's fuzzy.** Times, the database, timers, renames
  and lines with clock times ("3:10-3:25") never go to the model.

## Modes the model can pick

task (start something) · rename (the running task grows or is corrected; same session, same start) ·
continue (nothing changes) · note (a thought, or something that already happened) · feedback (about
Day Log itself; saved as a note "feedback: …") · ghost · break · back · focus · state · stop.

## The bar

- While the model reads: **reading…**. Its reading then replaces the preview with its reason.
- ⏎ waits for the reading (at most 3 s, then the rules); ⇧⏎ never waits.
- Opening the bar warms the model (`POST /harness/warm`): cold it takes ~8 s, warm ~1 s; it stays
  loaded 30 min (`keep_alive`).
- ⌘K → **Demo** shows the model live (`GET /harness`: busy line, last 20 readings with
  reason, time, whether code overruled it, whether it was applied), every pill state, and a try-a-line box.

## Knobs

| Knob | Default | Where |
|---|---|---|
| Which local model | `qwen2.5-coder:7b` | `harness.MODEL` |
| Give up and use the rules after (server) | 10 s | `harness.TIMEOUT_S` |
| ⏎ waits for the reading at most | 3 s | `Store.submit` (app) |
| Pause before asking the model | 350 ms | `Store.schedulePreview` (app) |
| Keep the model loaded | 30 min | `keep_alive` in `read_line` / `warm` |
| Same line, same answer | temperature 0 | `read_line` |
| Reason at length before answering | off (`think: false`) | `read_line` |

## Measured (Oct 15, M2 Pro 16 GB)

**His 45 real lines** (`server/eval/lines.local.jsonl`, on his Mac only; labeled by the agent, for
him to review). Right = an accepted mode and exactly the right substances. `cd server && uv run python eval/run.py <models>`.

| Reader | Right | Median / p95 time |
|---|---|---|
| rules (`intents.py`) | 23/45 (51%) | instant |
| **qwen2.5-coder:7b** | **36/45 (80%)** | **1.0 / 1.5 s** |
| gemma4:12b | 37/45 (82%) | 2.5 / 3.8 s |
| qwen3.5:9b | 33/45 (73%) | 3.7 / 4.2 s |

His Oct 13 bar for a model: ≥80% at p95 ≤ 1.5 s. qwen2.5-coder meets it; gemma4 is one line better
but too slow for the bar. Still missed: "took a nap now deep in the harness" (read as a break; the
guardrail stops it, the rules make it a task), feelings read as tasks, past events read as renames.

Earlier smoke test on the 5 card lines: rules 1/5, llama3.2:3b 1/5, qwen2.5-coder:7b 4/5,
qwen3.5:4b 2/5, qwen3.5:9b 1/5, gemma4:12b 4/5; gpt-oss:20b didn't load (removed).

## Next

1. **Memory:** his fixes become worked examples (the prompt grows from his own corrections).
2. **Past events:** "took a nap", "was doing laundry" become a block in the past, not a note.

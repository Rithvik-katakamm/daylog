# The harness: a local model reads what he types

Layer: backend + ai. Code: `server/daylog/harness.py`. **Status: wired into the bar (Oct 15).** The rules
preview instantly; the model's reading replaces it about a second after he pauses typing.

## The shape

```
 typed line ──▶ harness.messages()                     ┌── the model (Ollama, on the Mac)
               system: what each mode means            │   reads the messy part:
               examples: his past corrections ─────────┤   what he meant
               the new line                            │
                        │  POST /api/chat, format = the Reading shape, temperature 0
                        ▼                              │
               Reading.model_validate_json() ◀─────────┘
                        │
            fits the shape? ──yes──▶ Reading(mode, task, states, focus, ghost_status)
                        │
                        no / model down / too slow ──▶ None → use the rules (intents.py)
```

- **The model remembers nothing between calls.** Everything it knows about him rides in the
  prompt: the examples are the harness's memory (step 2 reads them from the event log).
- **The shape is the contract.** Ollama constrains the output to the `Reading` JSON schema, and
  the code still validates it. Anything outside the shape means "use the rules", never a crash.
- **Code does what's exact; the model does what's fuzzy.** Times, the database, timers and
  checking the answer stay in code.

## Knobs

| Knob | Default | Where |
|---|---|---|
| Which local model | `qwen2.5-coder:7b` (best accuracy for its speed on Oct 15) | `MODEL` |
| Give up and use the rules after | 10 s | `TIMEOUT_S` |
| Same line, same answer | temperature 0 | `read_line` |
| Reason before answering | off (`think: false`): the bar can't wait | `read_line` |

## Step 1 result (Oct 15, M2 Pro 16 GB, the 5 lines in `tests/test_intents.py`'s spirit)

| Reader | Right | Median / max time |
|---|---|---|
| rules (`intents.py`) | 1/5 | ~0 ms |
| llama3.2:3b | 1/5 | 573 / 1324 ms |
| **qwen2.5-coder:7b** | **4/5** | **982 / 2521 ms** |
| qwen3.5:4b | 2/5 | 2103 / 3173 ms |
| qwen3.5:9b | 1/5 | 2929 / 4801 ms |
| gemma4:12b | 4/5 | 3831 / 6996 ms |
| gpt-oss:20b | didn't load (old download; removed) | — |

Newer and bigger wasn't better: gemma4 matches qwen2.5-coder but is ~4x slower, and qwen3.5
copied the prompt's own example ("Working on Day Log") onto lines that weren't about Day Log.
Every model but one dropped *intoxicated* from "drinking with friends".

Five lines is a smoke test, not an eval. Step 3 scores readers on his real lines, labeled by him.

## Steps

1. **A model reads one line into a fixed shape** (done).
2. **The bar** (done, his pick to do it before memory and eval: feel it first). `GET /read` asks the
   model in a background thread; the bar shows its reading marked "read by the model"; ⏎ applies it
   through the same command code as the keys (`harness.plan` → `api._run`), and the reading is kept as
   a `line.read` prediction. ⏎ before the reading arrives, a line with times, or no model: the rules.
3. **Memory:** his past corrections from the event log become the prompt's examples.
4. **Eval:** rules vs models on his labeled lines, accuracy plus p95 time, bar set before measuring.

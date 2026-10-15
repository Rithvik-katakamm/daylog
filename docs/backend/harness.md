# The harness: a local model reads what he types

Layer: backend + ai. Code: `server/daylog/harness.py`. **Status: step 1 of 4, not wired into the
bar yet.** The bar still uses the rules in `intents.py`.

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
| Which local model | `llama3.2:3b` (step 1 data says `qwen2.5-coder:7b` reads better) | `MODEL` |
| Give up and use the rules after | 10 s | `TIMEOUT_S` |
| Same line, same answer | temperature 0 | `read_line` |

## Step 1 result (Oct 15, M2 Pro 16 GB, the 5 lines in `tests/test_intents.py`'s spirit)

| Reader | Right | Median / max time |
|---|---|---|
| rules (`intents.py`) | 1/5 | ~0 ms |
| llama3.2:3b | 1/5 | 779 / 1307 ms |
| qwen2.5-coder:7b | 4/5 | 959 / 2522 ms |
| gpt-oss:20b | didn't load (old download; this Ollama can't run it) | — |

Five lines is a smoke test, not an eval. Step 3 scores readers on his real lines, labeled by him.

## Steps

1. **A model reads one line into a fixed shape** (done).
2. **Memory:** his past corrections from the event log become the prompt's examples.
3. **Eval:** rules vs models on his labeled lines, accuracy plus p95 time, bar set before measuring.
4. **The bar:** rules preview instantly; the model's reading follows in the background.

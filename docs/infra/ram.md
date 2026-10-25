# The RAM problem (infra → machine resources)

**Thesis:** Day Log's models don't run inside Day Log. They run in Ollama, on the same 16 GB Mac as
everything else he uses. When both of Day Log's models are in play, Ollama keeps swapping them in
and out, memory runs out, and the whole Mac freezes. Day Log's own numbers don't show it, because
the memory is counted under Ollama.

## Vocabulary

| Word | Means |
|---|---|
| **Ollama** | The local model server on `localhost:11434`. Day Log sends it text; it runs the model |
| **llama-server** | Ollama's worker process that actually holds a loaded model. This is where the GBs live |
| **Load / evict** | Ollama reading a model from disk into memory / throwing it out to make room |
| **keep_alive** | How long Ollama keeps a model loaded after the last request |
| **Swap** | macOS writing memory to disk when RAM is full. Once swap fills, apps stall |
| **The RAM problem** | His name (Oct 25) for all of the above |

## How it works and why

| Piece | Model | Size on disk | keep_alive |
|---|---|---|---|
| Line reader (`server/daylog/harness.py`, `MODEL`) | gemma4:12b | 8.0 GB | 30 min |
| Pill word (`knobs.json` → `word_model`) | qwen2.5-coder:7b | 4.7 GB | 5 min |

1. Both models together (~13 GB loaded) don't fit beside macOS, Claude Code sessions (~3.5 GB) and
   apps on 16 GB. macOS gives the GPU roughly two-thirds of RAM.
2. So each time the other job runs, Ollama evicts one model and loads the other. That's the
   "models flip in ⌘K → MODELS" swap that [`backend/knobs.md`](../backend/knobs.md) already notes.
3. The 30-minute keep_alive means the big model stays resident long after Day Log is done with it.
4. Day Log's dashboard and Activity Monitor show Day Log as light, because the GBs sit in Ollama's
   `llama-server`, not in the Day Log app or server.

**Evidence (Ollama server logs, `~/.ollama/logs/`):**

| Measure | Value |
|---|---|
| Loads of gemma4:12b, Oct 15–25 | 259 |
| Loads of qwen2.5-coder:7b, Oct 15–25 | 254 |
| Loads of every other model | 13 |
| Oct 21, 1:50 PM: system memory free | 1.6 GiB of 16, Ollama logs "exceed available memory, evicting" |
| Oct 21 checkup: `llama-server` alone | 9.5 GB; swap 5.0 of 6 GB used |

Two near-equal load counts mean the two models take turns, not that one stays loaded.

## Knobs / rules

| Knob | Now | Effect of changing it |
|---|---|---|
| `word_model` (knobs.json, live) | qwen2.5-coder:7b | `null` = gemma makes the word too: no swapping, words get more polished and less playful |
| `harness.MODEL` (code, needs a release) | gemma4:12b | A ~4B model (~3.5 GB) would leave room for everything else; needs an eval that it reads notes as well |
| `keep_alive` in `harness.py` / `display.py` | 30m / 5m–30m | Shorter (2m) gives memory back sooner; the cost is a cold load (~6–8 s) after a pause |
| Rule | One model at a time on 16 GB | Two 7B+ models together always evict each other here |

## History

- Oct 16: one model for both jobs chosen because two 7–9B models don't fit (see `backend/display.md`).
  `word_model` later set to the coder for playful words, bringing back the swap.
- Oct 21: Mac froze (windows wouldn't close, forced shutdown the night before). Checkup found
  `llama-server` at 9.5 GB and swap nearly full; quitting Ollama took free memory from 13% to 81%.
- Oct 25: traced to Day Log's two models through the Ollama logs. Named "the RAM problem". Open:
  pick one model for both jobs, and/or a shorter keep_alive. His call; nothing changed yet.

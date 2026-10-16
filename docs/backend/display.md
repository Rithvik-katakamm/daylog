# The display agent: how the pill looks

Layer: ai + ui. Code: `server/daylog/display.py`, instructions `server/daylog/display_instructions.md`,
wired in `/now` (`server/daylog/api.py`) and the bar's `Theme.statusColor` (`app/…/Views.swift`).
**Status: live (Oct 16).** His call: "get an agent to pick a color for every status … no rules."

## What it does

For whatever is on the pill (a task, ghost, a break, idle, plus focus and substances) a local model
picks **one word** and **a color** for the pill and ring, and says **why**. Code only enforces the
shape: one word of letters (≤12), a `#RRGGBB` color. It never changes what's logged.

```
status changes ─▶ /now: no look for this status yet ─▶ "thinking" (violet, pill) + agent starts in background
                                                         │ PydanticAI Agent · NativeOutput(Display) · qwen2.5-coder:7b
                                                         ▼ ~1.5-2 s
                 /now: {word, color, why} ─▶ pill shows the word, pill + ring + bar take the color
                         └─▶ kept as a `display.choice` prediction (its behavior over time)
                         └─▶ OpenTelemetry spans ─▶ ~/Library/Logs/daylog/traces.jsonl (local)
```

- **It looks again on its own schedule (Oct 16):** with each pick it also says `recheck_minutes` (5-120),
  and it's told the time of day. When that time passes it decides again by itself (`again: true`), so the
  word and color can change as the day moves on without him doing anything. The old look stays up until
  the new one is in. A new status always decides at once. First picks: a walk → 15 min, idle → 60, work → 30.
- **Model down or slow (8 s):** the plain theme colors and the title stay.
- **The bar polls every 0.5 s while it thinks**, every 4 s otherwise.

First real picks: config cleanup → "ConfigClean" #9048FF; Code Geass ghost → "CodeGeass" #FF6347;
idle → "Empty" #39FF14.

**What it reads (Oct 16):** the status, the time of day, and what he wrote since the status began (his
typed lines and notes, newest last, put first in the message). A creative word for what he's doing now,
never "Working", and his latest words outweigh the task's old title.

## Which model, and the 16 GB limit (Oct 16)

Same model as the line reader: gemma4:12b since v0.45 (qwen2.5-coder:7b before). qwen3.5:9b read his notes' mood better ("fried" → Frying,
"locked in, music on" → FlowState; the 7B gave Backend, Progressing), but **two 7-9B models don't fit in GPU
memory together on a 16 GB Mac** (macOS gives the GPU roughly two-thirds of RAM): loading the 9B evicted the 7B,
so each would cold-load (~6-8 s) every time the other ran. One model at a time, until a smaller one reads notes
as well (an eval decides). Thinking models need `reasoning_effort: none` through PydanticAI, or they time out.

## Why PydanticAI, and not LangGraph or LangChain

| Library | What it is for | Here |
|---|---|---|
| **PydanticAI** | One agent: instructions + (optional) tools + a **typed output** you define as a Pydantic model; swap the model in one line (Ollama now, Claude later). | **Used.** The decision is one call with a fixed shape: exactly its job. |
| **LangGraph** | A **graph** of steps with saved state: loops, branches, several agents, a human approval step, resuming after a crash. | Not yet. One decision per status is not a graph. It earns its place when a feature needs several steps that remember (e.g. memory: read history → decide → ask him → learn). |
| **LangChain** | A large kit of wrappers (models, retrievers, document loaders, chains). | Not used. Nothing here needs its parts, and its layers hide what the model actually sees. |
| **Langfuse** | A place to **look at traces**: every model call with input, output, time, cost, scores; and evals over them. | Later. Today the spans go to a local file in the OpenTelemetry format; Langfuse (self-hosted in Docker) can read that same format when he wants a UI. |
| **OpenTelemetry** | The standard **format** for traces (what happened, when, how long, nested). | Used. PydanticAI emits it (`Agent.instrument_all`), so any viewer can read it later. |

**Output mode matters on a small model.** PydanticAI can return the shape by asking the model to call a
fake "tool" (default) or by constraining the JSON directly (`NativeOutput`). On qwen2.5-coder:7b the
tool route failed 4/4; native worked 4/4 in ~1-1.6 s (probe, Oct 16).

## Knobs

| Knob | Default | Where |
|---|---|---|
| Model | `harness.MODEL` (qwen2.5-coder:7b, already warm) | `display.MODEL` |
| Give up after | 8 s | `display.TIMEOUT_S` |
| What it's told | the whole instruction text | `display_instructions.md` |
| Traces file | `~/Library/Logs/daylog/traces.jsonl` | `DAYLOG_TRACES` |
| Poll while thinking | 0.5 s | `Store.startPolling` |

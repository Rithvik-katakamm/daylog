# Observability: what caused that?

Layer: infra + ai. Code: `server/daylog/telemetry.py` (setup), spans in `server/daylog/api.py`,
reader `server/daylog/why.py`. **Status: live (Oct 16).** His ask: "set up a system so you can just answer
that question in one go: this is the chain of events that caused that behavior."

## The idea

A **trace** is one thing's whole story; each step inside is a **span** (start, end, what it read or
decided). Spans nest, so the story reads top-down. This is OpenTelemetry, the standard format; PydanticAI
writes its own model-call spans into the same trace.

```
⏎ line "building daylog, doing linkedin posts too"         7.4 s
  · decided_by: model            (or: rules, the model didn't answer in time · rule: and…)
  line reader (gemma4:12b)                                  6.9 s
    · model_said: {"why": …, "mode": "rename", "tasks": [...], …}
    · kept: rename               (what the guardrails let through)
  ! skipped: break — "already on a break"
pill look                                                   6.6 s
  · trigger: a new status or something he wrote · its own recheck
  · decided: Surging #FF3399 · He is pushing through …
  model call (chat gemma4:12b)                              6.6 s
```

## How to read it

```sh
cd server && uv run python -m daylog.why       # the last 5 stories
cd server && uv run python -m daylog.why 12    # the last 12
```

The ⌘K panel's **LAST STATUS** shows the newest line: what it did, ⏎ → pill (end to end), how long the
server took, and how long the look took.

## Where it lives

`~/Library/Logs/daylog/traces.jsonl` (local only; `DAYLOG_TRACES` to move it). Langfuse self-hosted, or any
OpenTelemetry viewer, can read the same spans when he wants a timeline UI.

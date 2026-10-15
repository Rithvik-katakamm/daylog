"""Harness v0: a local model reads one typed line and says what it means.

The harness is the code around the model. It builds the prompt (with his past corrections as
examples), asks for one fixed JSON shape, checks the answer, and returns None when the model is
down or answers in the wrong shape, so the caller falls back to the rules in intents.py. The
model only does the fuzzy part: reading what he meant from how he actually types.

A model call remembers nothing. Everything it knows about him is what this prompt carries.
"""

from __future__ import annotations

import time
from typing import Literal, Sequence

import httpx
from pydantic import BaseModel, Field, ValidationError

OLLAMA = "http://localhost:11434"   # Ollama's local server; nothing leaves the Mac
MODEL = "qwen2.5-coder:7b"          # knob: which local model reads the line (best of 5 on Oct 15)
TIMEOUT_S = 10.0                    # knob: give up and fall back to the rules after this

Mode = Literal["task", "note", "ghost", "break", "back", "focus", "state", "stop"]
State = Literal["high", "intoxicated", "caffeinated"]


class StateChange(BaseModel):
    state: State
    on: bool


class Reading(BaseModel):
    """What one typed line means. This shape is the contract between the model and the code."""
    mode: Mode
    task: str | None = None              # a clean, short title when mode is task
    states: list[StateChange] = []       # substances mentioned anywhere in the line
    focus: int | None = Field(None, ge=0, le=3)  # 1 focused, 2 deep, 3 hyperfocus, 0 off
    ghost_status: str | None = None      # what he's doing off the clock, when mode is ghost


SYSTEM = """You read one line Rithvik typed into Day Log, his time tracker, and say what it means.

Pick ONE mode:
- task: he is starting or doing something. Put a short clean title in "task" (fix typos, drop
  feelings and substances: "wokring on daylog, little high" -> "Working on Day Log").
- note: a thought or feeling about right now, not a new activity.
- ghost: off the clock: hanging out, watching a show, drinking with friends. Put what he's
  doing in "ghost_status".
- break: stepping away briefly (walk, smoke, bathroom).
- back: he's back from a break.
- focus: the line is only about how focused he is.
- state: the line is only about substances.
- stop: he's done; stop the timer.

In any mode, also fill:
- "states": every substance he mentions: high (high, stoned, baked), intoxicated (drunk,
  tipsy, drinking), caffeinated (coffee, espresso). on=false if he says he's not anymore.
- "focus": 1 focused / locked in, 2 deep focus, 3 hyperfocus or in the zone, 0 lost focus.
  Leave it null if he doesn't mention focus.

Answer with JSON only."""


def messages(line: str, examples: Sequence[tuple[str, Reading]] = ()) -> list[dict]:
    """The whole prompt: instructions, then his past corrections as solved examples, then the
    new line. The examples are the harness's memory of him (step 2 reads them from the DB)."""
    msgs = [{"role": "system", "content": SYSTEM}]
    for text, reading in examples:
        msgs.append({"role": "user", "content": text})
        msgs.append({"role": "assistant", "content": reading.model_dump_json(exclude_none=True)})
    msgs.append({"role": "user", "content": line})
    return msgs


def read_line(line: str, examples: Sequence[tuple[str, Reading]] = (), model: str = MODEL,
              client: httpx.Client | None = None) -> tuple[Reading | None, float]:
    """Ask the local model what `line` means. Returns (reading or None, milliseconds).
    None means: the model was unreachable, slow, or broke the contract; use the rules."""
    body = {
        "model": model,
        "messages": messages(line, examples),
        "format": Reading.model_json_schema(),   # Ollama constrains the output to this shape
        "stream": False,
        "think": False,                          # models that reason first (qwen3.5) answer directly
        "options": {"temperature": 0},           # same line in, same answer out
    }
    started = time.perf_counter()
    try:
        with (client or httpx.Client(base_url=OLLAMA, timeout=TIMEOUT_S)) as c:
            r = c.post("/api/chat", json=body)
            r.raise_for_status()
            reading = Reading.model_validate_json(r.json()["message"]["content"])
    except (httpx.HTTPError, KeyError, ValueError, ValidationError):
        reading = None
    return reading, (time.perf_counter() - started) * 1000

"""The display agent: decides how the pill looks for whatever is on it right now.

For each status (a task, ghost, a break, nothing running, plus focus and substances) a local model
picks ONE word and a color for the pill and ring, and says why. No rules decide the look (his call,
Oct 16): the model chooses; code only enforces the shape (one word of letters, a #RRGGBB color). It
never writes what he did: it only changes how the bar looks. Its choices are kept as predictions so
its behavior can be watched over time.

Built with PydanticAI (one agent, typed output) and traced with OpenTelemetry. Why these and not
LangGraph or LangChain: see docs/backend/display.md.
"""

from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

from pydantic import BaseModel, Field
from pydantic_ai import Agent, ModelRetry, NativeOutput, RunContext
from pydantic_ai.models.instrumented import InstrumentationSettings
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.ollama import OllamaProvider

from . import harness, telemetry

os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")

# knob: the same model as the line reader. On 16 GB only one 7-9B model fits in GPU memory at a time: a second
# one (qwen3.5:9b read notes best) evicts the first, and every line then waits for a cold load (Oct 16).
MODEL = harness.MODEL
TIMEOUT_S = 12.0               # knob: give up after this; the pill keeps its plain colors


class Display(BaseModel):
    """What the pill shows. `why` first: the model says what the status is before it picks."""
    why: str = Field(description="one short sentence: what this status is about", max_length=200)
    word: str = Field(description="ONE word, letters only, at most 12, for a tiny pill",
                      pattern=r"^[A-Za-z]{1,12}$")
    color: str = Field(description="a hex color like #8B7BFF that fits the status",
                       pattern=r"^#[0-9A-Fa-f]{6}$")
    recheck_minutes: int = Field(30, ge=5, le=120,
                                 description="how many minutes until you want to look at this status again")


INSTRUCTIONS = re.sub(r"<!--.*?-->\s*", "", Path(__file__).with_name("display_instructions.md").read_text(),
                      flags=re.S).strip()


def describe(state: dict) -> str:
    """The status in words, the only thing the agent sees (with the time of day: late night matters)."""
    from datetime import datetime
    parts = [datetime.now().astimezone().strftime("it's %-I:%M %p on %A")]
    if state.get("on_break"):
        b = state["on_break"]
        parts.append(f'on a {b["label"]} for {b.get("elapsed_minutes", 0)} min'
                     + (f', then back to "{b["resume"]}"' if b.get("resume") else ""))
    elif state.get("ghost"):
        g = state["ghost"]
        parts.append(f'off the clock (ghost): "{g["status"]}" for {g.get("elapsed_minutes", 0)} min')
    elif state.get("timer"):
        t = state["timer"]
        mins = t.get("elapsed_minutes", 0)
        parts.append(f'doing "{t["label"]}"' + (f" for {mins} min" if mins else ", just started"))
        if t.get("focus"):
            parts.append(["", "focused", "in deep focus", "in hyperfocus"][t["focus"]])
    else:
        parts.append("nothing running")
    states = [s["state"] for s in state.get("states") or []]
    if states:
        parts.append("also " + " and ".join(states))
    notes = [n["text"] for n in state.get("notes") or []]
    if notes:   # his own words come first: a small model weighs the start of the message most
        said = " / ".join(f'"{t}"' for t in notes)
        return f"He just wrote: {said}. That's how it's going right now. Status: " + ", ".join(parts)
    return ", ".join(parts)


def key(state: dict) -> str:
    """What makes a status 'the same' (time passing doesn't): decide once per status."""
    t, g, b = state.get("timer") or {}, state.get("ghost") or {}, state.get("on_break") or {}
    notes = state.get("notes") or []
    return json.dumps([t.get("id"), t.get("label"), t.get("focus"), g.get("id"), g.get("status"),
                       b.get("id"), sorted(s["state"] for s in state.get("states") or []),
                       notes[-1]["id"] if notes else None])   # a new note = a new look


KNOBS = Path(__file__).with_name("knobs.json")


def knob(name: str, default):
    """A knob from knobs.json, read fresh each time so turning it takes effect on the next decision."""
    try:
        return json.loads(KNOBS.read_text()).get(name, default)
    except (OSError, ValueError):
        return default


async def _coin_word(state: dict, model: str) -> tuple[str | None, float]:
    """The word model's one job (his experiment, Oct 16): coin the pill's word, playfully, like "WorkTrix".
    It sees the raw status and his own words, never the look model's reading (his design, Oct 16: "both
    models see raw input, but the things they do are different"), so one model's framing can't steer the other.
    A second model can't sit in memory beside the first on 16 GB, so this swaps it in (slower)."""
    import httpx
    started = time.perf_counter()
    body = {"model": model, "stream": False, "think": False, "keep_alive": "5m",
            "options": {"temperature": float(knob("word_temperature", 1.0))},
            "format": {"type": "object", "properties": {"word": {"type": "string", "pattern": "^[A-Za-z]{1,12}$"}},
                       "required": ["word"]},
            "messages": [{"role": "system", "content": WORD_INSTRUCTIONS},
                         {"role": "user", "content": f"Status: {describe(state)}"}]}
    try:
        async with httpx.AsyncClient(base_url=harness.OLLAMA, timeout=TIMEOUT_S) as c:
            r = await c.post("/api/chat", json=body)
            word = json.loads(r.json()["message"]["content"])["word"]
        word = word if re.fullmatch(r"[A-Za-z]{1,12}", word or "") else None
    except Exception:
        word = None
    return word, (time.perf_counter() - started) * 1000


WORD_INSTRUCTIONS = ("Coin ONE word (letters only, at most 12) for a tiny status pill on a Mac. Be playful and "
                     "inventive: mash words together or invent one, like WorkTrix, Geassed, TeslaWatch. The word is "
                     "about what he's DOING, at work or off the clock (watching, savoring, unwinding count as much "
                     "as building). Substances are a flavor, never the word, unless taking one is the whole "
                     "activity. Never Working or Idle. Answer as JSON.")


_agent: Agent | None = None
_IDLE_WORDS = {"idle", "empty", "nothing", "none", "blank", "rest", "void", "waiting"}


def _get_agent() -> Agent:
    global _agent
    if _agent is None:
        model = OpenAIChatModel(MODEL, provider=OllamaProvider(base_url=f"{harness.OLLAMA}/v1"))
        # reasoning_effort none: qwen3.5 thinks at length by default, which ran past the timeout every time.
        _agent = Agent(model, output_type=NativeOutput(Display), instructions=INSTRUCTIONS, retries=1,
                       name="display", deps_type=bool,
                       model_settings={"extra_body": {"reasoning_effort": "none", "keep_alive": "30m"}})

        @_agent.output_validator
        def _alive(ctx: RunContext[bool], out: Display) -> Display:
            # deps = "nothing is running". Something running is never idle: the model is told why and
            # decides again itself (PydanticAI sends this message back as a retry). Not a rule picking the look.
            if not ctx.deps and out.word.lower() in _IDLE_WORDS:
                raise ModelRetry(f'"{out.word}" says nothing is happening, but something is running. '
                                 "Pick a word for what it is.")
            return out
        Agent.instrument_all(InstrumentationSettings(tracer_provider=telemetry.PROVIDER))  # nests in the look's trace
    return _agent


async def decide(state: dict) -> tuple[Display | None, float]:
    """Ask the agent how this status should look. (choice or None, milliseconds)."""
    import asyncio
    started = time.perf_counter()
    try:
        idle = not (state.get("timer") or state.get("ghost") or state.get("on_break"))
        result = await asyncio.wait_for(
            _get_agent().run(f"Status: {describe(state)}", deps=idle,
                             model_settings={"temperature": float(knob("display_temperature", 0.8))}),
            timeout=float(knob("display_timeout_s", TIMEOUT_S)))
        choice = result.output
        word_model = knob("word_model", None)
        if word_model and word_model != MODEL:   # the experiment: another model coins the word
            from . import telemetry
            with telemetry.tracer.start_as_current_span("word") as sp:
                word, wms = await _coin_word(state, word_model)
                sp.set_attribute("model", word_model)
                sp.set_attribute("coined", word or f"nothing; kept {choice.word}")
            if word and (idle or word.lower() not in _IDLE_WORDS):
                choice = choice.model_copy(update={"word": word})
    except Exception:   # model down, too slow, or broke the shape twice: plain colors stay
        choice = None
    return choice, (time.perf_counter() - started) * 1000

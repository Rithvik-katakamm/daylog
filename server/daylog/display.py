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
from pydantic_ai import Agent, NativeOutput
from pydantic_ai.models.instrumented import InstrumentationSettings
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.ollama import OllamaProvider

from . import harness

os.environ.setdefault("PYDANTIC_AI_NO_BANNER", "1")

MODEL = harness.MODEL          # knob: the same local model as the line reader (already warm)
TIMEOUT_S = 8.0                # knob: give up after this; the pill keeps its plain colors
TRACES = Path(os.environ.get("DAYLOG_TRACES", Path.home() / "Library/Logs/daylog/traces.jsonl"))


class Display(BaseModel):
    """What the pill shows. `why` first: the model says what the status is before it picks."""
    why: str = Field(description="one short sentence: what this status is about", max_length=200)
    word: str = Field(description="ONE word, letters only, at most 12, for a tiny pill",
                      pattern=r"^[A-Za-z]{1,12}$")
    color: str = Field(description="a hex color like #8B7BFF that fits the status",
                       pattern=r"^#[0-9A-Fa-f]{6}$")


INSTRUCTIONS = re.sub(r"<!--.*?-->\s*", "", Path(__file__).with_name("display_instructions.md").read_text(),
                      flags=re.S).strip()


def describe(state: dict) -> str:
    """The status in words, the only thing the agent sees."""
    parts = []
    if state.get("on_break"):
        b = state["on_break"]
        parts.append(f'on a {b["label"]} for {b.get("elapsed_minutes", 0)} min'
                     + (f', then back to "{b["resume"]}"' if b.get("resume") else ""))
    elif state.get("ghost"):
        g = state["ghost"]
        parts.append(f'off the clock (ghost): "{g["status"]}" for {g.get("elapsed_minutes", 0)} min')
    elif state.get("timer"):
        t = state["timer"]
        parts.append(f'working on "{t["label"]}" for {t.get("elapsed_minutes", 0)} min')
        if t.get("focus"):
            parts.append(["", "focused", "in deep focus", "in hyperfocus"][t["focus"]])
    else:
        parts.append("nothing running: idle")
    states = [s["state"] for s in state.get("states") or []]
    if states:
        parts.append("also " + " and ".join(states))
    return ", ".join(parts)


def key(state: dict) -> str:
    """What makes a status 'the same' (time passing doesn't): decide once per status."""
    t, g, b = state.get("timer") or {}, state.get("ghost") or {}, state.get("on_break") or {}
    return json.dumps([t.get("id"), t.get("label"), t.get("focus"), g.get("id"), g.get("status"),
                       b.get("id"), sorted(s["state"] for s in state.get("states") or [])])


class _FileExporter:
    """OpenTelemetry spans as JSON lines in a local file (raw logs stay local). Langfuse or any
    OpenTelemetry backend can read the same spans later; nothing leaves the Mac."""

    def export(self, spans):
        from opentelemetry.sdk.trace.export import SpanExportResult
        TRACES.parent.mkdir(parents=True, exist_ok=True)
        with TRACES.open("a") as f:
            for s in spans:
                f.write(s.to_json(indent=None) + "\n")
        return SpanExportResult.SUCCESS

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis: int = 0) -> bool:
        return True


_agent: Agent | None = None


def _get_agent() -> Agent:
    global _agent
    if _agent is None:
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import SimpleSpanProcessor
        provider = TracerProvider()
        provider.add_span_processor(SimpleSpanProcessor(_FileExporter()))
        model = OpenAIChatModel(MODEL, provider=OllamaProvider(base_url=f"{harness.OLLAMA}/v1"))
        _agent = Agent(model, output_type=NativeOutput(Display), instructions=INSTRUCTIONS, retries=1,
                       name="display")
        Agent.instrument_all(InstrumentationSettings(tracer_provider=provider))
    return _agent


async def decide(state: dict) -> tuple[Display | None, float]:
    """Ask the agent how this status should look. (choice or None, milliseconds)."""
    import asyncio
    started = time.perf_counter()
    try:
        result = await asyncio.wait_for(_get_agent().run(f"Status: {describe(state)}"), timeout=TIMEOUT_S)
        choice = result.output
    except Exception:   # model down, too slow, or broke the shape twice: plain colors stay
        choice = None
    return choice, (time.perf_counter() - started) * 1000

"""The harness: a local model reads one typed line and says what it means.

The harness is the code around the model. It builds the prompt (what's going on right now, worked
examples, the line), asks for one fixed JSON shape, checks the answer against what the words can
support, and returns None when the model is down, slow or wrong-shaped, so the caller falls back to
the rules in intents.py. The model only does the fuzzy part: reading what he meant.

A model call remembers nothing. Everything it knows is what this prompt carries.
"""

from __future__ import annotations

import re
import time
from dataclasses import dataclass, field
from typing import Literal, Sequence

import httpx
from pydantic import BaseModel, Field, ValidationError

from .intents import Command, states as rule_states

OLLAMA = "http://localhost:11434"   # Ollama's local server; nothing leaves the Mac
MODEL = "qwen2.5-coder:7b"          # knob: which local model reads the line (see docs/backend/harness.md)
TIMEOUT_S = 10.0                    # knob: give up and fall back to the rules after this

Mode = Literal["task", "rename", "continue", "note", "feedback", "ghost", "break", "back", "focus",
               "state", "stop"]
State = Literal["high", "intoxicated", "caffeinated"]


class StateChange(BaseModel):
    state: State
    on: bool


class Reading(BaseModel):
    """What one typed line means: the contract between the model and the code. `why` comes first on
    purpose: the model writes its reason before it picks, and the bar shows that reason."""
    why: str = Field("", max_length=160)  # one short sentence: what it understood
    mode: Mode
    task: str | None = None              # a clean, short title when mode is task or rename
    states: list[StateChange] = []       # substances mentioned anywhere in the line
    focus: int | None = Field(None, ge=0, le=3)  # 1 focused, 2 deep, 3 hyperfocus, 0 off
    ghost_status: str | None = None      # what he's doing off the clock, when mode is ghost


SYSTEM = """You read one line the user typed into Day Log, their time tracker, and say what it means.
Each message gives "Right now" (what's running) and the "Line". First write "why": one short
sentence on what they mean. Then pick ONE mode:

- task: starting something new. Put a short clean title in "task" (fix typos, drop feelings and
  substances). Use only words from the line for the title.
- rename: adding to or correcting what's already running ("and X", "also X", "actually it's Y").
  Put the whole new title for the running task in "task". Only when something is running.
- continue: still doing what's running ("still on it"). Nothing changes.
- note: a thought, feeling, or something that already happened ("was at the gym"). Not a new activity.
- feedback: a complaint or remark about Day Log itself (the app, the bar, a feature not working).
- ghost: off the clock: hanging out, watching a show, drinking with friends. Put what they're
  doing in "ghost_status".
- break: stepping away briefly (walk, smoke, bathroom, grabbing food or coffee).
- back: back from a break.
- focus: the line is only about how focused they are.
- state: the line is only about substances.
- stop: done for now; stop the timer.

In any mode, also fill "states" for substances the line names: high (high, stoned, baked),
intoxicated (drunk, tipsy, beers, drinking alcohol), caffeinated (coffee, espresso, caffeinated).
Drinking coffee is caffeinated, not intoxicated. on=false if they say they're not anymore.
"focus": 1 focused or locked in, 2 deep, 3 hyperfocus or in the zone, 0 lost focus; null if not
mentioned. Answer with JSON only."""

# Worked examples in his style, made up (his real lines stay on his Mac). Each: right now, line, reading.
_RUN = 'the running task is "Working on the API" (25 min so far).'
_IDLE = "nothing is running."
EXAMPLES: list[tuple[str, str, Reading]] = [
    (_IDLE, "workin on the api, lil buzzed",
     Reading(why="starting the API work, and buzzed means a bit drunk", mode="task", task="Working on the API",
             states=[StateChange(state="intoxicated", on=True)])),
    (_RUN, "and the docs too", Reading(why="adding docs to the running API task", mode="rename",
                                       task="Working on the API + docs")),
    (_RUN, "still on it", Reading(why="still doing the running task", mode="continue")),
    (_RUN, "kinda tired, brain is mush", Reading(why="a feeling, not a new activity", mode="note")),
    (_RUN, "was at the gym before this", Reading(why="something that already happened", mode="note")),
    (_RUN, "the bar didnt reset again ugh", Reading(why="a complaint about the app itself", mode="feedback")),
    (_RUN, "grabbing food real quick", Reading(why="stepping away briefly", mode="break")),
    (_IDLE, "movie night w roommates, couple beers",
     Reading(why="off the clock with friends, drinking beer", mode="ghost", ghost_status="movie night with roommates",
             states=[StateChange(state="intoxicated", on=True)])),
    (_RUN, "locked in rn", Reading(why="says they're focused", mode="focus", focus=1)),
    (_RUN, "had an espresso", Reading(why="caffeine", mode="state", states=[StateChange(state="caffeinated", on=True)])),
    (_IDLE, "took a nap, back on the api now", Reading(why="the nap is over; starting the API work", mode="task",
                                                       task="Working on the API")),
]


# The shape the model must fill: like Reading, but "why" is required so the model always says it first.
_SHAPE = {**Reading.model_json_schema(), "required": ["why", "mode"]}


def _user(context: str | None, line: str) -> str:
    return f"Right now: {context or 'unknown.'}\nLine: {line}"


def messages(line: str, examples: Sequence[tuple[str, str, Reading]] = (), context: str | None = None) -> list[dict]:
    """The whole prompt: instructions, worked examples (then his own corrections, when we have them),
    and the line with what's going on right now. This is everything the model knows."""
    msgs = [{"role": "system", "content": SYSTEM}]
    for ctx, text, reading in [*EXAMPLES, *examples]:
        msgs.append({"role": "user", "content": _user(ctx, text)})
        msgs.append({"role": "assistant", "content": reading.model_dump_json(exclude_none=True)})
    msgs.append({"role": "user", "content": _user(context, line)})
    return msgs


def read_line(line: str, examples: Sequence[tuple[str, str, Reading]] = (), model: str = MODEL,
              client: httpx.Client | None = None, context: str | None = None) -> tuple[Reading | None, float]:
    """Ask the local model what `line` means. Returns (reading or None, milliseconds).
    None means: the model was unreachable, slow, or broke the contract; use the rules."""
    body = {
        "model": model,
        "messages": messages(line, examples, context),
        "format": _SHAPE,                        # Ollama constrains the output to this shape
        "stream": False,
        "think": False,                          # the bar can't wait for a model to reason at length
        "keep_alive": "30m",                     # stay loaded between lines: a cold model takes seconds
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


def warm(model: str = MODEL) -> bool:
    """Load the model into memory now (it takes seconds cold) and keep it there 30 min. No prompt."""
    try:
        with httpx.Client(base_url=OLLAMA, timeout=60) as c:
            c.post("/api/generate", json={"model": model, "keep_alive": "30m"}).raise_for_status()
        return True
    except httpx.HTTPError:
        return False


# ---------- guardrails: code checks what the words can support ----------

_BREAK_WORDS = re.compile(r"walk|break|smok|cig|blunt|joint|pee|bathroom|restroom|toilet|step(ping)? (out|away)"
                          r"|\bbrb\b|\bafk\b|grab|getting up|get up|food|lunch|snack|coffee run", re.I)
_EVIDENCE = {
    "intoxicated": re.compile(r"drunk|tipsy|buzzed|wasted|faded|intoxicated|beers?\b|wine|shots?\b|alcohol|liquor"
                              r"|drinking(?!\s+(a\s+)?(coffee|water|tea|matcha|latte|espresso))", re.I),
    "high": re.compile(r"\bhigh\b|stoned|baked|blazed|\bweed\b|edible", re.I),
    "caffeinated": re.compile(r"caff|coffee|espresso|latte|matcha|red bull|energy drink", re.I),
}


def check(reading: Reading, text: str, running: bool, away: bool) -> Reading | None:
    """What the model said, kept only where the words and the moment support it. None = use the rules.
    - a state needs a word for it in the line ("drinking coffee" is caffeinated, never intoxicated);
      states the rules find are always added
    - a break needs a break word; "back" needs a break or ghost to come back from
    - rename / continue need something running (otherwise it's a new task)"""
    r = reading.model_copy(deep=True)
    states = {s.state: s.on for s in r.states if _EVIDENCE[s.state].search(text)}
    if "intoxicated" not in states and _EVIDENCE["intoxicated"].search(text):
        states["intoxicated"] = True   # every model on Oct 15 dropped it from "…drinking"
    states.update(dict(rule_states(text)))
    r.states = [StateChange(state=k, on=v) for k, v in states.items()]
    if r.mode == "break" and not _BREAK_WORDS.search(text):
        return None
    if r.mode == "back" and not away:
        return None
    if r.mode in ("rename", "continue") and not running:
        r.mode = "task"
    if r.mode == "state" and not r.states:
        return None
    return r


# ---------- from a reading to what Day Log does ----------

_FOCUS_SAY = {0: "focus off", 1: "focused", 2: "deep focus", 3: "hyperfocus"}
_SMOKE = re.compile(r"smok|cig|blunt|joint", re.I)


@dataclass
class Plan:
    """What a reading means for Day Log, in its own terms: an optional task, rename or note, then
    commands run through the same code as their keys. Code decides this; the model only read."""
    task: str | None = None
    rename: str | None = None            # new title for the running task (same session, same start)
    note: str | None = None
    commands: list[Command] = field(default_factory=list)
    keep: bool = False                   # "continue": nothing changes

    @property
    def say(self) -> str:
        parts = ([f"task: {self.task}"] if self.task else [f"rename: {self.rename}"] if self.rename
                 else [self.note if self.note.startswith("feedback:") else f"note: {self.note}"] if self.note
                 else ["keep going"] if self.keep and not self.commands else [])
        return " · ".join(parts + [c.say for c in self.commands])


def plan(reading: Reading, text: str) -> Plan | None:
    """Turn a reading into a plan, or None when it says nothing Day Log can act on."""
    states = [(s.state, s.on) for s in reading.states]
    state_cmd = ([Command("state", ", ".join(f"{n} {'on' if on else 'off'}" for n, on in states),
                          {"states": states})] if states else [])
    focus_cmd = ([Command("focus", _FOCUS_SAY[reading.focus], {"tier": reading.focus})]
                 if reading.focus is not None else [])
    m = reading.mode
    if m == "task":
        return Plan(task=(reading.task or text).strip(), commands=state_cmd + focus_cmd)
    if m == "rename":
        return Plan(rename=(reading.task or text).strip(), commands=state_cmd + focus_cmd)
    if m == "continue":
        return Plan(keep=True, commands=state_cmd + focus_cmd)
    if m == "note":
        return Plan(note=text.strip(), commands=state_cmd + focus_cmd)
    if m == "feedback":
        return Plan(note=f"feedback: {text.strip()}")
    if m == "ghost":
        status = (reading.ghost_status or text).strip()
        return Plan(commands=[Command("ghost", f"ghost: {status}", {"status": status})] + state_cmd)
    if m == "break":
        kind = "smoke" if _SMOKE.search(text) else "walk"
        return Plan(commands=[Command("break", "smoke break" if kind == "smoke" else "walk", {"kind": kind})])
    if m == "back":
        return Plan(commands=[Command("back", "back")] + state_cmd)
    if m == "focus":
        tier = 1 if reading.focus is None else reading.focus
        return Plan(commands=[Command("focus", _FOCUS_SAY[tier], {"tier": tier})] + state_cmd)
    if m == "stop":
        return Plan(commands=[Command("stop", "stop the timer")])
    return Plan(commands=state_cmd) if state_cmd else None   # "state" with no states: nothing to do

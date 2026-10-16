"""The HTTP API: the one front door to the event log.

Every client (the side button, the MCP server, later the phone) talks to this
process over HTTP instead of opening the database itself. That gives one owner for
the data and one place for the rules (auto-stop the old timer, tombstones, validation).

Endpoints are `async def` on purpose: they all run on one event-loop thread, so DB
access is naturally serialized and one SQLite connection is safe to share. That's
fine for one user on one machine; real concurrency is a later slice.

Run:  uv run uvicorn daylog.api:app --port 7878
Docs: http://127.0.0.1:7878/docs
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import re
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import autolabel, db, display, harness, intents, parse, stats, timeline, wispr

log = logging.getLogger("daylog")

IMPORT_EVERY = timedelta(minutes=int(os.environ.get("DAYLOG_IMPORT_MINUTES", "10")))


async def _break_loop(app: FastAPI) -> None:
    """Once a minute: a break nobody came back from turns into ghost (see timeline.expire_break)."""
    while True:
        try:
            timeline.expire_break(app.state.conn)
        except Exception:
            log.exception("break check failed")
        await asyncio.sleep(60)


async def _import_loop(app: FastAPI) -> None:
    while True:
        try:
            counts = wispr.import_all(app.state.conn)
            if any(counts.values()):
                log.info("wispr import: %s", counts)
        except Exception:  # an importer failing must never take the API down
            log.exception("wispr import failed")
        await asyncio.sleep(IMPORT_EVERY.total_seconds())


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.conn = db.connect()
    tasks = [asyncio.create_task(_break_loop(app))]
    if os.environ.get("DAYLOG_IMPORTERS", "1") == "1":
        tasks.append(asyncio.create_task(_import_loop(app)))
    yield
    for t in tasks:
        t.cancel()
    app.state.conn.close()


app = FastAPI(title="daylog", version="0.1.0", lifespan=lifespan)


def conn():
    return app.state.conn


# ---------- request bodies ----------

class TimerStart(BaseModel):
    label: str = Field(min_length=1, max_length=500)
    word: str | None = Field(default=None, max_length=12)   # the model's one word for the pill
    tasks: list[str] = []                                    # everything he's doing at once (the model's list)
    source: str = "api"


class TimerStop(BaseModel):
    source: str = "api"


class Entry(BaseModel):
    label: str = Field(min_length=1, max_length=500)
    start: datetime | None = None
    end: datetime | None = None
    minutes: int | None = Field(default=None, gt=0, le=24 * 60)
    source: str = "api"


class Line(BaseModel):
    text: str = Field(min_length=1, max_length=500, pattern=r"[A-Za-z0-9]")  # "\\" alone isn't a status
    timer: bool = False  # force a timer even if the text contains a time
    read: bool = False   # ⏎ before the bar had the model's reading: read it here first (the pill says "thinking")
    source: str = "api"


class Amend(BaseModel):
    label: str | None = Field(default=None, min_length=1, max_length=500)
    word: str | None = Field(default=None, max_length=12)   # a new one-word pill title, with a rename
    tasks: list[str] = []                                    # what he's doing at once, with a rename
    start: datetime | None = None
    end: datetime | None = None
    source: str = "api"


class Focus(BaseModel):
    tier: int = Field(ge=0, le=3)  # 0 off · 1 focused · 2 deep · 3 hyperfocus
    source: str = "api"


class Ghost(BaseModel):
    status: str = Field(default="", max_length=500)
    source: str = "api"


class StateSet(BaseModel):
    state: Literal["intoxicated", "high", "caffeinated"]
    on: bool | None = None  # None = toggle
    source: str = "api"


class Break(BaseModel):
    kind: Literal["walk", "smoke"] = "walk"
    label: str | None = Field(default=None, max_length=60)  # his word for it ("peeing"); default: walk / smoke break
    source: str = "api"


class Note(BaseModel):
    text: str = Field(min_length=1, max_length=5000)
    source: str = "api"


class Observation(BaseModel):
    type: str = Field(pattern=r"^(app\.focus|away\.start)$")
    start: datetime | None = None
    end: datetime | None = None
    data: dict = {}
    source: str = "mac"
    source_key: str | None = None


# ---------- helpers ----------

def _window(day: date | None, start: datetime | None, end: datetime | None):
    if start or end:
        if not (start and end):
            raise HTTPException(422, "pass both start and end, or date")
        lo, hi = db.parse(start.isoformat()), db.parse(end.isoformat())
        if hi <= lo:
            raise HTTPException(422, "end must be after start")
        return lo, hi
    return timeline.day_bounds(day or datetime.now().astimezone().date())


def _stop_running(source: str):
    running = timeline.running_timer(conn())
    if not running:
        return None
    return db.append(
        conn(), kind="claim", type="timer.stop", source=source,
        start=db.utcnow(), ref=running["id"],
    )


def _end_ghost(source: str):
    g = timeline.ghost(conn())
    if not g:
        return None
    return db.append(conn(), kind="claim", type="timer.stop", source=source,
                     start=db.utcnow(), ref=g["id"])


def _end_break(source: str):
    """End the break at its cap (see timeline.BREAK_CAP) if he's back late; the rest stays a gap."""
    b = timeline.on_break(conn())
    if not b:
        return None
    now = db.utcnow()
    end = timeline.break_end_at(b, now)
    return db.append(conn(), kind="claim", type="timer.stop", source=source if end == now else "auto",
                     start=end, ref=b["id"])


def _set_state(name: str, on: bool, source: str):
    db.append(conn(), kind="claim", type="state.set", source=source, start=db.utcnow(),
              data={"state": name, "on": on})


# ---------- routes ----------

def is_dev() -> bool:
    """The dev server (DAYLOG_DEV=1) holds test data only: ⌥D in the app points here."""
    return os.environ.get("DAYLOG_DEV") == "1"


# release.sh writes RELEASE.json at the root of each frozen release (version, what's new, what to
# try). Running from the working tree (Dev) there is none, so the version is "dev".
RELEASE_FILE = Path(__file__).resolve().parents[2] / "RELEASE.json"


def release_info() -> dict:
    try:
        return json.loads(RELEASE_FILE.read_text())
    except (OSError, ValueError):
        return {"version": "dev", "new": [], "try": []}


def is_owner() -> bool:
    """Owner-only features (his, not for other installs of the public repo): on when the file
    `owner` sits next to the database. Nothing in the repo creates it, so other installs never see them."""
    return (db.db_path().parent / "owner").exists()


@app.get("/health")
async def health():
    rel, owner = release_info(), is_owner()
    out = {"ok": True, "env": "dev" if is_dev() else "real", "db": str(db.db_path()),
           "version": rel.get("version", "dev"), "owner": owner,
           "code": str(RELEASE_FILE.parent)}  # where this server's code runs from: proof, not a claim
    if owner:
        out["release"] = rel  # what's new + what to try: owner-only for now
        try:  # CD's last result (scripts/autorelease.sh writes it next to the DB): the pill shows a skip and why
            out["cd"] = json.loads((db.db_path().parent / "cd-status.json").read_text())
        except (OSError, ValueError):
            pass
    return out


@app.post("/dev/reset")
async def dev_reset():
    """Wipe the dev database for a clean slate. Exists only on the dev server: the real
    log is append-only and this route is a 404 there."""
    if not is_dev():
        raise HTTPException(404, "not found")
    app.state.conn.close()
    path = db.db_path()
    for suffix in ("", "-wal", "-shm"):
        p = path.with_name(path.name + suffix)
        if p.exists():
            p.unlink()
    app.state.conn = db.connect()
    return {"reset": True}


# The display agent's choice per status (display.key → word, color, why), decided in the background.
_looks: dict[str, dict] = {}
_deciding: set[str] = set()


async def _decide_look(k: str, state: dict, again: bool = False) -> None:
    """Ask the display agent how this status looks. `again`: its own scheduled second look (the old look
    stays on the pill until the new one is in, so he sees it change, not flicker)."""
    try:
        choice, ms = await display.decide(state)
        if choice:
            _looks[k] = {"word": choice.word, "color": choice.color, "why": choice.why, "ms": round(ms),
                         "recheck_minutes": choice.recheck_minutes, "again": again, "_at": time.monotonic()}
            db.append(conn(), kind="prediction", type="display.choice", source=display.MODEL, start=db.utcnow(),
                      label=display.describe(state), data={k2: v for k2, v in _looks[k].items() if k2 != "_at"})
        elif k in _looks:   # a second look failed: keep the old one, try again after its interval
            _looks[k]["_at"] = time.monotonic()
        else:
            _looks[k] = {"word": None, "color": None, "why": "", "ms": round(ms), "recheck_minutes": 10,
                         "_at": time.monotonic()}
        while len(_looks) > 50:
            _looks.pop(next(iter(_looks)))
    finally:
        _deciding.discard(k)


def _recent_notes(state: dict, limit: int = 3) -> list[dict]:
    """What he wrote since the current status began: his typed lines (one input, Oct 16) and any notes, the
    last 3 within 3 hours. The display agent rethinks the look whenever he writes one."""
    cur = state.get("timer") or state.get("ghost") or state.get("on_break")
    now = db.utcnow()
    since = max(db.parse(cur["start"]), now - timedelta(hours=3)) if cur else now - timedelta(hours=1)
    rows = db.query(conn(), types=["note", "line.read"], since=since, until=now + timedelta(seconds=1))
    return [{"id": r["id"], "text": r["label"]} for r in rows[-limit:]]


def _with_look(state: dict) -> dict:
    """The status plus how it should look: the agent's choice ("thinking" while it first decides). When the
    agent's own recheck time has passed, it looks again in the background, with the time of day."""
    state = {**state, "notes": _recent_notes(state)}
    k = display.key(state)
    look = _looks.get(k)
    if look is None or time.monotonic() - look["_at"] > look["recheck_minutes"] * 60:
        if k not in _deciding:
            _deciding.add(k)
            asyncio.create_task(_decide_look(k, state, again=look is not None))
    if look is None:
        return {**state, "display": {"thinking": True}}
    return {**state, "display": {k2: v for k2, v in look.items() if k2 != "_at"}}


@app.get("/now")
async def now():
    timeline.expire_break(conn())  # never show a break that should already be ghost
    timeline.expire_stale(conn())  # nor last night's status
    timeline.end_ghost_after_night(conn(), db.utcnow())  # nor a ghost he slept through
    return _with_look(timeline.now_state(conn()))


@app.get("/auto")
async def auto(date: date | None = None, start: datetime | None = None, end: datetime | None = None):
    """every minute labeled with zero input (derived; never written to the log)."""
    lo, hi = _window(date, start, end)
    segs = autolabel.label_day(conn(), lo, hi)
    return {"from": db.iso(lo), "to": db.iso(hi), "segments": segs,
            "summary": autolabel.summarize(segs, autolabel.rules()["knobs"]["confident"])}


@app.get("/auto/score")
async def auto_score(days: int = 14):
    """How well zero-input labels match what he typed (category + task accuracy)."""
    return autolabel.score(conn(), db.utcnow(), days)


@app.post("/timer/start", status_code=201)
async def timer_start(body: TimerStart):
    _stop_running(body.source)  # one timer at a time: starting X ends Y
    _end_ghost(body.source)     # starting a task means you're back
    _end_break(body.source)
    db.append(conn(), kind="claim", type="timer.start", source=body.source,
              start=db.utcnow(), label=body.label.strip(),
              data={k: v for k, v in {"word": body.word, "tasks": body.tasks}.items() if v})
    return timeline.now_state(conn())


@app.post("/timer/stop")
async def timer_stop(body: TimerStop | None = None):
    stopped = _stop_running(body.source if body else "api")
    if not stopped:
        raise HTTPException(409, "no timer is running")
    return timeline.now_state(conn())


@app.post("/entries", status_code=201)
async def add_entry(body: Entry):
    if body.minutes:
        end = db.parse(body.end.isoformat()) if body.end else db.utcnow()
        start = end - timedelta(minutes=body.minutes)
    elif body.start and body.end:
        start, end = db.parse(body.start.isoformat()), db.parse(body.end.isoformat())
    else:
        raise HTTPException(422, "pass minutes, or start and end")
    if end <= start:
        raise HTTPException(422, "end must be after start")
    if end > db.utcnow() + timedelta(minutes=1):
        raise HTTPException(422, "daylog records what happened, not plans: end is in the future")
    return db.append(conn(), kind="claim", type="entry.log", source=body.source,
                     start=start, end=end, label=body.label.strip())


@app.delete("/entries/{event_id}")
async def delete_entry(event_id: str, source: str = "api"):
    target = db.get(conn(), event_id)
    if not target or target["type"] not in ("entry.log", "timer.start", "note"):
        raise HTTPException(404, "no entry, timer or note with that id")
    tombstone = db.append(conn(), kind="claim", type="entry.delete", source=source,
                          start=db.utcnow(), ref=event_id)
    return {"deleted": event_id, "tombstone": tombstone["id"]}


@app.post("/entries/{event_id}/amend")
async def amend_entry(event_id: str, body: Amend):
    """Edit a block after the fact: rename it, or move its start/end (e.g. cut back a timer
    that was left running). Appends an `entry.amend` event; the original is never touched."""
    target = db.get(conn(), event_id)
    if not target or target["type"] not in ("entry.log", "timer.start", "ghost.start"):
        raise HTTPException(404, "no entry, timer or ghost with that id")
    current = next((c for c in timeline.claims(conn(), db.parse(target["start"]) - timedelta(days=1),
                                               db.utcnow() + timedelta(seconds=1))
                    if c["id"] == event_id), None)
    if current is None:
        raise HTTPException(404, "that entry was deleted")
    start = db.parse(body.start.isoformat()) if body.start else db.parse(current["start"])
    end = db.parse(body.end.isoformat()) if body.end else (
        db.parse(current["end"]) if current["end"] else None)
    if end is not None:
        if end <= start:
            raise HTTPException(422, "end must be after start")
        if end > db.utcnow() + timedelta(minutes=1):
            raise HTTPException(422, "end is in the future")
    fields = {k: v for k, v in {
        "label": body.label.strip() if body.label else None,
        "word": body.word,
        "tasks": body.tasks or None,
        "start": db.iso(start) if body.start else None,
        "end": db.iso(end) if body.end else None,
    }.items() if v}
    if not fields:
        raise HTTPException(422, "nothing to change: pass label, start or end")
    row = db.append(conn(), kind="claim", type="entry.amend", source=body.source,
                    start=db.utcnow(), ref=event_id, data=fields)
    # Cutting back a running timer means it's over: record the stop too, so "now" agrees.
    if body.end and target["type"] == "timer.start" and current["running"]:
        db.append(conn(), kind="claim", type="timer.stop", source=body.source,
                  start=db.utcnow(), ref=event_id)
    return {"amended": event_id, "amend": row["id"], **fields}


@app.post("/observations", status_code=201)
async def add_observation(body: Observation):
    start = db.parse(body.start.isoformat()) if body.start else db.utcnow()
    # Ghost mode means log nothing. Enforced here, so no recorder can leak data by accident.
    # two bare facts get through, so a ghost can't run through the night:
    # the Mac sleeping ({reason} only) and the first app switch after it (no app, title or URL). If that
    # sleep ran through the night, ghost ends when the Mac went to sleep and logging resumes normally.
    if timeline.ghost(conn()):
        reason = body.data.get("reason")
        if body.type == "away.start" and reason in timeline.GHOST_ENDING_REASONS:
            body.data = {"reason": reason}
        elif body.type == "app.focus" and timeline.ghost_sleep(conn()):
            if not timeline.end_ghost_after_night(conn(), start):
                body.data = {}  # back from a daytime sleep: still ghost, just mark the wake
        else:
            return {"ignored": "ghost mode"}
    end = db.parse(body.end.isoformat()) if body.end else None
    row = db.append(conn(), kind="observation", type=body.type, source=body.source,
                    start=start, end=end, data=body.data, source_key=body.source_key)
    return row or {"duplicate": True}


def _describe(p: parse.Parsed) -> dict:
    if not p.is_range:
        return {"action": "timer", "label": p.label}
    return {"action": "log", "label": p.label, "start": db.iso(p.start), "end": db.iso(p.end),
            "minutes": round((p.end - p.start).total_seconds() / 60), "until_now": p.open_ended}


@app.post("/focus")
async def set_focus(body: Focus):
    """Mark how deep he is in the running task right now. A layer on the task, not a new
    task: it lasts until he changes it or switches tasks."""
    running = timeline.running_timer(conn())
    if not running:
        raise HTTPException(409, "start a task first: focus is a layer on the running task")
    db.append(conn(), kind="claim", type="focus.set", source=body.source, start=db.utcnow(),
              ref=running["id"], data={"tier": body.tier})
    return timeline.now_state(conn())


@app.post("/ghost", status_code=201)
async def ghost_on(body: Ghost):
    """Go dark: stop the timer, leave a status, and log nothing about him until he's back."""
    _stop_running(body.source)
    _end_break(body.source)
    _end_ghost(body.source)  # a new status replaces the old one
    db.append(conn(), kind="claim", type="ghost.start", source=body.source,
              start=db.utcnow(), label=body.status.strip() or "offline")
    return timeline.now_state(conn())


@app.delete("/ghost")
async def ghost_off(source: str = "api"):
    if not _end_ghost(source):
        raise HTTPException(409, "not in ghost mode")
    return timeline.now_state(conn())


@app.post("/state")
async def set_state(body: StateSet):
    """Substances (intoxicated, high, caffeinated): global layers on *him*, not on a task.
    `on` omitted = toggle."""
    active = {s["state"] for s in timeline.active_states(conn())}
    on = (body.state not in active) if body.on is None else body.on
    _set_state(body.state, on, body.source)
    return timeline.now_state(conn())


@app.post("/break", status_code=201)
async def break_start(body: Break):
    """⌘B: step away. The running task pauses (its timer stops) and is remembered, so coming
    back resumes it. A smoke break comes back high."""
    timeline.expire_break(conn())
    if timeline.on_break(conn()):
        raise HTTPException(409, "already on a break")
    if timeline.ghost(conn()):
        raise HTTPException(409, "you're in ghost mode")
    running = timeline.running_timer(conn())
    _stop_running(body.source)
    resume = running["label"] if running else None
    db.append(conn(), kind="claim", type="break.start", source=body.source, start=db.utcnow(),
              label=(body.label or "").strip() or timeline.BREAK_LABELS[body.kind],
              data={"kind": body.kind, "resume": resume})
    return timeline.now_state(conn())


@app.delete("/break")
async def break_end(source: str = "api"):
    """Back from a break: end it, resume the paused task, and turn high on after a smoke.
    Also works after the break already turned into ghost (he was gone over an hour)."""
    timeline.expire_break(conn())
    b = timeline.on_break(conn())
    g = timeline.ghost(conn())
    if b:
        kind, resume = b["data"].get("kind"), b["data"].get("resume")
        _end_break(source)
    elif g and g["data"].get("from_break"):
        kind, resume = g["data"].get("kind"), g["data"].get("resume")
        _end_ghost(source)
    else:
        raise HTTPException(409, "not on a break")
    if kind == "smoke":
        _set_state("high", True, source)
    if resume:
        db.append(conn(), kind="claim", type="timer.start", source=source,
                  start=db.utcnow(), label=resume)
    return {"resumed": resume, **timeline.now_state(conn())}


@app.post("/notes", status_code=201)
async def add_note(body: Note):
    """A thought at this moment. Attached to the running timer (if any) without
    changing it, so notes say what was on his mind *during* a task."""
    running = timeline.running_timer(conn())
    return db.append(conn(), kind="claim", type="note", source=body.source, start=db.utcnow(),
                     label=body.text.strip(), ref=running["id"] if running else None,
                     data={"during": running["label"]} if running else {})


@app.get("/parse")
async def parse_line(text: str):
    """What would /log do with this line? Used for the live preview while typing."""
    if title := _extended_title(text):
        return {"action": "command", "label": f"rename: {title}", "text": text}
    cmds = intents.commands(text)
    if cmds:
        return {"action": "command", "label": " · ".join(c.say for c in cmds), "text": text}
    out = _describe(parse.parse(text)) | {"text": text}
    if out["action"] == "timer":
        also = [f"{n} {'on' if on else 'off'}" for n, on in intents.states(text)]
        if also:
            out["also"] = also
    return out


# What the model read for lines typed in the last few minutes, so ⏎ uses the reading the bar showed
# without waiting for the model again. Keyed by the exact line.
READ_KEEP_S = 300
READ_WAIT_S = 8.0   # knob: how long /log waits for the model when the bar sends read=True (gemma4: ~3-6 s)
_readings: dict[str, tuple[float, harness.Reading, float]] = {}

# "and brain global config" / "also X" while a task runs: same session, the title grows. A rule, so it's
# instant and exact (his line, Oct 15: "and daylog and brain global config." meant rename, not a new task).
_EXTEND = re.compile(r"^\s*(?:and|also|plus|\+)\s+(.+?)[.!]*\s*$", re.I)


def _extended_title(text: str) -> str | None:
    """The running task's new title if `text` extends it ("and X" → "<current> + X"), else None."""
    m = _EXTEND.match(text)
    running = timeline.running_timer(conn())
    return f"{running['label'].rstrip('. ')} + {m.group(1)}" if m and running else None


def _now_context() -> str:
    """What's going on right now, in a sentence, for the model's prompt."""
    s = timeline.now_state(conn())
    if s["timer"]:
        t = s["timer"]
        return f"the running task is \"{t['label']}\" ({t['elapsed_minutes']} min so far)."
    if s["ghost"]:
        return f"he is in ghost mode: \"{s['ghost']['status']}\"."
    if s["on_break"]:
        return f"he is on a break ({s['on_break']['label']})."
    return "nothing is running."


async def _rename_running(title: str, source: str, word: str | None = None, tasks: list[str] = ()) -> None:
    running = timeline.running_timer(conn())
    if running:
        await amend_entry(running["id"], Amend(label=title, word=word, tasks=list(tasks), source=source))
    else:
        await timer_start(TimerStart(label=title, word=word, tasks=list(tasks), source=source))


@app.get("/read")
async def read_line(text: str):
    """The model's reading of a line, for the bar's preview (~1 s; the rules preview shows first).
    Lines with times stay with the rules (exact time math is code's job), and so does everything
    when the model is down: then the answer is action "none"."""
    text = text.strip()
    if not text or parse.parse(text).is_range:
        return {"action": "none", "label": "", "text": text}
    if title := _extended_title(text):   # the rule already knows: no need to wait for the model
        return {"action": "command", "label": f"rename: {title}", "text": text,
                "why": "starts with \"and\": same session, bigger title (rule)"}
    state = timeline.now_state(conn())
    raw, ms = await asyncio.to_thread(harness.read_line, text, context=_now_context())
    reading = raw and harness.check(raw, text, running=bool(state["timer"]),
                                    away=bool(state["on_break"] or state["ghost"]))
    p = harness.plan(reading, text) if reading else None
    if not p:
        return {"action": "none", "label": "", "text": text,
                "why": "the model was unsure or off; the rules handle it" if raw else "no model answer"}
    now = time.monotonic()
    for k in [k for k, (at, _, _) in _readings.items() if now - at > READ_KEEP_S]:
        del _readings[k]
    _readings[text] = (now, reading, ms)
    return {"action": "command", "label": p.say, "text": text, "by": harness.MODEL, "ms": round(ms),
            "why": reading.why}


@app.get("/stats")
async def get_stats():
    """The ⌘K analytics panel: version, models loaded, memory and CPU (Mac, app, server), model latency."""
    return await asyncio.to_thread(stats.collect, conn(), release_info().get("version", "dev"), str(RELEASE_FILE.parent))


@app.post("/harness/warm")
async def harness_warm():
    """The bar just opened, so he's about to type: load the model now so his first line isn't cold."""
    return {"warm": await asyncio.to_thread(harness.warm, harness.MODEL, display.MODEL)}


async def _apply_reading(text: str, reading: harness.Reading, ms: float, source: str) -> dict:
    """Do what the model read, through the same code the keys use. The reading itself is kept as a
    prediction (never a claim), so his later corrections can be measured against it."""
    p = harness.plan(reading, text)
    db.append(conn(), kind="prediction", type="line.read", source=harness.MODEL, start=db.utcnow(),
              label=text, data={"reading": reading.model_dump(exclude_none=True), "ms": round(ms),
                                "model": harness.MODEL})
    if p.task:
        await timer_start(TimerStart(label=p.task, word=p.word, tasks=p.tasks, source=source))
    if p.rename:
        await _rename_running(p.rename, source, word=p.word, tasks=p.tasks)
    if p.note:
        await add_note(Note(text=p.note, source=source))
    out: dict = {}
    for c in p.commands:
        if c.action == "focus" and not timeline.running_timer(conn()):
            continue  # focus is a layer on a task; with none running there's nothing to deepen
        try:
            out = await _run(c, source)
        except HTTPException as e:   # e.g. "already on a break": skip that part, keep the rest (Oct 16 "log failed")
            if e.status_code != 409:
                raise
    return {"action": "read", "did": p.say, **(out or timeline.now_state(conn()))}


def _undo_break(source: str) -> None:
    """"didnt actually break" (his, Oct 13): the break never happened. It gets a tombstone (append-only), and
    the task it paused starts again from the break's start, so that time counts as the task."""
    b = timeline.on_break(conn())
    if not b:
        raise HTTPException(409, "you're not on a break")
    db.append(conn(), kind="claim", type="entry.delete", source=source, start=db.utcnow(), ref=b["id"])
    if resume := b["data"].get("resume"):
        db.append(conn(), kind="claim", type="timer.start", source=source, start=db.parse(b["start"]),
                  label=resume, data={"reason": "break taken back"})


async def _run(cmd: intents.Command, source: str) -> dict:
    """Do a typed command through the same rules as its key would."""
    a = cmd.args
    if cmd.action == "break":
        await break_start(Break(kind=a["kind"], label=a.get("label"), source=source))
    elif cmd.action == "undo_break":
        _undo_break(source)
    elif cmd.action == "back":
        b, g = timeline.on_break(conn()), timeline.ghost(conn())
        if b or (g and g["data"].get("from_break")):
            await break_end(source)
        elif g:
            _end_ghost(source)
        else:
            raise HTTPException(409, "you're not away")
    elif cmd.action == "focus":
        await set_focus(Focus(tier=a["tier"], source=source))
    elif cmd.action == "state":
        for name, on in a["states"]:
            _set_state(name, on, source)
    elif cmd.action == "ghost":
        await ghost_on(Ghost(status=a["status"], source=source))
    elif cmd.action == "online":
        if not _end_ghost(source):
            raise HTTPException(409, "not in ghost mode")
    elif cmd.action == "stop":
        if not _stop_running(source):
            raise HTTPException(409, "no timer is running")
    return {"action": "command", "did": cmd.say, **timeline.now_state(conn())}


@app.post("/log", status_code=201)
async def log_line(body: Line):
    """One line in, the right thing out: a command ("smoke break", "deep focus") does it; a time
    in the text logs a past block; anything else starts a timer, turning on any substance it
    mentions ("working on daylog, little high"). The same endpoint the bar, phone or an agent uses."""
    if not body.timer and (title := _extended_title(body.text)):
        await _rename_running(title, body.source)
        return {"action": "command", "did": f"rename: {title}", **timeline.now_state(conn())}
    if body.read and not body.timer and body.text.strip() not in _readings:
        try:   # at most READ_WAIT_S: then the rules, so a stuck model never holds the line
            await asyncio.wait_for(read_line(body.text), timeout=READ_WAIT_S)
        except asyncio.TimeoutError:
            pass
    hit = None if body.timer else _readings.pop(body.text.strip(), None)
    if hit:
        return await _apply_reading(body.text.strip(), hit[1], hit[2], body.source)
    cmds = None if body.timer else intents.commands(body.text)
    if cmds:
        out: dict = {}
        for c in cmds:  # in the order said: "smoke break, then high" works step by step
            out = await _run(c, body.source)
        return out | {"did": " · ".join(c.say for c in cmds)}
    p = parse.parse(body.text)
    if body.timer or not p.is_range:
        await timer_start(TimerStart(label=p.label if p.is_range else body.text, source=body.source))
        for name, on in intents.states(body.text):
            _set_state(name, on, body.source)
        return {"action": "timer", **timeline.now_state(conn())}
    row = db.append(conn(), kind="claim", type="entry.log", source=body.source,
                    start=p.start, end=p.end, label=p.label.strip())
    return {"action": "log", "entry": row}


@app.get("/timeline")
async def get_timeline(date: date | None = None, start: datetime | None = None,
                       end: datetime | None = None):
    lo, hi = _window(date, start, end)
    return timeline.timeline(conn(), lo, hi)


@app.get("/history")
async def get_history(date: date | None = None, start: datetime | None = None,
                      end: datetime | None = None):
    """Newest-first stops for scrolling back: logs, meetings, and untracked gaps."""
    lo, hi = _window(date, start, end)
    return {"from": db.iso(lo), "to": db.iso(hi), "items": timeline.history(conn(), lo, hi)}


@app.get("/summary")
async def get_summary(date: date | None = None, start: datetime | None = None,
                      end: datetime | None = None):
    lo, hi = _window(date, start, end)
    return timeline.summary(conn(), lo, hi)


@app.post("/import/wispr")
async def import_wispr():
    return wispr.import_all(conn())

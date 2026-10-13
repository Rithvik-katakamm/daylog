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
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import autolabel, db, intents, parse, timeline, wispr

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
    text: str = Field(min_length=1, max_length=500)
    timer: bool = False  # force a timer even if the text contains a time
    source: str = "api"


class Amend(BaseModel):
    label: str | None = Field(default=None, min_length=1, max_length=500)
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
    b = timeline.on_break(conn())
    if not b:
        return None
    return db.append(conn(), kind="claim", type="timer.stop", source=source,
                     start=db.utcnow(), ref=b["id"])


def _set_state(name: str, on: bool, source: str):
    db.append(conn(), kind="claim", type="state.set", source=source, start=db.utcnow(),
              data={"state": name, "on": on})


# ---------- routes ----------

def is_dev() -> bool:
    """The dev server (DAYLOG_DEV=1) holds test data only: ⌥D in the app points here."""
    return os.environ.get("DAYLOG_DEV") == "1"


# RIT-124: release.sh writes RELEASE.json at the root of each frozen release (version, what's new, what to
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


@app.get("/now")
async def now():
    timeline.expire_break(conn())  # never show a break that should already be ghost
    timeline.expire_stale(conn())  # nor last night's status (RIT-101)
    state = timeline.now_state(conn())
    # RIT-122: with nothing running, the labeler's guess (a prediction; the pill shows it faded).
    idle = not (state["timer"] or state["ghost"] or state["on_break"])
    state["guess"] = autolabel.current_guess(conn()) if idle else None
    return state


class Label(BaseModel):
    action: Literal["confirm", "correct", "shown"]
    category: str | None = None
    task: str | None = None
    text: str | None = None          # a correction: what he typed instead
    start: datetime | None = None    # the guessed block
    end: datetime | None = None
    guess: dict = {}
    source: str = "api"


@app.post("/label", status_code=201)
async def label(body: Label):
    """RIT-122: ⏎ confirms the guess, typing corrects it (both claims = labels); every guess shown is
    logged too (an observation), so acceptance can be measured and auto-confirm decided later."""
    if body.action == "shown":
        db.append(conn(), kind="observation", type="guess.shown", source=body.source,
                  start=db.utcnow(), data={"guess": body.guess})
        return {"ok": True}
    end = db.parse(body.end.isoformat()) if body.end else db.utcnow()
    start = db.parse(body.start.isoformat()) if body.start else end
    category, task = body.category, body.task
    if body.action == "correct":
        task = (body.text or "").strip() or task
        category = autolabel.claim_category(autolabel.rules(), task or "") or category
    autolabel._guess_cache.update(at=None)  # the pill should reflect the label right away
    return db.append(conn(), kind="claim", type="label", source=body.source, start=start, end=end,
                     label=task or category, data={"action": body.action, "category": category,
                                                   "task": task, "guess": body.guess})


@app.get("/auto")
async def auto(date: date | None = None, start: datetime | None = None, end: datetime | None = None):
    """RIT-120: every minute labeled with zero input (derived; never written to the log)."""
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
              start=db.utcnow(), label=body.label.strip())
    return timeline.now_state(conn())


@app.post("/timer/cut")
async def timer_cut(body: TimerStop | None = None):
    """RIT-39: accept the cut offer. The task ends when he walked away (a backdated timer.stop,
    like the stale reset), and nothing is running until he types what he's on now."""
    offer = timeline.cut_offer(conn())
    if not offer:
        raise HTTPException(409, "no cut to offer")
    db.append(conn(), kind="claim", type="timer.stop", source=body.source if body else "api",
              start=db.parse(offer["away_from"]), ref=offer["timer_id"], data={"reason": "cut"})
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
    if not target or target["type"] not in ("entry.log", "timer.start"):
        raise HTTPException(404, "no entry or timer with that id")
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
    if g := timeline.ghost(conn()):
        reason = body.data.get("reason")
        if body.type != "away.start" or reason not in timeline.GHOST_ENDING_REASONS:
            return {"ignored": "ghost mode"}
        # RIT-43, his call (Oct 13): the Mac really sleeping ends ghost at that moment, so a ghost
        # can't run through the night. Only the bare fact is kept: when, and why (no app, title or URL).
        db.append(conn(), kind="claim", type="timer.stop", source="auto", start=start, ref=g["id"],
                  data={"reason": "slept"})
        body.data = {"reason": reason}
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
              label=timeline.BREAK_LABELS[body.kind], data={"kind": body.kind, "resume": resume})
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
    cmds = intents.commands(text)
    if cmds:
        return {"action": "command", "label": " · ".join(c.say for c in cmds), "text": text}
    out = _describe(parse.parse(text)) | {"text": text}
    if out["action"] == "timer":
        also = [f"{n} {'on' if on else 'off'}" for n, on in intents.states(text)]
        if also:
            out["also"] = also
    return out


async def _run(cmd: intents.Command, source: str) -> dict:
    """Do a typed command through the same rules as its key would."""
    a = cmd.args
    if cmd.action == "break":
        await break_start(Break(kind=a["kind"], source=source))
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

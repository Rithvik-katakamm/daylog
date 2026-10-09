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
import logging
import os
from datetime import date, datetime, timedelta

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from . import db, parse, timeline, wispr

log = logging.getLogger("daylog")

IMPORT_EVERY = timedelta(minutes=int(os.environ.get("DAYLOG_IMPORT_MINUTES", "10")))


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
    task = None
    if os.environ.get("DAYLOG_IMPORTERS", "1") == "1":
        task = asyncio.create_task(_import_loop(app))
    yield
    if task:
        task.cancel()
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


# ---------- routes ----------

@app.get("/health")
async def health():
    return {"ok": True, "db": str(db.db_path())}


@app.get("/now")
async def now():
    return timeline.now_state(conn())


@app.post("/timer/start", status_code=201)
async def timer_start(body: TimerStart):
    _stop_running(body.source)  # one timer at a time: starting X ends Y
    db.append(conn(), kind="claim", type="timer.start", source=body.source,
              start=db.utcnow(), label=body.label.strip())
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
    if not target or target["type"] not in ("entry.log", "timer.start"):
        raise HTTPException(404, "no entry or timer with that id")
    tombstone = db.append(conn(), kind="claim", type="entry.delete", source=source,
                          start=db.utcnow(), ref=event_id)
    return {"deleted": event_id, "tombstone": tombstone["id"]}


@app.post("/observations", status_code=201)
async def add_observation(body: Observation):
    start = db.parse(body.start.isoformat()) if body.start else db.utcnow()
    end = db.parse(body.end.isoformat()) if body.end else None
    row = db.append(conn(), kind="observation", type=body.type, source=body.source,
                    start=start, end=end, data=body.data, source_key=body.source_key)
    return row or {"duplicate": True}


def _describe(p: parse.Parsed) -> dict:
    if not p.is_range:
        return {"action": "timer", "label": p.label}
    return {"action": "log", "label": p.label, "start": db.iso(p.start), "end": db.iso(p.end),
            "minutes": round((p.end - p.start).total_seconds() / 60), "until_now": p.open_ended}


@app.get("/parse")
async def parse_line(text: str):
    """What would /log do with this line? Used for the live preview while typing."""
    return _describe(parse.parse(text))


@app.post("/log", status_code=201)
async def log_line(body: Line):
    """One line in, the right event out: a time in the text logs it, otherwise starts a timer.
    The same endpoint the panel, the phone, or a shortcut can call."""
    p = parse.parse(body.text)
    if body.timer or not p.is_range:
        await timer_start(TimerStart(label=p.label if p.is_range else body.text, source=body.source))
        return {"action": "timer", **timeline.now_state(conn())}
    row = db.append(conn(), kind="claim", type="entry.log", source=body.source,
                    start=p.start, end=p.end, label=p.label.strip())
    return {"action": "log", "entry": row}


@app.get("/timeline")
async def get_timeline(date: date | None = None, start: datetime | None = None,
                       end: datetime | None = None):
    lo, hi = _window(date, start, end)
    return timeline.timeline(conn(), lo, hi)


@app.get("/summary")
async def get_summary(date: date | None = None, start: datetime | None = None,
                      end: datetime | None = None):
    lo, hi = _window(date, start, end)
    return timeline.summary(conn(), lo, hi)


@app.post("/import/wispr")
async def import_wispr():
    return wispr.import_all(conn())

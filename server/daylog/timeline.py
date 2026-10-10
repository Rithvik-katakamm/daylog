"""Derived views. Everything here is computed from the event log at read time.

The log stores *what happened* (a timer started, an app came to the front). This module
turns that into *what it means* (a 42-minute "coding" segment). Because the views are
derived, fixing a bug here fixes history too; nothing stale is stored.
"""

from __future__ import annotations

import sqlite3
from datetime import date, datetime, time, timedelta
from typing import Any

from . import db

# An app-focus observation counts as "still on that app" for at most this long after
# its last event. The recorder heartbeats every 5 min, so a gap longer than this means
# the recorder (or the Mac) wasn't running and we shouldn't invent time.
ACTIVITY_CAP = timedelta(minutes=10)

# Claims can start before the window they overlap (a timer started last night).
CLAIM_LOOKBACK = timedelta(hours=24)

CLAIM_TYPES = ["timer.start", "entry.log", "ghost.start"]
ACTIVITY_TYPES = ["app.focus", "away.start"]


def day_bounds(d: date) -> tuple[datetime, datetime]:
    """Local midnight to the next local midnight, as UTC instants (DST-safe)."""
    start = datetime.combine(d, time.min).astimezone()
    end = datetime.combine(d + timedelta(days=1), time.min).astimezone()
    return db.parse(db.iso(start)), db.parse(db.iso(end))


def _clip(seg_start: datetime, seg_end: datetime, lo: datetime, hi: datetime):
    s, e = max(seg_start, lo), min(seg_end, hi)
    return (s, e) if e > s else None


def _seg(start: datetime, end: datetime | None, **fields: Any) -> dict[str, Any]:
    out = {"start": db.iso(start), "end": db.iso(end) if end else None}
    out.update(fields)
    return out


def _open_span(conn: sqlite3.Connection, start_type: str) -> dict[str, Any] | None:
    """The latest span of `start_type` that nothing has stopped or deleted yet."""
    r = conn.execute(
        "SELECT * FROM events e WHERE e.type = ? AND NOT EXISTS ("
        "  SELECT 1 FROM events x WHERE x.ref = e.id AND x.type IN ('timer.stop', 'entry.delete'))"
        " ORDER BY e.start DESC LIMIT 1",
        (start_type,),
    ).fetchone()
    return db.to_dict(r) if r else None


def running_timer(conn: sqlite3.Connection) -> dict[str, Any] | None:
    return _open_span(conn, "timer.start")


def ghost(conn: sqlite3.Connection) -> dict[str, Any] | None:
    """Ghost mode: he's gone dark. Nothing is logged about him until he comes back."""
    return _open_span(conn, "ghost.start")


def claims(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    """What he said he did, as segments overlapping [lo, hi). Running timer has end=None."""
    now = db.utcnow()
    events = db.query(conn, types=CLAIM_TYPES, since=lo - CLAIM_LOOKBACK, until=hi)
    ids = [e["id"] for e in events]
    deleted = db.refs_to(conn, "entry.delete", ids)
    stops = db.refs_to(conn, "timer.stop", ids)
    amends = db.refs_to(conn, "entry.amend", ids, latest=True)

    out = []
    for e in events:
        if e["id"] in deleted:
            continue
        fix = amends.get(e["id"], {}).get("data", {})  # the newest edit, if any
        start = db.parse(fix.get("start") or e["start"])
        label = fix.get("label") or e["label"]
        running = False
        if fix.get("end"):
            end = db.parse(fix["end"])
        elif e["type"] in ("timer.start", "ghost.start"):
            stop = stops.get(e["id"])
            if stop:
                end = db.parse(stop["start"])
            else:
                end, running = now, True
        else:
            end = db.parse(e["end"])
        # A just-started timer has zero length but must still show as running.
        visible = (start < hi and end >= lo) if running else _clip(start, end, lo, hi)
        if not visible:
            continue
        out.append(
            _seg(
                start,
                None if running else end,
                id=e["id"],
                label=label,
                source=e["source"],
                type={"timer.start": "timer", "ghost.start": "ghost"}.get(e["type"], "entry"),
                running=running,
            )
        )
    return out


def meetings(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    events = db.query(conn, types=["meeting"], since=lo - CLAIM_LOOKBACK, until=hi)
    out = []
    for e in events:
        start, end = db.parse(e["start"]), db.parse(e["end"])
        if _clip(start, end, lo, hi):
            out.append(_seg(start, end, id=e["id"], label=e["label"], source=e["source"]))
    return out


def activity(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    """Which app was in front, as merged segments. Observations only, never guesses."""
    # Include the last activity event before the window: it may still be in effect.
    prev = conn.execute(
        "SELECT * FROM events WHERE type IN ('app.focus', 'away.start') AND start < ?"
        " ORDER BY start DESC LIMIT 1",
        (db.iso(lo),),
    ).fetchone()
    events = ([db.to_dict(prev)] if prev else []) + db.query(
        conn, types=ACTIVITY_TYPES, since=lo, until=hi
    )
    now = db.utcnow()
    segs: list[dict[str, Any]] = []
    for i, e in enumerate(events):
        if e["type"] != "app.focus":
            continue
        start = db.parse(e["start"])
        nxt = db.parse(events[i + 1]["start"]) if i + 1 < len(events) else now
        end = min(nxt, start + ACTIVITY_CAP, now)
        clipped = _clip(start, end, lo, hi)
        if not clipped:
            continue
        app = e["data"].get("app") or "unknown"
        s, en = clipped
        last = segs[-1] if segs else None
        if last and last["app"] == app and db.parse(last["end"]) >= s - timedelta(seconds=1):
            last["end"] = db.iso(en)
        else:
            segs.append(_seg(s, en, app=app, bundle_id=e["data"].get("bundle_id")))
    return segs


def dictations(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    events = db.query(conn, types=["dictation"], since=lo, until=hi)
    return [
        {"start": e["start"], "end": e["end"], "app": e["data"].get("app"),
         "url": e["data"].get("url"), "words": e["data"].get("words")}
        for e in events
    ]


def notes(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    events = db.query(conn, types=["note"], since=lo, until=hi)
    deleted = db.refs_to(conn, "entry.delete", [e["id"] for e in events])
    return [{"id": e["id"], "at": e["start"], "text": e["label"], "during": e["data"].get("during")}
            for e in events if e["id"] not in deleted]


def timeline(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> dict[str, Any]:
    return {
        "from": db.iso(lo),
        "to": db.iso(hi),
        "claims": claims(conn, lo, hi),
        "meetings": meetings(conn, lo, hi),
        "activity": activity(conn, lo, hi),
        "dictations": dictations(conn, lo, hi),
        "notes": notes(conn, lo, hi),
    }


# Untracked stretches shorter than this aren't worth a stop when scrolling back.
GAP_MIN = timedelta(minutes=10)


def history(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    """Everything that fills [lo, hi), newest first: logged blocks, meetings, and the
    untracked gaps between them (so he can fill those in). The running timer is left out,
    because the bar already shows it."""
    now = db.utcnow()
    hi = min(hi, now)
    items: list[dict[str, Any]] = []
    known: list[tuple[datetime, datetime]] = []
    for c in claims(conn, lo, hi):
        s = db.parse(c["start"])
        if c["running"]:
            known.append((max(s, lo), hi))  # still counts as accounted-for time
            continue
        e = db.parse(c["end"])
        items.append({"kind": c["type"], "id": c["id"], "label": c["label"], "start": c["start"],
                      "end": c["end"], "minutes": _minutes(min(e, hi) - max(s, lo))})
        known.append((max(s, lo), min(e, hi)))
    for m in meetings(conn, lo, hi):
        s, e = db.parse(m["start"]), db.parse(m["end"])
        items.append({"kind": "meeting", "id": m["id"], "label": m["label"], "start": m["start"],
                      "end": m["end"], "minutes": _minutes(min(e, hi) - max(s, lo))})
        known.append((max(s, lo), min(e, hi)))

    for n in notes(conn, lo, hi + timedelta(seconds=1)):  # moments, not spans: never fill or split gaps
        items.append({"kind": "note", "id": n["id"], "label": n["text"], "start": n["at"],
                      "end": n["at"], "minutes": 0, "during": n["during"]})

    cursor = lo
    for s, e in sorted(known) + [(hi, hi)]:
        if s - cursor >= GAP_MIN:
            items.append({"kind": "gap", "id": None, "label": None, "start": db.iso(cursor),
                          "end": db.iso(s), "minutes": _minutes(s - cursor)})
        cursor = max(cursor, e)
    return sorted(items, key=lambda i: i["start"], reverse=True)


def _minutes(td: timedelta) -> int:
    return round(td.total_seconds() / 60)


def _union_length(intervals: list[tuple[datetime, datetime]]) -> timedelta:
    total, cur_s, cur_e = timedelta(), None, None
    for s, e in sorted(intervals):
        if cur_e is None or s > cur_e:
            if cur_e is not None:
                total += cur_e - cur_s
            cur_s, cur_e = s, e
        else:
            cur_e = max(cur_e, e)
    if cur_e is not None:
        total += cur_e - cur_s
    return total


def summary(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> dict[str, Any]:
    now = db.utcnow()
    tl = timeline(conn, lo, hi)
    by_label: dict[str, timedelta] = {}
    known: list[tuple[datetime, datetime]] = []
    segs = [dict(c, label=f"ghost: {c['label']}") if c["type"] == "ghost" else c for c in tl["claims"]]
    for seg in segs + [dict(m, label=f"meeting: {m['label']}") for m in tl["meetings"]]:
        s = db.parse(seg["start"])
        e = db.parse(seg["end"]) if seg["end"] else now
        clipped = _clip(s, e, lo, hi)
        if not clipped:
            continue
        by_label[seg["label"]] = by_label.get(seg["label"], timedelta()) + (clipped[1] - clipped[0])
        known.append(clipped)

    by_app: dict[str, timedelta] = {}
    for seg in tl["activity"]:
        d = db.parse(seg["end"]) - db.parse(seg["start"])
        by_app[seg["app"]] = by_app.get(seg["app"], timedelta()) + d

    elapsed = max(min(hi, now) - lo, timedelta())
    tracked = _union_length(known)
    return {
        "from": tl["from"],
        "to": tl["to"],
        "tracked_minutes": _minutes(tracked),
        "untracked_minutes": _minutes(max(elapsed - tracked, timedelta())),
        "computer_active_minutes": _minutes(sum(by_app.values(), timedelta())),
        "by_label": {k: _minutes(v) for k, v in sorted(by_label.items(), key=lambda kv: -kv[1])},
        "by_app": {k: _minutes(v) for k, v in sorted(by_app.items(), key=lambda kv: -kv[1])},
    }


def now_state(conn: sqlite3.Connection) -> dict[str, Any]:
    now = db.utcnow()
    timer = running_timer(conn)
    g = ghost(conn)
    last_act = conn.execute(
        "SELECT * FROM events WHERE type IN ('app.focus', 'away.start') ORDER BY start DESC LIMIT 1"
    ).fetchone()
    current_app = None
    if last_act:
        a = db.to_dict(last_act)
        fresh = now - db.parse(a["start"]) <= ACTIVITY_CAP
        if a["type"] == "app.focus" and fresh:
            current_app = {"app": a["data"].get("app"), "since": a["start"]}
        elif a["type"] == "away.start" and fresh:
            current_app = {"app": None, "away_since": a["start"]}
    meeting = next(
        (m for m in meetings(conn, now - timedelta(hours=4), now + timedelta(seconds=1))
         if db.parse(m["end"]) >= now),
        None,
    )
    return {
        "now": db.iso(now),
        "timer": (
            {"id": timer["id"], "label": timer["label"], "start": timer["start"],
             "elapsed_minutes": _minutes(now - db.parse(timer["start"]))}
            if timer else None
        ),
        "activity": current_app,
        "meeting": meeting,
        "ghost": (
            {"id": g["id"], "status": g["label"], "start": g["start"],
             "elapsed_minutes": _minutes(now - db.parse(g["start"]))}
            if g else None
        ),
    }

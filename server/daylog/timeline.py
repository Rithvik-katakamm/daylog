"""Derived views. Everything here is computed from the event log at read time.

The log stores *what happened* (a timer started, an app came to the front). This module
turns that into *what it means* (a 42-minute "coding" segment). Because the views are
derived, fixing a bug here fixes history too; nothing stale is stored.
"""

from __future__ import annotations

import json
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

CLAIM_TYPES = ["timer.start", "entry.log", "ghost.start", "break.start"]

# Substances: global layers ("how am I"), not tied to a task. A state.set event turns one on
# or off; the latest event per state wins.
STATES = ("intoxicated", "high", "caffeinated")

# Breaks (⌘B walk, ⌘⇧B smoke): the task pauses and resumes when he's back. If he isn't back
# after BREAK_GHOST_AFTER, the break was really only ~BREAK_ASSUMED long and he went dark
# after that, so the log says exactly that. (Smart capture can learn these numbers later.)
BREAK_GHOST_AFTER = timedelta(hours=1)
BREAK_ASSUMED = timedelta(minutes=15)
BREAK_LABELS = {"walk": "walk", "smoke": "smoke break"}
# Back from a break later than its cap: the break is logged only up to the cap, and the rest is a
# gap (unknown; the Mac's own observations say away). His smoke breaks run ~6 min when he presses
# back (Oct 11-13), so 15 min of smoking is generous. Walks have no cap: a real one ran 35 min.
BREAK_CAP = {"smoke": BREAK_ASSUMED}

# Stale status: display off and no status change for STALE_AFTER means last night's
# task and states are over; they end when the display went off. Idle alone doesn't count:
# only sleep, display sleep or lock mean the display is off.
STALE_AFTER = timedelta(hours=3)
STALE_MIN_OFF = timedelta(hours=1)  # so a quick lock late in a long session never ends the task
DISPLAY_OFF_REASONS = {"NSWorkspaceScreensDidSleepNotification", "NSWorkspaceWillSleepNotification",
                       "locked"}
# The lock screen reports itself as a focused app (Oct 27: "loginwindow" all night). That's the display
# still off, not him coming back, so it never ends an off-span.
LOCK_SCREEN_APPS = {"loginwindow", "ScreenSaverEngine"}
# the only observation that gets through ghost. A display sleeping or the screen locking doesn't
# count: that happens at dinner too, which is what ghost is for.
GHOST_ENDING_REASONS = {"NSWorkspaceWillSleepNotification"}
# His rule (Oct 13): a sleep ends ghost only if it runs through the night. Ghost at 10 AM, lid closed,
# back at 6 PM is a valid ghost; lid closed at 3:57 AM and back at 1 PM is a night's sleep. Knob, local time.
NIGHT_HOURS = (0, 7)
STATUS_CHANGE_TYPES = ("timer.start", "timer.stop", "state.set", "focus.set", "break.start",
                       "ghost.start")

# Focus is a layer on a task: focus.set events reference the task and carry a tier.
FOCUS_NAMES = {1: "focused", 2: "deep", 3: "hyperfocus"}


def focus_events(conn: sqlite3.Connection, ids: list[str]) -> dict[str, list[dict[str, Any]]]:
    """Map task id -> its focus.set events, oldest first."""
    out: dict[str, list[dict[str, Any]]] = {}
    for i in range(0, len(ids), 500):
        chunk = ids[i : i + 500]
        marks = ",".join("?" * len(chunk))
        rows = conn.execute(
            f"SELECT * FROM events WHERE type = 'focus.set' AND ref IN ({marks}) ORDER BY start, recorded_at",
            chunk,
        ).fetchall()
        for r in rows:
            e = db.to_dict(r)
            out.setdefault(e["ref"], []).append({"at": e["start"], "tier": e["data"].get("tier", 0)})
    return out
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
    if not r:
        return None
    span = db.to_dict(r)
    # A rename (entry.amend with a label) shows on the running span too, not only in history.
    fix = conn.execute("SELECT data FROM events WHERE type = 'entry.amend' AND ref = ?"
                       " ORDER BY recorded_at DESC LIMIT 1", (span["id"],)).fetchone()
    if fix:
        d = json.loads(fix["data"] or "{}")
        span["label"] = d.get("label") or span["label"]
        if "word" in d or d.get("label"):   # a rename without a word clears the old one
            span["data"] = {**span.get("data", {}), "word": d.get("word")}
    return span


def running_timer(conn: sqlite3.Connection) -> dict[str, Any] | None:
    return _open_span(conn, "timer.start")


def ghost(conn: sqlite3.Connection) -> dict[str, Any] | None:
    """Ghost mode: he's gone dark. Nothing is logged about him until he comes back."""
    return _open_span(conn, "ghost.start")


def on_break(conn: sqlite3.Connection) -> dict[str, Any] | None:
    return _open_span(conn, "break.start")


def state_events(conn: sqlite3.Connection, until: datetime | None = None) -> list[dict[str, Any]]:
    q = "SELECT * FROM events WHERE type = 'state.set'"
    args: tuple = ()
    if until is not None:
        q += " AND start < ?"
        args = (db.iso(until),)
    return [db.to_dict(r) for r in conn.execute(q + " ORDER BY start, recorded_at", args).fetchall()]


def active_states(conn: sqlite3.Connection) -> list[dict[str, Any]]:
    """Which substances are on right now, and since when."""
    since: dict[str, str] = {}
    for e in state_events(conn):
        name = e["data"].get("state")
        if e["data"].get("on"):
            since.setdefault(name, e["start"])
        else:
            since.pop(name, None)
    return [{"state": k, "since": v} for k, v in since.items() if k in STATES]


def state_spans(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    """Each substance as on-spans overlapping [lo, hi). An open span ends now."""
    now = db.utcnow()
    open_at: dict[str, datetime] = {}
    spans = []
    for e in state_events(conn, until=hi):
        name, at = e["data"].get("state"), db.parse(e["start"])
        if e["data"].get("on"):
            open_at.setdefault(name, at)
        elif name in open_at:
            spans.append((name, open_at.pop(name), at))
    spans += [(n, s, min(now, hi)) for n, s in open_at.items()]
    out = []
    for name, s, e in spans:
        c = _clip(s, e, lo, hi)
        if c:
            out.append(_seg(c[0], c[1], state=name))
    return out


def break_end_at(b: dict[str, Any], back: datetime) -> datetime:
    """When the break claim ends if he's back at `back`: then, or at its kind's cap."""
    cap = BREAK_CAP.get(b["data"].get("kind"))
    start = db.parse(b["start"])
    return min(back, start + cap) if cap else back


def expire_break(conn: sqlite3.Connection) -> dict[str, Any] | None:
    """A break nobody came back from: end it BREAK_ASSUMED after it began and go ghost from
    there, remembering the paused task so ⌘B can still resume it. Returns the ghost, if any."""
    b = on_break(conn)
    if not b:
        return None
    start = db.parse(b["start"])
    if db.utcnow() - start < BREAK_GHOST_AFTER:
        return None
    end = start + BREAK_ASSUMED
    db.append(conn, kind="claim", type="timer.stop", source="auto", start=end, ref=b["id"])
    return db.append(conn, kind="claim", type="ghost.start", source="auto", start=end,
                     label=f"away after a {b['label']}",
                     data={"from_break": b["id"], "kind": b["data"].get("kind"),
                           "resume": b["data"].get("resume")})


def overlaps_night(a: datetime, b: datetime) -> bool:
    """Does [a, b) touch NIGHT_HOURS on any day, in his local time?"""
    from zoneinfo import ZoneInfo
    tz = ZoneInfo("America/New_York")
    day = a.astimezone(tz).date() - timedelta(days=1)
    while datetime.combine(day, datetime.min.time(), tz) < b:
        lo = datetime.combine(day, datetime.min.time(), tz).replace(hour=NIGHT_HOURS[0])
        hi = datetime.combine(day, datetime.min.time(), tz).replace(hour=NIGHT_HOURS[1])
        if a < hi and lo < b:
            return True
        day += timedelta(days=1)
    return False


def ghost_sleep(conn: sqlite3.Connection) -> dict[str, Any] | None:
    """The Mac's latest sleep during the current ghost that he hasn't come back from yet (no app.focus after)."""
    g = ghost(conn)
    if not g:
        return None
    marks = ",".join("?" * len(GHOST_ENDING_REASONS))
    r = conn.execute(
        "SELECT * FROM events s WHERE s.type = 'away.start' AND s.start >= ?"
        f" AND json_extract(s.data, '$.reason') IN ({marks}) AND NOT EXISTS ("
        "  SELECT 1 FROM events f WHERE f.type = 'app.focus' AND f.start >= s.start)"
        " ORDER BY s.start DESC LIMIT 1", (g["start"], *GHOST_ENDING_REASONS)).fetchone()
    return db.to_dict(r) if r else None


def end_ghost_after_night(conn: sqlite3.Connection, back_at: datetime) -> datetime | None:
    """He's back (or the bar opened) at `back_at`: if the Mac slept through the night during ghost, the ghost
    ends when it went to sleep, logged as an `auto` stop so history stays honest. Returns that time, if so."""
    s = ghost_sleep(conn)
    if not s or not overlaps_night(db.parse(s["start"]), back_at):
        return None
    slept = db.parse(s["start"])
    db.append(conn, kind="claim", type="timer.stop", source="auto", start=slept, ref=ghost(conn)["id"],
              data={"reason": "slept"})
    return slept


def is_stale(display_off_at: datetime | None, last_change_at: datetime, now: datetime) -> bool:
    """His rule (Oct 12): a status is stale when the display has been off for STALE_MIN_OFF AND
    it's been more than STALE_AFTER since he last changed it. `display_off_at` is None while the
    display is on. `now` is the moment being judged (for a past night, when the display came back)."""
    return (display_off_at is not None and now - display_off_at >= STALE_MIN_OFF
            and now - last_change_at > STALE_AFTER)


def expire_stale(conn: sqlite3.Connection) -> datetime | None:
    """A status left over from last night: if is_stale() says so, end the task and clear the
    states at the moment the display went off, logged as `auto` events so history stays
    honest. Ghost is left alone (he chose it). Returns when the status was cleared, if it was."""
    timer, on = running_timer(conn), active_states(conn)
    if (not timer and not on) or ghost(conn):
        return None
    marks = ",".join("?" * len(STATUS_CHANGE_TYPES))
    last = conn.execute(f"SELECT MAX(start) FROM events WHERE type IN ({marks})",
                        STATUS_CHANGE_TYPES).fetchone()[0]
    if last is None:
        return None
    last_change = db.parse(last)

    # Walk the display-off spans since the last change; the first stale one wins.
    off_at, stale_at = None, None
    for r in conn.execute("SELECT type, start, data FROM events WHERE type IN ('app.focus', 'away.start')"
                          " AND start >= ? ORDER BY start", (last,)):
        a = db.to_dict(r)
        if a["type"] == "away.start" and a["data"].get("reason") in DISPLAY_OFF_REASONS:
            off_at = off_at or db.parse(a["start"])
        elif a["type"] == "app.focus" and off_at and a["data"].get("app") not in LOCK_SCREEN_APPS:
            if is_stale(off_at, last_change, db.parse(a["start"])):
                stale_at = off_at
                break
            off_at = None
    if stale_at is None and off_at and is_stale(off_at, last_change, db.utcnow()):
        stale_at = off_at
    if stale_at is None:
        return None

    if timer:
        db.append(conn, kind="claim", type="timer.stop", source="auto", start=stale_at,
                  ref=timer["id"], data={"reason": "stale"})
    for s in on:
        db.append(conn, kind="claim", type="state.set", source="auto", start=stale_at,
                  data={"state": s["state"], "on": False, "reason": "stale"})
    return stale_at


def claims(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    """What he said he did, as segments overlapping [lo, hi). Running timer has end=None."""
    now = db.utcnow()
    events = db.query(conn, types=CLAIM_TYPES, since=lo - CLAIM_LOOKBACK, until=hi)
    ids = [e["id"] for e in events]
    deleted = db.refs_to(conn, "entry.delete", ids)
    stops = db.refs_to(conn, "timer.stop", ids)
    amends = db.refs_to(conn, "entry.amend", ids, latest=True)
    focus = focus_events(conn, ids)

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
        elif e["type"] in ("timer.start", "ghost.start", "break.start"):
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
                type={"timer.start": "timer", "ghost.start": "ghost",
                      "break.start": "break"}.get(e["type"], "entry"),
                running=running,
                focus=focus.get(e["id"], []),
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
        if e["type"] != "app.focus" or not e["data"]:
            continue  # an empty app.focus is a ghost wake mark: it ends an away, it isn't activity
        start = db.parse(e["start"])
        nxt = db.parse(events[i + 1]["start"]) if i + 1 < len(events) else now
        end = min(nxt, start + ACTIVITY_CAP, now)
        clipped = _clip(start, end, lo, hi)
        if not clipped:
            continue
        app = e["data"].get("app") or "unknown"
        # Window title and browser URL.
        title, url = e["data"].get("title") or "", e["data"].get("url") or ""
        s, en = clipped
        last = segs[-1] if segs else None
        if (last and last["app"] == app and last.get("title", "") == title and last.get("url", "") == url
                and db.parse(last["end"]) >= s - timedelta(seconds=1)):
            last["end"] = db.iso(en)
        else:
            extra = {k: v for k, v in (("title", title), ("url", url)) if v}
            segs.append(_seg(s, en, app=app, bundle_id=e["data"].get("bundle_id"), **extra))
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
    return [{"id": e["id"], "at": e["start"],
             "at_local": db.parse(e["start"]).astimezone().strftime("%-I:%M %p"),
             "text": e["label"], "during": e["data"].get("during")}
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
        "states": state_spans(conn, lo, hi),
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
                      "end": c["end"], "minutes": _minutes(min(e, hi) - max(s, lo)),
                      "focus_peak": max((f["tier"] for f in c.get("focus", [])), default=0)})
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

    # Minutes spent at each focus tier, from each task's focus.set events up to the next
    # change or the task's end.
    by_focus: dict[str, timedelta] = {}
    for c in tl["claims"]:
        c_end = db.parse(c["end"]) if c["end"] else now
        marks = c.get("focus", [])
        for i, f in enumerate(marks):
            if not f["tier"]:
                continue
            f_start = db.parse(f["at"])
            f_end = db.parse(marks[i + 1]["at"]) if i + 1 < len(marks) else c_end
            clipped = _clip(f_start, min(f_end, c_end), lo, hi)
            if clipped:
                name = FOCUS_NAMES[f["tier"]]
                by_focus[name] = by_focus.get(name, timedelta()) + (clipped[1] - clipped[0])

    by_state: dict[str, timedelta] = {}
    for sp in state_spans(conn, lo, hi):
        d = db.parse(sp["end"]) - db.parse(sp["start"])
        by_state[sp["state"]] = by_state.get(sp["state"], timedelta()) + d

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
        "by_focus": {k: _minutes(by_focus[k]) for k in FOCUS_NAMES.values() if k in by_focus},
        "by_state": {k: _minutes(by_state[k]) for k in STATES if k in by_state},
    }


def now_state(conn: sqlite3.Connection) -> dict[str, Any]:
    now = db.utcnow()
    timer = running_timer(conn)
    g = ghost(conn)
    b = on_break(conn)
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
            {"id": timer["id"], "label": timer["label"], "word": (timer.get("data") or {}).get("word"),
             "start": timer["start"],
             "elapsed_minutes": _minutes(now - db.parse(timer["start"])),
             "focus": (focus_events(conn, [timer["id"]]).get(timer["id"]) or [{"tier": 0}])[-1]["tier"]}
            if timer else None
        ),
        "activity": current_app,
        "meeting": meeting,
        "ghost": (
            {"id": g["id"], "status": g["label"], "start": g["start"],
             "elapsed_minutes": _minutes(now - db.parse(g["start"])),
             "resume": g["data"].get("resume")}
            if g else None
        ),
        "on_break": (
            {"id": b["id"], "kind": b["data"].get("kind"), "label": b["label"], "start": b["start"],
             "resume": b["data"].get("resume"), "elapsed_minutes": _minutes(now - db.parse(b["start"]))}
            if b else None
        ),
        "states": active_states(conn),
    }

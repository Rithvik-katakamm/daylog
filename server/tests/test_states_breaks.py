"""Substances, breaks, and a break you never came back from."""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from daylog import db, timeline


class Clock:
    def __init__(self):
        self.t = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(hours=3)

    def __call__(self):
        return self.t

    def advance(self, **kw):
        self.t += timedelta(**kw)


@pytest.fixture
def clock(monkeypatch):
    c = Clock()
    monkeypatch.setattr(db, "utcnow", c)
    return c


@pytest.fixture
def client(tmp_path, monkeypatch, clock):
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "t.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    from daylog.api import app
    with TestClient(app) as c:
        yield c


def states(c):
    return {s["state"] for s in c.get("/now").json()["states"]}


# ---------- substances ----------

def test_state_toggles_and_is_global(client):
    assert states(client) == set()
    client.post("/state", json={"state": "high"})
    assert states(client) == {"high"}
    client.post("/log", json={"text": "reading"})          # switching tasks keeps it on
    client.post("/state", json={"state": "caffeinated"})
    assert states(client) == {"high", "caffeinated"}
    client.post("/state", json={"state": "high"})          # toggle off
    assert states(client) == {"caffeinated"}


def test_state_explicit_on_is_idempotent(client):
    client.post("/state", json={"state": "intoxicated", "on": True})
    client.post("/state", json={"state": "intoxicated", "on": True})
    assert states(client) == {"intoxicated"}


def test_unknown_state_rejected(client):
    assert client.post("/state", json={"state": "sleepy"}).status_code == 422


def test_summary_counts_minutes_per_state(client, clock):
    start = clock.t
    client.post("/state", json={"state": "high"})
    clock.advance(minutes=40)
    client.post("/state", json={"state": "high"})
    window = {"start": db.iso(start - timedelta(hours=1)), "end": db.iso(clock.t + timedelta(hours=1))}
    assert client.get("/summary", params=window).json()["by_state"] == {"high": 40}  # no midnight flake


# ---------- breaks ----------

def test_walk_pauses_and_resumes_the_task(client, clock):
    start = clock.t
    client.post("/log", json={"text": "building daylog"})
    clock.advance(minutes=20)
    now = client.post("/break", json={"kind": "walk"}).json()
    assert now["timer"] is None
    assert now["on_break"]["kind"] == "walk" and now["on_break"]["resume"] == "building daylog"
    clock.advance(minutes=8)
    back = client.delete("/break").json()
    assert back["resumed"] == "building daylog"
    assert back["timer"]["label"] == "building daylog" and back["on_break"] is None
    assert "high" not in {s["state"] for s in back["states"]}
    window = {"start": db.iso(start - timedelta(hours=1)), "end": db.iso(clock.t + timedelta(hours=1))}
    assert client.get("/summary", params=window).json()["by_label"]["walk"] == 8  # no midnight flake


def test_smoke_break_comes_back_high(client, clock):
    client.post("/log", json={"text": "linear cleanup"})
    client.post("/break", json={"kind": "smoke"})
    clock.advance(minutes=10)
    back = client.delete("/break").json()
    assert {s["state"] for s in back["states"]} == {"high"}
    assert back["timer"]["label"] == "linear cleanup"


def test_break_without_a_task(client):
    client.post("/break", json={"kind": "walk"})
    back = client.delete("/break").json()
    assert back["resumed"] is None and back["timer"] is None


def test_double_break_and_end_without_break(client):
    client.post("/break", json={})
    assert client.post("/break", json={}).status_code == 409
    client.delete("/break")
    assert client.delete("/break").status_code == 409


def test_starting_a_task_ends_the_break(client):
    client.post("/break", json={})
    now = client.post("/log", json={"text": "something new"}).json()
    assert now["timer"]["label"] == "something new" and now["on_break"] is None


def test_break_you_never_came_back_from_becomes_ghost(client, clock):
    client.post("/log", json={"text": "deep work"})
    client.post("/break", json={"kind": "smoke"})
    start = clock.t
    clock.advance(minutes=59)
    assert client.get("/now").json()["on_break"] is not None   # still just a break
    clock.advance(minutes=2)
    now = client.get("/now").json()
    assert now["on_break"] is None
    assert now["ghost"]["resume"] == "deep work"
    # The break is logged as ~15 min, and ghost starts right after it.
    assert db.parse(now["ghost"]["start"]) == start + timeline.BREAK_ASSUMED
    tl = client.get("/timeline", params={"start": db.iso(start - timedelta(minutes=1)),
                                         "end": db.iso(clock.t)}).json()
    brk = next(c for c in tl["claims"] if c["type"] == "break")
    assert db.parse(brk["end"]) - db.parse(brk["start"]) == timeline.BREAK_ASSUMED
    # ⌘B still brings you back: ghost ends, the task resumes, and smoke means high.
    back = client.delete("/break").json()
    assert back["ghost"] is None and back["timer"]["label"] == "deep work"
    assert {s["state"] for s in back["states"]} == {"high"}


def _break_claim(client, start, clock):
    tl = client.get("/timeline", params={"start": db.iso(start - timedelta(minutes=1)),
                                         "end": db.iso(clock.t)}).json()
    return next(c for c in tl["claims"] if c["type"] == "break")


def test_smoke_break_back_late_is_logged_only_to_the_cap(client, clock):
    # Oct 13: "a 44-min smoke break that wasn't". Smoking is logged to the cap; the rest is a gap.
    client.post("/log", json={"text": "deep work"})
    client.post("/break", json={"kind": "smoke"})
    start = clock.t
    clock.advance(minutes=44)
    back = client.delete("/break").json()
    assert back["timer"]["label"] == "deep work"
    assert {s["state"] for s in back["states"]} == {"high"}   # smoke still means high
    brk = _break_claim(client, start, clock)
    assert db.parse(brk["end"]) - db.parse(brk["start"]) == timeline.BREAK_CAP["smoke"]
    assert db.parse(back["timer"]["start"]) == clock.t        # nothing claimed in between


def test_smoke_break_back_in_time_is_logged_as_is(client, clock):
    client.post("/break", json={"kind": "smoke"})
    start = clock.t
    clock.advance(minutes=6)
    client.delete("/break")
    brk = _break_claim(client, start, clock)
    assert db.parse(brk["end"]) - db.parse(brk["start"]) == timedelta(minutes=6)


def test_walks_have_no_cap(client, clock):
    client.post("/break", json={"kind": "walk"})
    start = clock.t
    clock.advance(minutes=35)
    client.delete("/break")
    brk = _break_claim(client, start, clock)
    assert db.parse(brk["end"]) - db.parse(brk["start"]) == timedelta(minutes=35)


def test_plain_ghost_is_not_ended_by_break_key(client):
    client.post("/ghost", json={"status": "dinner"})
    assert client.delete("/break").status_code == 409


# ---------- breaks you name, and take back by typing (his calls, Oct 13) ----------

def test_typing_peeing_starts_a_named_break_and_back_resumes(client, clock):
    client.post("/timer/start", json={"label": "daylog backend."})
    clock.advance(minutes=30)
    now = client.post("/log", json={"text": "peeing"}).json()
    assert now["on_break"]["label"] == "peeing" and now["timer"] is None
    clock.advance(minutes=3)
    now = client.post("/log", json={"text": "back"}).json()
    assert now["timer"]["label"] == "daylog backend." and now["on_break"] is None


def test_didnt_actually_break_takes_the_break_back_replaying_oct_13(client, clock):
    # 5:41:56 PM: ⌘B walk while on "daylog backend."; 5:47:37 PM he typed "didnt actually break".
    # It must not become a task: the break goes, and the task runs on from the break's start.
    start = clock.t
    client.post("/timer/start", json={"label": "daylog backend."})
    clock.advance(minutes=60)
    client.post("/break", json={"kind": "walk"})
    clock.advance(minutes=5)
    now = client.post("/log", json={"text": "didnt actually break"}).json()
    assert now["did"] == "no break after all"
    assert now["on_break"] is None and now["timer"]["label"] == "daylog backend."
    window = {"start": db.iso(start - timedelta(hours=1)), "end": db.iso(clock.t + timedelta(hours=1))}
    by = client.get("/summary", params=window).json()["by_label"]  # no midnight flake
    assert "didnt actually break" not in by and "walk" not in by
    assert by["daylog backend."] == 65  # the 5 minutes count as task time


def test_take_back_only_means_something_on_a_break(client):
    client.post("/timer/start", json={"label": "coding"})
    assert client.post("/log", json={"text": "never mind"}).status_code == 409

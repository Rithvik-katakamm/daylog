"""Stale status: display off and no change for 3h ends last night's task and states."""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from daylog import db, timeline


class Clock:
    def __init__(self):
        self.t = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(hours=12)

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
    from daylog.api import app
    with TestClient(app) as c:
        yield c


def observe(c, clock, type, reason=None, app="Terminal"):
    data = {"reason": reason} if reason else {"app": app}
    c.post("/observations", json={"type": type, "start": db.iso(clock.t), "data": data})


# ---------- the rule: is_stale ----------

T0 = datetime(2026, 10, 12, 1, 0, tzinfo=timezone.utc)


def test_display_off_and_over_3h_is_stale():
    assert timeline.is_stale(T0 + timedelta(hours=1), T0, T0 + timedelta(hours=3, minutes=1))


def test_display_on_is_never_stale():
    assert not timeline.is_stale(None, T0, T0 + timedelta(hours=10))


def test_display_off_under_3h_is_not_stale():
    assert not timeline.is_stale(T0 + timedelta(minutes=10), T0, T0 + timedelta(hours=3))


def test_quick_lock_late_in_a_long_session_is_not_stale():
    off = T0 + timedelta(hours=4)
    assert not timeline.is_stale(off, T0, off + timedelta(minutes=5))


# ---------- plumbing: /now applies it ----------

def test_night_away_ends_task_and_states_when_display_went_off(client, clock):
    client.post("/log", json={"text": "watching anime"})
    client.post("/state", json={"state": "high"})
    clock.advance(hours=1)
    observe(client, clock, "away.start", "NSWorkspaceScreensDidSleepNotification")
    off = clock.t
    clock.advance(hours=7)
    observe(client, clock, "app.focus")                     # morning: display back on
    now = client.get("/now").json()
    assert now["timer"] is None and now["states"] == []
    tl = client.get("/timeline", params={"start": db.iso(off - timedelta(hours=2)),
                                         "end": db.iso(clock.t)}).json()
    anime = next(c for c in tl["claims"] if c["label"] == "watching anime")
    assert db.parse(anime["end"]) == off                    # ended when the display went off


def test_lock_screen_focus_is_not_the_display_coming_back(client, clock):
    # Oct 27: display off at 2:17, then the lock screen showed up as app.focus "loginwindow"
    # through the night; that ended the off-span after 4 min and the task ran 23 hours.
    client.post("/log", json={"text": "jobhunt"})
    clock.advance(hours=4)
    observe(client, clock, "away.start", "NSWorkspaceScreensDidSleepNotification")
    off = clock.t
    for _ in range(3):
        clock.advance(minutes=4)
        observe(client, clock, "app.focus", app="loginwindow")
    clock.advance(hours=10)
    observe(client, clock, "app.focus")                     # morning: really back
    assert client.get("/now").json()["timer"] is None
    tl = client.get("/timeline", params={"start": db.iso(off - timedelta(hours=5)),
                                         "end": db.iso(clock.t)}).json()
    assert db.parse(next(c for c in tl["claims"] if c["label"] == "jobhunt")["end"]) == off


def test_still_asleep_past_3h_clears_on_next_check(client, clock):
    client.post("/log", json={"text": "reading"})
    observe(client, clock, "away.start", "locked")
    clock.advance(hours=4)
    assert client.get("/now").json()["timer"] is None


def test_short_display_off_keeps_status(client, clock):
    client.post("/log", json={"text": "deep work"})
    clock.advance(minutes=30)
    observe(client, clock, "away.start", "NSWorkspaceScreensDidSleepNotification")
    clock.advance(minutes=20)
    observe(client, clock, "app.focus")
    clock.advance(hours=4)                                   # back at the desk, long session
    assert client.get("/now").json()["timer"]["label"] == "deep work"


def test_bathroom_lock_after_4h_of_deep_work_keeps_status(client, clock):
    client.post("/log", json={"text": "deep work"})
    clock.advance(hours=4)
    observe(client, clock, "away.start", "locked")
    clock.advance(minutes=5)
    observe(client, clock, "app.focus")
    assert client.get("/now").json()["timer"]["label"] == "deep work"


def test_idle_alone_is_not_display_off(client, clock):
    client.post("/log", json={"text": "thinking"})
    observe(client, clock, "away.start", "idle")
    clock.advance(hours=5)
    assert client.get("/now").json()["timer"]["label"] == "thinking"


def test_ghost_is_left_alone(client, clock):
    client.post("/state", json={"state": "caffeinated"})
    client.post("/ghost", json={"status": "dinner"})
    clock.advance(hours=4)
    now = client.get("/now").json()
    assert now["ghost"] is not None and now["states"] != []

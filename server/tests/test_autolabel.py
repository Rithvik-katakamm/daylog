"""Auto-labeler (RIT-120): zero-input labels for every minute, derived from the log."""
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from daylog import autolabel, db


class Clock:
    def __init__(self):
        # 9 AM New York on a fixed day, so sleep-window rules are deterministic.
        self.t = datetime(2026, 10, 5, 13, 0, tzinfo=timezone.utc)

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


def focus(c, clock, app, **extra):
    c.post("/observations", json={"type": "app.focus", "start": db.iso(clock.t), "data": {"app": app, **extra}})


def work(c, clock, app, minutes, **extra):
    """Sit in an app for a while: the real recorder sends a heartbeat every 5 minutes."""
    for _ in range(0, minutes, 5):
        focus(c, clock, app, **extra)
        clock.advance(minutes=min(5, minutes))


def away(c, clock):
    c.post("/observations", json={"type": "away.start", "start": db.iso(clock.t), "data": {"reason": "locked"}})


def segs(c):
    return c.get("/auto", params={"start": db.iso(datetime(2026, 10, 5, 4, tzinfo=timezone.utc)),
                                  "end": db.iso(datetime(2026, 10, 6, 4, tzinfo=timezone.utc))}).json()


# ---------- rules ----------

def test_app_and_site_rules():
    R = autolabel.rules()
    assert autolabel.app_category(R, "iTerm2")[0] == "build"
    assert autolabel.app_category(R, "Safari", url="https://www.youtube.com/watch?v=x")[0] == "watch"
    assert autolabel.app_category(R, "Safari", url="https://linear.app/x")[0] == "plan"
    assert autolabel.app_category(R, "Safari")[1] < 0.5          # unknown site: low confidence
    assert autolabel.claim_category(R, "watching b99") == "watch"
    assert autolabel.task_key("working on dauylog focused.") == "working on dauylog"


# ---------- labeling a day ----------

def test_typed_task_wins_and_unlabeled_time_gets_a_rule_label(client, clock):
    client.post("/log", json={"text": "building day log"})
    work(client, clock, "iTerm2", 30)
    client.post("/timer/stop")
    work(client, clock, "WhatsApp", 20)
    out = segs(client)
    kinds = [(s["category"], s["source"]) for s in out["segments"] if s["minutes"] >= 5]
    assert ("build", "claim") in kinds
    assert ("talk", "rule") in kinds
    assert out["summary"]["by_source"]["claim"] >= 29


def test_task_left_running_while_asleep_becomes_sleep(client, clock):
    clock.t = datetime(2026, 10, 5, 4, 30, tzinfo=timezone.utc)       # 12:30 AM local
    client.post("/log", json={"text": "watching anime"})
    work(client, clock, "Safari", 20, url="https://crunchyroll.com/x")
    away(client, clock)
    clock.advance(hours=7)                                             # asleep, timer still running
    focus(client, clock, "iTerm2")
    clock.advance(minutes=5)
    out = segs(client)["summary"]["by_category"]
    assert out.get("sleep", 0) >= 6 * 60
    assert out.get("watch", 0) < 40                                    # not 7 hours of anime


def test_history_guesses_the_task_he_usually_types(client, clock):
    client.post("/log", json={"text": "reading papers"})
    work(client, clock, "Preview", 60)
    client.post("/timer/stop")
    clock.advance(hours=25)                                            # next day, nothing typed
    work(client, clock, "Preview", 30)
    day = client.get("/auto", params={"start": db.iso(datetime(2026, 10, 6, 4, tzinfo=timezone.utc)),
                                      "end": db.iso(datetime(2026, 10, 7, 4, tzinfo=timezone.utc))}).json()
    guess = [s for s in day["segments"] if s["source"] == "history"]
    assert guess and guess[0]["task"] == "reading papers"


def test_short_away_inside_work_is_still_work(client, clock):
    client.post("/log", json={"text": "deep work"})
    work(client, clock, "iTerm2", 20)
    away(client, clock)
    clock.advance(minutes=3)
    work(client, clock, "iTerm2", 20)
    out = segs(client)
    assert not any(s["category"] == "away" and s["minutes"] <= 5 and s["start"] > db.iso(datetime(2026, 10, 5, 13, tzinfo=timezone.utc))
                   for s in out["segments"])


def test_score_reports_accuracy(client, clock):
    client.post("/log", json={"text": "building day log"})
    work(client, clock, "iTerm2", 30)
    client.post("/log", json={"text": "watching a video"})
    work(client, clock, "iTerm2", 30)                                  # video in a terminal? rules miss it
    s = client.get("/auto/score", params={"days": 2}).json()
    assert s["minutes_scored"] >= 55
    assert 30 <= s["category_accuracy_pct"] <= 70
    assert any("iTerm2" in k for k in s["top_misses"])


# ---------- RIT-122: the guess, confirm/correct = labels, and the numbers ----------

def test_guess_shows_when_nothing_runs_and_confirm_becomes_a_label(client, clock):
    from daylog import autolabel as al
    al._guess_cache.update(at=None)
    work(client, clock, "WhatsApp", 20)
    now = client.get("/now").json()
    g = now["guess"]
    assert g["category"] == "talk" and g["ask"] in (True, False)
    client.post("/label", json={"action": "shown", "guess": g})
    client.post("/label", json={"action": "confirm", "category": g["category"], "task": g["task"],
                                "start": g["start"], "end": g["end"], "guess": g})
    day = segs(client)
    assert any(s["category"] == "talk" and s["source"] == "claim" for s in day["segments"])
    fb = client.get("/auto/score", params={"days": 1}).json()["label_feedback"]
    assert fb == {"shown": 1, "confirmed": 1, "corrected": 0, "acceptance_pct": 100}


def test_no_guess_while_a_task_runs(client, clock):
    from daylog import autolabel as al
    al._guess_cache.update(at=None)
    client.post("/log", json={"text": "building day log"})
    work(client, clock, "iTerm2", 10)
    assert client.get("/now").json()["guess"] is None


def test_correction_takes_the_category_from_what_he_typed(client, clock):
    from daylog import autolabel as al
    al._guess_cache.update(at=None)
    work(client, clock, "iTerm2", 20)
    g = client.get("/now").json()["guess"]
    assert g["category"] == "build"
    lab = client.post("/label", json={"action": "correct", "text": "watching anime",
                                      "start": g["start"], "end": g["end"], "guess": g}).json()
    assert lab["data"]["category"] == "watch" and lab["data"]["task"] == "watching anime"

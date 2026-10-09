import sqlite3
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from daylog import db, timeline, wispr


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "t.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    from daylog.api import app
    with TestClient(app) as c:
        yield c


class Clock:
    """A controllable clock so tests can say 'ten minutes pass'."""
    def __init__(self):
        self.t = datetime.now(timezone.utc).replace(microsecond=0) - timedelta(hours=2)

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
def conn(tmp_path):
    return db.connect(tmp_path / "c.sqlite")


def ago(**kw):
    return datetime.now(timezone.utc) - timedelta(**kw)


# ---------- the invariant ----------

def test_events_table_rejects_update_and_delete(conn):
    e = db.append(conn, kind="claim", type="entry.log", source="t",
                  start=ago(hours=1), end=ago(minutes=1), label="x")
    with pytest.raises(sqlite3.DatabaseError, match="append-only"):
        conn.execute("UPDATE events SET label = 'y' WHERE id = ?", (e["id"],))
    with pytest.raises(sqlite3.DatabaseError, match="append-only"):
        conn.execute("DELETE FROM events WHERE id = ?", (e["id"],))


def test_source_key_makes_imports_idempotent(conn):
    kw = dict(kind="observation", type="meeting", source="wispr", start=ago(hours=2),
              end=ago(hours=1), label="m", source_key="wispr:meeting:1")
    assert db.append(conn, **kw) is not None
    assert db.append(conn, **kw) is None


# ---------- timer ----------

def test_timer_start_stop_roundtrip(client, clock):
    r = client.post("/timer/start", json={"label": "coding daylog"})
    assert r.status_code == 201
    assert r.json()["timer"]["label"] == "coding daylog"

    tl = client.get("/timeline").json()
    assert [c["running"] for c in tl["claims"]] == [True]

    clock.advance(minutes=25)
    r = client.post("/timer/stop")
    assert r.status_code == 200 and r.json()["timer"] is None
    tl = client.get("/timeline").json()
    assert tl["claims"][0]["running"] is False and tl["claims"][0]["end"]


def test_starting_a_timer_stops_the_previous_one(client, clock):
    client.post("/timer/start", json={"label": "a"})
    clock.advance(minutes=10)
    client.post("/timer/start", json={"label": "b"})
    claims = client.get("/timeline").json()["claims"]
    assert [(c["label"], c["running"]) for c in claims] == [("a", False), ("b", True)]


def test_stop_with_nothing_running_is_409(client):
    assert client.post("/timer/stop").status_code == 409


# ---------- entries ----------

def test_log_minutes_ending_now(client):
    r = client.post("/entries", json={"label": "ideated about daylog", "minutes": 40})
    assert r.status_code == 201
    s = client.get("/summary").json()
    # The entry may straddle midnight when tests run just after 00:00.
    assert 0 < s["by_label"]["ideated about daylog"] <= 40


def test_future_entries_rejected(client):
    now = datetime.now(timezone.utc)
    r = client.post("/entries", json={"label": "x", "start": now.isoformat(),
                                      "end": (now + timedelta(hours=1)).isoformat()})
    assert r.status_code == 422


def test_delete_is_a_tombstone_not_an_erase(client):
    e = client.post("/entries", json={"label": "oops", "minutes": 5}).json()
    assert client.delete(f"/entries/{e['id']}").status_code == 200
    assert client.get("/timeline").json()["claims"] == []
    # The original row is still in the log.
    from daylog.api import app
    assert db.get(app.state.conn, e["id"])["label"] == "oops"


# ---------- activity derivation ----------

def test_activity_segments_merge_and_cap(conn):
    t0 = ago(minutes=60)
    for minutes, app in [(0, "Cursor"), (5, "Cursor"), (8, "Safari"), (9, "Cursor")]:
        db.append(conn, kind="observation", type="app.focus", source="mac",
                  start=t0 + timedelta(minutes=minutes), data={"app": app})
    db.append(conn, kind="observation", type="away.start", source="mac",
              start=t0 + timedelta(minutes=12))
    segs = timeline.activity(conn, t0 - timedelta(hours=1), datetime.now(timezone.utc))
    got = [(s["app"], round((db.parse(s["end"]) - db.parse(s["start"])).seconds / 60)) for s in segs]
    # Cursor 0-5 and the 5-min heartbeat merge into 0-8; away at 12 ends the last one.
    assert got == [("Cursor", 8), ("Safari", 1), ("Cursor", 3)]


def test_activity_never_invents_time_past_the_cap(conn):
    db.append(conn, kind="observation", type="app.focus", source="mac",
              start=ago(hours=3), data={"app": "Cursor"})
    segs = timeline.activity(conn, ago(hours=4), datetime.now(timezone.utc))
    assert len(segs) == 1
    length = db.parse(segs[0]["end"]) - db.parse(segs[0]["start"])
    assert length == timeline.ACTIVITY_CAP


def test_observation_endpoint_only_accepts_known_types(client):
    assert client.post("/observations", json={"type": "app.focus", "data": {"app": "X"}}).status_code == 201
    assert client.post("/observations", json={"type": "timer.start"}).status_code == 422


# ---------- wispr import ----------

def test_wispr_import_meetings_and_dictations(conn, tmp_path):
    w = sqlite3.connect(tmp_path / "flow.sqlite")
    w.executescript("""
        CREATE TABLE Meetings (id TEXT, title TEXT, createdAt TEXT, endedAt INTEGER,
            participantNames TEXT, isDeleted INTEGER, isTourDemo INTEGER);
        CREATE TABLE History (transcriptEntityId TEXT, timestamp TEXT, app TEXT, url TEXT,
            duration REAL, numWords INTEGER, isArchived INTEGER);
    """)
    start = datetime(2026, 10, 8, 20, 0, tzinfo=timezone.utc)
    end_ms = int((start + timedelta(minutes=30)).timestamp() * 1000)
    w.execute("INSERT INTO Meetings VALUES ('m1','Sync','2026-10-08 20:00:00.000 +00:00',?,NULL,0,0)", (end_ms,))
    w.execute("INSERT INTO Meetings VALUES ('m2','Live','2026-10-08 21:00:00.000 +00:00',NULL,NULL,0,0)")
    w.execute("INSERT INTO History VALUES ('d1','2026-10-08 20:10:05.000 +00:00','com.apple.Safari','x.com',5.0,12,0)")
    w.commit()
    w.close()

    assert wispr.import_all(conn, tmp_path / "flow.sqlite") == {"meetings": 1, "dictations": 1}
    assert wispr.import_all(conn, tmp_path / "flow.sqlite") == {"meetings": 0, "dictations": 0}

    ms = timeline.meetings(conn, start - timedelta(hours=1), start + timedelta(hours=2))
    assert [(m["label"], m["start"], m["end"]) for m in ms] == [
        ("Sync", "2026-10-08T20:00:00Z", "2026-10-08T20:30:00Z")]

import json
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


# ---------- one-line logging ----------

def test_log_line_with_duration_records_an_entry(client):
    r = client.post("/log", json={"text": "client call 15m"})
    assert r.status_code == 201 and r.json()["action"] == "log"
    assert r.json()["entry"]["label"] == "client call"
    assert client.get("/now").json()["timer"] is None


def test_log_line_without_time_starts_timer(client):
    r = client.post("/log", json={"text": "building daylog"})
    assert r.json()["action"] == "timer"
    assert client.get("/now").json()["timer"]["label"] == "building daylog"


def test_parse_preview_does_not_write(client):
    r = client.get("/parse", params={"text": "client call 30m"})
    assert r.json()["action"] == "log" and r.json()["minutes"] == 30
    assert client.get("/timeline").json()["claims"] == []


# ---------- history (scroll back) ----------

def test_history_lists_entries_meetings_and_gaps_newest_first(conn, clock):
    base = clock.t - timedelta(hours=3)
    lo, hi = base, clock.t
    db.append(conn, kind="claim", type="entry.log", source="t", start=base + timedelta(minutes=30),
              end=base + timedelta(minutes=90), label="deep work")
    db.append(conn, kind="observation", type="meeting", source="wispr",
              start=base + timedelta(minutes=95), end=base + timedelta(minutes=120), label="client")
    items = timeline.history(conn, lo, hi)
    got = [(i["kind"], i["label"], i["minutes"]) for i in items]
    # 0-30 gap, 30-90 work, 90-95 too short to be a gap, 95-120 meeting, 120-180 gap
    assert got == [("gap", None, 60), ("meeting", "client", 25), ("entry", "deep work", 60),
                   ("gap", None, 30)]


def test_history_running_timer_fills_time_but_is_not_a_stop(client, clock):
    client.post("/timer/start", json={"label": "coding"})
    clock.advance(minutes=40)
    items = client.get("/history").json()["items"]
    assert all(i["label"] != "coding" for i in items)
    assert not any(i["kind"] == "gap" and i["end"] == db.iso(clock.t) for i in items)


# ---------- notes ----------

def test_note_attaches_to_running_timer_without_changing_it(client, clock):
    client.post("/timer/start", json={"label": "building daylog"})
    clock.advance(minutes=5)
    r = client.post("/notes", json={"text": "history view should show notes"})
    assert r.status_code == 201
    assert client.get("/now").json()["timer"]["label"] == "building daylog"
    notes = client.get("/timeline").json()["notes"]
    assert [(n["text"], n["during"]) for n in notes] == [("history view should show notes", "building daylog")]
    kinds = [i["kind"] for i in client.get("/history").json()["items"]]
    assert "note" in kinds


# ---------- ghost mode ----------

def test_ghost_stops_timer_blocks_activity_and_ends_on_new_task(client, clock):
    client.post("/timer/start", json={"label": "coding"})
    clock.advance(minutes=10)
    now = client.post("/ghost", json={"status": "dinner with family"}).json()
    assert now["timer"] is None and now["ghost"]["status"] == "dinner with family"

    r = client.post("/observations", json={"type": "app.focus", "data": {"app": "Safari"}})
    assert r.json() == {"ignored": "ghost mode"}

    clock.advance(minutes=60)
    now = client.post("/timer/start", json={"label": "back to coding"}).json()
    assert now["ghost"] is None and now["timer"]["label"] == "back to coding"
    s = client.get("/summary").json()
    assert s["by_label"]["ghost: dinner with family"] == 60


def _obs_since(t):
    from daylog import api
    rows = api.conn().execute("SELECT type, data FROM events WHERE kind = 'observation' AND start >= ? ORDER BY start",
                              (db.iso(t),)).fetchall()
    return [(k, json.loads(d)) for k, d in rows]


def _sleep(client, clock):
    return client.post("/observations", json={"type": "away.start", "start": clock.t.isoformat(),
                                               "data": {"reason": "NSWorkspaceWillSleepNotification", "app": "Brave"}})


def _focus(client, clock):
    return client.post("/observations", json={"type": "app.focus", "start": clock.t.isoformat(),
                                               "data": {"app": "Safari", "title": "Day Log Map"}})


def test_night_sleep_ends_ghost_replaying_oct_12(client, clock):
    # His calls (Oct 13): ghost "watching code geass" at 3:17 AM, lid closed 3:57 AM, opened the Mac
    # at the coffee shop at 1:14 PM to a 13-hour ghost. A sleep through 12-7 AM ends ghost when the Mac slept.
    clock.t = datetime(2026, 10, 13, 7, 17, tzinfo=timezone.utc)  # 3:17 AM New York
    client.post("/ghost", json={"status": "watching code geass"})
    ghost_at = clock.t
    clock.advance(minutes=20)
    assert _focus(client, clock).json() == {"ignored": "ghost mode"}  # watching: nothing about it is stored
    clock.advance(minutes=20)
    assert _sleep(client, clock).status_code == 201                   # 3:57 AM
    clock.advance(hours=9, minutes=17)                                # 1:14 PM, coffee shop
    _focus(client, clock)
    assert client.get("/now").json()["ghost"] is None
    assert client.get("/summary", params={"day": "2026-10-13"}).json()["by_label"]["ghost: watching code geass"] == 40
    assert _obs_since(ghost_at) == [("away.start", {"reason": "NSWorkspaceWillSleepNotification"}),
                                    ("app.focus", {"app": "Safari", "title": "Day Log Map"})]  # logging resumed


def test_daytime_sleep_keeps_ghost(client, clock):
    # "If I go ghost at 10 AM and come back at 6, that is valid."
    clock.t = datetime(2026, 10, 13, 14, 0, tzinfo=timezone.utc)  # 10 AM
    client.post("/ghost", json={"status": "family day"})
    ghost_at = clock.t
    clock.advance(hours=3); _sleep(client, clock)                 # 1 PM lid closed
    clock.advance(hours=5); _focus(client, clock)                 # 6 PM back
    assert client.get("/now").json()["ghost"]["status"] == "family day"
    clock.advance(hours=9)                                        # 3 AM, bar opened: the nap is long over
    assert client.get("/now").json()["ghost"]["status"] == "family day"
    assert _obs_since(ghost_at) == [("away.start", {"reason": "NSWorkspaceWillSleepNotification"}),
                                    ("app.focus", {})]            # just the wake mark, no app or title
    assert client.get("/timeline", params={"day": "2026-10-13"}).json()["activity"] == []  # the mark isn't activity


def test_overnight_ghost_from_the_evening_ends_at_the_sleep(client, clock):
    clock.t = datetime(2026, 10, 14, 2, 0, tzinfo=timezone.utc)   # 10 PM
    client.post("/ghost", json={"status": "movie"})
    clock.advance(hours=1, minutes=30); _sleep(client, clock)    # 11:30 PM lid closed
    clock.advance(hours=8, minutes=30)                            # 8 AM, opens the bar before switching apps
    assert client.get("/now").json()["ghost"] is None


def test_display_sleep_or_lock_does_not_end_ghost(client, clock):
    # Dinner with family: the display sleeps and the screen locks while he's away. Only a real sleep ends ghost.
    client.post("/ghost", json={"status": "dinner with family"})
    clock.advance(minutes=15)
    for reason in ("NSWorkspaceScreensDidSleepNotification", "locked", "idle"):
        r = client.post("/observations", json={"type": "away.start", "data": {"reason": reason}})
        assert r.json() == {"ignored": "ghost mode"}
    assert client.get("/now").json()["ghost"]["status"] == "dinner with family"


def test_amend_cuts_a_ghost_back_to_when_he_slept(client, clock):
    # Oct 13: the Oct 12 ghost ran 13 h before the night rule shipped; history gets corrected by an amend.
    g = client.post("/ghost", json={"status": "watching code geass"}).json()["ghost"]
    clock.advance(hours=13)
    client.post("/timer/start", json={"label": "coffee shop"})
    slept = (clock.t - timedelta(hours=12, minutes=20)).isoformat()
    assert client.post(f"/entries/{g['id']}/amend", json={"end": slept}).status_code == 200
    by = client.get("/summary").json()["by_label"]
    assert by["ghost: watching code geass"] == 40


def test_ghost_off(client):
    client.post("/ghost", json={})
    assert client.get("/now").json()["ghost"]["status"] == "offline"
    assert client.delete("/ghost").status_code == 200
    assert client.get("/now").json()["ghost"] is None
    assert client.delete("/ghost").status_code == 409


# ---------- amend (edit a block after the fact) ----------

def test_amend_cuts_a_running_timer_back(client, clock):
    client.post("/timer/start", json={"label": "daylog"})
    tid = client.get("/now").json()["timer"]["id"]
    started = clock.t
    clock.advance(hours=5)  # left running far too long
    cut = started + timedelta(minutes=50)
    r = client.post(f"/entries/{tid}/amend", json={"end": cut.isoformat()})
    assert r.status_code == 200
    assert client.get("/now").json()["timer"] is None  # cutting it back also stops it
    claim = client.get("/timeline").json()["claims"][0]
    assert claim["end"] == db.iso(cut) and claim["running"] is False
    assert client.get("/summary").json()["by_label"]["daylog"] == 50


def test_amend_renames_and_keeps_the_original(client, clock):
    e = client.post("/entries", json={"label": "client cal", "minutes": 20}).json()
    client.post(f"/entries/{e['id']}/amend", json={"label": "client call"})
    assert client.get("/timeline").json()["claims"][0]["label"] == "client call"
    from daylog.api import app
    assert db.get(app.state.conn, e["id"])["label"] == "client cal"  # history kept


def test_latest_amend_wins_and_bad_ranges_rejected(client, clock):
    e = client.post("/entries", json={"label": "x", "minutes": 60}).json()
    start = db.parse(e["start"])
    client.post(f"/entries/{e['id']}/amend", json={"end": (start + timedelta(minutes=40)).isoformat()})
    client.post(f"/entries/{e['id']}/amend", json={"end": (start + timedelta(minutes=30)).isoformat()})
    window = {"start": (start - timedelta(hours=1)).isoformat(), "end": (start + timedelta(hours=2)).isoformat()}
    assert client.get("/summary", params=window).json()["by_label"]["x"] == 30  # explicit window: no midnight flake
    bad = client.post(f"/entries/{e['id']}/amend", json={"end": (start - timedelta(minutes=1)).isoformat()})
    assert bad.status_code == 422


# ---------- focus tiers ----------

def test_focus_layers_on_the_running_task(client, clock):
    assert client.post("/focus", json={"tier": 1}).status_code == 409  # no task yet
    client.post("/timer/start", json={"label": "building daylog"})
    clock.advance(minutes=10)
    client.post("/focus", json={"tier": 1})
    clock.advance(minutes=20)
    client.post("/focus", json={"tier": 3})
    clock.advance(minutes=30)
    now = client.get("/now").json()
    assert now["timer"]["focus"] == 3 and now["timer"]["label"] == "building daylog"

    claim = client.get("/timeline").json()["claims"][0]
    assert [f["tier"] for f in claim["focus"]] == [1, 3]
    s = client.get("/summary").json()
    assert s["by_focus"] == {"focused": 20, "hyperfocus": 30}
    client.post("/timer/stop")
    item = next(i for i in client.get("/history").json()["items"] if i["label"] == "building daylog")
    assert item["focus_peak"] == 3


def test_switching_tasks_resets_focus(client, clock):
    client.post("/timer/start", json={"label": "a"})
    client.post("/focus", json={"tier": 2})
    clock.advance(minutes=5)
    client.post("/timer/start", json={"label": "b"})
    assert client.get("/now").json()["timer"]["focus"] == 0


def test_focus_tier_validated(client):
    client.post("/timer/start", json={"label": "a"})
    assert client.post("/focus", json={"tier": 4}).status_code == 422


# ---------- dev mode ----------

def test_health_reports_env(client):
    assert client.get("/health").json()["env"] == "real"


def test_health_reports_where_its_code_runs_from(client):
    # the version is a claim from RELEASE.json; `code` is the folder this server actually runs from.
    from daylog import api
    assert client.get("/health").json()["code"] == str(api.RELEASE_FILE.parent)


def test_dev_reset_is_refused_on_the_real_server(client):
    assert client.post("/dev/reset").status_code == 404


def test_dev_reset_wipes_only_the_dev_db(tmp_path, monkeypatch):
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "dev.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    monkeypatch.setenv("DAYLOG_DEV", "1")
    from daylog.api import app
    with TestClient(app) as c:
        assert c.get("/health").json()["env"] == "dev"
        c.post("/entries", json={"label": "test", "minutes": 5})
        assert c.get("/timeline").json()["claims"]
        assert c.post("/dev/reset").status_code == 200
        assert c.get("/timeline").json()["claims"] == []


# ---------- version + owner-only release notes on /health ----------

def test_health_reports_version_and_hides_notes_from_non_owners(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from daylog import api
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "t.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    rel = tmp_path / "RELEASE.json"
    rel.write_text('{"version": "v9.9", "new": ["the bar shows what\'s new"], "try": ["open the bar"]}')
    monkeypatch.setattr(api, "RELEASE_FILE", rel)
    with TestClient(api.app) as c:
        h = c.get("/health").json()
        assert h["version"] == "v9.9" and h["owner"] is False and "release" not in h
        (tmp_path / "owner").touch()                       # his Mac only
        h = c.get("/health").json()
        assert h["owner"] is True and h["release"]["new"] == ["the bar shows what's new"]

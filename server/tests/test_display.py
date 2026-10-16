"""The display agent: how a status looks (word + color), decided by the model, never by rules."""
import time

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

from daylog import display
from daylog.display import Display


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "t.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    from daylog import api
    api._looks.clear(); api._deciding.clear()
    with TestClient(api.app) as c:
        yield c


def test_the_shape_holds_the_model_to_one_word_and_a_color():
    Display(why="x", word="Watching", color="#A18CD1")
    for bad in [dict(word="Calm Down", color="#A18CD1"), dict(word="Watching", color="purple"),
                dict(word="Supercalifragilistic", color="#A18CD1")]:
        with pytest.raises(ValidationError):
            Display(why="x", **bad)


def test_describe_is_what_the_agent_sees():
    s = {"timer": {"label": "daylog backend", "elapsed_minutes": 12, "focus": 2}, "states": [{"state": "high"}]}
    assert display.describe(s).endswith('doing "daylog backend" for 12 min, in deep focus, also high')
    assert display.describe({}).startswith("it's ") and display.describe({}).endswith("nothing running: idle")


def test_time_passing_is_the_same_status():
    a = {"timer": {"id": "1", "label": "x", "focus": 0, "elapsed_minutes": 1}}
    b = {"timer": {"id": "1", "label": "x", "focus": 0, "elapsed_minutes": 50}}
    assert display.key(a) == display.key(b)
    assert display.key(a) != display.key({"timer": {"id": "1", "label": "x", "focus": 2}})


def test_now_says_thinking_then_shows_the_agents_choice(client, monkeypatch):
    async def picks(state):
        return Display(why="config cleanup", word="Tidying", color="#87CEEB"), 900.0
    monkeypatch.setattr(display, "decide", picks)
    client.post("/log", json={"text": "cleaning up claude config"})
    first = client.get("/now").json()["display"]
    assert first == {"thinking": True} or first["word"] == "Tidying"
    for _ in range(50):
        look = client.get("/now").json()["display"]
        if not look.get("thinking"):
            break
        time.sleep(0.02)
    assert look["word"] == "Tidying" and look["color"] == "#87CEEB" and look["why"] == "config cleanup"


def test_a_junk_line_is_not_a_status(client):
    assert client.post("/log", json={"text": "\\"}).status_code == 422
    assert client.get("/now").json()["timer"] is None


def test_just_started_is_not_zero_minutes():
    s = {"timer": {"label": "Code Geass", "elapsed_minutes": 0, "focus": 0}}
    assert display.describe(s).endswith('doing "Code Geass", just started')


def test_the_agent_looks_again_on_its_own_schedule(client, monkeypatch):
    picks = iter([Display(why="just started", word="Starting", color="#111111", recheck_minutes=5),
                  Display(why="an hour in, late", word="Winding", color="#222222", recheck_minutes=20)])

    async def decide(state):
        return next(picks), 10.0
    monkeypatch.setattr(display, "decide", decide)
    from daylog import api
    client.post("/log", json={"text": "watching code geass"})

    def look():
        for _ in range(50):
            d = client.get("/now").json()["display"]
            if not d.get("thinking"):
                return d
            time.sleep(0.02)
    first = look()
    assert first["word"] == "Starting" and first["recheck_minutes"] == 5
    k = next(iter(api._looks))
    api._looks[k]["_at"] -= 6 * 60          # its 5 minutes have passed
    assert client.get("/now").json()["display"]["word"] == "Starting"   # old look stays while it rethinks
    for _ in range(50):
        d = client.get("/now").json()["display"]
        if d["word"] == "Winding":
            break
        time.sleep(0.02)
    assert d["word"] == "Winding" and d["again"] is True


def test_a_new_note_makes_the_agent_rethink(client, monkeypatch):
    seen = []

    async def decide(state):
        seen.append(display.describe(state))
        return Display(why="x", word="Fried" if state.get("notes") else "Coding", color="#123456"), 5.0
    monkeypatch.setattr(display, "decide", decide)
    client.post("/log", json={"text": "daylog backend"})

    def settle(word):
        for _ in range(50):
            d = client.get("/now").json()["display"]
            if d.get("word") == word:
                return d
            time.sleep(0.02)
        return d
    assert settle("Coding")["word"] == "Coding"
    client.post("/notes", json={"text": "fried, need a break"})
    assert settle("Fried")["word"] == "Fried"
    assert seen[-1].startswith('He just wrote: "fried, need a break"')


def test_stats_reports_the_mac_the_models_and_latency(client, monkeypatch):
    from daylog import stats
    monkeypatch.setattr(stats, "_models", lambda: [{"name": "qwen2.5-coder:7b", "gb": 4.7, "jobs": ["line reader"], "until": None}])
    s = client.get("/stats").json()
    assert s["mac"]["ram_total_gb"] > 0 and 0 <= s["mac"]["ram_used_pct"] <= 100
    assert s["server"]["ram_mb"] > 0
    assert s["models"][0]["gb"] == 4.7 and s["jobs"]["display agent"]
    assert s["latency"]["line reader"] == {"count": 0}

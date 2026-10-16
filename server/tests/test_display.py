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
    assert display.describe(s) == 'doing "daylog backend" for 12 min, in deep focus, also high'
    assert display.describe({}) == "nothing running: idle"


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
    assert display.describe(s) == 'doing "Code Geass", just started'

"""Typed commands (RIT-78 MVP): the keyword baseline."""
import pytest
from fastapi.testclient import TestClient

from daylog import intents


@pytest.mark.parametrize("text,action,say", [
    ("smoke break", "break", "smoke break"),
    ("going on a smoke break", "break", "smoke break"),
    ("smoke", "break", "smoke break"),
    ("walk", "break", "walk"),
    ("taking a quick walk", "break", "walk"),
    ("brb", "break", "walk"),
    ("back", "back", "back"),
    ("I'm back!", "back", "back"),
    ("back from my walk", "back", "back"),
    ("focus", "focus", "focused"),
    ("locked in", "focus", "focused"),
    ("deep focus", "focus", "deep focus"),
    ("hyperfocus", "focus", "hyperfocus"),
    ("in the zone", "focus", "hyperfocus"),
    ("focus off", "focus", "focus off"),
    ("ghost", "ghost", "ghost"),
    ("ghost: dinner with family", "ghost", "ghost: dinner with family"),
    ("online", "online", "back online"),
    ("stop", "stop", "stop the timer"),
    ("high", "state", "high on"),
    ("little high", "state", "high on"),
    ("not high anymore", "state", "high off"),
    ("drunk", "state", "intoxicated on"),
    ("caffeinated", "state", "caffeinated on"),
    ("sober", "state", "high off, intoxicated off"),
])
def test_command_lines(text, action, say):
    c = intents.command(text)
    assert c is not None and (c.action, c.say) == (action, say)


@pytest.mark.parametrize("text", [
    "working on daylog", "back end refactor", "walking through the linear tour",
    "high priority bug", "smoke test the release", "focus group notes",
    "working on daylog drunk as shit little high too", "deep focus on the parser",
])
def test_task_lines_are_not_commands(text):
    assert intents.command(text) is None


@pytest.mark.parametrize("text,expected", [
    ("working on daylog drunk as shit little high too", {("intoxicated", True), ("high", True)}),
    ("reading, had coffee", {("caffeinated", True)}),
    ("high priority bug", set()),
    ("highlights reel", set()),
    ("coding, not high anymore", {("high", False)}),
])
def test_states_in_task_lines(text, expected):
    assert set(intents.states(text)) == expected


# ---------- through the API ----------

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "t.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    from daylog.api import app
    with TestClient(app) as c:
        yield c


def log(c, text):
    return c.post("/log", json={"text": text})


def test_type_a_smoke_break_and_come_back(client):
    log(client, "working on daylog")
    r = log(client, "smoke break").json()
    assert r["action"] == "command" and r["on_break"]["kind"] == "smoke"
    r = log(client, "back").json()
    assert r["timer"]["label"] == "working on daylog"
    assert {s["state"] for s in r["states"]} == {"high"}


def test_task_line_with_substance_starts_task_and_state(client):
    r = log(client, "working on daylog, little high").json()
    assert r["timer"]["label"] == "working on daylog, little high"
    assert {s["state"] for s in r["states"]} == {"high"}


def test_typed_focus_needs_a_task(client):
    assert log(client, "deep focus").status_code == 409
    log(client, "parser work")
    assert log(client, "deep focus").json()["timer"]["focus"] == 2


def test_preview_says_what_will_happen(client):
    assert client.get("/parse", params={"text": "smoke break"}).json()["action"] == "command"
    p = client.get("/parse", params={"text": "coding high"}).json()
    assert p["action"] == "timer" and p["also"] == ["high on"]


def test_forced_timer_skips_commands(client):
    r = client.post("/log", json={"text": "walk", "timer": True}).json()
    assert r["timer"]["label"] == "walk"


def test_back_when_not_away(client):
    assert log(client, "back").status_code == 409


@pytest.mark.parametrize("text,says", [
    ("Coffee, high, change the status to deep focus.", ["caffeinated on", "high on", "deep focus"]),
    ("change the status to focus", ["focused"]),
    ("set it to hyperfocus", ["hyperfocus"]),
    ("okay going on a smoke break", ["smoke break"]),
    ("I'm back and not high anymore", ["back", "high off"]),
    ("switch to ghost mode", ["ghost"]),
    ("working on daylog and linear", None),  # a task with "and" in it
])
def test_dictated_lines(text, says):
    got = intents.commands(text)
    assert (got and [c.say for c in got]) == says if says else got is None


def test_dictated_sentence_runs_every_command(client):
    log(client, "writing the parser")
    r = log(client, "Coffee, high, change the status to deep focus.").json()
    assert {s["state"] for s in r["states"]} == {"caffeinated", "high"}
    assert r["timer"]["focus"] == 2 and r["timer"]["label"] == "writing the parser"

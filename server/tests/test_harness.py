"""The harness around the model, tested with a fake Ollama: no model, no network."""

import json

import httpx

from daylog import harness
from daylog.harness import Reading, StateChange


def fake_ollama(answer: str, seen: list | None = None):
    def handle(request: httpx.Request) -> httpx.Response:
        if seen is not None:
            seen.append(json.loads(request.content))
        return httpx.Response(200, json={"message": {"role": "assistant", "content": answer}})
    return httpx.Client(base_url="http://ollama.test", transport=httpx.MockTransport(handle))


def test_a_good_answer_becomes_a_reading():
    answer = json.dumps({"mode": "task", "task": "Working on Day Log",
                         "states": [{"state": "intoxicated", "on": True}, {"state": "high", "on": True}]})
    reading, ms = harness.read_line("working on daylog drunk as shit little high too",
                                    client=fake_ollama(answer))
    assert reading.mode == "task" and reading.task == "Working on Day Log"
    assert {s.state for s in reading.states} == {"intoxicated", "high"}
    assert ms >= 0


def test_an_answer_outside_the_contract_means_use_the_rules():
    for bad in ('{"mode": "party"}', '{"mode": "focus", "focus": 9}', "sure! it's a task", "{}"):
        reading, _ = harness.read_line("focused rn", client=fake_ollama(bad))
        assert reading is None, bad


def test_no_model_running_means_use_the_rules():
    def down(request):
        raise httpx.ConnectError("connection refused")
    client = httpx.Client(base_url="http://ollama.test", transport=httpx.MockTransport(down))
    assert harness.read_line("focused rn", client=client)[0] is None


def test_his_past_corrections_ride_in_the_prompt():
    # The model remembers nothing between calls: memory is what the harness puts in the prompt.
    seen: list = []
    past = [("nothing is running.", "geass", Reading(mode="ghost", ghost_status="watching code geass"))]
    harness.read_line("geass again", examples=past, client=fake_ollama('{"mode": "ghost"}', seen))
    sent = seen[0]["messages"]
    n = len(harness.EXAMPLES)
    assert [m["role"] for m in sent] == ["system"] + ["user", "assistant"] * (n + 1) + ["user"]
    assert sent[-3]["content"].endswith("Line: geass") and '"ghost"' in sent[-2]["content"]
    assert sent[-1]["content"].endswith("Line: geass again")
    assert seen[0]["format"]["properties"]["mode"]   # the output shape is sent too
    assert seen[0]["options"]["temperature"] == 0
    assert seen[0]["think"] is False   # the bar can't wait for a model to reason out loud


def test_the_shape_rejects_unknown_states():
    assert StateChange(state="high", on=True)
    try:
        StateChange(state="sleepy", on=True)
        assert False, "unknown state accepted"
    except ValueError:
        pass


# ---------- wired into /read and /log (the model is faked; no Ollama needed) ----------

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("DAYLOG_DB", str(tmp_path / "t.sqlite"))
    monkeypatch.setenv("DAYLOG_IMPORTERS", "0")
    from daylog import api
    api._readings.clear()
    with TestClient(api.app) as c:
        yield c


def model_reads(monkeypatch, reading):
    monkeypatch.setattr(harness, "read_line", lambda text, **kw: (reading, 900.0))


def test_his_drunk_daylog_line_starts_the_task_with_both_states(client, monkeypatch):
    line = "working on daylog drunk as shit little high too"
    model_reads(monkeypatch, Reading(mode="task", task="Working on Day Log",
                                     states=[StateChange(state="intoxicated", on=True),
                                             StateChange(state="high", on=True)]))
    preview = client.get("/read", params={"text": line}).json()
    assert preview["action"] == "command" and preview["label"].startswith("task: Working on Day Log")
    now = client.post("/log", json={"text": line}).json()
    assert now["timer"]["label"] == "Working on Day Log"
    assert {s["state"] for s in now["states"]} == {"intoxicated", "high"}


def test_drinking_with_friends_goes_ghost_and_the_reading_is_kept_as_a_prediction(client, monkeypatch):
    line = "having fun with friends roommates drinking"
    model_reads(monkeypatch, Reading(mode="ghost", ghost_status="drinking with friends",
                                     states=[StateChange(state="intoxicated", on=True)]))
    client.get("/read", params={"text": line})
    now = client.post("/log", json={"text": line}).json()
    assert now["ghost"]["status"] == "drinking with friends"
    from datetime import datetime, timedelta, timezone
    from daylog import api, db
    t = datetime.now(timezone.utc)
    read = db.query(api.conn(), types=["line.read"], since=t - timedelta(hours=1), until=t + timedelta(hours=1))
    assert read and read[0]["kind"] == "prediction" and read[0]["label"] == line


def test_focused_rn_deepens_the_running_task(client, monkeypatch):
    client.post("/log", json={"text": "working on daylog"})
    model_reads(monkeypatch, Reading(mode="focus", focus=1))
    client.get("/read", params={"text": "focused rn"})
    now = client.post("/log", json={"text": "focused rn"}).json()
    assert now["timer"]["label"] == "working on daylog" and now["timer"]["focus"] == 1


def test_no_model_means_the_rules_do_it_like_before(client, monkeypatch):
    model_reads(monkeypatch, None)
    assert client.get("/read", params={"text": "smoke break"}).json()["action"] == "none"
    assert client.post("/log", json={"text": "smoke break"}).json()["on_break"]["kind"] == "smoke"


def test_a_line_with_times_never_goes_to_the_model(client, monkeypatch):
    def boom(*a, **kw):
        raise AssertionError("the model was asked about a time range")
    monkeypatch.setattr(harness, "read_line", boom)
    assert client.get("/read", params={"text": "client call 3:10-3:25"}).json()["action"] == "none"


def test_without_a_preview_log_uses_the_rules(client, monkeypatch):
    # ⏎ before the reading arrived: nothing cached, so the rules handle the line.
    now = client.post("/log", json={"text": "working on daylog, little high"}).json()
    assert now["timer"]["label"] == "working on daylog, little high"


# ---------- his Oct 15 line: "and …" while a task runs renames it (same session) ----------

def test_and_line_renames_the_running_task_without_the_model(client, monkeypatch):
    def boom(*a, **kw):
        raise AssertionError("the rule should answer; no model needed")
    monkeypatch.setattr(harness, "read_line", boom)
    started = client.post("/log", json={"text": "daylog"}).json()["timer"]
    line = "and daylog and brain global config."
    assert client.get("/parse", params={"text": line}).json()["label"] == "rename: daylog + daylog and brain global config"
    assert client.get("/read", params={"text": line}).json()["label"].startswith("rename: ")
    now = client.post("/log", json={"text": line}).json()
    assert now["timer"]["id"] == started["id"]                       # same session
    assert now["timer"]["start"] == started["start"]                 # same start time
    assert now["timer"]["label"] == "daylog + daylog and brain global config"


def test_and_line_with_nothing_running_is_just_a_task(client):
    now = client.post("/log", json={"text": "and some reading"}).json()
    assert now["timer"]["label"] == "and some reading"


def test_model_rename_keeps_the_session(client, monkeypatch):
    started = client.post("/log", json={"text": "daylog backend"}).json()["timer"]
    model_reads(monkeypatch, Reading(mode="rename", task="Day Log backend + harness"))
    client.get("/read", params={"text": "actually it's the harness too"})
    now = client.post("/log", json={"text": "actually it's the harness too"}).json()
    assert now["timer"]["id"] == started["id"] and now["timer"]["label"] == "Day Log backend + harness"


def test_the_model_is_told_what_is_running(client, monkeypatch):
    seen = {}
    def spy(text, **kw):
        seen.update(kw)
        return None, 5.0
    monkeypatch.setattr(harness, "read_line", spy)
    client.post("/log", json={"text": "daylog backend"})
    client.get("/read", params={"text": "deep in it now"})
    assert 'running task is "daylog backend"' in seen["context"]


def test_context_rides_with_the_line():
    msgs = harness.messages("x", context="the running task is \"daylog\" (5 min so far).")
    assert msgs[-1] == {"role": "user", "content": 'Right now: the running task is "daylog" (5 min so far).\nLine: x'}


# ---------- guardrails: code keeps only what the words support ----------

def test_coffee_is_never_intoxicated():
    r = Reading(mode="note", states=[StateChange(state="intoxicated", on=True)])
    kept = harness.check(r, "still drinking coffee and im at starbucks", running=True, away=False)
    assert {s.state for s in kept.states} == {"caffeinated"}   # the rules add caffeinated; drunk is dropped


def test_drinking_with_friends_adds_intoxicated_even_if_the_model_forgot():
    kept = harness.check(Reading(mode="ghost"), "having fun wiht friends roomates drinking", running=False, away=False)
    assert [(s.state, s.on) for s in kept.states] == [("intoxicated", True)]


def test_a_break_needs_a_break_word():
    assert harness.check(Reading(mode="break"), "took a nap now deep in the harness", running=True, away=False) is None
    assert harness.check(Reading(mode="break"), "grabbing a coffee", running=True, away=False).mode == "break"


def test_rename_with_nothing_running_is_a_new_task():
    assert harness.check(Reading(mode="rename", task="X"), "and x", running=False, away=False).mode == "task"


def test_back_needs_somewhere_to_come_back_from():
    assert harness.check(Reading(mode="back"), "back at it", running=True, away=False) is None


def test_feedback_becomes_a_feedback_note(client, monkeypatch):
    client.post("/log", json={"text": "daylog backend"})
    model_reads(monkeypatch, Reading(why="a complaint about the app", mode="feedback"))
    preview = client.get("/read", params={"text": "no overnight reset i see"}).json()
    assert preview["label"] == "feedback: no overnight reset i see" and preview["why"] == "a complaint about the app"
    now = client.post("/log", json={"text": "no overnight reset i see"}).json()
    assert now["timer"]["label"] == "daylog backend"            # the task keeps running


def test_continue_changes_nothing(client, monkeypatch):
    started = client.post("/log", json={"text": "working on daylog"}).json()["timer"]
    model_reads(monkeypatch, Reading(mode="continue"))
    client.get("/read", params={"text": "still working on daylog"})
    now = client.post("/log", json={"text": "still working on daylog"}).json()
    assert now["timer"]["id"] == started["id"] and now["timer"]["label"] == "working on daylog"

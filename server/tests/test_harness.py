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
    past = [("geass", Reading(mode="ghost", ghost_status="watching code geass"))]
    harness.read_line("geass again", examples=past, client=fake_ollama('{"mode": "ghost"}', seen))
    sent = seen[0]["messages"]
    assert [m["role"] for m in sent] == ["system", "user", "assistant", "user"]
    assert sent[1]["content"] == "geass" and '"ghost"' in sent[2]["content"]
    assert sent[-1]["content"] == "geass again"
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

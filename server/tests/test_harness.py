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

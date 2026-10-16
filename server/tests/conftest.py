"""Shared test setup: no test ever calls the real model or writes traces outside its temp folder."""
import pytest

from daylog import display


@pytest.fixture(autouse=True)
def no_real_display_agent(monkeypatch, tmp_path):
    async def unsure(state):
        return None, 0.0
    monkeypatch.setattr(display, "decide", unsure)
    monkeypatch.setattr(display, "TRACES", tmp_path / "traces.jsonl")

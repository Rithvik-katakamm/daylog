"""MCP server: lets any agent ask "what is Rithvik doing?"

This is deliberately a thin *client* of the HTTP API, not a second door into the
database. REST is the contract; MCP is an adapter that describes those endpoints as
tools an LLM can call. If an agent logs something, it goes through the same rules as
the side button does.

Register with Claude Code:
  claude mcp add --scope user daylog -- uv run --project <repo>/server python -m daylog.mcp_server
"""

from __future__ import annotations

import os

import httpx
from mcp.server.mcpserver import MCPServer

import logging
logging.getLogger("httpx").setLevel(logging.WARNING)

API = os.environ.get("DAYLOG_API", "http://127.0.0.1:7878")

mcp = MCPServer(
    "daylog",
    instructions=(
        "daylog is Rithvik's record of what he actually did and when. "
        "'claims' are what he logged himself (ground truth). 'meetings' come from his "
        "Wispr notetaker (ground truth). 'activity' is which Mac app was in front "
        "(an observation, not proof of the task). 'notes' are thoughts he jotted at a "
        "moment, tagged with the task running then. 'focus' on a task is his self-reported "
        "depth (1 focused, 2 deep, 3 hyperfocus) from that moment on. 'ghost' means he deliberately went "
        "offline with a status: respect it and don't speculate about what he was doing. "
        "'states' are substances he marked on himself (intoxicated, high, caffeinated): global, "
        "not tied to a task. 'on_break' / type 'break' is a walk or smoke break; the task resumes "
        "when he's back. A ghost with 'resume' means a break he didn't return from within an hour "
        "(the break is logged as ~15 min). Times are UTC; convert to his local "
        "time (America/New_York) before showing them. Gaps mean unknown, not idle."
    ),
)


def _call(method: str, path: str, **kw) -> dict:
    try:
        r = httpx.request(method, API + path, timeout=5, **kw)
    except httpx.ConnectError:
        return {"error": "daylog server is not running (expected at " + API + ")"}
    if r.status_code >= 400:
        return {"error": r.json().get("detail", r.text), "status": r.status_code}
    return r.json()


@mcp.tool()
def what_is_rithvik_doing() -> dict:
    """Right now: his running timer (if any), the app in front of him, any ongoing meeting."""
    return _call("GET", "/now")


@mcp.tool()
def timeline(date: str | None = None, start: str | None = None, end: str | None = None) -> dict:
    """What he did over a period. Pass `date` (YYYY-MM-DD, his local day; default today)
    or both `start` and `end` (ISO-8601). Returns claims, meetings, app activity, dictations."""
    params = {k: v for k, v in {"date": date, "start": start, "end": end}.items() if v}
    return _call("GET", "/timeline", params=params)


@mcp.tool()
def day_summary(date: str | None = None) -> dict:
    """Totals for one local day: minutes per logged activity, minutes per app, and
    how much of the day is tracked vs unknown."""
    return _call("GET", "/summary", params={"date": date} if date else {})


@mcp.tool()
def log_activity(label: str, start: str, end: str) -> dict:
    """Record something Rithvik told you he did (past only). ISO-8601 start/end with
    timezone offset. Only log what he actually said, never a guess."""
    return _call("POST", "/entries", json={"label": label, "start": start, "end": end,
                                           "source": "mcp"})


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()

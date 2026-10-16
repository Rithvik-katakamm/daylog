"""What caused that? Prints the last few traces as readable chains, newest last.

    cd server && uv run python -m daylog.why        # the last 5
    cd server && uv run python -m daylog.why 12     # the last 12

Each trace is one thing that happened: a line he sent (⏎) or a pill decision (look). Inside it, every step
with how long it took and what it read or decided. Spans come from daylog/telemetry.py.
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from datetime import datetime

from .telemetry import TRACES

# What to show for each step (span name → its attributes worth reading).
SHOW = {
    "line": ["line", "decided_by", "did"],
    "line_reader": ["model", "model_said", "kept", "plan"],
    "look": ["trigger", "status", "decided"],
}


def _t(iso: str) -> datetime:
    return datetime.fromisoformat(iso.replace("Z", "+00:00"))


def _load() -> dict[str, list[dict]]:
    traces: dict[str, list[dict]] = defaultdict(list)
    if not TRACES.exists():
        return traces
    for line in TRACES.read_text().splitlines():
        try:
            s = json.loads(line)
        except ValueError:
            continue
        traces[s["context"]["trace_id"]].append(s)
    return traces


def _label(s: dict) -> str:
    name = s["name"]
    if name.startswith("chat ") or name.startswith("invoke_agent"):
        return f"model call ({name})"
    return {"line": "⏎ line", "line_reader": "line reader", "look": "pill look"}.get(name, name)


def render(n: int = 5) -> str:
    traces = _load()
    ordered = sorted(traces.values(), key=lambda spans: min(_t(s["start_time"]) for s in spans))
    out = []
    for spans in ordered[-n:]:
        by_id = {s["context"]["span_id"]: s for s in spans}
        kids: dict[str | None, list[dict]] = defaultdict(list)
        for s in spans:
            parent = s.get("parent_id")
            kids[parent if parent in by_id else None].append(s)

        def walk(s: dict, depth: int):
            ms = (_t(s["end_time"]) - _t(s["start_time"])).total_seconds() * 1000
            when = _t(s["start_time"]).astimezone().strftime("%-I:%M:%S %p")
            out.append(f"{'  ' * depth}{_label(s):24} {ms / 1000:5.1f} s" + (f"   {when}" if depth == 0 else ""))
            for key in SHOW.get(s["name"], []):
                v = s.get("attributes", {}).get(key)
                if v not in (None, ""):
                    out.append(f"{'  ' * depth}  · {key}: {str(v)[:150]}")
            for e in s.get("events", []):
                out.append(f"{'  ' * depth}  ! {e['name']}: {json.dumps(e.get('attributes', {}))[:150]}")
            for k in sorted(kids[s["context"]["span_id"]], key=lambda x: x["start_time"]):
                walk(k, depth + 1)

        for root in sorted(kids[None], key=lambda x: x["start_time"]):
            walk(root, 0)
        out.append("")
    return "\n".join(out) if out else f"No traces yet in {TRACES}."


if __name__ == "__main__":
    print(render(int(sys.argv[1]) if len(sys.argv) > 1 else 5))

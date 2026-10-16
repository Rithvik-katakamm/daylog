"""Observability: one OpenTelemetry trace per thing that happens, so "what caused that?" has a one-look answer.

A **trace** is one event's whole story (one ⏎, or one pill decision); each step inside it is a **span**
with a start, an end and attributes (what it read, what it decided). Spans nest: the line reader and the
commands sit inside the line's trace; PydanticAI's own model-call spans sit inside the display agent's.

Everything goes to a local JSON-lines file (raw logs stay local). Read it with `uv run python -m daylog.why`.
Langfuse, or any OpenTelemetry viewer, can read the same spans later.
"""

from __future__ import annotations

import os
from pathlib import Path

from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import SimpleSpanProcessor, SpanExportResult

TRACES = Path(os.environ.get("DAYLOG_TRACES", Path.home() / "Library/Logs/daylog/traces.jsonl"))


class _FileExporter:
    """Each finished span as one JSON line in TRACES."""

    def export(self, spans):
        path = TRACES  # read at export time, so tests can point it at a temp file
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a") as f:
            for s in spans:
                f.write(s.to_json(indent=None) + "\n")
        return SpanExportResult.SUCCESS

    def shutdown(self):
        pass

    def force_flush(self, timeout_millis: int = 0) -> bool:
        return True


PROVIDER = TracerProvider()
PROVIDER.add_span_processor(SimpleSpanProcessor(_FileExporter()))
tracer = PROVIDER.get_tracer("daylog")

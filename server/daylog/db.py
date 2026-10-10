"""The event store: one append-only SQLite table.

Every write in daylog is a new row in `events`. Nothing is ever updated or deleted.
Triggers enforce that in the database itself, so no code path can break it by
accident. "Edits" are new events that point at old ones via `ref`.
"""

from __future__ import annotations

import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_DB = Path.home() / "Library" / "Application Support" / "daylog" / "daylog.sqlite"

SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id          TEXT PRIMARY KEY,
    recorded_at TEXT NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('claim', 'observation', 'prediction')),
    type        TEXT NOT NULL,
    source      TEXT NOT NULL,
    start       TEXT NOT NULL,
    "end"       TEXT,
    label       TEXT,
    ref         TEXT REFERENCES events(id),
    data        TEXT NOT NULL DEFAULT '{}',
    source_key  TEXT UNIQUE
);

-- Time-range queries ("what overlaps 2pm-5pm?") are the hot path.
CREATE INDEX IF NOT EXISTS events_start ON events(start);
CREATE INDEX IF NOT EXISTS events_type_start ON events(type, start);
CREATE INDEX IF NOT EXISTS events_ref ON events(ref);

CREATE TRIGGER IF NOT EXISTS events_no_update BEFORE UPDATE ON events
BEGIN SELECT RAISE(ABORT, 'events is append-only'); END;

CREATE TRIGGER IF NOT EXISTS events_no_delete BEFORE DELETE ON events
BEGIN SELECT RAISE(ABORT, 'events is append-only'); END;
"""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    """Canonical storage format: UTC, second precision, 'Z' suffix.

    One fixed format means string comparison == time comparison, so SQLite can
    range-scan the index without parsing dates.
    """
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse(s: str) -> datetime:
    dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    if dt.tzinfo is None:  # naive input means local wall-clock time
        dt = dt.astimezone()
    return dt.astimezone(timezone.utc)


def db_path() -> Path:
    return Path(os.environ.get("DAYLOG_DB", DEFAULT_DB))


def connect(path: Path | None = None) -> sqlite3.Connection:
    path = path or db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
    conn.row_factory = sqlite3.Row
    # WAL lets the API read while an importer writes, without blocking each other.
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(SCHEMA)
    return conn


def append(
    conn: sqlite3.Connection,
    *,
    kind: str,
    type: str,
    source: str,
    start: datetime,
    end: datetime | None = None,
    label: str | None = None,
    ref: str | None = None,
    data: dict[str, Any] | None = None,
    source_key: str | None = None,
) -> dict[str, Any] | None:
    """Append one event. Returns it, or None if `source_key` was already imported."""
    row = {
        "id": str(uuid.uuid4()),
        "recorded_at": iso(utcnow()),
        "kind": kind,
        "type": type,
        "source": source,
        "start": iso(start),
        "end": iso(end) if end else None,
        "label": label,
        "ref": ref,
        "data": json.dumps(data or {}),
        "source_key": source_key,
    }
    cur = conn.execute(
        'INSERT OR IGNORE INTO events (id, recorded_at, kind, type, source, start, "end",'
        " label, ref, data, source_key) VALUES (:id, :recorded_at, :kind, :type, :source,"
        " :start, :end, :label, :ref, :data, :source_key)",
        row,
    )
    if cur.rowcount == 0:
        return None
    row["data"] = data or {}
    return row


def get(conn: sqlite3.Connection, event_id: str) -> dict[str, Any] | None:
    r = conn.execute("SELECT * FROM events WHERE id = ?", (event_id,)).fetchone()
    return to_dict(r) if r else None


def to_dict(r: sqlite3.Row) -> dict[str, Any]:
    d = dict(r)
    d["data"] = json.loads(d["data"])
    return d


def query(
    conn: sqlite3.Connection, *, types: list[str], since: datetime, until: datetime
) -> list[dict[str, Any]]:
    """Events of the given types whose start falls in [since, until), oldest first."""
    marks = ",".join("?" * len(types))
    rows = conn.execute(
        f"SELECT * FROM events WHERE type IN ({marks}) AND start >= ? AND start < ?"
        " ORDER BY start, recorded_at",
        (*types, iso(since), iso(until)),
    ).fetchall()
    return [to_dict(r) for r in rows]


def refs_to(conn: sqlite3.Connection, type: str, ids: list[str],
            latest: bool = False) -> dict[str, dict[str, Any]]:
    """Map target id -> the event of `type` that references it: the first one (stops,
    deletes) or, with latest=True, the most recent one (amends: the newest edit wins)."""
    if not ids:
        return {}
    out: dict[str, dict[str, Any]] = {}
    for i in range(0, len(ids), 500):  # stay under SQLite's variable limit
        chunk = ids[i : i + 500]
        marks = ",".join("?" * len(chunk))
        rows = conn.execute(
            f"SELECT * FROM events WHERE type = ? AND ref IN ({marks}) ORDER BY recorded_at",
            (type, *chunk),
        ).fetchall()
        for r in rows:
            if latest:
                out[r["ref"]] = to_dict(r)
            else:
                out.setdefault(r["ref"], to_dict(r))
    return out

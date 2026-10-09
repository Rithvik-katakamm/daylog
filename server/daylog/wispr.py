"""Import from Wispr Flow's local SQLite database (read-only).

Meetings recorded with Wispr Notetaker are ground truth: he was talking to people from
start to end. Dictations are observations: he spoke into an app at that moment.
`source_key` makes this idempotent, so the server can re-run it every few minutes.
"""

from __future__ import annotations

import os
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

from . import db

WISPR_DB = Path.home() / "Library" / "Application Support" / "Wispr Flow" / "flow.sqlite"


def _wispr_ts(s: str) -> datetime:
    # Wispr stores "2026-10-08 20:14:38.997 +00:00"
    return datetime.fromisoformat(s.replace(" +", "+")).astimezone(timezone.utc)


def import_all(conn: sqlite3.Connection, wispr_path: Path | None = None) -> dict[str, int]:
    path = Path(os.environ.get("DAYLOG_WISPR_DB", wispr_path or WISPR_DB))
    if not path.exists():
        return {"meetings": 0, "dictations": 0}
    src = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    src.row_factory = sqlite3.Row
    try:
        # One transaction for the whole batch: thousands of rows commit in one fsync.
        conn.execute("BEGIN")
        try:
            result = {"meetings": _meetings(conn, src), "dictations": _dictations(conn, src)}
            conn.execute("COMMIT")
        except Exception:
            conn.execute("ROLLBACK")
            raise
        return result
    finally:
        src.close()


def _meetings(conn: sqlite3.Connection, src: sqlite3.Connection) -> int:
    n = 0
    # Only finished meetings: the log is append-only, so a half-finished meeting
    # imported now could never get its end time later.
    rows = src.execute(
        "SELECT id, title, createdAt, endedAt, participantNames FROM Meetings"
        " WHERE endedAt IS NOT NULL AND isDeleted = 0 AND COALESCE(isTourDemo, 0) = 0"
    )
    for r in rows:
        start = _wispr_ts(r["createdAt"])
        end = datetime.fromtimestamp(r["endedAt"] / 1000, timezone.utc)
        if end <= start:
            continue
        added = db.append(
            conn, kind="observation", type="meeting", source="wispr",
            start=start, end=end, label=r["title"] or "Meeting",
            data={"wispr_id": r["id"], "participants": r["participantNames"]},
            source_key=f"wispr:meeting:{r['id']}",
        )
        n += added is not None
    return n


def _dictations(conn: sqlite3.Connection, src: sqlite3.Connection) -> int:
    n = 0
    rows = src.execute(
        "SELECT transcriptEntityId, timestamp, app, url, duration, numWords FROM History"
        " WHERE timestamp IS NOT NULL AND COALESCE(isArchived, 0) = 0"
    )
    for r in rows:
        end = _wispr_ts(r["timestamp"])
        start = end - timedelta(seconds=r["duration"] or 0)
        added = db.append(
            conn, kind="observation", type="dictation", source="wispr",
            start=start, end=end,
            data={"app": r["app"], "url": r["url"], "words": r["numWords"]},
            source_key=f"wispr:dictation:{r['transcriptEntityId']}",
        )
        n += added is not None
    return n

"""What Day Log is costing the Mac right now, and how its models are doing: the ⌘K analytics panel.

Numbers come from three places, because no single one sees everything:
- macOS (psutil): total and available memory, CPU, and the Day Log app's and server's own processes
- Ollama (/api/ps): which models are loaded and how much GPU memory each takes. A model's memory is NOT
  in Ollama's process size: on Apple silicon it sits in GPU memory, which is the same RAM.
- the event log: how long the line reader and the display agent took (their predictions carry `ms`)
"""

from __future__ import annotations

import os
import statistics
from datetime import timedelta

import httpx
import psutil

from . import db, display, harness

GB = 1024 ** 3
_procs: dict[str, psutil.Process] = {}   # kept between calls: psutil's CPU % needs the previous sample


def _proc(key: str, find) -> psutil.Process | None:
    p = _procs.get(key)
    if p is None or not p.is_running():
        p = find()
        if p:
            p.cpu_percent(None)   # prime: the first reading is always 0
            _procs[key] = p
    return p


def _find_app() -> psutil.Process | None:
    for p in psutil.process_iter(["exe"]):
        exe = p.info.get("exe") or ""
        if exe.endswith("/Daylog.app/Contents/MacOS/Daylog"):
            return p
    return None


def _usage(p: psutil.Process | None) -> dict | None:
    if not p:
        return None
    try:
        return {"ram_mb": round(p.memory_info().rss / 2**20), "cpu": round(p.cpu_percent(None), 1)}
    except psutil.Error:
        return None


def _models() -> list[dict]:
    try:
        r = httpx.get(f"{harness.OLLAMA}/api/ps", timeout=1.0).json()
    except (httpx.HTTPError, ValueError):
        return []
    jobs = {harness.MODEL: [], display.MODEL: []}
    jobs[harness.MODEL].append("line reader")
    jobs[display.MODEL].append("display agent")
    return [{"name": m["name"], "gb": round(m.get("size_vram", m.get("size", 0)) / GB, 1),
             "jobs": jobs.get(m["name"], []), "until": m.get("expires_at")} for m in r.get("models", [])]


def _latency(conn, kind: str, since) -> dict:
    rows = db.query(conn, types=[kind], since=since, until=db.utcnow() + timedelta(seconds=1))
    ms = sorted(r["data"].get("ms") for r in rows if isinstance(r["data"].get("ms"), (int, float)))
    if not ms:
        return {"count": 0}
    return {"count": len(ms), "p50": round(statistics.median(ms)), "p95": round(ms[max(0, int(len(ms) * 0.95) - 1)])}


def collect(conn, version: str, code: str) -> dict:
    vm = psutil.virtual_memory()
    since = db.utcnow() - timedelta(hours=24)
    return {
        "version": version, "code": code,
        "mac": {"ram_total_gb": round(vm.total / GB, 1), "ram_used_gb": round((vm.total - vm.available) / GB, 1),
                "ram_used_pct": round(vm.percent), "cpu": round(psutil.cpu_percent(None), 1)},
        "app": _usage(_proc("app", _find_app)),
        "server": _usage(_proc("server", lambda: psutil.Process(os.getpid()))),
        "models": _models(),
        "jobs": {"line reader": harness.MODEL, "display agent": display.MODEL},
        "latency": {"line reader": _latency(conn, "line.read", since),
                    "display agent": _latency(conn, "display.choice", since)},
    }

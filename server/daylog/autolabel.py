"""Auto-labeler (RIT-120): every minute of the day gets a category and a best-guess task,
with zero input. A derived view: it reads the log and never writes to it, so changing a
rule in labels.json relabels history on the next read.

How a minute is labeled, in order of trust:
  1. claim   He typed a task (or break/ghost) covering it, and the Mac wasn't away.
  2. rule    The app / window title / URL in front matches a rule in labels.json.
  3. history The task he usually types when this app/site is in front (his past claims).
Away minutes become break (if he said so), sleep (long and at night) or away.

Each segment carries `source` and `confidence` so a guess is never mistaken for a claim
(vision non-negotiable #2: claimed vs observed vs predicted, never mixed).
"""
from __future__ import annotations

import json
import re
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo

from . import db, timeline

RULES_PATH = Path(__file__).with_name("labels.json")
LOCAL = ZoneInfo("America/New_York")
MIN = timedelta(minutes=1)


def rules() -> dict[str, Any]:
    return json.loads(RULES_PATH.read_text())


def _first(rule_list: list[dict], text: str) -> str | None:
    t = text.lower()
    for r in rule_list:
        if any(m in t for m in r["match"]):
            return r["category"]
    return None


def app_category(R: dict, app: str, title: str = "", url: str = "") -> tuple[str | None, float]:
    """What the thing in front says about the activity. Returns (category, confidence)."""
    a = (app or "").lower()
    if any(b in a for b in R["browsers"]):
        hit = _first(R["web"], f"{url} {title}")
        return (hit, 0.8) if hit else (R["browser_default"], 0.3)
    hit = _first(R["apps"], a)
    if hit and title:
        # A window title can override the app (e.g. a YouTube video in a non-browser player).
        by_title = _first(R["web"], title)
        if by_title:
            return by_title, 0.75
    return (hit, 0.7) if hit else (None, 0.0)


def claim_category(R: dict, label: str) -> str | None:
    return _first(R["claim_words"], f" {label} ")


def task_key(label: str) -> str:
    """Typos and suffixes aside, the same task: 'working on dauylog focused.' ~ 'working on day log'."""
    t = re.sub(r"[^a-z0-9 ]", " ", label.lower())
    t = re.sub(r"\b(focused|deep|hyperfocus|now|rn|again)\b", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def feature_key(app: str, title: str = "", url: str = "") -> str:
    host = re.sub(r"^https?://(www\.)?", "", url or "").split("/")[0]
    return f"{(app or '').lower()}|{host}"


# ---------- the minute grid ----------

def _grid(conn: sqlite3.Connection, lo: datetime, hi: datetime):
    """One cell per minute: what was in front (or None = away) and which claim covers it."""
    n = max(0, int((hi - lo) / MIN))
    front: list[dict | None] = [None] * n
    for seg in timeline.activity(conn, lo, hi):
        s, e = db.parse(seg["start"]), db.parse(seg["end"])
        for i in range(max(0, int((s - lo) / MIN)), min(n, int((e - lo) / MIN) + 1)):
            front[i] = seg
    cover: list[dict | None] = [None] * n
    for c in timeline.claims(conn, lo, hi):
        if c["type"] not in ("timer", "break", "ghost"):
            continue
        s = db.parse(c["start"])
        e = db.parse(c["end"]) if c["end"] else min(hi, db.utcnow())
        for i in range(max(0, int((s - lo) / MIN)), min(n, int((e - lo) / MIN) + 1)):
            cover[i] = c
    # RIT-122: a confirmed or corrected guess is his label for that span (a claim; wins over timers).
    for e in db.query(conn, types=["label"], since=lo - timedelta(hours=24), until=hi):
        d = e["data"]
        if d.get("action") not in ("confirm", "correct") or not e["end"]:
            continue
        s, en = db.parse(e["start"]), db.parse(e["end"])
        lab = {"type": "label", "id": e["id"], "label": d.get("task") or d.get("category") or "",
               "category": d.get("category")}
        for i in range(max(0, int((s - lo) / MIN)), min(n, int((en - lo) / MIN))):
            cover[i] = lab
    return n, front, cover


def history_model(conn: sqlite3.Connection, until: datetime, days: int,
                  exclude: set[str] = frozenset()) -> dict[str, Counter]:
    """For each app/site key, how many minutes he spent under each typed task (his past
    claims). The 'model' is a lookup table; it learns every time he types a task."""
    lo = until - timedelta(days=days)
    n, front, cover = _grid(conn, lo, until)
    table: dict[str, Counter] = defaultdict(Counter)
    for i in range(n):
        f, c = front[i], cover[i]
        if f and c and c["type"] in ("timer", "label") and c["id"] not in exclude and c["label"]:
            table[feature_key(f["app"], f.get("title", ""), f.get("url", ""))][task_key(c["label"])] += 1
    return table


def _predict_task(table: dict[str, Counter], key: str) -> tuple[str | None, float]:
    counts = table.get(key)
    if not counts:
        return None, 0.0
    task, k = counts.most_common(1)[0]
    return task, k / sum(counts.values())


def label_day(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> list[dict[str, Any]]:
    R = rules()
    K = R["knobs"]
    hi = min(hi, db.utcnow().replace(second=0, microsecond=0))
    if hi <= lo:
        return []
    n, front, cover = _grid(conn, lo, hi)
    table = history_model(conn, lo, K["history_days"])
    cells: list[dict] = []
    for i in range(n):
        f, c = front[i], cover[i]
        away = f is None or app_category(R, f["app"])[0] == "away"
        if c and c["type"] == "label" and c.get("category"):
            cells.append({"category": c["category"], "task": c["label"] if c["label"] != c["category"] else None,
                          "source": "claim", "confidence": 1.0})
        elif c and c["type"] in ("break", "ghost"):
            cat = "break" if c["type"] == "break" else (claim_category(R, c["label"]) or "away")
            cells.append({"category": cat, "task": c["label"], "source": "claim", "confidence": 1.0})
        elif away:
            cells.append({"category": "away", "task": None, "source": "rule", "confidence": 0.6})
        elif c:
            cat = claim_category(R, c["label"]) or app_category(R, f["app"], f.get("title", ""), f.get("url", ""))[0] or "build"
            cells.append({"category": cat, "task": c["label"], "source": "claim", "confidence": 1.0})
        else:
            cat, conf = app_category(R, f["app"], f.get("title", ""), f.get("url", ""))
            task, tconf = _predict_task(table, feature_key(f["app"], f.get("title", ""), f.get("url", "")))
            cells.append({"category": cat or "build", "task": task,
                          "source": "history" if task else "rule",
                          "confidence": round(max(conf, tconf) if task else conf, 2), "app": f["app"]})

    _absorb_short_away(cells, K["away_absorb_minutes"])
    _mark_sleep(cells, lo, K)
    _absorb_blips(cells, K["blip_minutes"])
    return _runs(cells, lo)


def _absorb_short_away(cells: list[dict], limit: int) -> None:
    """A 3-minute bathroom gap between two stretches of the same work is still that work."""
    i = 0
    while i < len(cells):
        if cells[i]["category"] == "away" and cells[i]["source"] == "rule":
            j = i
            while j < len(cells) and cells[j]["category"] == "away" and cells[j]["source"] == "rule":
                j += 1
            if 0 < i and j < len(cells) and j - i <= limit and cells[i - 1]["category"] == cells[j]["category"]:
                for k in range(i, j):
                    cells[k] = dict(cells[i - 1])
            i = j
        else:
            i += 1


def _mark_sleep(cells: list[dict], lo: datetime, K: dict) -> None:
    """A long away that overlaps the night is sleep (a prediction until he confirms)."""
    start_h, end_h = K["sleep_window_local"]
    i = 0
    while i < len(cells):
        if cells[i]["category"] == "away":
            j = i
            while j < len(cells) and cells[j]["category"] == "away":
                j += 1
            if (j - i) >= K["sleep_min_hours"] * 60:
                hours = {(lo + k * MIN).astimezone(LOCAL).hour for k in range(i, j, 15)}
                night = any(h >= start_h or h < end_h for h in hours)
                if night:
                    for k in range(i, j):
                        cells[k] = {"category": "sleep", "task": None, "source": "rule", "confidence": 0.7}
            i = j
        else:
            i += 1


def _absorb_blips(cells: list[dict], limit: int) -> None:
    """A 1-minute hop to another app inside a stretch of work doesn't start a new segment."""
    i = 0
    while i < len(cells):
        j = i
        while j < len(cells) and _same(cells[j], cells[i]):
            j += 1
        if 0 < i and j < len(cells) and j - i <= limit and _same(cells[i - 1], cells[j]) \
                and cells[i]["source"] != "claim":
            for k in range(i, j):
                cells[k] = dict(cells[i - 1])
        i = j


def _same(a: dict, b: dict) -> bool:
    return a["category"] == b["category"] and a["task"] == b["task"] and a["source"] == b["source"]


def _runs(cells: list[dict], lo: datetime) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for i, c in enumerate(cells):
        if out and _same(out[-1], c):
            out[-1]["end"] = db.iso(lo + (i + 1) * MIN)
            out[-1]["_conf"].append(c["confidence"])
        else:
            out.append({"start": db.iso(lo + i * MIN), "end": db.iso(lo + (i + 1) * MIN),
                        "category": c["category"], "task": c["task"], "source": c["source"],
                        "_conf": [c["confidence"]]})
    for s in out:
        conf = s.pop("_conf")
        s["confidence"] = round(sum(conf) / len(conf), 2)
        s["minutes"] = int((db.parse(s["end"]) - db.parse(s["start"])) / MIN)
    return out


def summarize(segs: list[dict[str, Any]], confident: float) -> dict[str, Any]:
    by_cat: Counter = Counter()
    by_task: Counter = Counter()
    by_source: Counter = Counter()
    sure = total = 0
    for s in segs:
        by_cat[s["category"]] += s["minutes"]
        by_source[s["source"]] += s["minutes"]
        if s["task"]:
            by_task[s["task"]] += s["minutes"]
        total += s["minutes"]
        sure += s["minutes"] if s["source"] != "claim" and s["confidence"] >= confident else 0
    guessed = total - by_source["claim"]
    return {"minutes": total,
            # Of the minutes he didn't label himself, how many the labeler is fairly sure of.
            "guessed_minutes": guessed, "guessed_confident_pct": round(100 * sure / guessed) if guessed else 0,
            "by_source": dict(by_source), "by_category": dict(by_cat.most_common()),
            "by_task": dict(by_task.most_common(12))}


# ---------- the score ----------

def score(conn: sqlite3.Connection, until: datetime, days: int = 14) -> dict[str, Any]:
    """How well would zero-input labels match what he typed? For every minute he was at the
    Mac under a typed task, hide that task and predict it.
      category: rules only (what the app/site says) vs the category of what he typed.
      task:     history built from his OTHER tasks (leave-one-task-out) vs what he typed."""
    R = rules()
    lo = until - timedelta(days=days)
    n, front, cover = _grid(conn, lo, until)
    cat_hit = cat_n = task_hit = task_n = 0
    misses: Counter = Counter()
    tables: dict[str, dict] = {}
    for i in range(n):
        f, c = front[i], cover[i]
        if not f or not c or c["type"] not in ("timer", "label"):
            continue
        got, _ = app_category(R, f["app"], f.get("title", ""), f.get("url", ""))
        if got == "away":
            continue
        want = c.get("category") if c["type"] == "label" else claim_category(R, c["label"])
        if want:
            cat_n += 1
            if got == want:
                cat_hit += 1
            else:
                misses[f"{f['app']} → {got} (you: {want})"] += 1
        if c["id"] not in tables:
            tables[c["id"]] = history_model(conn, until, days + R["knobs"]["history_days"], exclude={c["id"]})
        pred, _ = _predict_task(tables[c["id"]], feature_key(f["app"], f.get("title", ""), f.get("url", "")))
        task_n += 1
        task_hit += pred == task_key(c["label"])
    return {
        "days": days,
        "minutes_scored": cat_n,
        "category_accuracy_pct": round(100 * cat_hit / cat_n) if cat_n else None,
        "task_minutes_scored": task_n,
        "task_accuracy_pct": round(100 * task_hit / task_n) if task_n else None,
        "top_misses": dict(misses.most_common(6)),
        "labels_typed": len({c["id"] for c in cover if c and c["type"] == "timer"}),
        "label_feedback": feedback(conn, lo, until),
    }


def feedback(conn: sqlite3.Connection, lo: datetime, hi: datetime) -> dict[str, Any]:
    """RIT-122's numbers: how often a guess was shown, confirmed (⏎) or corrected (typed)."""
    hi = hi + timedelta(seconds=1)  # include events recorded this very second
    shown = len(db.query(conn, types=["guess.shown"], since=lo, until=hi))
    acts = Counter(e["data"].get("action") for e in db.query(conn, types=["label"], since=lo, until=hi))
    return {"shown": shown, "confirmed": acts["confirm"], "corrected": acts["correct"],
            "acceptance_pct": round(100 * acts["confirm"] / shown) if shown else None}


_guess_cache: dict[str, Any] = {"at": None, "guess": None}


def current_guess(conn: sqlite3.Connection) -> dict[str, Any] | None:
    """What the labeler thinks he's doing right now, for the pill when nothing is running.
    Recomputed at most every guess_refresh_seconds (the bar polls /now every 4 s)."""
    K = rules()["knobs"]
    now = db.utcnow()
    at = _guess_cache["at"]
    if at and (now - at).total_seconds() < K["guess_refresh_seconds"]:
        return _guess_cache["guess"]
    segs = label_day(conn, now - timedelta(hours=6), now)
    g = None
    if segs:
        last = segs[-1]
        fresh = db.parse(last["end"]) >= now - timedelta(minutes=2)
        if fresh and last["source"] != "claim" and last["category"] not in ("away", "sleep"):
            g = {"category": last["category"], "task": last["task"], "confidence": last["confidence"],
                 "start": last["start"], "end": last["end"], "ask": last["confidence"] < K["ask_below"]}
    _guess_cache.update(at=now, guess=g)
    return g

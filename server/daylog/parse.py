"""Read a time out of one line of text, so logging never leaves the keyboard.

    "client call 3:10-3:25"      -> "client call", 3:10 PM to 3:25 PM
    "client call 2pm to 2:40"    -> "client call", 2:00 PM to 2:40 PM
    "client call 15m"            -> "client call", the 15 minutes ending now
    "client call for 1h30m"      -> same, 90 minutes
    "deep work since 1pm"       -> "deep work", 1:00 PM until now
    "building daylog"           -> no time: the caller starts a timer

Times without am/pm resolve to the most recent past occurrence, because daylog records
what happened, not plans.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta

TIME = r"(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?"
RANGE = re.compile(rf"^(?P<label>.+?)\s+(?:from\s+)?{TIME}\s*(?:-|–|to)\s*{TIME}$", re.I)
SINCE = re.compile(rf"^(?P<label>.+?)\s+since\s+{TIME}$", re.I)
DURATION = re.compile(
    r"^(?P<label>.+?)\s+(?:for\s+)?"
    r"(?:(?P<h>\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours))?\s*"
    r"(?:(?P<m>\d+)\s*(?:m|min|mins|minute|minutes))?$",
    re.I,
)


@dataclass
class Parsed:
    label: str
    start: datetime | None = None
    end: datetime | None = None
    open_ended: bool = False  # "since 1pm": a range that ends now

    @property
    def is_range(self) -> bool:
        return self.start is not None


def _clock(now: datetime, h: str, m: str | None, mer: str | None,
           not_after: datetime) -> datetime | None:
    hour, minute = int(h), int(m or 0)
    if minute > 59 or hour > 23:
        return None
    if mer:
        if hour > 12 or hour == 0:
            return None
        hour = hour % 12 + (12 if mer.lower().startswith("p") else 0)
        candidates = [hour]
    elif hour > 12 or hour == 0:
        candidates = [hour]  # 24-hour clock
    else:
        candidates = [hour % 12, hour % 12 + 12]
    best = None
    for c in candidates:
        for back in (0, 1):  # today, else yesterday
            t = (now - timedelta(days=back)).replace(hour=c, minute=minute, second=0, microsecond=0)
            if t <= not_after and (best is None or t > best):
                best = t
    return best


def parse(text: str, now: datetime | None = None) -> Parsed:
    now = (now or datetime.now().astimezone()).astimezone()
    text = " ".join(text.strip().split())
    slack = now + timedelta(minutes=1)

    if m := RANGE.match(text):
        h1, m1, a1, h2, m2, a2 = m.group(2, 3, 4, 5, 6, 7)
        # "2-2:40pm": the start borrows the end's am/pm when it has none.
        if a2 and not a1 and int(h1) <= 12:
            a1 = a2
        end = _clock(now, h2, m2, a2, slack)
        start = _clock(now, h1, m1, a1, end) if end else None
        if start and end and end > start:
            return Parsed(m["label"], start, end)

    if m := SINCE.match(text):
        start = _clock(now, m.group(2), m.group(3), m.group(4), now)
        if start and start < now:
            return Parsed(m["label"], start, now, open_ended=True)

    if (m := DURATION.match(text)) and (m["h"] or m["m"]):
        minutes = float(m["h"] or 0) * 60 + int(m["m"] or 0)
        if 0 < minutes <= 24 * 60:
            return Parsed(m["label"], now - timedelta(minutes=minutes), now)

    return Parsed(text)

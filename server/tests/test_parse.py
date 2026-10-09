from datetime import datetime, timedelta

import pytest

from daylog.parse import parse

# A fixed "now": Friday 3:32 PM local.
NOW = datetime(2026, 10, 9, 15, 32).astimezone()


def hm(p):
    return (p.start.strftime("%H:%M"), p.end.strftime("%H:%M"))


@pytest.mark.parametrize("text,label,span", [
    ("client call 3:10-3:25", "client call", ("15:10", "15:25")),
    ("client call 3:10 - 3:25", "client call", ("15:10", "15:25")),
    ("client call 3:10–3:25", "client call", ("15:10", "15:25")),
    ("client call from 2pm to 2:40", "client call", ("14:00", "14:40")),
    ("client call 2-2:40pm", "client call", ("14:00", "14:40")),
    ("gym 9am-10:15am", "gym", ("09:00", "10:15")),
    ("gym 9-10", "gym", ("09:00", "10:00")),  # most recent past: 9-10 AM, not PM
    ("call 14:00-14:30", "call", ("14:00", "14:30")),
])
def test_ranges(text, label, span):
    p = parse(text, NOW)
    assert p.label == label and hm(p) == span


def test_future_range_resolves_to_yesterday():
    p = parse("party 10pm-11pm", NOW)
    assert p.start.date() == (NOW - timedelta(days=1)).date() and hm(p) == ("22:00", "23:00")


@pytest.mark.parametrize("text,minutes", [
    ("client call 15m", 15), ("client call 15 min", 15), ("client call for 1h", 60),
    ("client call 1h30m", 90), ("client call 1.5h", 90), ("reading 45 minutes", 45),
])
def test_durations_end_now(text, minutes):
    p = parse(text, NOW)
    assert p.label in ("client call", "reading")
    assert p.end == NOW and NOW - p.start == timedelta(minutes=minutes)


def test_since():
    p = parse("deep work since 1pm", NOW)
    assert p.label == "deep work" and p.open_ended and p.start.strftime("%H:%M") == "13:00"


@pytest.mark.parametrize("text", [
    "building daylog", "reading chapter 3", "call with 2 people", "client call 3:10-",
])
def test_no_time_means_timer(text):
    p = parse(text, NOW)
    assert not p.is_range and p.label == text

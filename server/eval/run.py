"""Score readers of a typed line on his real lines: the rules vs local models (through the harness's
guardrails). The lines live in eval/lines.local.jsonl, which never leaves his Mac (gitignored).

    cd server && uv run python eval/run.py [model ...]

Right = the mode is one of the accepted ones AND the substances match exactly. Prints each reader's
score, its median / p95 time, and the lines it got wrong.
"""

import json
import re
import statistics
import sys
from pathlib import Path

from daylog import harness, intents

LINES = Path(__file__).with_name("lines.local.jsonl")
_ACTION_MODE = {"break": "break", "back": "back", "focus": "focus", "state": "state", "ghost": "ghost",
                "stop": "stop", "online": "back", "undo_break": "task"}
_EXTEND = re.compile(r"^\s*(?:and|also|plus|\+)\s+", re.I)


def rules(case):
    """What today's rules would do with the line, as (mode, states)."""
    text, running = case["text"], case["context"].startswith("the running task")
    if running and _EXTEND.match(text):
        return "rename", intents.states(text)
    cmds = intents.commands(text)
    if cmds:
        c = cmds[0]
        return _ACTION_MODE.get(c.action, c.action), [tuple(s) for s in c.args.get("states", [])] or intents.states(text)
    return "task", intents.states(text)


def right(mode, states, case):
    modes = set(case["modes"]) | ({"continue"} if "note" in case["modes"] else set())  # notes became continue (Oct 16)
    return mode in modes and {tuple(s) for s in states} == {tuple(s) for s in case["states"]}


def main(models):
    cases = [json.loads(l) for l in LINES.read_text().splitlines() if l.strip()]
    hits = [c for c in cases if right(*rules(c), c)]
    print(f"{'rules':18} {len(hits):2}/{len(cases)}   instant")
    for model in models:
        harness.read_line("warm up", model=model)
        good, times, misses = 0, [], []
        for c in cases:
            raw, ms = harness.read_line(c["text"], model=model, context=c["context"])
            times.append(ms)
            running = c["context"].startswith("the running task")
            away = "break" in c["context"] or "ghost" in c["context"]
            r = raw and harness.check(raw, c["text"], running=running, away=away)
            mode, states = (r.mode, [(s.state, s.on) for s in r.states]) if r else rules(c)
            if right(mode, states, c):
                good += 1
            else:
                misses.append((c["text"][:46], mode, states, c["modes"], raw.why if raw else "-"))
        p95 = sorted(times)[int(len(times) * 0.95) - 1]
        print(f"{model:18} {good:2}/{len(cases)}   median {statistics.median(times):.0f} ms, p95 {p95:.0f} ms")
        for text, mode, states, want, why in misses:
            print(f"     ✗ {text:46} got {mode} {states or ''}  want {want}  · why: {why[:60]}")


if __name__ == "__main__":
    main(sys.argv[1:] or [harness.MODEL])

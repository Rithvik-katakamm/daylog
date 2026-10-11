"""Say what you mean: typed lines → commands (the MVP of Smart capture, RIT-78).

Two kinds of match, both plain rules (no model yet):
1. **Command lines**: the whole line is a command ("smoke break", "back", "deep focus",
   "ghost dinner with family"). The bar does the command instead of starting a task.
2. **Substances inside a task line**: "working on daylog, little high" starts the task *and*
   turns high on. "not high anymore" / "sober" turn them off.

This is the keyword baseline. A model can replace or back it later; the eval compares the two on
his real entries (labeled set, frozen test set, the simple version is allowed to win).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field


@dataclass
class Command:
    action: str            # break · back · focus · state · ghost · online · stop
    say: str               # what the bar shows: "smoke break", "deep focus", "high on"
    args: dict = field(default_factory=dict)


def _norm(text: str) -> str:
    t = text.lower().strip()
    t = t.replace("’", "'")
    t = re.sub(r"[.!?,;]+$", "", t)
    return re.sub(r"\s+", " ", t)


# Each entry: (pattern for the WHOLE line, command builder).
_FOCUS = {1: "focused", 2: "deep focus", 3: "hyperfocus"}
_LINES: list[tuple[re.Pattern, callable]] = [
    (re.compile(r"^(?:(?:going|gonna go|stepping out)(?: on| for)? )?(?:a |on a |taking a |quick )?"
                r"(?:smoke|smoke break|smoking|cig|cig break|blunt|joint)(?: break)?$"),
     lambda m: Command("break", "smoke break", {"kind": "smoke"})),
    (re.compile(r"^(?:(?:going|gonna go|stepping out)(?: on| for)? )?(?:a |on a |taking a |quick )*"
                r"(?:walk|break|breather|stretch)(?: break)?$|^(?:brb|afk|stepping away|be right back)$"),
     lambda m: Command("break", "walk", {"kind": "walk"})),
    (re.compile(r"^(?:i'?m |i am )?back(?: now)?$|^back from (?:my |the |a )?(?:walk|break|smoke)$"),
     lambda m: Command("back", "back")),
    (re.compile(r"^(?:focus off|unfocus|out of focus|no focus|lost focus|done focusing)$"),
     lambda m: Command("focus", "focus off", {"tier": 0})),
    (re.compile(r"^(?:hyper ?focus(?:ed)?|in the zone|flow state|flow)$"),
     lambda m: Command("focus", _FOCUS[3], {"tier": 3})),
    (re.compile(r"^(?:deep focus|deep|deeply focused)$"),
     lambda m: Command("focus", _FOCUS[2], {"tier": 2})),
    (re.compile(r"^(?:focus|focused|focusing|locked in|lock in|locking in)$"),
     lambda m: Command("focus", _FOCUS[1], {"tier": 1})),
    (re.compile(r"^(?:going )?(?:ghost|offline|going offline|dark|going dark)(?: mode)?(?:[: -]+(?P<status>.+))?$"),
     lambda m: Command("ghost", "ghost" + (f": {m['status']}" if m["status"] else ""),
                       {"status": m["status"] or ""})),
    (re.compile(r"^(?:online|back online)$"), lambda m: Command("online", "back online")),
    (re.compile(r"^(?:stop|stop timer|done|finished|stop tracking)$"), lambda m: Command("stop", "stop the timer")),
]

# Substances: words that mean "on", anywhere in a line.
_STATE_WORDS = {
    "high": r"high|stoned|baked|blazed",
    "intoxicated": r"drunk|tipsy|buzzed|intoxicated|wasted|faded",
    "caffeinated": r"caffeinated|wired|coffee|on coffee|had (?:a )?coffee|after coffee|espresso|on espresso",
}
# "high" that isn't about being high.
_NOT_HIGH = r"(?!\s+(?:priority|level|school|score|quality|res|resolution|five|ground))"
_NEG = r"(?:not|no longer|no more|isn't|not as)\s+(?:\w+\s+){0,2}?"


def states(text: str) -> list[tuple[str, bool]]:
    """Substances mentioned in a line, as (state, on). "sober" turns high and drunk off."""
    t = _norm(text)
    out: list[tuple[str, bool]] = []
    if re.search(r"\bsober(?:ed up)?\b", t):
        out += [("high", False), ("intoxicated", False)]
    for name, words in _STATE_WORDS.items():
        guard = _NOT_HIGH if name == "high" else ""
        pat = rf"\b(?:{words})\b{guard}"
        if re.search(rf"\b{_NEG}(?:{words})\b", t) or re.search(rf"\b(?:{words})\s+off\b", t):
            out.append((name, False))
        elif re.search(pat, t):
            out.append((name, True))
    return out


# Lead-ins people say (especially when dictating with Wispr): "change the status to focus".
_LEAD = re.compile(r"^(?:ok(?:ay)?|hey|so|um|uh|please|alright|(?:change|set|switch|put|make|turn|move)"
                   r"(?: (?:the|my|me|it))?(?: (?:status|mode|state))?(?: (?:to|into|on))?|go(?:ing)? (?:to|into)|"
                   r"i'?m going|i'?m|i am|now|status|mode)[: ]+")


def _strip_lead(t: str) -> str:
    prev = None
    while prev != t:
        prev, t = t, _LEAD.sub("", t).strip()
    return t


def commands(text: str) -> list[Command] | None:
    """Several commands in one line, the way you'd dictate them: "coffee, high, change the status
    to deep focus". Returns them only if EVERY part is a command; otherwise None (it's a task)."""
    t = _norm(text)
    one = command(t)
    if one:
        return [one]
    parts = [p.strip() for p in re.split(r"\s*(?:,|;|\band then\b|\bthen\b|\band\b)\s*", t) if p.strip()]
    if len(parts) < 2:
        return None
    out = [command(p) for p in parts]
    return out if all(out) else None


def command(text: str) -> Command | None:
    """A command, if the whole line is one. Substance-only lines ("high", "not drunk") count."""
    t = _strip_lead(_norm(text))
    if not t:
        return None
    for pat, build in _LINES:
        m = pat.match(t)
        if m:
            return build(m)
    found = states(t)
    if found and _only_state_words(t):
        say = ", ".join(f"{n} {'on' if on else 'off'}" for n, on in found)
        return Command("state", say, {"states": found})
    return None


def _only_state_words(t: str) -> bool:
    """True if the line is just substances ("high", "little high", "not drunk anymore")."""
    filler = r"(?:i'?m|i am|feeling|getting|got|kinda|kind of|a|little|bit|lil|pretty|very|so|"
    filler += r"super|now|rn|right now|anymore|and|too|also|off|not|no longer|no more|on|sober|sobered|up)"
    words = "|".join(_STATE_WORDS.values())
    rest = re.sub(rf"\b(?:{words})\b", " ", t)
    rest = re.sub(rf"\b{filler}\b", " ", rest)
    return rest.strip() == ""

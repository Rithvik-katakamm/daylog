#!/usr/bin/env python3
"""UserPromptSubmit: when a prompt sounds like a concept gap, attach the learn-slice protocol.

Deterministic trigger, model judgment on whether it's a real gap. Every trigger is logged to
.learning/triggers.jsonl (gitignored), so we can count learn slices per build slice."""
import json, os, re, sys, datetime

GAP = re.compile(
    r"\b(i\s*don'?t\s+(get|understand|know\s+(what|how|why))|what('?s| is| are| does| do)\b|"
    r"why\s+(does|is|do|did|are|would)|how\s+(does|do|is)|explain|confus|lost\s+me|huh\b|wtf|"
    r"no\s+idea|teach\s+me|what\s+do\s+you\s+mean|eli5|i'?m\s+lost)",
    re.I,
)

PROTOCOL = (
    "LEARN-SLICE TRIGGER (Day Log hook). If Rithvik just hit a concept he doesn't understand, pause the "
    "build and: 1) Name the concept and its stack layer (ui/ux/backend/infra/ai/data). 2) Teach it in 5 "
    "sentences or fewer, using THIS repo's code from the current slice (cite file:line). 3) Ask him ONE "
    "check question and wait for his answer. 4) Map it to an EXISTING learn card (Linear project "
    "'Learning', or a card with the learn label) and comment there 'pulled by <build issue>'. Do NOT create "
    "a new learn card unless he explicitly asks (his rule, Oct 13). Always say which: 'existing card RIT-x' "
    "vs 'new card'. If none fits, say so and offer one; don't file it. 5) Resume the slice. If this isn't "
    "a concept gap (just a normal question), ignore this note."
)

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return
    prompt = data.get("prompt", "") or ""
    if not GAP.search(prompt):
        return
    try:
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        os.makedirs(os.path.join(root, ".learning"), exist_ok=True)
        with open(os.path.join(root, ".learning", "triggers.jsonl"), "a") as f:
            f.write(json.dumps({"at": datetime.datetime.now().isoformat(timespec="seconds"),
                                "session": data.get("session_id"), "prompt": prompt[:300]}) + "\n")
    except Exception:
        pass
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                             "additionalContext": PROTOCOL}}))

if __name__ == "__main__":
    main()

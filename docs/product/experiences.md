# Product experiences (friction log)

Layer: product → ux. **What it's like to actually use Day Log**, captured live. His method (Oct 13): while
clicking and typing, he names out loud what he's doing ("⌥L, typing daylog, ⌘H for high…"); we parse that
narration later and fix the UI from it. This file is data for improving the UI, not a to-do list: each
entry is a moment, the friction in it, and how it felt. Solutions come later, from patterns across entries.

## How to log a moment

| Field | What goes in it |
|---|---|
| **When** | date and time |
| **Doing** | what he was trying to do, in his words |
| **Steps** | what he actually pressed, clicked or typed, in order |
| **Friction** | where it slowed, broke or needed a second try |
| **Felt** | his reaction, quoted |

Good moments go in too: they show what to protect.

## Versions that mattered (his marks)

- **v0.46, "legendary" (Oct 16).** One input is the whole product, gemma4 12B reads it and picks the pill's
  look: words like Floating, Igniting, Surging, Manifesting, and colors that follow his mood. "46 is great …
  I want you to mark that shit completely … the jump from 45 to 46, there was an idea there that really
  changed the experience."
- **v0.47, "hit reality" (Oct 16).** The coder 7B coins only the word (FridayFiend, PushTrike, DayLogRush),
  gemma the rest. "Version 47 has hit … these smaller coding models, they got style." And the trade-off:
  both don't fit in 16 GB, so each look swaps them. "47 was when I consolidated and hit reality."

## Moments

### 2026-10-14

- **4:10 PM · what a break is (product thought).** Doing: reading the smoke-break cap. Friction: the
  break keys assume he takes breaks; he doesn't think of it that way. Felt: "i never break man tbh i
  just walk around and come back and i dont want this to feel like a admin system for a compny you
  know this is for me."

### 2026-10-13

- **6:00 PM · smoke break · ⌘⇧B on a walk.** Doing: start a smoke break. Steps: ⌘⇧B. Friction: he was
  already on a walk, so the key meant "back" and ended the walk; the smoke break took a second try.
  Felt: "the command shift break does not directly go to a smoke break."
- **5:47 PM · took back a break.** Doing: undo a break he didn't take. Steps: typed "didnt actually break".
  Friction: it became a task with that name (fixed the same day: typing it now takes the break back).
  Felt: "it moves me back to the old status with the extra appended time" is what he wanted.
- **5:46 PM · named break.** Doing: a bathroom break. Steps: ⌘B, then tried to type "peeing". Friction:
  ⌘B starts a walk with no way to name it (typing "peeing" works since the same day).
- **6:45 PM · a 44-min "smoke break" that wasn't.** Doing: came back to the Mac. Friction: the log said smoke
  break (and high), but he hadn't smoked; he walked home and took a train. Felt: "I would have liked that
  to have been a backend thing." Location would have told the truth.
- **7:35 PM · coming back after 1.5 h (a good moment).** Steps: opened the Mac, the bar said "away after a
  smoke break". Felt: "You know what I like? … it says away after a smoke break."
- **7:36 PM · ⌥L, typed "daylog", ⌘H for high.** Steps: ⌥L, typed "daylog", ⏎ (locked in), then ⌘H.
  Friction: ⌘H didn't turn high on. He had to take his hand off the keyboard and click the bar, then ⌘H
  worked. Felt: "the Command+H is how I think I should do the high thing, but it's not working. I don't
  know why." (Hypothesis, unverified: after ⏎ the bar's typing line loses keyboard focus, so the next
  shortcut doesn't reach it until a click.)
- **Afternoon · knowing which version runs.** Friction: couldn't tell if changes were live. Felt: "what is
  the point of me making changes if I can't use and test them." (Since then: ⌘K shows `vX · runs
  releases/vX`.)

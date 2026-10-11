# Motion: the precision knobs

How the pill moves is its own layer (**ui → motion**). "Crisp" vs "sloppy" comes down to four
knobs. All live in `struct Motion` (`app/Sources/DaylogBar/Views.swift`) and can be tuned **live**,
no rebuild: `defaults write com.rithvik.daylog motion.<knob> <value>`, then press ⌥L again.
Reset one with `defaults delete com.rithvik.daylog motion.<knob>`.

| Knob | Default | What it does | Feels |
|---|---|---|---|
| `response` | 0.22 s | How long the spring takes to arrive | lower = snappier; above ~0.3 feels slow |
| `damping` | 0.9 | 1 = lands dead on target; lower = overshoot and wobble | below ~0.8 reads as sloppy/bouncy |
| `stagger` | 0.03 s | Gap between widening and dropping | bigger = more "two-step", slower overall |
| `contentDelay` | 0.08 s | When the text appears after the press | too late feels laggy; too early looks messy |
| `closeResponse` | 0.18 s | How fast it goes back up | close can be faster than open |

The fifth factor isn't a number: **input to first frame**. Since v0.8 the bar starts animating on
the frame after ⌥L and takes the keyboard right after, instead of activating the app first.

History: v1 liquid (underdamped 0.62–0.68, wobbly) → v2 widen-then-drop (0.12 s stagger, 0.26 s
text delay: correct path, too slow) → v3 crisp (Oct 11 night).

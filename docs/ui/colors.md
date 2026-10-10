# Colors

The bar is one input line. **The ring color tells you what you're doing right now.** This
file is the source of truth for every color in the app (`app/Sources/DaylogBar/Views.swift`,
`enum Theme`).

## Today (shipped)

| Meaning | Where you see it | Color | Hex | `Theme` name |
|---|---|---|---|---|
| **Task:** typing what you're doing; running timer | ring, timer chip | neon mint | `#5CF5C7` | `accent` |
| **Note** (⌘N) | ring, note chip | soft blue | `#8CC2FF` | `note` |
| **Ghost** (⌘O), offline | ring, ghost chip | purple | `#B87AFF` | `ghost` |
| **Looking at the past:** scroll back (↑), edit (↓), fill a gap | ring, time chip, date | yellow | `#FFD652` | `ring` |
| **Wispr meeting** (when scrolling back) | dot | violet | `#B38CFF` | `meeting` |
| Bar background | capsules | near-black, solid | `#090909` | `chrome` |
| Hairline edge | capsule border | white 9% | — | `edge` |
| Text / muted text | everywhere | white 94% / 48% | — | `text`, `muted` |

**Focus today:** ⌘F keeps the ring mint and makes it glow brighter per tier (▲ ▲▲ ▲▲▲).

**Known problem:** ghost purple (`#B87AFF`) and meeting violet (`#B38CFF`) are nearly the
same color.

## PROPOSED (Oct 10): two dimensions, mode and state

He wants focus to change color (yellow → orange → red), plus **intoxicated** and **high**
states that can **stack with focus**. One ring can't show two things at once, so the
proposal splits color into two dimensions:

1. **Mode = the main ring.** What the input line means right now.
2. **State layers = outer rings.** How you are while doing the task. They stack.

### Main ring

| Ring | Color | Hex | Change from today |
|---|---|---|---|
| Task, no focus | neon mint | `#5CF5C7` | same |
| Task + **focused** ▲ | yellow | `#FFD652` | **new** (was a mint glow) |
| Task + **deep focus** ▲▲ | orange | `#FF9A3C` | **new** |
| Task + **hyperfocus** ▲▲▲ | red | `#FF4D4D` | **new** |
| Note | soft blue | `#8CC2FF` | same |
| Ghost | purple | `#B87AFF` | same |
| Looking at the past (↑ ↓ fill) | silver | `#D9DEE6` | **changed**: yellow now belongs to focus |
| **Dev mode** (⌥D) | cyan, dashed ring + `DEV` chip | `#3FD9FF` | **new** |

### State layers (outer rings, combinable)

| State | Color | Hex |
|---|---|---|
| Intoxicated | rose | `#FF6FA5` |
| High | lime green | `#9CFF4F` |

```
 deep focus + high:            ╭──────────────────────────────╮   ← lime (high)
                              ╭┴──────────────────────────────┴╮  ← orange (deep focus)
                              │ ● building daylog ▲▲   1:12:40 │
                              ╰────────────────────────────────╯
```

### Other fixes in the proposal
- Meetings move to periwinkle `#7A8CFF`, so they stop looking like ghost.

### Open questions
- Is lime the right green for "high", or did you mean something else by "green can be
  another color"?
- Do altered states (intoxicated, high) also change the sound or anything else, or only color?

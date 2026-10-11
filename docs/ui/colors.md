# Colors

The bar is one input line. Colors follow **three dimensions** (decided in the UI talk,
Oct 10). Every color in the app is a token in `enum Theme`
(`app/Sources/DaylogBar/Views.swift`), and this file is the source of truth for them.

| Dimension | Channel | Lifetime |
|---|---|---|
| **1. What am I doing** | the main ring | persistent |
| **2. How am I** | ring *heat* (focus) + *outer rings* (substances) | persistent; they stack |
| **3. What am I typing** | the ring, only while typing | temporary (the *color* is temporary; what you type is data) |

## Shipped

| Dimension | Meaning | Color | Hex | Token |
|---|---|---|---|---|
| 1 | Nothing running | grey | `#6B7280` | `idle` |
| 1 | Task | pearl white | `#ECEEF2` | `task` |
| 1 | Ghost (⌘O), off the clock | purple | `#B87AFF` | `ghost` |
| 2 | Task + focused ▲ (⌘F) | yellow | `#FFD652` | `focusHeat[1]` |
| 2 | Task + deep focus ▲▲ | orange | `#FF9A3C` | `focusHeat[2]` |
| 2 | Task + hyperfocus ▲▲▲ | red | `#FF4D4D` | `focusHeat[3]` |
| 3 | Typing a note (⌘N) | blue | `#8CC2FF` | `note` |
| 3 | Looking back (↑), editing (↓), filling a gap | silver, **dashed** ring | `#C9CED6` | `past` |
| — | Wispr meeting (when looking back) | periwinkle | `#7A8CFF` | `meeting` |
| — | Bar background | near-black, solid | `#090909` | `chrome` |
| — | Hairline edge / text / muted text | white 9% / 94% / 48% | — | `edge`, `text`, `muted` |

**How the heat works:** `Theme.taskColor(focus:)` picks the task color for a tier. The timer
chip, its ▲s, the ring and the glow all use it, so the whole bar heats up together. The glow
radius and ring width grow with the tier.

**Dev mode** (⌥D) changes no colors: a `DEV` tag floats above the bar instead.

## Defined, not used yet

| Dimension | Meaning | Color | Hex | Token | Ships with |
|---|---|---|---|---|---|
| 2 | Intoxicated (outer ring) | rose | `#FF6FA5` | `intoxicated` | RIT-68 |
| 2 | High (outer ring) | green | `#7CFF6B` | `high` | RIT-68, smoke break RIT-69 |

```
 deep focus + high:            ╭──────────────────────────────╮   ← green (high)
                              ╭┴──────────────────────────────┴╮  ← orange (deep focus)
                              │ ● building daylog ▲▲   1:12:40 │
                              ╰────────────────────────────────╯
```

## History
- Oct 9: mint green task ring, yellow for the past.
- Oct 10: green replaced by pearl (he didn't like it); yellow moved to focus; the past became
  dashed silver; meetings moved off violet (it was too close to ghost).

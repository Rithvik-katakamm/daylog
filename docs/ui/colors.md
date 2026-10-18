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
| 1 | Ghost (⌘O), offline | purple | `#B87AFF` | `ghost` |
| 1 | On a break (⌘B walk, ⌘⇧B smoke) | blue-grey | `#8FA3B8` | `away` |
| 2 | High (⌘H) | neon green | `#39FF14` | `high` |
| 2 | Intoxicated (⌘I) | rose | `#FF6FA5` | `intoxicated` |
| 2 | Caffeinated (⌘C) | coffee brown | `#A8754A` | `caffeinated` |
| 2 | Task + focused ▲ (⌘F) | yellow | `#FFD652` | `focusHeat[1]` |
| 2 | Task + deep focus ▲▲ | orange | `#FF9A3C` | `focusHeat[2]` |
| 2 | Task + hyperfocus ▲▲▲ | red | `#FF4D4D` | `focusHeat[3]` |
| 3 | Typing a note (⌘N) | blue | `#8CC2FF` | `note` |
| 3 | Looking back (↑), editing (↓), filling a gap | silver, **dashed** ring | `#C9CED6` | `past` |
| — | Wispr meeting (when looking back) | periwinkle | `#7A8CFF` | `meeting` |
| — | Bar background | near-black, solid | `#090909` | `chrome` |
| — | Hairline edge / text / muted text | white 9% / 94% / 48% | — | `edge`, `text`, `muted` |

**How the heat works:** `Theme.taskColor(focus:)` picks the task color for a tier. The timer
chip, the clock (its filled arc and number), the ring and the glow all use it, so the whole bar
heats up together, open or closed. The glow
radius and ring width grow with the tier.

**The test copy** (agent tests only, never on his screens) changes no colors: a `DEV` tag floats above the bar instead.

## The clock (Oct 18)

One number inside a ring, on the **right** of the pill in every state: the right ear by the notch,
the right corner of the monitor pill, the right end of the open bar (the input sits in the middle).
His words: "a circle around it filling in like an analog watch… simple and minimalistic."

- The outline fills clockwise with the minutes of the hour. Under an hour the number is minutes;
  from 60 on it's hours, and the outline starts over (a minute hand).
- **Accent:** only the filled arc and the number take the status color (focus yellow → red, ghost
  violet, break blue-grey). The unfilled track is the title's color, dimmed to 22% so a pearl
  (no-focus) fill still reads against it. That dim is a knob.
- "Hide the time" (⌘K) hides the clock on the closed pill only; the open bar always shows it.
- Component: `ClockRing` in `Views.swift`. Font: SF Mono across the bar (Oct 18: the Claude Code look).

## Substances: one blended glow, not lines

Substances (dimension 2) are a **soft halo outside the main ring**, never separate outlines
(his call, Oct 11: "more of a blend and glow than 3 distinct lines"). One substance is a plain
colored glow; several blend into each other around the shape (an angular gradient, blurred).
The crisp main ring stays dimension 1 + focus heat. Component: `OuterRings` in `Views.swift`.

## Always on: the notch pill (Oct 11)

**One shape, not two.** Closed, the bar hugs the notch like the Dynamic Island: black (it merges
with the notch), the status in words on the left ear, the clock on the right ear, the camera in
between. No dots beside the status (Oct 18): the clock carries the color. ⌥L grows the same shape down into the bar; closing shrinks it back. The notch width
comes from macOS (`auxiliaryTopLeftArea/RightArea`); with no notch it's a small tab hanging
from the top edge. It never takes clicks while closed.

- Focus and substance glows **breathe** slowly (2.2s) while closed, so "on" is felt, not read.
- **Side ring** (right edge) is still in ⌘K, off by default: it felt in the way (Oct 11).
- Open UX question (to file as a UX talk): how much should be visible while working.

## History
- Oct 13: caffeinated is coffee brown (`#A8754A`, was aqua `#5CE1E6`), his call; key moved to ⌘C.
- Oct 11 (later): high made a brighter neon green (`#39FF14`, was `#7CFF6B`); the pill's
  curved shoulders removed (straight sides into the screen edge).
- Oct 11: substances shipped as a blended glow (not stacked rings); caffeinated (aqua) and
  break (blue-grey) added; always-on pill and side ring.
- Oct 9: mint green task ring, yellow for the past.
- Oct 10: green replaced by pearl (he didn't like it); yellow moved to focus; the past became
  dashed silver; meetings moved off violet (it was too close to ghost).

**Thinking** `#8B7BFF` (violet, Oct 15): after ⏎ the bar closes and the pill says *thinking* in violet, the word pulsing (no dots, Oct 18), until the model decides; then it shows the model's one word for the task.

**The display agent picks the status color (Oct 16).** For every status the agent chooses the pill +
ring + bar color itself (`docs/backend/display.md`); the colors above are only the fallback when the
model is down or still deciding. Substance rings keep their colors.

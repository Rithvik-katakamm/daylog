# Neon: the light language of the pill

Day Log's status is **light, not paint**. The pill is a black shape that grows out of the notch,
outlined by a neon tube. Everything about *how you are* is told by that light. Text stays quiet.
Code: `NeonTube`, `OuterRings`, `NotchShape`, `Breathing` in `app/Sources/DaylogBar/Views.swift`.

## The vocabulary (use these words when we talk about it)

| Name | What it is | Tells you | Lives in |
|---|---|---|---|
| **Body** | The black shape hanging from the notch. Flat top, straight sides into the screen edge, continuous ("squircle") corners | Day Log is there | `NotchShape` |
| **Tube** | The neon outline: bloom + colored glass + hot core | **What** you're doing (pearl task, purple ghost, blue-grey break, silver past) | `NeonTube` |
| **Heat** | The tube getting hotter: yellow → orange → red, thicker and brighter | **How deep** your focus is (⌘F tiers) | `NeonTube(heat:)` + the bloom |
| **Halo** | A soft colored aura just outside the tube; several blend into one gradient | **Substances**: high (green), intoxicated (rose), caffeinated (coffee brown) | `OuterRings` |
| **Breath** | A slow 2.2s rise and fall of the bloom while the pill is closed | Something is "on" (focus or a substance): felt, not read | `Breathing` |
| **Unlit tube** | Dashed, dim, no hot core | You're looking at the **past** (↑ look back, ↓ edit, fill) | `NeonTube(dashed:)` |

## How the tube is built (why it reads as neon)

Real neon has three visible parts, so the tube draws three strokes, outermost first:
1. **Bloom**: wide, very blurred, ~45% opacity. Light scattering in the air around the glass.
2. **Glass**: the colored line, barely blurred.
3. **Hot core**: thin, near-white, additive blend (`.plusLighter`). The core is what makes it
   look *lit*. Without it, a glow just looks like a painted line.

Heat raises all three: thicker, brighter, wider bloom.

## Rules

- **One loud thing.** The tube is the only bright element. Text is white at reduced opacity,
  digits are SF Pro with even-width digits (not a monospace font).
- **Halo never becomes lines.** Substances blend; they are never stacked outlines (Oct 11).
- **Closed is quieter than open** (`dim`): a glance, not a sign.
- **Motion only means something.** Breath = something's on. Grow/shrink = you opened/closed it.
  Nothing moves for decoration.
- Text size is the user's: ⌘= / ⌘− / ⌘0 (0.8×–1.4×), remembered.

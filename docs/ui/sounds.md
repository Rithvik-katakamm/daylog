# Sounds

Sound is a product dimension. Code: `app/Sources/DaylogBar/Sound.swift`.

## Today (shipped)

All sounds are macOS built-ins from `/System/Library/Sounds`, at 35% volume.

| Action | Sound |
|---|---|
| Bar opens | Purr |
| Switch mode (note, ghost, look back, edit, focus, a substance) | Tink |
| Saved (log, note, edit, stop, back online, back from a break) | Bottle |
| Go ghost, or step away on a break | Submarine |
| Edit arrows (↓↑ moving the end) | silent |

## Rules (learned the hard way)

- **One action = one sound.** Never alternate variants (the tick/tock experiment was rejected).
- He likes the **style of the macOS palette**. Keep new sounds in that family.
- No sound on repeated keys (arrows), so scrubbing stays calm.
- **One sound = one hit.** Pop (the old open sound) is two hits 70 ms apart and read as two
  sounds; it was swapped for Purr. Before picking a built-in, check it has a single onset.
- The "two sounds on open" bug was macOS's error beep on an unhandled key, not ours. Any
  unexplained sound is probably a key nothing handled.

## Next

Audition sounds one at a time with him, then rewrite the table above as a full sound map:
action → sound → why.

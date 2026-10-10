# Sounds

Sound is a product dimension (Linear **RIT-37**). Code: `app/Sources/DaylogBar/Sound.swift`.

## Today (shipped)

All sounds are macOS built-ins from `/System/Library/Sounds`, at 35% volume.

| Action | Sound |
|---|---|
| Bar opens | Pop |
| Switch mode (note, ghost, look back, edit, focus) | Tink |
| Saved (log, note, edit, stop, back online) | Bottle |
| Go ghost | Submarine |
| Edit arrows (↓↑ moving the end) | silent |

## Rules (learned the hard way)

- **One action = one sound.** Never alternate variants (the tick/tock experiment was rejected).
- He likes the **style of the macOS palette**. Keep new sounds in that family.
- No sound on repeated keys (arrows), so scrubbing stays calm.
- The "two sounds on open" bug was macOS's error beep on an unhandled key, not ours. Any
  unexplained sound is probably a key nothing handled.

## Next (RIT-37)

Audition sounds one at a time with him, then rewrite the table above as a full sound map:
action → sound → why.

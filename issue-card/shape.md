# Issue card (skill in development)

The shape of an issue card, worked out live in Day Log sessions. It will become its own skill;
Day Log is just the playground. Living doc: he gives feedback while we build, we change the shape
here until it feels right, and each change gets a dated line in the log at the bottom.
we change the shape here until it feels right. Each change gets a dated line in the log at the bottom.

## Today's shape

An issue is **something he and Claude think through together**, not a spec Claude can build
in one go. The top block stays short; whatever was said before goes below `### Context`.

```
**Question / Ships:** the problem or the change, in his terms
**Done when:** the check that proves it (a test, a number, or him seeing it work)
**Think together:** the open questions we have to decide before or while building
**Knobs:** the numbers or choices he can tune later (remembered in docs as knobs)
**Layer:** taste / ui / ux / product / backend / infra / ai
**Data / Components:** what it reads and writes, which files, so he sees the system's shape

---
### Context
his words, history, links
```

## Why

- Short top block: the issue size shouldn't slow building down.
- "Think together": the value is in framing the problem, not just typing code.
- Layer + data + components: keeps him at the right altitude to learn the system as we go.

## Log

- **2026-10-12:** compressed cards (Ships / Done when / Knobs / Layer / Data / Components,
  context kept below). Same evening: he said issues should be "things me and Claude would have
  to think and work on", so **Think together** was added and Question can replace Ships for spikes.

# Issue card (skill in development)

The shape of an issue card, worked out live in Day Log sessions. It will become its own skill;
Day Log is just the playground. Living doc: he gives feedback while we build, we change the shape
here until it feels right, and each change gets a dated line in the log at the bottom.

## Two kinds of card

- **Build card:** short, so issue size never slows the build. The shape below.
- **Think card:** for a raw thought that hides a deeper problem (first one: RIT-118). It should
  provoke the nuance, bring the data and the outside knowledge, set up **one informed choice**,
  and teach something on the way:

```
**The thought:** his words, one or two lines
## Principal components   the problem split into parts that can be solved separately
## What we actually have  real numbers from his data, not guesses
## Prior art              who solved part of it and what to steal
## The choice             2-3 options with costs; one recommended, often "measure first"
**Done when / Layer / Data / Components**
## Learn                  the concept, its layer, where it shows up in this repo, 2-3 sources + a do-it step
```

## Build card shape

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
- **2026-10-12, 7 PM:** cards carry a **Design lens** line where it matters: *does it understand me / is it
  competent / is it reliable* (his frame, "a bigger thought" than friction). Each card names which leg it serves
  (e.g. RIT-39 and RIT-117 = reliable). One Linear tab open at a time: the card he's on.
- **2026-10-12, 7:07 PM:** "each issue card should help with and provoke capture of that nuance, the data, and
  bring in supporting information… help me make a very informed choice right there and learn something in the
  process." → **Think card** type added (principal components, real data, prior art, one choice, learn).
  Build cards stay short.
- **2026-10-13, 1:38 PM:** "the layer preference or tag is important to me." Every card names its Layer; whether it
  becomes a Linear label is open until the data seasons. Logged in Notion "Linear Card Management (feedback + rules)".

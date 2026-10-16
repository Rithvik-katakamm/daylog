# Keys

Keyboard-first: you should never need the mouse. The bindings live in
`app/Sources/DaylogBar/main.swift` (the key monitor) and `HotKey.swift` (the global shortcut).

## The grammar

Keys are grouped by **what kind of thing they do**, so a new feature has an obvious slot:

| Group | Pattern | Meaning |
|---|---|---|
| **Global** | ⌥ + letter | Works from any app: opens the bar |
| **Line** | ⏎ / ⇧⏎ | Do what the line says |
| **Navigate** | arrows, Tab, Esc | Move through time, or leave |
| **Modes** | ⌘ + letter | Change what the input line *means* (note, ghost) |
| **Layers** | ⌘ + letter | Describe *how you are* on the current task. They stack (focus, states) |
| **Actions** | ⌘ + symbol | Do something to what's selected (stop, delete) |

## Say it instead (v0.6): typing is the main way, keys are shortcuts

Type what you mean and press ⏎. The hint above the bar shows what will happen first.
Works with Wispr Flow dictation too (⌥L, dictate, ⏎). Code: `server/daylog/intents.py`.

| Type (or dictate) | Does |
|---|---|
| `smoke break` · `smoke` · `going on a smoke break` | Smoke break (comes back high) |
| `peeing` · `pee break` · `bathroom` · `lunch break` | A break with that name; the task pauses, `back` resumes it |
| `didnt actually break` · `never mind` · `cancel break` · `false alarm` (on a break) | Takes the break back: it's removed and the task runs on from when the break started |
| `walk` · `break` · `brb` · `stepping away` | Walk break |
| `back` · `I'm back` | End the break and resume the task (or come back from ghost) |
| `focus` · `locked in` / `deep focus` / `hyperfocus` · `in the zone` / `focus off` | Focus tiers |
| `high` · `drunk` · `caffeinated` · `coffee` / `not high anymore` · `sober` | Substances on / off |
| `ghost` · `ghost: dinner` · `ghost mode` / `online` | Ghost on / off |
| `stop` · `done` | Stop the timer |
| `working on daylog, little high` | Starts the task **and** turns high on |
| `Coffee, high, change the status to deep focus.` | All three, in order (dictation style) |

⇧⏎ always logs the line as a plain task, never a command.

## Today (shipped)

| Key | Where | Does |
|---|---|---|
| **⌥L** | anywhere | Open or close the bar (and take the keyboard) |
| ⏎ | typing | Start a timer, or log a past block if the text has a time (`15m`, `3:10-3:25`, `since 1pm`) |
| ⇧⏎ | typing | Force a timer even if the text contains a time |
| ↑ | empty line | Look back through logs, meetings, notes and gaps |
| ↑ / ↓ | looking back | Earlier / later |
| ⏎ | on a gap | Fill it in |
| ⌘⌫ | looking back | Delete that block or note |
| ↓ | empty line | Edit the running (or last) block |
| ↓ / ↑ (⇧ = 15m) | editing | Move the end time 5 minutes earlier / later |
| ⏎ | note, ghost, edit, fill | Save |
| ⌘N | typing | Note mode |
| ⌘O | typing | Ghost mode (or come back online) |
| ⌘F | typing, task running | Focus: focused → deep → hyperfocus → off |
| ⌘⇧F | typing, in focus | Focus off, straight away |
| ⌘B | typing | Walk break: the task pauses. ⌘B again when you're back resumes it |
| ⌘⇧B | typing | Smoke break: same, and you come back **high** |
| ⌘H | typing | Toggle **high** (bar wins over macOS Hide, Oct 13) |
| ⌘I | typing | Toggle **intoxicated** |
| ⌘C | typing | Toggle **caffeinated** (C for coffee; bar wins over Copy, Oct 13) |
| ⌘. | typing | Stop the timer |
| Tab | anywhere in the bar | Close and return to the app you were in |
| Esc | anywhere | Step back one level; closes from the typing line |

Not back from a break within an hour? It’s logged as a ~15 min break, then ghost from there. Back from a smoke break after 15 min: the smoke break is logged as 15 min, and the time after it stays blank (unknown). Walks have no cap.
⌘B still brings you back and resumes the task.

Menu-only (⌘K): **Always on: center pill / side ring / pill + ring / off**: what stays on
screen while the bar is closed. **Demo**: a window that shows the pill in every
state (made up on screen; nothing is logged), the model reading lines live (with its reason), and a
try-a-line box.

While the model reads a line the bar says **reading…**; its reading replaces the preview with its
reason. ⏎ waits for it (at most 3 s, then the rules); ⇧⏎ never waits.

## Reserved

| Key | Group | Does |
|---|---|---|
| ← / → | Navigate | Flip ghost ↔ tracker |

## Rules for picking new keys

- Avoid keys macOS or text editing owns: ⌘Q ⌘W ⌘H ⌘M ⌘C ⌘V ⌘X ⌘Z ⌘A ⌘Tab.
- Mnemonic first (N note, O offline, F focus).
- **Global ⌥ shortcuts take that key away from every app.** ⌥L means you can't type ¬.
- One key, one meaning per context, and one sound per action (see `sounds.md`).
- Before adding a key, add it to this file.

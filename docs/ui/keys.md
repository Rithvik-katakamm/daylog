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
| ⌘. | typing | Stop the timer |
| Tab | anywhere in the bar | Close and return to the app you were in |
| Esc | anywhere | Step back one level; closes from the typing line |

## PROPOSED (Oct 10)

| Key | Group | Does |
|---|---|---|
| **⌥D** | Global | Open the bar in **dev mode**: same UI, separate test database |
| **⌘I** | Layer | Toggle **intoxicated** |
| **⌘G** | Layer | Toggle **high** ("G" for green) |
| ← / → | Navigate | Reserved: flip ghost ↔ tracker (RIT-43) |

## Rules for picking new keys

- Avoid keys macOS or text editing owns: ⌘Q ⌘W ⌘H ⌘M ⌘C ⌘V ⌘X ⌘Z ⌘A ⌘Tab.
- Mnemonic first (N note, O offline, F focus).
- **Global ⌥ shortcuts take that key away from every app.** ⌥L means you can't type ¬. ⌥D
  in a terminal is "delete word forward", which is acceptable for dev mode only.
- One key, one meaning per context, and one sound per action (see `sounds.md`).
- Before adding a key, add it to this file.

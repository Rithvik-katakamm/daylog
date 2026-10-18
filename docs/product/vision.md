# Day Log: vision

> The horizon, not the plan. The work queue lives in Linear; what's built is in
> `docs/ui`, `docs/backend` and `docs/infra`.

## One sentence

**Day Log answers one question: what am I doing?** Now and historically, with honest
sources, for me and for every AI agent that works for me.

## Why it exists

- **Your felt sense of time is unmeasured and usually wrong.** Holding a dozen things in your
  head creates context switching, and the day dissolves. Day Log turns "I think my days go
  like X" into "my days go like X."
- **A scheduler can't plan on guesses.** Any planner, human or AI, needs real durations, real
  start times, and when you hyperfocus vs. drift.
- **Agents are blind to your day.** Any agent you use should be able to ask what you're doing.
- **Guilt-free time.** "I was building then" is something to see, not just believe.

## Non-negotiables

1. **No nagging, just logging.** Observational. It never judges or interrupts.
2. **Source attribution on every entry.** Claimed by you vs. observed by a machine vs.
   predicted by a model. Never mixed.
3. **Fast and keyboard-first, or it won't get used.** One input line, one shortcut.
4. **Greedy for ground truth.** If a system of record proves it (a recorded meeting, a
   workout), it goes in without asking.
5. **Append-only.** Nothing is erased; edits are new events; views are derived.
6. **Day Log never writes your calendar.** It records actuals; planning belongs elsewhere.

## The model: three dimensions

| Dimension | Shown as | Examples |
|---|---|---|
| **What am I doing** | the main ring | a task, ghost (offline), a break |
| **How am I** | ring heat + outer rings | focus tiers, altered states |
| **What am I typing** | the ring, while typing | a note, looking back, editing |

Details: `docs/ui/colors.md` and `docs/ui/keys.md`.

## Where it's going

- **Capture:** focus that feels like a game, states that stack, a command menu, phone/watch.
- **Ground truth:** wearables (workouts), music, location, coding sessions.
- **Access:** a server any agent can reach at any time (remote MCP), off the laptop.
- **Intelligence (only if it passes the no-nagging test):** smart titles, predictions trained
  on your own confirmations.

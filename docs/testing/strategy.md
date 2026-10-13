# Testing strategy

**Thesis.** Tests never appear on his screens. Almost everything is checked headless; a hidden macOS
virtual machine is the escalation for the few checks that need a real window; CI comes when agents push
on their own. (His preference, Oct 13: "let's switch to headless testing for all of the features that we
are building now and going to build. If there's any discrepancy… escalate to the need for the VM.")

## Vocabulary

| Word | Means |
|---|---|
| **Headless** | The Dev app runs with every window off-screen (x = −30000) and no sound. It still draws; nobody sees it. |
| **devctl** | The test remote: sends commands to the Dev app through a private channel, never the real keyboard. |
| **State line** | `test-state …` written to `~/Library/Logs/daylog/app-dev.log` after every devctl command. |
| **Snapshot** | A PNG of the bar exactly as drawn: `~/Library/Logs/daylog/snapshots/<name>.png`. How a test "sees". |
| **The lab (VM)** | A hidden macOS VM on his Mac for stubborn real-window checks. **Not set up yet.** |
| **The gate (CI)** | GitHub Actions checking every push (RIT-130). **Not set up yet.** |

## How it works and why

| Level | What runs | Where | Speed |
|---|---|---|---|
| Unit + API | `cd server && uv run pytest -q` | headless by nature | under 1 s for all |
| App, headless | `devctl start` → `open` / `key` / `type` / `snap` → read the state line + snapshot → `devctl stop` | his Mac, off-screen | seconds |
| Real window | the lab VM (when needed) | a hidden macOS VM | tens of seconds to start, seconds per check (estimate) |
| Every push | CI (later) | GitHub's macOS runners (free for public repos) | minutes |

A headless snapshot can differ from the real window (glow and blur use window effects). If a check
depends on that, or on real keyboard focus or animation, escalate to the lab: say so, and ask before
setting it up (it costs his Mac memory, CPU and disk).

## Rules

| Rule | Why |
|---|---|
| Use `devctl start` (headless), never a visible Dev app, for tests | Tests looked identical to stable on his screen |
| Quit with `devctl stop` after testing | Only one Day Log should run on his screen |
| Escalate to the VM only on a real discrepancy, and ask first | Resource cost; pain first |
| The number to watch: test windows on his screen, target **0** | Decide with numbers |
| ⌥D (opening Dev from stable) stays visible | That's him playing with Dev, not a test |

## History

- Oct 12: tests drove a visible Dev app; he couldn't tell it from stable ("I can't tell the difference
  between that and the stable version I'm using").
- Oct 13: options compared (headless / unmistakable look / another machine). He chose headless for all
  features, the local VM as the escalation ("spin up a VM on my Mac that I don't see"), CI later.
  Headless mode shipped: `DAYLOG_HEADLESS=1`, `devctl start|stop|snap`.

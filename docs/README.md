# Day Log docs

The map of everything that isn't code. If you can't hold it in your head, it should be here.

| Folder | What lives here | Start with |
|---|---|---|
| `product/` | What Day Log is and where it's going; what it's like to use (friction log) | `vision.md`, `experiences.md`, then `specs/` |
| `ui/` | What you see, press and hear | `keys.md`, `colors.md`, `sounds.md` |
| `backend/` | The server, the event log, the API; the model harness; the display agent | `events.md`, `harness.md`, `display.md` |
| `infra/` | How it's installed, run, signed and released | `install.md` |
| `infra/dev-infra/` | Sub-layer (his, Oct 13): how *building* works, phone → cloud → CI → his Mac | `cloud-loop.html` (explainer), `cloud.md` |
| `testing/` | How changes are checked without touching his screens (his layer, Oct 13) | `strategy.md` |
| `skills/` | Drafts of skills distilled from how he runs builds (PROPOSED, not installed) | `README.md` |

## Rules for these docs

- **Docs describe what's true today.** Anything not built yet is marked **PROPOSED** or
  links to its Linear issue. When something ships, the doc changes in the same commit.
- **Vision vs. work:** `product/vision.md` is the horizon. The work queue is Linear (team
  RIT, project "Day Log"). Don't track tasks in these files.
- **One topic, one file.** If a section grows its own sub-questions, it becomes a file.

## Where else things live

- **Linear:** issues, priorities, what's next. Label rules: the team doc "How we use labels".
- **Notion (read-only for agents unless he says so):** ideas, Focus, Agent Context.
- **`CLAUDE.md`:** working rules for Claude Code in this repo.
- **`README.md` (repo root):** how to use it and how it's built.

# Runtime reference

From an installed project's root:

`python3 .claude/build-learn/runtime.py --session SESSION status`

Use the session ID supplied by the hook. For mutations, pass JSON on stdin using a
quoted heredoc (`<<'JSON'`); do not interpolate the user's text into shell commands.
The default project is CLAUDE_PROJECT_DIR, then cwd. Pass `--project /absolute/root`
when operating elsewhere. Runtime data lives at `.learning/build-learn.sqlite3`.

In a restricted session that disallows heredocs, use the Write tool to save the
JSON to `.learning/request.json`, then run
`python3 .claude/build-learn/runtime.py --session SESSION --input-file .learning/request.json assess`.
This is a single command without shell redirection. The runtime accepts input files
only inside this project's `.learning/` directory. Use the same path for other actions.
Alternatively, `--data-json` accepts one shell-quoted JSON argument. Use proper
single-quote escaping; never paste unescaped user text into double-quoted shell code.

## Assessment

Command: `assess`. Example JSON (substitute actual evidence IDs):

```json
{"observation":1,"evidence":[1],"build_issue":"CARD-150","concept":"request ownership","worthy":true,"blocking":true,"route":"existing","learn_issue":"CARD-123","reason":"Choosing the field location requires tracing the running request path"}
```

Use `unassigned` for build_issue only when there is no current card. `new` additionally
requires `existing_search` (search evidence ID) and `user_request` (user observation
ID). These verify that sources exist; read the actual words before claiming approval.
`deferred` is worthy but waiting; `none` dismisses a candidate; `inline` answers locally.
Appending another assessment for the same observation supersedes it without deletion.
Pending means unassessed, not unlearned: a valid assessment clears that observation
from the pending list. It does not imply mastery or learning-card completion.
For a correction from a new observation, include `supersedes` with the prior assessment
ID. This preserves both sources and invalidates permits based on the old assessment.

## Source evidence and outcomes

Command `evidence`: `{"kind":"verification","summary":"Request failed after server stopped, as predicted","source":"transcript path:line or test output path"}`.
Kinds: verification, search, code, shipping, decision_result. Agent-recorded sources
remain distinct from directly captured user observations. Cite inspectable artifacts;
do not create evidence because the gate requires it.

Command `outcome`: `{"assessment":2,"result":"helped","reason":"User predicted the failure and chose the correct boundary","evidence":[7,8]}`.
Results: helped, hurt, unclear. Result is still a model judgment unless the cited
source is user feedback. Do not automatically close learning from this field.

## Linear writes

Command `permit` needs `tool`, `tool_input`, `action`, `assessment`, `reason`, and
`evidence` IDs. Input must match the actual tool call exactly. Permit expires after
10 minutes, is session-bound, is invalid after reassessment, and is consumed once.
Actions: build_update, learning_create, learning_update, learning_complete, reorder.
Learning creation and description updates require `card_review`: a passing review
of a `card_draft` whose description exactly matches the outgoing description. The
development skill documents the fields and rubric. The runtime checks review
completeness and exact content, not whether an agent's quality score is correct.
Reorder additionally requires `ranking_change`, describing old/new ordering and why.
Learning_complete additionally needs user observation IDs `explanation` and
`prediction`, plus a `verification` evidence ID. Link `learn_issue` using the same ID
as the mutation; record a new assessment if switching between identifier and UUID.
After success, the hook records return metadata, not a claim of learning success.
After a tool failure, inspect state before obtaining a fresh permit and retrying.

## Direct feedback

The user's literal prompt `build-learn feedback Too many questions` is captured as
feedback. `build-learn skip Keep building; revisit later` releases pending checks
in this session and leaves understanding unverified. Slash forms are also accepted
when the harness forwards the literal prompt. Natural-language feedback also works:
cite that observation in a revised assessment.

## Coverage

Project-local Claude Code hooks gate direct Linear MCP issue create/update/save
tools. They do not gate arbitrary shell HTTP, wrappers, browser edits, other hosts,
other projects, or manually changed settings. Never use those routes to evade the
protocol. Registered learning cards receive extra completion checks; unregistered
cards depend on truthful classification. Semantic adequacy, duplicate equivalence,
and intent remain model judgments. The system is workflow enforcement, not a security
boundary against a hostile agent. Stop requests one reassessment pass, never an
infinite quiz loop. Hook errors preserve normal work but deny covered Linear writes
while storage is unavailable. No model API, daemon, automatic uploads, or auto-training.

`export` emits the full local ledger for evaluation. Keep this personal data local.
The database resists accidental updates/deletes; the owner can deliberately erase
it. SQLite WAL transactions handle concurrent hooks. Schema and policy versions are
separate; v0.1 creates schema version 1, with migrations required for future changes.

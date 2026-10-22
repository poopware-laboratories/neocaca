# CLAUDE.md

All project instructions live in [`AGENTS.md`](AGENTS.md), shared by every
coding agent and human contributor. Read it first and follow it; do not
duplicate its content here.

Claude Code specifics: the skills in `.claude/skills/` are per-task
checklists for these rules (start every change with `making-a-change`), and
`.claude/settings.json` pre-approves the build and test commands.

Four rules from `AGENTS.md` that sessions most often get wrong:

- **Clean room.** Never read, fetch or reproduce the source of another
  editor or library, even to compare; design from specifications and
  documented behavior (see "Clean-room policy").
- **Test first, 3:1.** Every change starts with a failing test.
- **The roadmap is [`TODO.md`](TODO.md);** keep it and every other doc
  current in the same commit, [`docs/keys.md`](docs/keys.md) included.
- **One piece, then stop.** Do the next piece from `TODO.md`, push it, and
  report. Merge or start another only when the maintainer says so (see
  "Work in pieces").

@AGENTS.md

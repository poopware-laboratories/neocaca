---
name: making-a-change
description: Use when starting any code change, bug fix or feature in neocaca, and again before committing, pushing or opening a pull request.
---

# Making a change in neocaca

AGENTS.md is the rulebook; this is the order to apply it in. Every step is
required. Skipping one is how pull requests go red.

## 1. Before writing code

- Take the first unticked piece in `TODO.md` (or the one the maintainer
  names), and say in a line or two what it will change. Do only that
  piece. If a pull request for its heading is open, stack onto that
  branch.
- Search the open issues and `TODO.md` for the topic.
  Someone may own it, or an issue may say how it must be done.
- Branch from an up-to-date `main`: `git switch main && git pull --rebase &&
  git switch -c type/short-topic` (`fix/undo-merge`, `feat/soft-wrap`).
- Find the folder from the table in AGENTS.md ("Architecture in one
  screen") and the file for the concern; start a new file rather than
  mixing two concerns in one. If the logic needs a terminal or a file to
  test, it belongs in a pure module instead; only `term/`, `fs/`,
  `main.zig` and the shell files of `app/` that wire them do I/O.

## 2. Red, green, refactor

**REQUIRED SUB-SKILL:** test-driven-development. In short: write the test,
watch it fail for the expected reason, write the least code that passes,
refactor with the suite green. Allocating code: **REQUIRED SUB-SKILL:**
managing-memory.

## 3. Checks, in this order

```sh
zig build fmt
zig build test --summary all
zig build test -Doptimize=safe --summary all
zig build -Dtarget=x86_64-macos     # when platform-gated code changed
zig build -Dtarget=x86_64-freebsd   # likewise
```

In the same commit, bring every Markdown file in step with the change,
unasked:

- tick or add the `TODO.md` item; change `docs/keys.md` with any binding
  or `:` command, checked against the keymap and `app/commands.zig`;
- `git grep -n` the `*.md` files for each name the diff touches (file,
  function, key, command, flag, `max_*` limit, CI job) and fix every
  sentence it makes wrong: AGENTS.md's table and rules, README,
  SECURITY, ACCESSIBILITY, CONTRIBUTING, the skills;
- add what is new and undocumented; delete what no longer exists.

Then count the diff (`build.zig` and benchmarks excluded, see AGENTS.md):
three test lines (inside `test` blocks, `*_test.zig`,
`tests/`) per production line, no padding.

## 4. Commit and pull request

- Commits and the PR title are Conventional Commits: `type(scope): summary`,
  lower case, imperative, no final period. The title becomes the squashed
  commit on `main`, so write it for a reader of the changelog.
- One concern per pull request. Link the issue: `Closes #N`.
- Fill in `.github/pull_request_template.md`: *Why*, *How it was checked*,
  the checklist. When stacking a piece, widen the title and body to cover
  it.

## 5. Stop and report

Once the piece is pushed and CI is green (or you know why it is not),
stop. Tell the maintainer what changed, the CI result, and the next
piece, and whether it stacks onto this pull request or needs a new one.
Tick the piece in `TODO.md` as part of the piece itself. Then wait:
*merge* squashes the pull request, and *continue* starts the next piece
on the same branch. Never merge or start the next piece unasked.

## Related skills

| Change | Skill |
|--------|-------|
| Any behavior change or bug fix | test-driven-development |
| Anything that allocates, frees or owns memory | managing-memory |
| Anything users see: rendering, layout, colors, cursor | checking-screen-output |
| A SIMD kernel, or anything claimed to be faster | AGENTS.md "Performance and security"; `zig build bench` in fast and safe |
| Driving an open PR to green | steward |

## Common mistakes

| Mistake | Fix |
|---------|-----|
| A new file the test step never imports | Reference it from its folder's namespace file (`_ = @import("cli/x.zig");` in its `test` block) and check the test count went up. |
| A new subsystem as one big file, or importing another folder's files | A folder plus a namespace file of the same name (`src/x.zig`, `src/x/`); reach other subsystems only through their namespace file. |
| A function no test calls | Zig never analyzes it, so it may not even compile. Test it. |
| `catch unreachable` on an allocation | Propagate `error.OutOfMemory`. |
| Writing file text straight to the terminal | Render control bytes visibly; files are untrusted. |
| Adding a package to `build.zig.zon` | Never without an agreed issue (mimalloc is the one exception). Write it ourselves. |
| Calling `mi_malloc` or other `mi_*` functions directly | Take a `std.mem.Allocator`; only `src/alloc/mimalloc.zig` touches mimalloc. |
| `@setRuntimeSafety(false)` to speed up a loop | Reshape the loop (`while (rest.len >= n)`, `rest[0..n]`) so the checks are free. |
| Growing a file past ~400 lines | New file, starting with a `//!` line saying what it is for. |

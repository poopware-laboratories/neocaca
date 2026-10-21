<!--
Title: a Conventional Commit, e.g. `fix(edit): keep the cursor column on undo`.
It becomes the squashed commit on main. The full rules are in AGENTS.md.
-->

## Why

<!-- The problem this solves or the behavior it adds. Not what the diff does line by line. -->

Closes #

## How it was checked

<!--
Delete what does not apply:
- Performance: before and after numbers from the same machine, ReleaseFast.
- Screen output: captures before and after (tmux capture-pane -p -e).
-->

## Checklist

- [ ] I wrote each test first and saw it fail for the expected reason before making it pass.
- [ ] At least 3 test lines per production line, with no padding.
- [ ] `zig fmt --check .` and `zig build test` (Debug and ReleaseSafe) pass.
- [ ] Platform-gated code builds for the other targets, or there is none.
- [ ] Every allocation is freed on every path; allocation failures are tested where handled.
- [ ] No new dependencies in `build.zig.zon`.
- [ ] File and terminal input stays bounded, and no raw control bytes reach the terminal.
- [ ] Saving cannot lose or truncate user files, and the terminal is restored on every exit path.
- [ ] README, AGENTS.md and docs are updated where this changes what they say.

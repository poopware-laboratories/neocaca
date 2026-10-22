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
- Performance: `zig build bench` before and after, same machine, in ReleaseFast and ReleaseSafe (`-Dbench-optimize=safe`).
- Screen output: captures before and after (tmux capture-pane -p -e).
-->

## Checklist

- [ ] I wrote each test first and saw it fail for the expected reason before making it pass.
- [ ] At least 3 test lines per production line, with no padding (`build.zig` and benchmarks not counted).
- [ ] `zig build fmt-check` and `zig build test` (Debug and ReleaseSafe) pass.
- [ ] Platform-gated code builds for the other targets, or there is none.
- [ ] Every allocation is freed on every path; allocation failures are tested where handled.
- [ ] No new dependencies in `build.zig.zon` (mimalloc is the only one), and no `mi_*` calls outside `src/alloc/mimalloc.zig`.
- [ ] File and terminal input stays bounded, and no raw control bytes reach the terminal.
- [ ] Saving cannot lose or truncate user files, and the terminal is restored on every exit path.
- [ ] README, AGENTS.md and docs are updated where this changes what they say, and anything new that users do has a scenario in `docs/dogfooding.md`.

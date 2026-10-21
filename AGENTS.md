# AGENTS.md

Instructions for AI coding agents (any model or tool) and for humans working
on neocaca. This file is the single source of truth; `CLAUDE.md` and any
other agent-specific files only point here. The Claude Code skills in
`.claude/skills/` turn these rules into per-task checklists (a change, a
test written first, memory and allocators, screen output, a pull request to
drive); when they disagree with this file, this file wins and the skill is
fixed.

neocaca is a modern terminal (TUI) code editor written in Zig. It talks to
the terminal directly (raw mode, escape sequences out, key bytes in) and
keeps its own text buffer, input decoder and screen renderer, all tested
without a real terminal.

## Quick reference

```sh
zig build                                   # debug build: zig-out/bin/neocaca
zig build test --summary all                # every unit and integration test
zig build test -Dtest-filter="piece table"  # only tests whose name matches
zig fmt --check .                           # formatting (zig fmt is the style)
zig build -Doptimize=safe                   # ReleaseSafe: the shipping build
zig build test -Doptimize=safe --summary all  # the tests as shipped
zig build bench                             # SIMD kernels against scalar (ReleaseFast)
zig build bench -Dbench-optimize=safe       # the same, as shipped
zig build -Dtarget=aarch64-macos            # cross-compile; also x86_64-macos, x86_64-freebsd
zig build run -- path/to/file               # run the editor
```

Build options: `-Doptimize=debug|safe|fast|small` (Zig 0.17 names; the old
`ReleaseSafe`-style names are deprecated), `-Dtest-filter=…`,
`-Dmimalloc-secure=off|on|full` (default `on`), `-Dbench-optimize=…`.

- **Toolchain:** Zig 0.17.0, pinned by `minimum_zig_version` in
  `build.zig.zon`. Use exactly that version; Zig's standard library changes
  between releases, so code that builds on another version proves nothing.
- **Formatting:** `zig fmt`, no exceptions. Run it before every commit.
- **`build.zig` contract:** `zig build test` must run every test in the project
  and `-Dtest-filter` narrows it. Keep both working when you add modules;
  a test file not reachable from the test step is a test that never runs.
- **CI** (`.github/workflows/ci.yml`) runs `zig fmt --check .`, the tests
  in Debug and ReleaseSafe on Linux and macOS (and ReleaseSafe again with
  `-Dmimalloc-secure=off`), a ReleaseSafe build for every supported target,
  and a benchmark smoke run. All must pass; run them before pushing.
- **Platform-gated code** (`switch (builtin.os.tag)`, `@import("builtin")`
  checks) is only analyzed for the target you build. Zig compiles lazily:
  a function nobody calls is never type-checked. Check other targets with
  `zig build -Dtarget=x86_64-macos` / `aarch64-macos` / `x86_64-freebsd`
  / `aarch64-linux`,
  and make sure tests reference the code you changed.

## Before you start

Search the open [issues](https://github.com/poopware-laboratories/neocaca/issues)
first. Someone may already be working on the change, an issue may set out
how it should be done, or a higher-priority item may come first. Comment on
an issue to claim it, and link the issue from your pull request
(`Closes #N`). Once a `TODO.md` exists, read it too.

## Workflow: strict test-driven development

Every behavior change and bug fix follows red → green → refactor. There is
no "I'll add the tests after".

1. **Red.** Write or change a test that describes the desired behavior.
   Run it (`zig build test -Dtest-filter="<name>"`) and confirm it fails
   *for the expected reason*: a failed `expect*`, or a compile error
   because the function does not exist yet. A typo, a leak in the setup or
   a crash in an unrelated helper is not a red step; fix the test.
2. **Green.** Write the smallest change that makes it pass. Nothing
   speculative: no extra parameters, options or branches the test does not
   demand.
3. **Refactor.** Clean up, with the whole suite (`zig build test`) green
   after every step.
4. Run the full checks (`zig fmt --check .`, `zig build test` with
   `-Doptimize=debug` and `-Doptimize=safe`) before pushing.

A test that passes the first time you run it proves nothing; adjust it until
you have seen it fail. When fixing a bug, the first commit may be the
failing regression test alone. Pure refactors keep existing tests green and
add characterization tests first for code that had none.

**The 3:1 rule.** Every pull request adds at least **three lines of tests
for each line of production code**. Test lines are those inside `test "…"
{ }` blocks, in `*_test.zig` files and under `tests/`; blank lines and
comments count for neither side. Until a script enforces it in CI,
reviewers count it from the diff.

- Pull requests without production code (docs, CI, build tweaks) pass.
- Meet the ratio with tests that pin real behavior: edge cases, bounds,
  allocation failures, malformed input, regressions, differential cases.
  Never pad (duplicate assertions, filler, loops that only add lines);
  reviewers reject padding like any other bad test.
- When a change cannot meet the ratio cheaply, it is usually too big or too
  hard to test. Split it, or make the logic pure and testable.

Performance work is measured, not guessed: benchmark before and after
with `zig build bench` (alternating builds, several runs, medians), in
ReleaseFast and in ReleaseSafe (`-Dbench-optimize=safe`), and drop changes
that do not show a reproducible gain. A fast path must produce output
identical to the slow path it replaces, and a test must show that.

## Performance and security

neocaca ships as **ReleaseSafe**: bounds, overflow and unreachable checks
stay on in the build users run. Performance comes from better algorithms
and SIMD, never from turning safety off.

- **SIMD lives in `src/simd/`**, written with `@Vector` and
  `std.simd.suggestVectorLength`, generic over the width (`fooWidth(n, …)`)
  so tests can run every width (16, 32, 64) on any CPU. No inline assembly
  and no CPU-specific intrinsics.
- **Every kernel has a scalar reference** (`fooScalar`), the simplest
  correct loop, and a differential test against it: random input from a
  fixed seed (printed on failure), every byte value, lengths and offsets
  around every vector boundary. A kernel without one does not merge.
- **Read only through slices.** Load chunks as `rest[0..n].*` and advance
  with `rest = rest[n..]` under `while (rest.len >= n)`; the tail shorter
  than a vector goes to the scalar reference. Never read past the end of
  the input, not even within the same page, and never `@ptrCast` a pointer
  to a wider type to load.
- **Make checks free instead of removing them.** Shape loops so the
  optimizer can prove a bounds check redundant (the pattern above runs as
  fast in ReleaseSafe as in ReleaseFast). `@setRuntimeSafety(false)`
  needs a benchmark showing a gain in ReleaseSafe, a comment stating the
  invariant that makes it safe, a `std.debug.assert` of that invariant,
  and a test at its boundary; prefer it never.
- **Bounds on untrusted sizes** hold on fast paths too: a fast path takes
  the same `max_*` limits as the slow path.
- **Hardened allocator.** mimalloc runs with `-Dmimalloc-secure=on` by
  default; `off` exists only to measure the allocator itself.

## Memory and allocators

Zig makes every allocation explicit; keep it that way.

- **No global allocator.** Every function that allocates takes a
  `std.mem.Allocator` parameter (or is a method on a type that stores one
  from `init`). Only `main.zig` chooses the process allocator, by
  `alloc.process.kindFor(builtin.mode)`: `std.heap.SafeAllocator` in Debug
  (leaks, double frees and use after free reported),
  [mimalloc](https://github.com/microsoft/mimalloc) in ReleaseSafe,
  ReleaseFast and ReleaseSmall.
- **mimalloc is the release allocator.** It is Microsoft's C library (MIT),
  v3.5.3, pinned by URL and hash in `build.zig.zon`, compiled by
  `build.zig` from its single-file `src/static.c` with its `include/`
  directory (no CMake, the defines its CMakeLists.txt would set), and
  linked with libc. `src/alloc/mimalloc.zig` wraps it as a
  `std.mem.Allocator` (`mi_malloc_aligned`, `mi_expand` to grow in place,
  `mi_realloc_aligned` for remap, `mi_free`); no other file calls `mi_*`
  functions, and they are declared there as `extern fn`, not through
  `@cImport`. Shrinking always succeeds in place (`mi_free` needs no
  length); growing in place fails under hardening, whose overflow-detection
  padding `mi_expand` refuses to touch. Requests over `max_request` fail
  before reaching mimalloc. The wrapper's tests (alignment for every power
  of two up to a page, resize and remap keep contents, huge requests fail
  with `error.OutOfMemory`, the std allocator conformance tests) run in
  every build mode and hardening level. Debug builds and tests keep the
  leak-checking std allocators; never make mimalloc the test allocator.
- **Ownership is written down.** A doc comment says who frees what:
  "Caller owns the returned slice", "Borrowed; valid until the next edit".
  Types with resources have `init`/`deinit`; `deinit` frees everything and
  leaves the value undefined (`self.* = undefined`).
- **`defer` and `errdefer` go on the line after the acquisition**, never
  later. Every `try` between an allocation and its hand-off needs an
  `errdefer` that frees it.
- **Arenas for scratch.** Per-frame render scratch and per-command temporary
  data use an `std.heap.ArenaAllocator` reset each frame or command. Long-
  lived state (buffers, undo history) never lives in a frame arena.
- **Out of memory is an error, not a crash.** Propagate `error.OutOfMemory`;
  never `catch unreachable` or `@panic` on allocation. An edit that fails to
  allocate leaves the buffer exactly as it was.
- **Tests use `std.testing.allocator`**, which fails the test on any leak.
  Code that handles allocation failure is tested with
  `std.testing.checkAllAllocationFailures`.
- **Undefined behavior is a bug even when tests pass.** Run the suite in
  Debug and ReleaseSafe; never ship code that only works in ReleaseFast.

## Architecture in one screen

The repository is at its start: `src/alloc`, `src/simd`, `src/cli.zig`,
`src/main.zig` and `src/bench.zig` exist; the rest is the layout new code
goes into. Update this table in the same pull request whenever the code
diverges.

```
stdin bytes ──► input::decode ──► input::Event ──► app::EventLoop ──► edit::Command
 (raw mode)       (pure)             (key, mouse,       │ (one thread)       │
                                      paste, resize)    │                    ▼
                                                        │            buffer::Buffer + edit::History
                                                        ▼                    │
terminal ◄── term::Output ◄── render::diff ◄── render::Screen ◄── ui::layout ◄┘
 (escape bytes)   (writes)       (pure)          (cell grid)       (pure)
```

| Path | Responsibility |
|------|----------------|
| `src/main.zig` | Allocator choice, I/O setup, then `run` (arguments to exit code, tested over plain writers). Later: terminal setup and guaranteed restore, then `app.run`. |
| `src/root.zig` | The `neocaca` module: re-exports every subsystem, and references them all so `zig build test` reaches their tests. |
| `src/cli.zig` | Pure command-line parsing. |
| `src/alloc/` | `mimalloc.zig`: the `std.mem.Allocator` wrapper around mimalloc, the only code that calls `mi_*`. `process.zig`: which allocator each build mode uses. |
| `src/simd/` | SIMD kernels and their scalar references: byte counting and search, control-byte search (`bytes.zig`, tested in `bytes_test.zig`). |
| `src/bench.zig` | `zig build bench`: each kernel against its scalar reference. |
| `src/buffer/` | Text storage (piece table or rope), byte offsets, line index, UTF-8 and grapheme boundaries. No I/O, no terminal. |
| `src/edit/` | Commands applied to buffers: insert, delete, cursor and selection movement, undo/redo history. |
| `src/input/` | Pure decoder: raw terminal bytes to key, mouse, paste and resize events; keymaps from events to commands. |
| `src/render/` | `Screen` (a grid of cells: grapheme, width, style), the diff of two screens into minimal escape output, display width. |
| `src/ui/` | Pure layout: views, splits, gutter, status line, prompts, scrolling. |
| `src/term/` | The only code that touches the real terminal: raw mode, size, non-blocking reads, buffered writes. Platform-gated. |
| `src/app/` | The event loop gluing the rest together. `App` methods route events to the pure modules above. |
| `src/fs/` | Loading and saving files: atomic writes, encodings, line endings, size limits. |
| `tests/` | Integration tests that drive a whole editor session from scripted input bytes and assert on the final `Screen` and buffers. |

## Rules of thumb

- **Keep files small and single-purpose.** Prefer a new file over growing
  one past roughly 400 lines. Each file starts with a `//!` doc comment
  saying what it is for. Tests that outgrow their file move to a sibling
  `name_test.zig`, referenced from the module so `zig build test` reaches it.
- **Functional core, imperative shell.** Encoding, decoding, layout, editing
  and diffing are pure functions over plain data (`input.decode(bytes)`,
  `ui.layout(state, size)`, `render.diff(old, new, writer)`). Only `term/`,
  `fs/` and `main.zig` do I/O; `App` mostly routes events. If a test needs a
  real terminal, the logic is in the wrong place.
- **Never block the event loop.** Reading the terminal, saving files and
  running external tools must not freeze typing. Long work goes off the
  loop and reports back as an event.
- **The terminal is always restored.** Raw mode, the alternate screen,
  mouse and bracketed-paste modes are undone on normal exit, on error
  returns and on panic (install a panic handler that restores first).
- **Never lose user data.** Save by writing a temporary file in the same
  directory and renaming it over the original; keep permissions; on any
  error leave the original untouched and tell the user. Every edit is
  undoable. A crash must never truncate a file.
- **File contents are untrusted.** A file can contain escape sequences,
  invalid UTF-8, NUL bytes, enormous lines and gigabytes of text. Never
  write raw control characters to the terminal (render them visibly, e.g.
  `^[`), never assume valid UTF-8, and keep explicit limits (`max_*`
  constants) on what is loaded or decoded, each tested at the limit and one
  past it. The same holds for bytes coming back from the terminal (replies,
  pastes).
- **Widths are hard.** Cursor movement and rendering work in grapheme
  clusters and display columns, not bytes or code points. Wide characters,
  combining marks, tabs and emoji each need tests.
- **No new dependencies; write our own.** Use the Zig standard library only.
  Implement features in-house from their specifications (clean room: never
  read or copy another implementation's source), so we keep control over
  speed, limits and security. The one deliberate exception is mimalloc, the
  release allocator (see "Memory and allocators"). Adding any other package
  to `build.zig.zon` needs an issue where the maintainers agree to it first;
  bumping mimalloc's version is a `build(deps)` pull request with benchmark
  numbers.
- **Standards compliance.** Emit escape sequences as their specifications
  define them (ECMA-48, xterm ctlseqs, kitty keyboard protocol), probe for
  optional features instead of assuming them, and fall back cleanly on
  terminals that do not answer.
- **Errors are values.** Use specific error sets for library code, handle
  every error explicitly, and never discard one with `catch {}` without a
  comment saying why that is safe.
- **Config compatibility.** User-facing configuration keys and keybindings,
  once released, keep working under their old names.
- Match surrounding style: comment density, naming (`camelCase` functions,
  `TitleCase` types, `snake_case` variables and fields), and `pub` only on
  what other modules use.

## Branches, pull requests and commits

`main` takes no direct pushes or force-pushes. Every change, however small,
goes through a branch and a pull request.

1. **Branch from an up-to-date `main`:**
   `git switch main && git pull --rebase && git switch -c fix/undo-merge`.
   Name branches `type/short-topic` after the Conventional Commits type.
2. **Commit in small steps** on the branch; the red and green steps may be
   separate commits. To pick up new work from `main` on your own branch,
   rebase: `git pull --rebase origin main`, then `git push --force-with-lease`.
   Force-push only to your own branch.
3. **Open a pull request.** One concern per pull request; keep it small.
   The **title is a Conventional Commit** (see below): it becomes the
   squashed commit on `main`. The body explains *why*, links the issue, and
   carries the evidence: benchmark numbers for performance work, screen
   captures for rendering changes. Fill in `.github/pull_request_template.md`.
4. **All checks must pass** before merging. Ask for review when a second
   pair of eyes helps.
5. **Merge by squashing** once green. History on `main` stays linear, one
   commit per pull request.

**Titles and commits follow [Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/):**
`type(scope)!: summary`, with the scope optional, and the summary in lower
case, imperative mood, and without a final period. Types: `feat`, `fix`,
`perf`, `refactor`, `docs`, `test`, `bench`, `build`, `ci`, `style`,
`chore`, `revert`. Scopes name the area touched, usually a module (`buffer`,
`edit`, `input`, `render`, `ui`, `term`, `fs`, `app`, `build`). Breaking
changes get `!` and a `BREAKING CHANGE:` footer. The body explains *why*.
Add no session links or other tool trailers; a `Co-Authored-By:` footer is
fine.

## Verifying UI changes

Unit tests see `Screen` cells, not the terminal. For anything users see,
also run the editor and look: in a real terminal, or headless in tmux
(`tmux new-session -d -x 80 -y 24 'zig-out/bin/neocaca file'`, then
`tmux send-keys` and `tmux capture-pane -p -e`). Check a narrow size, a
resize, wide and combining characters, and a light and a dark terminal
theme. The `checking-screen-output` skill has the full process.

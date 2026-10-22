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
zig build test -Dtest-filter="regex:"       # only tests whose name matches
zig build fmt                               # format our sources (zig fmt is the style)
zig build fmt-check                         # fail on unformatted sources, as CI does
zig build test -fincremental --watch        # rebuild and rerun the tests on every save (x86_64-linux)
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
- **Formatting:** `zig fmt`, no exceptions. Run `zig build fmt` before every
  commit; it covers `build.zig`, `build.zig.zon`, `src/` and `tests/`, never the
  fetched packages in `zig-pkg/`.
- **Zig 0.17 idioms.** Write current Zig, not what older examples show:
  `std.lang` (not the deprecated `std.builtin`), `std.lang.Optimize` with
  `.debug`/`.safe`/`.fast`/`.small`, and `mode.runtimeSafety()` to ask
  whether checks are on; `builtin.target.os` / `.cpu` / `.abi` (the bare
  `builtin.os` and friends are deprecated); `@backingInt` /
  `@fromBackingInt` for enums; `@splat` for repeated arrays (`**` is gone);
  `@divCeil`; `list.last()` on `ArrayList`; `arena.print(...)` instead of
  `std.fmt.allocPrint`; `std.heap.SafeAllocator` (DebugAllocator is
  deprecated); `std.heap.BufferFirstAllocator` for small stack-first
  scratch; `run.addPassthruArgs()` in `build.zig`; `extern fn` instead of
  `@cImport` (removed). Watch `std.mem.containsAtLeastScalar`, whose
  arguments swapped order without a compile error.
- **`build.zig` contract:** `zig build test` must run every test in the project
  and `-Dtest-filter` narrows it. Keep both working when you add modules;
  a test file not reachable from the test step is a test that never runs.
- **CI** (`.github/workflows/ci.yml`, all with the pinned Zig) runs
  `fmt-check`; the tests in Debug and ReleaseSafe on Ubuntu, macOS (Apple
  Silicon), Alpine (musl, whose binary must be static) and
  `aarch64-linux-musl` under qemu, with ReleaseSafe again at
  `-Dmimalloc-secure=off`; a ReleaseSafe build of every supported target;
  and a benchmark smoke run. Test runs pass `--test-timeout 3m` and test
  jobs stop at 45 minutes. All must pass; run them before pushing
  (`-Dtarget=x86_64-linux-musl` for musl, `-Dtarget=aarch64-linux-musl
  -fqemu` with `qemu-user` for aarch64). The `zig-latest` job tries the
  newest stable Zig without blocking.
- **Platform-gated code** (`switch (builtin.target.os.tag)` and other
  `@import("builtin")` checks) is only analyzed for the target you build. Zig compiles lazily:
  a function nobody calls is never type-checked. Check other targets with
  `zig build -Dtarget=x86_64-macos` / `aarch64-macos` / `x86_64-freebsd`
  / `aarch64-linux`,
  and make sure tests reference the code you changed.

## Before you start

Search the open [issues](https://github.com/poopware-laboratories/neocaca/issues)
first. Someone may already be working on the change, an issue may set out
how it should be done, or a higher-priority item may come first. Comment on
an issue to claim it, and link the issue from your pull request
(`Closes #N`). Read [`TODO.md`](TODO.md), the roadmap: tick items off in the
pull request that finishes them and add what you find missing.

## Clean-room policy

Every line of neocaca is written from first principles. This is a hard
rule, for editor logic as much as for decoders and data structures.

- **Allowed sources:** specifications and standards (Unicode, ECMA-48, xterm
  ctlseqs, the kitty keyboard protocol, POSIX), the Zig standard library and
  its documentation, published *user-facing* documentation of how another
  editor behaves (manuals, key charts, tutorials), and our own experiments
  (running a program and observing its behavior).
- **Forbidden:** reading, copying, porting or translating the source code of
  other editors (Kakoune, Vim, Neovim, Helix, Emacs, …) or of libraries that
  solve the same problem (regex engines, rope or piece-table crates, Unicode
  width tables, terminal toolkits), including "just to see how they did it",
  and pasting code from answers or generated output that reproduces them.
- **Data tables** (character widths, combining ranges) are derived from the
  Unicode standard itself (the Character Database, UAX #11, UAX #29), never
  copied from another project's generated tables.
- **Record the derivation.** A pull request that adds a non-trivial design
  (an algorithm, a key binding scheme, a table) says in its body where the
  design came from: which specification sections, which documented behavior,
  which experiments.
- **When unsure, ask** in the issue before writing the code. Code found to be
  derived from another implementation is removed, not fixed.

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
4. Run the full checks (`zig build fmt-check`, `zig build test` with
   `-Doptimize=debug` and `-Doptimize=safe`) before pushing.

A test that passes the first time proves nothing; adjust it until you have
seen it fail. Pure refactors keep the tests green, adding characterization
tests first for code that had none.

**The 3:1 rule.** Every pull request adds at least **three lines of tests
for each line of production code**. Test lines are those inside `test "…"
{ }` blocks, in `*_test.zig` files and under `tests/`; blank lines and
comments count for neither side. Until a script enforces it in CI,
reviewers count it from the diff.

- Pull requests without production code (docs, CI, build tweaks) pass.
- **Build scripts and benchmarks are not counted** (`build.zig`,
  `src/bench/`), provided `build.zig` keeps every test reachable and
  honors `-Dtest-filter`, and each benchmark fails when a fast path
  disagrees with its reference. Logic they need beyond that lives in
  `src/` and is counted like any other code.
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
- **Make checks free instead of removing them**: shape loops so the
  optimizer proves a bounds check redundant, as the pattern above does.
  `@setRuntimeSafety(false)` needs a ReleaseSafe benchmark gain, a comment
  and `std.debug.assert` of the invariant, and a test at its boundary.
- **Bounds on untrusted sizes** hold on fast paths too: a fast path takes
  the same `max_*` limits as the slow path.
- **Hardened allocator.** mimalloc runs with `-Dmimalloc-secure=on` by
  default. `off` exists to measure the allocator itself; CI also runs the
  tests with it so the wrapper is checked in both settings, but nothing
  ships with it.

## Memory and allocators

Zig makes every allocation explicit; keep it that way.

- **No global allocator.** Every function that allocates takes a
  `std.mem.Allocator` parameter (or is a method on a type that stores one
  from `init`). Only `main.zig` chooses the process allocator, by
  `alloc.process.Gpa(kindFor(builtin.mode))`: `std.heap.SafeAllocator` in Debug
  (leaks, double frees and use after free reported),
  [mimalloc](https://github.com/microsoft/mimalloc) in ReleaseSafe,
  ReleaseFast and ReleaseSmall.
- **mimalloc is the release allocator:** Microsoft's C library (MIT),
  v3.5.3, pinned in `build.zig.zon` and compiled by `build.zig` from its
  single-file `src/static.c` (no CMake). `src/alloc/mimalloc.zig` wraps it
  as a `std.mem.Allocator` and is the only file that calls `mi_*`
  (declared as `extern fn`); its comments say how each call maps, and its
  tests run in every build mode and hardening level. Debug builds and
  tests keep the leak-checking std allocators; never make mimalloc the
  test allocator.
- **Ownership is written down.** A doc comment says who frees what:
  "Caller owns the returned slice", "Borrowed; valid until the next edit".
  Types with resources have `init`/`deinit`; `deinit` frees everything and
  leaves the value undefined (`self.* = undefined`).
- **`defer` and `errdefer` go on the line after the acquisition**, never
  later. Every `try` between an allocation and its hand-off needs an
  `errdefer` that frees it.
- **Arenas for scratch.** When a frame or a command needs temporary
  memory, it comes from an `std.heap.ArenaAllocator` reset after each frame
  or command. Long-lived state (buffers, undo history) never lives in a
  frame arena.
- **Out of memory is an error, not a crash.** Propagate `error.OutOfMemory`;
  never `catch unreachable` or `@panic` on allocation. An edit that fails to
  allocate leaves the buffer exactly as it was.
- **Tests use `std.testing.allocator`**, which fails the test on any leak.
  Code that handles allocation failure is tested with
  `std.testing.checkAllAllocationFailures`.
- **Undefined behavior is a bug even when tests pass.** Run the suite in
  Debug and ReleaseSafe; never ship code that only works in ReleaseFast.

## Architecture in one screen

**Layout: one folder per subsystem, one concern per file.** Each subsystem
is a folder with a namespace file of the same name beside it, as the
standard library does (`src/cli.zig` and `src/cli/`). The namespace file
starts with a `//!` line naming its files, re-exports the public API, and
has a `test { _ = @import(...); }` block referencing every file in the
folder, so `zig build test` reaches them. `src/root.zig` re-exports the
namespaces. Inside a folder, files import siblings directly
(`@import("command.zig")`) and other subsystems through their namespace
file (`@import("../cli.zig")`), never another folder's files. Every row
below exists; keep the table and the diagram in step with the code in the
pull request that changes it.

```
terminal bytes ──► term::Tty ──► app::loop ──► app::Session ──► input::Decoder ──► input::Key
 (raw mode)      (wait, read,     (one thread)   (joins the        (pure; Alt, CSI,     │
                  size, resize)                   outside world)     paste, timeouts)    ▼
                                                      │ fs::file        app::Editor ◄── input::keymap
                                                      │ (load, save on   │  (modes,       (pure state
                                                      ▼  own threads)    │   prompts)      machine)
                                                 :w, :e requests         ▼
                                                                  edit::Document (buffer::Buffer,
                                                                  selections, history) + regex
                                                                         │
terminal ◄── render::diff ◄── render::Screen ◄── app::layout ◄── ui (document, status, prompt) ◄┘
 (escape bytes)   (pure)        (cell grid)         (pure)
```

| Path | Responsibility |
|------|----------------|
| `src/main.zig` | Process setup only: the process allocator, I/O, the arguments, the panic handler that restores the terminal, then `app.run`. No logic worth testing lives here. |
| `src/root.zig` | The `neocaca` module: re-exports every subsystem namespace, so `zig build test` reaches their tests. |
| `src/app/` | `run.zig`: a command line to an exit code (tested in `run_test.zig`); `exit.zig`: the exit codes; `edit.zig`: opens the terminal, runs the loop, restores the terminal however it ends; `loop.zig`: the event loop, generic over the terminal so tests script it; `session.zig`: an `Editor` joined to terminal bytes, files and frames; `saving.zig`: one save on its own thread, which wakes the loop when done; `loading.zig`: one `:e` load on its own thread, the keys typed meanwhile held for the file it reads; `recovery.zig`: the file unsaved changes go to when the terminal hangs up; `editor.zig`: the editing state and key routing; `requesting.zig`: the saves and loads it asks the shell for; `prompting.zig`: what a submitted prompt does; `viewing.zig`: the view keys (`v`, pages); `commands.zig`: `:` command parsing, `:map` included; `layout.zig`: the screen layout. |
| `src/cli/` | `command.zig`: what a command line asks for, and its error messages; `parse.zig`: pure parsing; `usage.zig`: the help text. |
| `src/alloc/` | `mimalloc.zig`: the `std.mem.Allocator` wrapper around mimalloc, the only code that calls `mi_*` (tested in `mimalloc_test.zig`). `process.zig`: which allocator each build mode uses, and `Gpa`, its init, allocator and deinit. |
| `src/simd/` | One kernel per file with its scalar reference and width-generic form: `count.zig`, `find.zig`, `control.zig`, `plain.zig`; `width.zig`: the default vector width; `kernels_test.zig`: every kernel against its reference at every width. |
| `src/bench/` | `zig build bench`: `main.zig` runs each kernel against its scalar reference, `text.zig` makes the input, `measure.zig` times and checks. |
| `src/unicode/` | `utf8.zig`: decoding that never fails; `width.zig`: display width from UAX #11; `chars.zig`: characters with their combining marks; `class.zig`: word and space classes; `display.zig`: how a character is drawn (`^[` for controls). |
| `src/buffer/` | `buffer.zig`: one file's text with its line index (`lines.zig`); `change.zig`: change sets applied in one pass. No I/O, no terminal. |
| `src/regex/` | A linear-time, bounded regex engine: `parse.zig` into `ast.zig`, compiled by `program.zig` (forwards, and reversed for backward search), run by the Pike VM in `vm.zig` within a step budget, skipping to the pattern's first byte; `regex.zig`: the public `Regex`. |
| `src/edit/` | `document.zig`: a buffer with its selections (`selection.zig`) and history (`history.zig`); `motion.zig`, `object.zig`, `selecting.zig`, `search.zig`: selection changes, with `repeat.zig` for counted moves; `verbs.zig`, `insert.zig`: text changes; `registers.zig`. |
| `src/input/` | `decode.zig`: pure decoding of terminal bytes into `Key`s (`key.zig`); `decoder.zig`: keys split across reads, pastes, the Escape timeout; `keymap.zig`: keys to `Action`s (`action.zig`) as a pure state machine; `keyname.zig`: the key notation of `:map`; `mapping.zig`: the user's mappings. |
| `src/render/` | `screen.zig`: the cell grid and display columns; `style.zig`: cell styles and their SGR; `diff.zig`: the escape bytes from one screen to the next. |
| `src/ui/` | Pure drawing into a `Screen`: `document.zig` (gutter and text), `status.zig`, `prompt.zig`, `view.zig` (scrolling with scroll-off), `theme.zig`. |
| `src/term/` | The only code that touches the real terminal: `tty.zig` (raw mode on and off, suspending, size, waits, resizes, hang-ups and finished saves and loads through a self-pipe), `attr.zig` (termios through the kernel's layout on Linux), `raw.zig` (the raw settings), `modes.zig` (alternate screen, bracketed paste). POSIX only. |
| `src/fs/` | `file.zig`: bounded loads, atomic saves that keep permissions and links, and new files that never replace one; `link.zig`: the file a path names once its links are followed. |
| `tests/` | Integration tests, built against the `neocaca` module: `harness.zig` drives a whole session from scripted key bytes; `editing_test.zig` and `display_test.zig` assert on the buffers, files and `Screen`; `random_test.zig` types random keys from fixed seeds, with memory running short at random, and checks the selections, the frames and that everything undoes; `counts_test.zig` types counts before moves on one selection and on thousands, which must answer at once; `terminal_test.zig` runs the editor on a pseudo-terminal end to end; `root.zig` gathers them for the test step. |

## Keybinding model (Kakoune-inspired)

neocaca's modal editing follows the *conceptual* model popularised by
Kakoune, designed and implemented independently (see "Clean-room policy"):

- **Selection first, verb second.** In normal mode keys first select text
  (an *object*), then a verb acts on the selections: `wd` selects a word,
  then deletes it. What a verb will touch is always visible before it runs.
- **There is always a selection.** Every cursor is a selection of at least
  one character (anchor and cursor, inclusive). Moves replace the
  selections; the same move with Shift extends them.
- **Multiple selections are first-class.** Every move, object and verb
  applies to every selection at once. Selections are split by a pattern
  (`S`), filtered (`Alt-k`, `Alt-K`), narrowed to a regex match (`s`),
  duplicated (`C`), rotated (`(` `)`) and reduced (`,` `;`).
- **Modes:** normal (select and act), insert (type at every cursor), prompt
  (`:` commands, `/` search, `s` select, `|` filters later). `Esc` always
  returns to normal mode.
- **Pure keymap.** `src/input/keymap.zig` maps events to commands as a pure
  state machine (pending prefixes, counts, registers); `src/edit/` applies
  commands to buffers and selections. Neither touches the terminal.

`docs/keys.md` is the reference for every binding; change it together with
the keymap and its tests.

## Rules of thumb

- **Keep files small and single-purpose.** Prefer a new file over growing
  one past roughly 400 lines, and a new folder (with its namespace file)
  over a file holding two subsystems. Each file starts with a `//!` doc
  comment saying what it is for. The limit holds for test files too:
  tests that outgrow their file move to a sibling `name_test.zig`, and a
  test file that outgrows itself splits by topic (as the count tests of
  `selecting_test.zig` went to `selecting_count_test.zig`), each
  referenced from the namespace file so `zig build test` reaches it.
- **Functional core, imperative shell.** Encoding, decoding, layout, editing
  and diffing are pure functions over plain data (`input.decode.parse(bytes,
  final)`, `app.layout.draw(editor, screen)`, `render.diff(old, new,
  writer)`). Only `term/`, `fs/`, `main.zig` and the shell files of `app/`
  (`edit.zig`, `session.zig`, `saving.zig`, `loading.zig`, `recovery.zig`)
  do I/O; the rest of `app/` is pure. If a test needs a real terminal, the
  logic is in the wrong place.
- **Never block the event loop.** Reading the terminal, saving files and
  running external tools must not freeze typing. Long work goes off the
  loop and reports back as an event.
- **The terminal is always restored.** Raw mode, the alternate screen,
  bracketed paste and every mode added later (mouse, the kitty keyboard
  protocol) are undone on normal exit, on error returns, on suspend and on
  panic (the panic handler restores first).
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
- **Widths are hard.** Cursor movement and rendering work in characters
  (a code point with the combining marks after it, `unicode/chars.zig`)
  and display columns, never bytes. Full grapheme clusters (UAX #29) are
  on the roadmap. Wide characters, combining marks, tabs and emoji each
  need tests.
- **Overflow is checked, not wrapped.** Use plain `+`, `-`, `*` so
  ReleaseSafe catches a mistake, and saturating `+|` where a bound is
  meant. A wrapping operator (`+%`) is allowed only where wrapping cannot
  happen or is the point, with a comment stating why (see
  `simd/count.zig`).
- **No new dependencies; write our own.** Use the Zig standard library only.
  Implement features in-house from their specifications (clean room: never
  read or copy another implementation's source), so we keep control over
  speed, limits and security. The one exception is mimalloc (see "Memory
  and allocators"); bumping it is a `build(deps)` pull request with
  benchmark numbers. Any other package, Tree-sitter for highlighting
  included (see `TODO.md`), needs an issue where the maintainers agree
  first.
- **Standards compliance.** Emit escape sequences as their specifications
  define them (ECMA-48, xterm ctlseqs, kitty keyboard protocol), probe for
  optional features instead of assuming them, and fall back cleanly on
  terminals that do not answer.
- **Errors are values.** Use specific error sets for library code, handle
  every error explicitly, and never discard one with `catch {}` without a
  comment saying why that is safe.
- **Docs follow the code, in the same commit.** Every Markdown file
  describes the code as it is: a change that makes a sentence wrong fixes
  it, new behavior is documented and removed behavior deleted, without
  being asked. A pull request that leaves a doc stale is not finished.
- **Config compatibility.** User-facing configuration keys and keybindings,
  once released, keep working under their old names.
- Match surrounding style: comment density, naming (`camelCase` functions,
  `TitleCase` types, `snake_case` variables and fields), and `pub` only on
  what other modules use.

## Branches, pull requests and commits

`main` takes no direct pushes or force-pushes. Every change, however small,
goes through a branch and a pull request.

1. **Branch from an up-to-date `main`**, named `type/short-topic` after
   the Conventional Commits type (`fix/undo-merge`).
2. **Commit in small steps**; the red and green steps may be separate
   commits. Pick up `main` by rebasing (`git pull --rebase origin main`,
   then `git push --force-with-lease`), and force-push only your own branch.
3. **Open a pull request** with one concern, filling in
   `.github/pull_request_template.md`. Its **title is a Conventional
   Commit** and becomes the squashed commit on `main`; the body explains
   *why*, links the issue, and carries the evidence (benchmarks, screen
   captures).
4. **Merge by squashing** once every check passes and the maintainer says
   to, so `main` stays linear.

**Work in pieces.** Usage limits cut long sessions short, so open work
moves in pieces of about 20 to 40 minutes. `TODO.md` lists them, grouped
under the pull request they stack into.

- **One piece, then stop.** Take the first unticked piece and say what it
  will change. Do it, push it, wait for CI, then report to the maintainer:
  what changed, whether CI is green, and what the next piece is. Never
  roll on into the next piece unasked.
- **Every piece leaves the pull request mergeable**: green, with its docs
  and `TODO.md` current and nothing half-built, so stopping is always
  safe.
- **The maintainer chooses.** *Merge* squashes it, and the next piece
  starts a new pull request. *Continue* stacks the next piece of the same
  pull request onto it, and its title and body grow to cover it. Only
  pieces under the same heading stack; say so when the next one belongs
  in a new pull request.
- **Push after every green step.** After a session ends early, finish the
  open piece on the pushed branch before anything else. A piece that
  outgrows its size stops at a green point and is reported; the rest
  becomes a new piece in `TODO.md`.

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
also run the editor and look, in a terminal or headless in tmux, at a
narrow size, after a resize, with wide and combining characters, in a
light and a dark theme. The `checking-screen-output` skill has the steps.

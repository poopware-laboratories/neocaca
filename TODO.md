# TODO

The neocaca roadmap. Tick an item in the pull request that finishes it, and
add items when you find gaps. Phases run roughly in order; within a phase,
items are independent. Every item follows `AGENTS.md`: tests first, 3:1,
clean room.

Open work is cut into **pieces**: **S** is about 20 minutes, **M** about
40. Each one leaves the pull request green and mergeable. Under each
**PR:** heading, the pieces stack into one pull request; see "Work in
pieces" in `AGENTS.md`. Take the first unticked piece. Cut a phase into
pieces when you reach it.

## Phase 0: foundations

- [x] Build, test, fmt and bench steps
- [x] CI on Ubuntu (glibc) and Alpine (musl, static), release artifacts
      for every target, and an early-warning job on the newest stable Zig
- [x] CI tests passing on macOS (Apple Silicon), each test with a
      3-minute timeout so one that hangs is named
- [x] CI tests for aarch64 under qemu on Linux, to catch aarch64-only
      bugs without waiting for a macOS runner
- [x] mimalloc as the release allocator, SafeAllocator in Debug
- [x] SIMD kernels (count, find, control bytes, printable-ASCII runs) with scalar references
- [x] Command line parsing, help and version
- [x] Folder-per-subsystem layout
- [x] Clean-room policy, Kakoune-inspired keybinding model documented
- **PR: split the files past about 400 lines, by topic**
  - [ ] S: `edit/selecting.zig`
  - [ ] S: `edit/verbs_test.zig` and `edit/selecting_test.zig`
  - [ ] S: `input/keymap_test.zig`, `regex/regex_test.zig` and
        `tests/editing_test.zig`
- **PR: a hang outside any test fails in minutes**
  - [ ] S: give each test step its own `timeout-minutes`. The macOS Debug
        job once hung for 20 minutes without `--test-timeout` firing, so
        the hang was outside any test body: compiling, the build runner,
        or a test binary's start or exit.

## Phase 1: a usable modal editor

- [x] `unicode/`: UTF-8 decoding that never fails on invalid bytes, display
      width (wide, zero width, combining), character boundaries
- [x] `buffer/`: text storage with a line index; byte offset ⇄ line/column
- [x] `regex/`: a linear-time, bounded regex engine (Pike VM) for search,
      select and split; each command bounded in steps (`max_steps`), and
      the search skipped ahead to the pattern's first byte (SIMD)
- [x] `edit/`: selections (anchor + cursor, multiple, a main one), change
      sets mapped through edits, undo and redo history
- [x] `edit/`: motions (characters, words, WORDs, lines, find character,
      matching bracket, buffer start/end) and text objects
- [x] `input/`: decode terminal bytes into keys (legacy, CSI, SS3, Alt as
      ESC prefix, bracketed paste)
- [x] **Kakoune-style modal keybind system** (`input/keymap.zig`):
  - [x] normal mode: selection first, then verb (`d c y p P R r ~ > <`)
  - [x] Shift extends; counts; registers (`"x`)
  - [x] multiple selections: `C`, `Alt-C`, `s`, `S`, `Alt-s`, `Alt-k`,
        `Alt-K`, `,`, `Alt-,`, `(`, `)`, `Alt-(`, `Alt-)`, `;`, `Alt-;`, `Alt-x`
  - [x] object selection: `Alt-i` / `Alt-a` with `w W ( [ { < " ' ` p`
  - [x] goto prefix (`g`)
  - [x] view prefix (`v`: center, top, bottom, scroll without moving)
  - [x] `vh` / `vl`: scroll the view by columns
  - [x] insert mode at every cursor (`i a I A o O`), auto-indent
  - [x] search `/ ? n N Alt-n *`
  - [x] prompt commands `:w :q :q! :wq :x :e :e! :<line>`
  - [x] user-configurable key mappings (`:map`, `:unmap`) with stable names
- [x] `render/`: a cell grid and a minimal diff into escape bytes; control
      bytes and invalid UTF-8 shown visibly
- [x] `ui/`: gutter, status line, prompt, scrolling with scroll-off
- [x] `term/`: raw mode, alternate screen, size, restore on exit and panic
- [x] `fs/`: bounded load, atomic save that keeps permissions
- [x] `app/`: the event loop wired into `main`
- [x] `tests/`: whole sessions from scripted key bytes, and the editor
      end to end on a pseudo-terminal
- [x] Saves off the event loop: `:w` writes a copy of the text on its own
      thread and wakes the loop when done
- [x] Loads off the event loop: `:e` reads on its own thread, and the keys
      typed meanwhile edit the file once it is in
- [x] Ctrl-Z suspends and resumes (raw mode turns off ISIG, so the editor
      stops itself and restores the terminal first)
- [x] A hang-up (closed terminal window) writes the unsaved buffer to a
      recovery file instead of dropping it
- [x] `Alt-(` `Alt-)` rotate contents, `Alt-x` trim to lines, `Alt-j` join
      (`J` extends down; see `docs/keys.md`)

## Phase 2: everyday comfort

Safety first, then the biggest daily gains.

- **PR: cap the number of selections**
  - [ ] S: `max_selections`, tested at the limit and one past it. Today
        `S` or `s` on a huge file can make millions of selections (32
        bytes each), bounded only by memory.
- **PR: respect line endings, the BOM and a missing final newline.**
  The bytes of a file are kept as loaded, but:
  - [ ] M: CRLF files show no `^M` at each line end, and the lines added
        to them (Enter, `o`, `O`, paste) end in CRLF, not a bare `\n`
  - [ ] S: a BOM is hidden and cannot be deleted by accident; today it
        shows as a replacement glyph at the start of the file
  - [ ] S: a file without a final newline is saved without one; today the
        buffer adds one on load and `:w` writes it
- **PR: never overwrite a change made on disk**
  - [ ] S: notice when the file changed on disk (size and modification
        time), checked on focus and before `:w`
  - [ ] S: `:w` refuses to overwrite it and says so; `:w!` forces
- **PR: soft wrap of long lines**
  - [ ] M: wrapped line layout, pure and tested
  - [ ] M: draw it, with the cursor and scrolling over wrapped lines
- **PR: multiple buffers.** `app::Editor` holds one `Document` today;
  splits build on this.
  - [ ] M: a list of documents with a current index, each keeping its
        own path, selections, history and save state (no new keys yet)
  - [ ] S: `:e` opens a second buffer; `:bn` and `:bp` switch
  - [ ] S: `:b <name>` and `:bd`, and the buffer in the status line
- **PR: system clipboard through OSC 52 (write only)**
  - [ ] S: yank also copies to the system clipboard
- **PR: mouse**
  - [ ] M: click to place a selection, drag to extend
  - [ ] S: wheel to scroll
- **PR: shell filters, off the event loop**
  - [ ] M: run a command on its own thread, bounded output, cancelled by
        `Esc`
  - [ ] S: `|` replaces each selection with its output
  - [ ] S: `!` inserts the output and `Alt-|` only runs the command
- **PR: kitty keyboard protocol, with legacy fallback.** The legacy
  encoding cannot tell Esc from the start of an Alt key without the
  25 ms timeout, nor Ctrl-i from Tab or Ctrl-m from Enter.
  - [ ] S: probe for it and fall back cleanly
  - [ ] M: decode its key events
- **PR: searches off the event loop.** Today they run on the loop within
  `max_steps`, which caps how much of a large file one search can cover.
  - [ ] M: `/`, `?`, `s`, `S` and `Alt-k` run on their own thread
  - [ ] S: `Esc` cancels them; raise the step bound
- **PR: large files.** Today the text is one contiguous array, and every
  edit rebuilds it and its line index, so an edit costs the size of the
  file.
  - [ ] S: a benchmark of typing into a 100 MB file
  - [ ] M: a piece table behind the `buffer::Buffer` interface
  - [ ] M: its line index; `Buffer`'s API is unchanged, so `edit/` does
        not change
  - [ ] S: the benchmark again, with the numbers in the PR
- **PR: grapheme clusters per UAX #29** (emoji ZWJ sequences, regional
  indicators) instead of code point and combining marks
  - [ ] M: the break property table, derived from the Unicode data
  - [ ] M: cursor movement and drawing by cluster
- **PR: configuration file**
  - [ ] M: load and validate it (tab width, scroll-off, colors), bounded
  - [ ] S: key mappings from it
- **PR: key hints**
  - [ ] S: after a prefix (`g`, `v`, `"`, `Alt-i`), show the keys that
        can follow and what they do, from the keymap itself
- **PR: undo tree and selection history**
  - [ ] M: browse the undo tree
  - [ ] S: selection history (`Alt-u`, `Alt-U`)
- **PR: latency in CI**
  - [ ] S: a benchmark of keypress-to-frame time and startup on a large
        file, in ReleaseSafe, reported on every run

## Phase 3: code awareness

- [ ] **Syntax highlighting through Tree-sitter** via C interop in Zig
      (`extern fn` declarations, the runtime compiled by `build.zig` from
      source like mimalloc). Needs maintainer agreement first: it would be
      the second dependency exception (see `AGENTS.md`). Plan:
  - [ ] issue agreeing on the dependency, its pinning and its limits
  - [ ] `src/syntax/`: the only code calling `ts_*`, with an allocator
        bridge (`ts_set_allocator`) so it uses our allocators
  - [ ] incremental reparse from our change sets (`ts_tree_edit`)
  - [ ] highlight queries mapped to theme faces, off the event loop for
        large files, bounded parse time
  - [ ] grammars compiled in per language, tests on malformed input
- [ ] Indentation per language
- [ ] Language server client (diagnostics, go to definition), off the loop
- [ ] Auto-pairing of brackets and quotes

## Phase 4: polish

- [ ] Splits and windows
- [ ] Themes (light and dark), true color with 256-color fallback
- [ ] Accessibility (see `ACCESSIBILITY.md`): honor `NO_COLOR`, show
      which text is selected without relying on color, and a screen
      reader mode that announces changes instead of redrawing the grid
- [ ] Session restore
- [ ] Persistent undo: history saved beside the file (bounded, checked
      against the file's contents before use, never trusted blindly)
- [ ] Command palette: every `:` command and key action, searchable by
      name, showing its binding
- [ ] Packaging and releases

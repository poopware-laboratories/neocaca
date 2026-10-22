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

## The yardstick: a step up from flow

[flow](https://flow-control.dev) (Flow Control) is the Zig terminal editor
neocaca is measured against. A step up means two things: whatever a flow
user relies on works in neocaca too, and wherever both do something,
neocaca does it measurably better (faster, safer, or on more terminals).
What flow does comes from its README, its manual
(<https://flow-control.dev/docs/help/>) and its devlog, as of release
0.7.2 and the October 2026 devlog, and from running it. As everywhere,
the clean-room policy holds: its user-facing documentation and its
behavior, never its source.

**Already ahead.**

- **Ships with safety checks on.** flow's README builds it with
  `-Doptimize=fast`; neocaca ships ReleaseSafe, with bounds and overflow
  checks in the build users run.
- **Runs on any terminal as it is.** flow asks for 24-bit color and a Nerd
  Font; neocaca's default theme uses the sixteen basic colors and draws no
  icon glyphs.
- **Selections are the editing model.** flow's manual says its Helix mode
  lacks selection operations, registers and macros, and its Vim mode lacks
  macros and registers. neocaca splits, filters, rotates and narrows
  selections, with registers.

**Still behind.** Each gap is a roadmap item below:

| flow has | neocaca's item |
|----------|----------------|
| Tree-sitter highlighting for more than 95 languages, a forced language | Phase 3: syntax highlighting |
| LSP: completion, hover, definitions, references, symbols, diagnostics, formatting | Phase 3: language server client |
| Tabs, vertical splits, a centered view | Phase 2: multiple buffers; Phase 4: splits |
| Mouse on every element, scrollbars, animated scrolling | Phase 2: mouse; Phase 4: scrollbars |
| Command palette and key hints | Phase 2: key hints; Phase 4: command palette |
| Clipboard history | Phase 2: system clipboard |
| Very large files, thousands of cursors | Phase 2: large files, selection cap |
| Smart-case search | Phase 2: smart-case search |
| Paragraph reflow | Phase 2: reflow |
| `file:line` and `+line` on the command line | Phase 2: command line |
| Git change markers and blame | Phase 3: git |
| Session save every two minutes, restore after a crash | Phase 4: session restore |
| Restart under sudo to save root-owned files | Phase 4: saving files you cannot write |
| Many themes, VS Code themes imported | Phase 4: themes |
| The kitty text sizing protocol | Phase 4: kitty text sizing |
| Android (termux) | Phase 4: termux |
| Windows | Not planned: neocaca is POSIX only |
| Vim, Helix, Emacs and VS Code key modes | Not planned: one modal model done well, with `:map` |
| An integrated terminal, remote control over a socket | Phase 4: decide whether neocaca wants them |

**Ahead on paper only, until it ships.** Persistent undo is still in
development in flow (its README roadmap); neocaca's undo tree and
persistent undo would beat it once they land (Phase 2 and Phase 4).

- **PR: measured against flow.** flow claims frame times of 6 ms or
  less. Running flow's release binary in a session needs the
  maintainer's permission.
  - [ ] M: `zig build compare -Dflow=<path>` runs both editors on a
        pseudo-terminal with the same files and reports, for each: startup
        to the first frame, keypress to frame, open time and peak memory on
        1 MB, 100 MB and 1 GB files, a 10 MB single line, and 10,000
        selections. The numbers go in the PR and in this section.

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
  - [x] S: `edit/selecting.zig` (its moves went to `edit/moving.zig`)
  - [x] S: `edit/verbs_test.zig` (paste went to `paste_test.zig`) and
        `edit/selecting_test.zig` (moves went to `moving_test.zig`)
  - [x] S: `input/keymap_test.zig` (verbs went to `keymap_verb_test.zig`),
        `regex/regex_test.zig` (`escape` to `escape_test.zig`) and
        `tests/editing_test.zig` (the `:` commands to `commands_test.zig`)
- **PR: a hang outside any test fails in minutes**
  - [x] S: each test step stops at 15 minutes (`timeout-minutes`). The
        macOS Debug job once hung for 20 minutes without `--test-timeout`
        firing, so the hang was outside any test body: compiling, the
        build runner, or a test binary's start or exit.

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
- [x] A dogfood pass: real files edited in a ReleaseSafe build under
      tmux (a Zig source file, the README, CRLF, BOM, control bytes, wide
      and combining characters, a 50 MB file, a 48 MB single line, a
      directory, a missing directory), resizes down to one cell, Ctrl-Z
      and `fg`. What it found is below or already in Phase 2; how a pass
      is run from now on is in `docs/dogfooding.md`.
- **PR: fixes from the dogfood pass**
  - [x] S: the view keeps its old scroll when the window grows, hiding
        lines above while the rows below stay empty (a 4-line file,
        resized to 5 rows and back to 8, showed lines 2 to 4). A taller
        window now scrolls back to fill its rows.
  - [ ] S: messages name Zig errors (`cannot open ".": IsDir`, `cannot
        write "…": FileNotFound`); say it in words ("is a directory",
        "no such directory").
  - [ ] S: `neocaca <directory>` opens an empty buffer named after the
        directory; refuse it at startup with an exit code instead. A file
        in a directory that does not exist says "new file" and fails only
        at `:w`; say so when it opens.
  - [ ] S: a message wider than the window is cut mid-word with no mark
        (`unsaved changes; :q! dis` at 24 columns); end it with `…`.
  - [ ] S: `Alt-i` or `Alt-a` with no such object around the cursor
        (`Alt-i"` outside quotes) changes nothing and says nothing, so the
        next verb acts on the old selection; say "no object here".
- **PR: the dogfood pass that closes Phase 1**
  - [ ] M: every scenario of `docs/dogfooding.md` on its corpus, once the
        fixes above are in; its findings become pieces, and Phase 1 is done
        when none of them is a crash, lost data or raw terminal bytes.

## Phase 2: everyday comfort

Safety first, then the biggest daily gains.

- **PR: cap the number of selections**
  - [ ] S: `max_selections`, tested at the limit and one past it. Today
        `S` or `s` on a huge file can make millions of selections (32
        bytes each), bounded only by memory: `%` then `s` `a` on a 50 MB
        file made 9.6 million, froze the editor for 5 seconds and used
        830 MB.
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
  - [ ] S: a history of the last yanks, to paste an older one
- **PR: command line**
  - [ ] S: `neocaca file:12` and `neocaca +12 file` open at line 12
- **PR: smart-case search**
  - [ ] S: a pattern without capitals matches either case, one with
        capitals matches exactly
- **PR: reflow**
  - [ ] S: rewrap the selected paragraphs to a width, keeping their line
        prefix (indentation, `//`, `#`, `>`)
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
  - [ ] S: a benchmark of typing into a 100 MB file (by hand, a 50 MB
        file takes about 50 ms a key in ReleaseSafe)
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
- **PR: the dogfood pass that closes Phase 2**
  - [ ] M: every scenario of `docs/dogfooding.md`, with those Phase 2 added

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
  - [ ] the language picked from the file name, or forced by `--language`
- [ ] Indentation per language
- [ ] Language server client, off the loop: diagnostics, go to definition
      and references, hover, completion, document symbols, formatting
- [ ] Git: change markers in the gutter against `HEAD`, and blame for the
      current line, off the loop
- [ ] Auto-pairing of brackets and quotes
- [ ] The dogfood pass that closes Phase 3 (`docs/dogfooding.md`)

## Phase 4: polish

- [ ] Splits and windows, and a centered view on wide screens
- [ ] Scrollbars and smooth scrolling
- [ ] Themes (light and dark), true color with 256-color fallback, and
      VS Code themes imported
- [ ] The kitty text sizing protocol
- [ ] Accessibility (see `ACCESSIBILITY.md`): honor `NO_COLOR`, show
      which text is selected without relying on color, and a screen
      reader mode that announces changes instead of redrawing the grid
- [ ] Session restore, with the unsaved buffers backed up every few
      minutes so a crash, not only a hang-up, loses nothing
- [ ] Saving a file you cannot write (owned by root) without restarting
      the editor
- [ ] Android under termux, checked in CI or by hand
- [ ] An integrated terminal and remote control over a socket (flow has
      both): decide whether neocaca wants them
- [ ] Plugins: programs the editor starts, over a bounded, versioned
      message protocol shared with shell filters, the language server
      client and remote control. Plugin edits are change sets against a
      buffer version, always undoable. Custom motions and text objects
      come from the configuration file, not from plugins.
- [ ] Persistent undo: history saved beside the file (bounded, checked
      against the file's contents before use, never trusted blindly)
- [ ] Command palette: every `:` command and key action, searchable by
      name, showing its binding
- [ ] Packaging and releases, each release after a dogfood pass with the
      1 GB log (`BIG=1`)
- [ ] The dogfood pass that closes Phase 4 (`docs/dogfooding.md`)

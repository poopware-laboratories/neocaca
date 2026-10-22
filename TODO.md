# TODO

The neocaca roadmap. Tick an item in the pull request that finishes it, and
add items when you find gaps. Phases run roughly in order; within a phase,
items are independent. Every item follows `AGENTS.md`: tests first, 3:1,
clean room.

## Phase 0: foundations

- [x] Build, test, fmt and bench steps; CI on Linux and macOS
- [x] CI on Ubuntu (glibc), Alpine (musl, static) and macOS (Apple Silicon),
      release artifacts for every target, and an early-warning job on the
      newest stable Zig
- [x] mimalloc as the release allocator, SafeAllocator in Debug
- [x] SIMD kernels (count, find, control bytes, printable-ASCII runs) with scalar references
- [x] Command line parsing, help and version
- [x] Folder-per-subsystem layout
- [x] Clean-room policy, Kakoune-inspired keybinding model documented

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
- [x] `xd` on the last line leaves an empty line, because the final
      newline is never deleted; delete the newline before it instead
- [x] `Alt-(` `Alt-)` rotate contents, `Alt-x` trim to lines, `Alt-j` join
      (`J` extends down; see `docs/keys.md`)

## Phase 2: everyday comfort

- [ ] Soft wrap of long lines
- [ ] Multiple buffers (`:b`, `:bn`, `:bp`, `:bd`) and a buffer list
- [ ] Shell filters (`|`, `!`, `Alt-|`) run off the event loop
- [ ] System clipboard through OSC 52 (write only)
- [ ] Mouse: click to place a selection, drag to extend, wheel to scroll
- [ ] Kitty keyboard protocol, probed, with legacy fallback
- [ ] Grapheme clusters per UAX #29 (emoji ZWJ sequences, regional
      indicators) instead of codepoint + combining marks
- [ ] Line endings (CRLF kept on save) and a BOM kept on save
- [ ] Large files: a piece table or rope once the contiguous buffer is
      measured to be the bottleneck
- [ ] Configuration file (keys, tab width, scroll-off, colors)
- [ ] Searches and `s`/`S`/`Alt-k` off the event loop, cancelled by
      `Esc`, so the step bound can grow past what one key may freeze
- [ ] Undo tree browsing and selection history (`Alt-u`, `Alt-U`)

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
- [ ] Packaging and releases

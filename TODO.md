# TODO

The neocaca roadmap. Tick an item in the pull request that finishes it, and
add items when you find gaps. Phases run roughly in order; within a phase,
items are independent. Every item follows `AGENTS.md`: tests first, 3:1,
clean room.

## Phase 0: foundations

- [x] Build, test, fmt and bench steps; CI on Linux and macOS
- [x] mimalloc as the release allocator, SafeAllocator in Debug
- [x] SIMD kernels (count, find, control bytes) with scalar references
- [x] Command line parsing, help and version
- [x] Folder-per-subsystem layout
- [x] Clean-room policy, Kakoune-inspired keybinding model documented

## Phase 1: a usable modal editor

- [ ] `unicode/`: UTF-8 decoding that never fails on invalid bytes, display
      width (wide, zero width, combining), character boundaries
- [ ] `buffer/`: text storage with a line index; byte offset ⇄ line/column
- [ ] `regex/`: a linear-time, bounded regex engine (Pike VM) for search,
      select and split
- [ ] `edit/`: selections (anchor + cursor, multiple, a main one), change
      sets mapped through edits, undo and redo history
- [ ] `edit/`: motions (characters, words, WORDs, lines, find character,
      matching bracket, buffer start/end) and text objects
- [ ] `input/`: decode terminal bytes into keys (legacy, CSI, SS3, Alt as
      ESC prefix, bracketed paste)
- [ ] **Kakoune-style modal keybind system** (`input/keymap.zig`):
  - [ ] normal mode: selection first, then verb (`d c y p P R r ~ > <`)
  - [ ] Shift extends; counts; registers (`"x`)
  - [ ] multiple selections: `C`, `Alt-C`, `s`, `S`, `Alt-s`, `Alt-k`,
        `Alt-K`, `,`, `Alt-,`, `(`, `)`, `;`, `Alt-;`
  - [ ] object selection: `Alt-i` / `Alt-a` with `w W ( [ { < " ' ` p`
  - [ ] goto (`g`) and view prefixes
  - [ ] insert mode at every cursor (`i a I A o O`), auto-indent
  - [ ] search `/ ? n N Alt-n *`
  - [ ] prompt commands `:w :q :q! :wq :x :e :e! :<line>`
  - [ ] user-configurable key mappings (`:map`) with stable names
- [ ] `render/`: a cell grid and a minimal diff into escape bytes; control
      bytes and invalid UTF-8 shown visibly
- [ ] `ui/`: gutter, status line, prompt, scrolling with scroll-off
- [ ] `term/`: raw mode, alternate screen, size, restore on exit and panic
- [ ] `fs/`: bounded load, atomic save that keeps permissions
- [ ] `app/`: the event loop wired into `main`
- [ ] `tests/`: whole sessions from scripted key bytes

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
- [ ] Session restore
- [ ] Packaging and releases

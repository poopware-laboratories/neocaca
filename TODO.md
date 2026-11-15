# TODO

The caca roadmap. Tick an item in the pull request that finishes it, and
add items when you find gaps. Phases run roughly in order; within a phase,
items are independent. Every item follows `AGENTS.md`: tests first, 3:1,
clean room.

Open work is cut into **pieces**: **S** is about 20 minutes, **M** about
40. Each one leaves the pull request green and mergeable. Under each
**PR:** heading, the pieces stack into one pull request; see "Work in
pieces" in `AGENTS.md`. Take the first unticked piece. Cut a phase into
pieces when you reach it.

## The yardstick: a step up from every editor compared

caca is compared with five terminal editors: Kakoune and Helix, which
share its selection-first model; Neovim and Vim, the most widely used
modal editors; and [flow](https://flow-control.dev), another editor
written in Zig. A step up means two things: whatever a user of any of
them relies on works in caca too, and wherever caca and another
editor both do something, caca does it measurably better (faster, in
less memory, safer, or on more terminals). What each editor does comes
from its user-facing documentation (manuals, key references, release
notes) and from running it, as of Kakoune 2026.05.21, Helix 25.07.1,
Neovim 0.12.6, Vim 9.2 and flow 0.7.2 with its development build of
2026-11-13. As everywhere, the clean-room policy holds: their
documentation and their behavior, never their source.

**Features.** "Plugin" means through a plugin or an outside program, not
built in.

| | caca | Kakoune | Helix | Neovim | Vim | flow |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| Selections as the editing model (split, filter, rotate) | yes | yes | yes | no | no | no (its manual: multiple cursors, without selection operations) |
| Registers | yes | yes | yes | yes | yes | no (its manual) |
| Macros | no | yes | yes | yes | yes | no (its manual) |
| Syntax highlighting | no | yes | yes | yes | yes | yes |
| Language servers | no | plugin | yes | yes | plugin | yes |
| Several buffers | no | yes | yes | yes | yes | yes |
| Splits | no | through its clients | yes | yes | yes | vertical |
| Mouse | no | yes | yes | yes | yes | yes |
| System clipboard | no | plugin | yes | yes | yes | yes |
| Persistent undo | no | no | no | yes | yes | in development |
| Scripting or plugins | no | yes | no | yes | yes | no |
| Integrated terminal | no | no | no | yes | yes | yes |
| Files past 256 MiB | no | yes | yes | yes | yes | yes |
| Shipped with bounds checks | yes (ReleaseSafe) | no (C++) | yes (Rust) | no (C) | no (C) | no (its README builds `-Doptimize=fast`) |
| Any terminal as it is (16 colors, no icon font) | yes | yes | yes | yes | yes | no (asks for 24-bit color and a Nerd Font) |
| Windows | no | no | yes | yes | yes | yes |

**Already ahead.**

- **Selections are the editing model, and the fastest.** Of the editors
  that have them, caca makes 10,000 selections and types at them
  fastest ("Measured"); Vim and Neovim have none, and flow's manual says
  its Helix mode lacks selection operations, registers and macros.
- **Ships with safety checks on.** Only Helix is also built with bounds
  checks; Kakoune, Neovim and Vim are C and C++, and flow ships
  ReleaseFast.
- **Starts and opens small files fastest:** a first frame in under 1 ms,
  a 1 MiB file in 2.2 ms, a 10 MiB line in 10 ms ("Measured").
- **Runs on any terminal as it is,** as Kakoune, Helix, Neovim and Vim do;
  flow asks for 24-bit color and a Nerd Font.

**Still behind.** Each gap is a roadmap item below:

| Gap | Who has it | caca's item |
|-----|------------|----------------|
| Syntax highlighting (Tree-sitter in Helix, Neovim and flow) | all five | Phase 3: syntax highlighting |
| Language servers: completion, hover, definitions, references, diagnostics, formatting | Helix, Neovim, flow; Kakoune and Vim by plugin | Phase 3: language server client |
| Several buffers | all five | Phase 2: multiple buffers |
| Splits and windows, a centered view | Helix, Neovim, Vim, flow; Kakoune through its clients | Phase 4: splits |
| Mouse, scrollbars | all five; scrollbars in flow | Phase 2: mouse; Phase 4: scrollbars |
| Macros | Kakoune, Helix, Neovim, Vim | Phase 2: macros |
| Key hints and a command palette | Kakoune and Helix (hints), flow (both) | Phase 2: key hints; Phase 4: command palette |
| System clipboard, clipboard history | Helix, Neovim, Vim, flow (history) | Phase 2: system clipboard |
| Files past 256 MiB | all five ("Measured") | Phase 2: large files |
| Less memory (startup, files, selections) | Kakoune at startup, on 1 MiB, a 10 MiB line and 10,000 selections; Helix and Vim on 100 MiB ("Measured") | Phase 2: memory |
| A key answered faster, 100 MiB opened faster | Vim (keys), Helix (100 MiB) ("Measured") | Phase 2: speed |
| Smart-case search | Helix, Neovim, Vim, flow | Phase 2: smart-case search |
| Paragraph reflow | Helix, Neovim, Vim, flow | Phase 2: reflow |
| `file:line` and `+line` on the command line | all five | Phase 2: command line |
| Git change markers and blame | Helix, flow; the others by plugin | Phase 3: git |
| Persistent undo, session restore | Neovim and Vim (undo files, sessions), flow (sessions) | Phase 4: persistent undo; session restore |
| Restart under sudo to save root-owned files | flow | Phase 4: saving files you cannot write |
| Scripting and plugins | Kakoune, Neovim, Vim | Phase 4: plugins |
| Many themes | all five; VS Code themes imported in flow | Phase 4: themes |
| The kitty text sizing protocol | flow | Phase 4: kitty text sizing |
| Android (termux) | all five | Phase 4: termux |
| An integrated terminal, remote control | Neovim, Vim, flow; Kakoune's clients | Phase 4: decide whether caca wants them |
| Windows | Helix, Neovim, Vim, flow | Not planned: caca is POSIX only |
| Several key modes (Vim, Helix, Emacs) | flow | Not planned: one modal model done well, with `:map` |

**Measured.** `zig build compare -Deditors=kak,hx,nvim,vim,flow` runs
caca and the editors listed on a 120x40 pseudo-terminal with the same
files and answers the queries a terminal would (x86_64 Linux, 2026-11-15:
caca's ReleaseSafe build, the others as Arch Linux packages them,
flow from its development build, each without user configuration;
medians, with p90 and max). A frame is timed to its last byte, once the
screen has been quiet for 60 ms:

| | caca | kakoune | helix | neovim | vim | flow |
|---|---:|---:|---:|---:|---:|---:|
| startup to first frame (10 runs) | 0.99 ms (p90 1.18 ms, max 1.23 ms) | 1.78 ms (p90 1.92 ms, max 2.11 ms) | 16.4 ms (p90 20.5 ms, max 21.1 ms) | 13.4 ms (p90 14.2 ms, max 21.2 ms) | 10.7 ms (p90 11.2 ms, max 12.6 ms) | 31.7 ms (p90 31.8 ms, max 49.7 ms) |
| memory at startup | 11.2 MiB | 6.7 MiB | 20.7 MiB | 9.7 MiB* | 19.2 MiB | 22.6 MiB |
| keypress to frame (200 Down, 1 MiB file) | 0.62 ms (p90 0.68 ms, max 0.74 ms) | 50.6 ms† (p90 50.7 ms, max 50.8 ms) | 0.99 ms (p90 1.12 ms, max 2.55 ms) | 0.71 ms (p90 0.83 ms, max 26.9 ms) | 0.40 ms (p90 0.48 ms, max 0.60 ms) | 302.4 ms† (p90 302.9 ms, max 303.2 ms) |
| open 1 MiB (5 runs) | 2.23 ms (p90 2.47 ms, max 2.47 ms) | 3.24 ms (p90 3.69 ms, max 3.69 ms) | 18.0 ms (p90 18.5 ms, max 18.5 ms) | 15.1 ms (p90 16.0 ms, max 16.0 ms) | 12.2 ms (p90 12.6 ms, max 12.6 ms) | 44.5 ms (p90 45.1 ms, max 45.1 ms) |
| memory, 1 MiB | 18.1 MiB | 9.0 MiB | 21.8 MiB | 9.5 MiB* | 20.6 MiB | 25.0 MiB |
| open 100 MiB (3 runs) | 108.2 ms (p90 150.2 ms, max 150.2 ms) | 138.8 ms (p90 141.7 ms, max 141.7 ms) | 105.3 ms (p90 107.1 ms, max 107.1 ms) | 153.2 ms (p90 154.1 ms, max 154.1 ms) | 138.7 ms (p90 139.1 ms, max 139.1 ms) | 1.12 s (p90 1.16 s, max 1.16 s) |
| memory, 100 MiB | 232.1 MiB | 259.8 MiB | 135.9 MiB | 9.6 MiB* | 134.8 MiB | 593.7 MiB |
| open 1 GiB | refused | 1.45 s | 847.0 ms | 1.34 s | 1.27 s | 15.94 s |
| memory, 1 GiB | refused | 2573.5 MiB | 1201.1 MiB | 9.7 MiB* | 1206.0 MiB | 5336.3 MiB |
| open a 10 MiB line (3 runs) | 10.3 ms (p90 11.4 ms, max 11.4 ms) | 10.4 ms (p90 11.1 ms, max 11.1 ms) | 686.7 ms (p90 747.8 ms, max 747.8 ms) | 194.4 ms (p90 195.4 ms, max 195.4 ms) | 1.31 s (p90 1.33 s, max 1.33 s) | 134.5 ms (p90 157.6 ms, max 157.6 ms) |
| memory, 10 MiB line | 28.0 MiB | 26.6 MiB | 32.2 MiB | 9.5 MiB* | 68.7 MiB | 63.6 MiB |
| make 10,000 selections | 2.84 ms | 3.68 ms | 10.6 ms | not supported | not supported | 143.2 ms |
| type at 10,000 selections: first key | 1.47 ms | 1.73 ms | 59.9 ms | not supported | not supported | 2.92 s |
| type at 10,000 selections: next 10 keys | 1.57 ms (p90 1.63 ms, max 1.67 ms) | 1.66 ms (p90 2.31 ms, max 2.72 ms) | 10.5 ms (p90 10.9 ms, max 34.9 ms) | not supported | not supported | 579.4 ms (p90 606.8 ms, max 608.9 ms) |
| memory, 10,000 selections | 55.8 MiB | 16.6 MiB | 27.1 MiB | not supported | not supported | 197.8 MiB |

\* Neovim's text lives in a child process its terminal interface starts,
which the driver does not count yet; its memory rows are too low until
it does (an item below).
† Every one of the 200 keys takes the same time: the editor seems to
draw again after the key, and the 60 ms wait for a quiet screen counts
it. Not counted as lost or won until checked (an item below).
The files measured began with the marker `neocaca-compare-top`; since
the rename to caca it reads `caca-compare-top`, four bytes shorter,
every other byte the same.

The pass that closes each phase, and every pass before a release,
measures again against the editors' current releases and replaces this
table ("Against the other editors" in `docs/field-validation.md`); the
aim is a table with no row caca loses to any of them. caca is
fastest to start, to open small files and long lines, and with 10,000
selections. It is behind in these rows, each an item below:

- memory against Kakoune at startup, on small files, a long line and
  10,000 selections, and on 100 MiB against Helix and Vim
  (Phase 2: memory);
- a key answered in 0.62 ms to Vim's 0.40, and 100 MiB opened in 108 ms
  to Helix's 105 (Phase 2: speed);
- files past `max_file` (256 MiB), which all five open (Phase 2: large
  files).

The first measurement, against flow alone (0.7.2's release binary,
2026-10-23), is kept in the history of this file.

- **PR: measured against flow.**
  - [x] M: `zig build compare -Dflow=<path>` (now `-Deditors=flow=<path>`)
        runs both editors on a pseudo-terminal with the same files and
        reports, for each: startup to the first frame, keypress to frame,
        open time and peak memory on 1 MB, 100 MB and 1 GB files, a 10 MB
        single line, and 10,000 selections.

## Phase 0: foundations

Done on 2026-10-22.

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

Done on 2026-10-23, when the short pass of the second field validation pass came
back clean and the change-on-disk fix it led to was in (#15).

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
- [x] A field validation pass: real files edited in a ReleaseSafe build under
      tmux (a Zig source file, the README, CRLF, BOM, control bytes, wide
      and combining characters, a 50 MB file, a 48 MB single line, a
      directory, a missing directory), resizes down to one cell, Ctrl-Z
      and `fg`. What it found is below or already in Phase 2; how a pass
      is run from now on is in `docs/field-validation.md`.
- **PR: fixes from the field validation pass**
  - [x] S: the view keeps its old scroll when the window grows, hiding
        lines above while the rows below stay empty (a 4-line file,
        resized to 5 rows and back to 8, showed lines 2 to 4). A taller
        window now scrolls back to fill its rows.
  - [x] S: messages name Zig errors (`cannot open ".": IsDir`, `cannot
        write "…": FileNotFound`); say it in words ("is a directory",
        "no such file or directory"). Files, recovery, bad patterns and
        the error printed when the terminal fails now all say why in
        words (`fs.describe`, `regex.describe`). Testing it found a
        crash: a path part over 255 bytes made the standard library
        panic in Debug builds; `fs/file.zig` now refuses it first.
  - [x] S: `caca <directory>` opens an empty buffer named after the
        directory; refuse it at startup with an exit code instead. A file
        in a directory that does not exist says "new file" and fails only
        at `:w`; say so when it opens. So does a path through a file
        (`:e f/x`) on macOS, where Linux says it is not a directory. Any
        file that cannot be read (a directory, one over the size limit,
        an unreadable one) now stops `caca` before the terminal is
        touched, with exit code 1, since `:w` on the empty buffer would
        have replaced it; a missing directory, or a path through a file,
        opens new and says "its directory does not exist" on every
        system.
  - [x] S: a message wider than the window is cut mid-word with no mark
        (`unsaved changes; :q! dis` at 24 columns); end it with `…`.
        A message over its 256 bytes loses its end too, so a long path
        hides the reason (`cannot open "nnn…` with no "the name is too
        long"); shorten the path, never the reason. A path in a message
        (`Message.path`) now gives way first: past 256 bytes, and on a
        window too narrow, it loses its start to `…`, so its file name
        and the reason stay. A message too wide even then, or one
        without a path, ends with `…` in the last column.
  - [x] S: `Alt-i` or `Alt-a` with no such object around the cursor
        (`Alt-i"` outside quotes) changes nothing and says nothing, so the
        next verb acts on the old selection; say "no object here". It
        now says so, as an error, when no selection has the object
        around it; one found around any selection says nothing.
- **PR: the field validation pass that closes Phase 1**
  - [x] M: every scenario of `docs/field-validation.md` on its corpus, once the
        fixes above are in; its findings become pieces, and Phase 1 is done
        when none of them is a crash, lost data or raw terminal bytes.
        Run on 2026-10-23 as a user who is not root, under tmux. It found
        one crash (a file size limit kills the editor) and four rough
        edges, all in the pull request below; nothing raw reached the
        terminal. The rest is already on the roadmap, with the numbers
        added to its items.
- **PR: fixes from the second field validation pass.** The crash goes first;
  Phase 1 is done once this pull request is in and its short pass is
  clean.
  - [x] S: a save past the file size limit kills the editor. `ulimit -f 1`
        in the shell, then `:w` on `unicode.txt` (9 KB): `SIGXFSZ` ends
        caca with exit code 153, the unsaved edit is lost, the
        terminal is left in raw mode without echo, and a 512-byte
        temporary file (`4efc61bb66dd3e91`) stays beside the original,
        which is untouched. Ignore `SIGXFSZ`, so the write fails with
        `EFBIG`, the temporary file is removed and the message says the
        file is too large, as a full disk already does. Done: `term.Tty`
        ignores `SIGXFSZ` while it is open, and the save fails with
        "the file is too big".
  - [x] S: `:w` replaces a read-only file. `read-only.txt` (mode 0444,
        owned by the user, in a writable directory) is saved without a
        word, since the save renames a new file over it, and keeps its
        mode 0444. Refuse it ("the file is read-only") and let `:w!`
        write it anyway. Done: a file nobody may write (no write bit) is
        refused, as root too, with "the file is read-only; :w! writes it
        anyway"; `:w!` replaces it and keeps its mode.
  - [x] S: `Ctrl-z` suspends only from normal mode. In insert mode or a
        prompt it does nothing, so the next keys go to the buffer or the
        prompt: `:w half-typed`, `Ctrl-z`, then `fg` Enter wrote a file
        named `half-typedfg`. Suspend from every mode and come back to it.
        Done: `keymap.isSuspend` is Ctrl-z in insert mode and the prompt
        too; the mode, the prompt line and the insert session are kept.
  - [x] S: on a narrow window, a message with a path loses its reason when
        its start and its reason do not fit beside even a shortened path:
        at 30 columns, `:w` to a missing directory shows `cannot write
        "a-very-long-dir…` and `:e` there shows the path but not "its
        directory does not exist". Keep the reason: the path goes to `…`
        first, then the start of the message. Done: at 30 columns they
        read `…": no such file or directory` and `… its directory does
        not exist`.
  - [x] S: a temporary file left by a save that never finished (the
        editor killed, the power cut) has a bare random name nobody can
        connect to the file. Name it after the file and hide it
        (`.unicode.txt.<random>.tmp`). Done: `fs/temp.zig` names it
        `.unicode.txt.4efc61bb66dd3e91.tmp` beside the file, a hidden
        file keeping its one dot and a long name cut between characters
        to fit 255 bytes; one left by an earlier save is never touched.
  - [x] S: the short pass: scenarios 8, 9 and 10 of `docs/field-validation.md`
        again; Phase 1 is done when it finds no crash, lost data or raw
        terminal bytes. Run on 2026-10-23 on a fresh corpus, in ReleaseSafe
        as a user who is not root, under tmux. Nothing new: every path of
        scenario 8 is refused or saved as documented (`read-only.txt`
        refused, then written by `:w!` and still 0444); a resize to one
        cell and back, a 220 KB paste (0.12 s, one undo), a hang-up (the
        `.recovered` file holds the edit) and Ctrl-z from a prompt and
        insert mode all held; a full 64 KB tmpfs and `ulimit -f 1` left the
        original byte for byte and no temporary file; `kill -9` mid-save
        left `server.log` whole beside `.server.log.<random>.tmp`. One gap
        is lost data: a line appended from another shell was overwritten
        by `:w` without a word. It is fixed below, ahead of Phase 2.
  - [x] S: `:w` refuses to overwrite a file changed on disk and says so;
        `:w!` forces. Done: `fs/disk.zig` stamps the file (inode, size,
        modification time) just before it is read and after every save;
        a save whose file no longer matches fails with "the file changed
        on disk; :w! writes it anyway", and so does one of a new file
        that something else made meanwhile. A file deleted since is
        written again; `:w other` is not checked.

## Phase 2: everyday comfort

Safety first, then the biggest daily gains.

- **PR: cap the number of selections**
  - [x] S: `max_selections` (2^20), tested at the limit and one past it:
        `s`, `S`, `Alt-s`, `C` and `N` that would make more stop as they
        pass it, say so and change nothing. Before, `%` then `s` `a` on a
        50 MB file made 9.6 million, froze the editor for 5 seconds and
        used 830 MB; on the 100 MB log of the corpus, `%` `s` `a` made 2.8
        million in 1.5 s (457 MB), and `%` `Alt-s` 1.4 million lines in
        0.6 s (350 MB). Now, in ReleaseSafe on the same log, `%` `s` `a`
        is refused in 0.69 s and `%` `Alt-s` in 0.07 s, peaking at 252 MB
        against the 232 MB the open file takes.
- **PR: respect line endings, the BOM and a missing final newline.**
  The bytes of a file are kept as loaded, but:
  - [x] M: CRLF files show no `^M` at each line end, and the lines added
        to them (Enter, `o`, `O`, paste) end in CRLF, not a bare `\n`.
        Before, `gl` then `a` on a CRLF line put the text between the
        `\r` and the `\n`. A file whose every line ends in CRLF is now
        edited with `\n` and written (and recovered) with CRLF, byte for
        byte; a file that mixes the two is kept as it is, `^M` and all
        (`buffer/endings.zig`). In ReleaseSafe the 100 MB log with CRLF
        opens in 0.25 s against 0.17 s with LF, peaking at 250 MB against
        244 MB; saves take as long either way.
  - [x] S: a BOM is hidden and cannot be deleted by accident; before, it
        showed as a replacement glyph at the start of the file. A UTF-8
        byte order mark at the very start is now taken off on load and
        written back first on save and in the recovery file, with CRLF
        line ends too (`buffer/form.zig`); one later in the text is text.
  - [x] S: a file without a final newline is saved without one; before,
        the buffer added one on load and `:w` wrote it. The buffer still
        ends in one, so every line has an end to edit; the file's form
        remembers there was none and a save, or the recovery file, drops
        it again (`buffer/form.zig`). Lines added after the last one end
        in a newline, all but the new last. A carriage return that ends a
        CRLF file is now text, shown as `^M` and kept.
  - [x] S: an empty file saved untouched gets a newline; it should stay
        empty, while text typed into it still ends in one. Now the form
        remembers a file with no text, and while the buffer holds none
        either a save writes it empty (a byte order mark alone stays
        alone). A new file saved untouched still gets its newline.
- **PR: fixes from the codebase audit.** A read of the whole codebase
  on 2026-10-26, each finding reproduced in ReleaseSafe on `main` at
  25cc5a5. The first two lose data, the last puts raw bytes on the
  terminal, so they go ahead of the rest of the phase.
  - [x] S: SIGTERM left the terminal raw, on the alternate screen, and
        lost unsaved changes (exit 143, no `.recovered` file) (#20). It is
        now taken as a hang-up: it wakes the loop, the terminal is
        restored and the changes go to the recovery file.
  - [x] S: a SIGTSTP from outside (`kill -TSTP`, not Ctrl-z) stopped the
        editor on the alternate screen, and after `fg` the terminal was
        left cooked with echo on and the screen not redrawn: keys echoed
        and arrived only after Enter (#26). Its handler now wakes the
        loop (`Ready.stop`), which suspends as Ctrl-z does: the modes and
        raw mode given back, the signal let through to stop the process,
        and on `fg` raw mode, the modes and the whole screen back.
  - [x] S: a SIGSTOP (`kill -STOP`, which no handler can take) left
        the terminal cooked after `fg`, nothing redrawn (#37). SIGCONT
        now wakes the loop (`Ready.continued`) unless the editor stopped
        itself, and the loop takes raw mode and the modes back
        (`Tty.retake`) and draws the whole screen. While stopped the
        terminal is still raw on the alternate screen: nothing runs to
        give it back.
  - [x] S: a hang-up lost unsaved changes when the file's name was
        longer than 245 bytes: `<name>.recovered` passed the 255-byte
        limit on a name and every try failed, yet the exit status was 0
        (#21). The file's own name is now cut between characters to
        leave room for the suffix (`fs.fitName`, shared with
        `fs/temp.zig`), and the exit status is 1 whenever unsaved
        changes could not be written.
  - [x] S: `:w` broke hard links without a word: the rename gives the
        edited name a new inode and the other names keep the old text
        (#22). A file with more than one link is now refused ("the file
        has other hard links, which would keep the old text; :w! writes
        it anyway"), and `:w!` writes this name alone.
  - [x] S: a save gave the file the editor's owner and group: the
        temporary file is created by the user, so editing a file owned
        by another group (a shared directory, or as root) changed who
        owns it (#32). `fs/owner.zig` reads them (`statx` on Linux,
        `fstatat` elsewhere) and gives them to the temporary file: both
        as root, the group alone where the user is a member of it,
        neither otherwise. The same tests found every save dropping the
        set-user-ID and set-group-ID bits, which a write clears: the
        permissions are now set again after it.
  - [x] S: the messages on stderr (`cannot open "…"`, `unsaved changes
        written to "…"`) printed a path's control bytes raw, so a file
        named with an OSC sequence set the window title (#23). They go
        through `unicode/visible.zig` now, which writes each character as
        the screen draws it: controls in caret form, C1 controls,
        bidirectional controls and invalid bytes as U+FFFD; tested with
        every byte and every pair of bytes.
  - [x] S: rough edges (#24). `:w d/` on a directory `d` said "a part
        of the path is not a directory", and `:w .` "the file is busy",
        after writing a temporary file beside it: a name ending in a
        slash, or one that names a directory, is now refused at once as
        "is a directory", forced or not. `Prompt.set` could cut a
        character in two at `max_len`; it cuts between characters now.
- **PR: required checks on `main`.** Nothing stopped a merge while CI
  was red, and auto-merge merged at once.
  - [x] S: a `ci` job that needs every blocking job and a `title` check
        of the Conventional Commit title, both required on `main` by a
        ruleset that also allows only squash merges and no direct or
        force pushes.
  - [x] M: a `ratio` job that counts the 3:1 rule in a pull request's
        diff (`zig build ratio`, `src/ratio/`), part of the required `ci`
        gate. A line the diff also removes counts as moved, not added.
- **PR: notice a change made on disk while the file is open.** `:w`
  already refuses to write over one (Phase 1); nothing says so sooner.
  - [x] S: when the terminal reports focus (xterm focus events, mode
        1004), compare the file with its stamp and say it changed, before
        any edit is made on the old text
- **PR: fixes from the 2026-11-14 check.** CI on `main` failed once
  after #43, and a read of the screen code found a second bug.
  - [x] S: a terminal closed under the editor could end it with "the
        terminal failed: an input/output error" and a failed exit,
        changes recovered all the same: Linux fails a read with EIO,
        not 0, while it hangs up a pseudo-terminal whose other side
        closed. `Tty.read` now takes EIO as the end of input. The
        pseudo-terminal test of the longest recovered name hit it on
        Alpine (ReleaseSafe, `-Dmimalloc-secure=off`).
  - [x] S: a wide character with more than 32 bytes of combining marks
        was drawn as a one-column replacement while the layout gave it
        two, so the rest of its row sat one column left of the cursor;
        the replacement now keeps both columns.
- **PR: keys typed during a load keep their pauses.**
  - [x] S: an Escape typed while `:e` is still reading the file, then
        `:` or another key, was read as Alt plus that key when the held
        bytes were decoded after the load, because the pause after the
        Escape was lost (`session.zig` held raw bytes). `:e f` then
        `ox`, Esc, `:w` typed quickly inserted `xw`. The Escape timeout
        now runs during a load too: it decodes the held bytes into keys
        (pastes copied), which wait for the load in order and count
        against `max_held`. Found by the CRLF tests.
- **PR: quit after a save in flight.**
  - [x] S: `:q` (and `:e`) typed while a save is still being written
        waits for it to finish, then quits (or opens), instead of
        refusing with "a save is still being written", which `:w` then
        `:q` typed quickly, or mapped to one key, hit. Keys typed while
        it waits are dropped, as during `:wq`. Refused at once when the
        text changed since the save began; a failed save, or one to
        another file, leaves the editor open and says why.
- **PR: tidy-ups from the 2026-10-26 scan.** Small rule breaks; nothing
  wrong in behavior.
  - [x] S: `term/tty.zig` drops the error of the self-pipe drain read
        (`catch {}`) without the comment AGENTS.md asks for; say why it
        is safe (a short read only leaves a wake byte for the next wait)
  - [x] S: `app/editor.zig` (410 lines) and `fs/file_test.zig` (438) are
        past the ~400-line limit: move a concern out of the editor, and
        split the file tests by topic. `Message` moved to
        `app/message.zig` (the editor is 342 lines), and the path tests
        to `fs/file_path_test.zig`.
- **PR: soft wrap of long lines**
  - [x] M: wrapped line layout, pure and tested (`ui/wrap.zig`): rows
        break after the last blank before the edge, a longer word at
        the edge; widths in characters and display columns, the line's
        end takes a column, and a line over `max_line` (1 MiB) is one
        row, scrolled sideways
  - [x] M: draw it, with the cursor and scrolling over wrapped lines:
        `View` keeps a row within its top line (`row`) and follows the
        cursor by rows with scroll-off (`followRows`); continuation rows
        have a blank gutter; `j`/`k` still move by buffer line. `:wrap`
        and `:nowrap` turn it on and off, off by default for now
  - [x] S: the page keys (`Ctrl-d` `Ctrl-u` `Ctrl-f` `Ctrl-b`), `v`
        (`vt` `vc` `vb`, `vj` `vk`) and a resized window filling its
        rows count screen rows when wrapping (`View.scrollRows`,
        `placeRows`, `fillRows`); the cursor goes along a long line
        from row to row, keeping its column within the row
  - [x] S: wrap by default (`:nowrap` to turn it off), the tests that
        scroll sideways set `:nowrap`; `vh` `vl` scroll only lines that
        are not wrapped
- **PR: comparison with several editors.** The comparisons and
  benchmarks are universal rather than built around one editor: caca
  is measured alone or beside Kakoune, Helix, Neovim, Vim and flow, and
  its features are compared with all of them.
  - [x] M: `zig build compare -Deditors=kak,hx,nvim,vim,flow` runs
        caca beside any editors listed, each from a profile of its
        arguments and keys (`compare/editors.zig`), and alone with no
        list; an editor without multiple selections reads "not
        supported" in their rows
  - [x] M: "The yardstick" becomes a comparison with every editor
        listed: a feature table with a column per editor (from their
        user documentation and by running them), the "Measured" table
        with a column per editor, and `README.md`, `AGENTS.md`,
        `docs/field-validation.md` and the `field-validation` skill
        reworded to compare with all of them rather than with flow
  - [ ] S: memory counts every process an editor runs: Neovim's
        terminal interface keeps its text in a child process, so the
        first run measured 9.4 MiB for it with 1 GiB open (sum the
        peak of each descendant, and test the sum on a scripted tree)
  - [ ] S: keypress rows checked where every key takes the same time
        (Kakoune 50.6 ms, flow 302 ms on 2026-11-15): find with
        `--trace` what each draws after the key, and time the frame
        that answers it rather than the redraws after, or say why not
- **PR: multiple buffers.** Splits build on this.
  - [x] M: a list of documents with a current index, each keeping its
        own path, selections, history and save state (no new keys yet):
        the current one stays in `Editor`'s fields, the others wait in
        `app/buffers.zig`
  - [ ] S: every buffer, not only the current one, is checked by `:q`
        for unsaved changes and written by the recovery on a hang-up;
        no switch while a save is in flight
  - [ ] S: `:e` opens a second buffer; `:bn` and `:bp` switch
  - [ ] S: `:b <name>` and `:bd`, and the buffer in the status line
- **PR: concurrency and crash safety.** More work moves off the event
  loop and out of the process, without races: one thread owns the
  editing state, and nothing that changes is shared. Today the loop does
  all editing, with one thread per save or `:e` load; a panic, SIGKILL
  or the out-of-memory killer loses the unsaved changes that a hang-up
  or SIGTERM would have written to the recovery file.
  - [ ] S: the rules in `AGENTS.md`: the loop is the only owner of
        documents, selections, registers and the view; a worker takes an
        owned copy or a snapshot that never changes, and answers with one
        message through the wake pipe, tagged with the document version
        it read (a stale answer is dropped); cancelling is an atomic
        flag; no locks in the editing code; workers injected so tests
        run them in a fixed order
  - [ ] S: a CI job running the tests with the thread sanitizer
        (Linux), shown once by hand to catch a deliberate race
  - [ ] M: a crash journal: every change set appended, bounded, to a
        file beside the document (named as `fs/temp.zig` names its
        temporary files), removed on a save or a clean quit, so a crash
        of any kind loses at most the last change
  - [ ] M: opening a file that has a journal offers to replay it; a
        journal written against other file contents than those on disk
        is refused, never trusted blindly
  - [ ] M: a supervisor: caca starts as a small parent holding the
        terminal's settings and runs the editor as its child; when the
        child dies by a signal its panic handler cannot catch, the
        parent restores the terminal and names the journal; suspending,
        resizes and exit codes pass through unchanged
- **PR: system clipboard through OSC 52 (write only)**
  - [ ] S: yank also copies to the system clipboard
  - [ ] S: a history of the last yanks, to paste an older one
- **PR: command line**
  - [ ] S: `caca file:12` and `caca +12 file` open at line 12
- **PR: smart-case search**
  - [ ] S: a pattern without capitals matches either case, one with
        capitals matches exactly
- **PR: reflow**
  - [ ] S: rewrap the selected paragraphs to a width, keeping their line
        prefix (indentation, `//`, `#`, `>`)
- **PR: macros.** Kakoune, Helix, Neovim and Vim record keys into a
  register and replay them ("Still behind").
  - [ ] M: record the keys typed into a register, replay them with a
        count, as one undo step; the keys chosen in `docs/keys.md` first
- **PR: mouse**
  - [ ] M: click to place a selection, drag to extend
  - [ ] S: wheel to scroll
- **PR: shell filters, off the event loop**, each a child process
  watched from its own thread, following the rules of "concurrency and
  crash safety"
  - [ ] M: run a command on its own thread, bounded output, cancelled by
        `Esc`
  - [ ] S: `|` replaces each selection with its output
  - [ ] S: `!` inserts the output and `Alt-|` only runs the command
- **PR: kitty keyboard protocol, with legacy fallback.** The legacy
  encoding cannot tell Esc from the start of an Alt key without the
  25 ms timeout, nor Ctrl-i from Tab or Ctrl-m from Enter.
  - [ ] S: probe for it and fall back cleanly
  - [ ] M: decode its key events
- **PR: large files.** Today the text is one contiguous array, and every
  edit rebuilds it and its line index, so an edit costs the size of the
  file.
  - [ ] S: a benchmark of typing into a 100 MB file (by hand, in
        ReleaseSafe: about 100 ms a key on the 100 MB log, 35 ms on the
        31 MB CSV, 50 ms with 1000 cursors there)
  - [ ] M: a piece table behind the `buffer::Buffer` interface
  - [ ] M: its line index; `Buffer`'s API is unchanged, so `edit/` does
        not change
  - [ ] S: the benchmark again, with the numbers in the PR
  - [ ] M: open files past `max_file` (256 MiB, so a 1 GiB file is
        refused today; Helix opens it in 0.85 s and 1.2 GiB, Vim in
        1.3 s and 1.2 GiB, see "Measured"), with the new limit tested at
        it and one past it, and the `zig build compare` row again
- **PR: searches off the event loop**, on a snapshot of the piece table
  (pieces never change once written, so a snapshot copies no text),
  following the rules of "concurrency and crash safety". Today they run
  on the loop within `max_steps`, which caps how much of a large file
  one search can cover: on the 100 MB log, a pattern that starts with a
  class (`[0-9]+ZZ`, `\d+ZZ`) stops after 1.5 s with "too much work for
  this regex" where the answer is "not found", while a literal one
  misses all 100 MB in 129 ms.
  - [ ] M: `/`, `?`, `s`, `S` and `Alt-k` run on their own thread
  - [ ] S: `Esc` cancels them; raise the step bound
- **PR: memory.** Kakoune uses less memory at startup, on 1 MiB, on a 10 MiB
  line and with 10,000 selections; Helix and Vim on 100 MiB ("Measured").
  - [ ] S: startup: find where the 11.2 MiB goes (mimalloc's
        reservations, the two screens, the line index; Kakoune starts in
        6.7) and cut what is not needed, measured with `zig build compare`
  - [ ] S: selections: 10,000 take 55.8 MiB to Kakoune's 16.6 and
        Helix's 27.1; find what each selection costs and cut it
  - [ ] S: files: 100 MiB held in 232 MiB, to Helix's and Vim's 135 (no
        second copy of the text, a smaller line index)
- **PR: speed.** The rows of "Measured" another editor wins on time.
  - [ ] S: a key answered in 0.62 ms to Vim's 0.40: profile one Down on
        the 1 MiB file and cut what a frame does that it need not
  - [ ] S: 100 MiB opened in 108 ms to Helix's 105: profile the load
        (reading, the line index, the first frame)
- **PR: grapheme clusters per UAX #29** (emoji ZWJ sequences, regional
  indicators) instead of code point and combining marks. Under tmux,
  which draws a ZWJ sequence or an emoji with its skin tone as one
  character, moving over them in `unicode.txt` leaves a second copy of
  🏽 and 👧 on screen.
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
- **PR: the field validation pass that closes Phase 2**
  - [ ] M: every scenario of `docs/field-validation.md`, with those Phase 2 added
  - [ ] S: against the other editors' current releases ("Against the other
        editors" in `docs/field-validation.md`): "Measured", "Features" and
        "Still behind" redone, an item for every row caca loses

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
- [ ] The field validation pass that closes Phase 3 (`docs/field-validation.md`), with
      its measurement against the other editors

## Phase 4: polish

- [ ] Splits and windows, and a centered view on wide screens
- [ ] Scrollbars and smooth scrolling
- [ ] Themes (light and dark), true color with 256-color fallback, and
      VS Code themes imported
- [ ] The kitty text sizing protocol
- [ ] Accessibility (see `ACCESSIBILITY.md`): honor `NO_COLOR`, show
      which text is selected without relying on color, and a screen
      reader mode that announces changes instead of redrawing the grid
- [ ] Session restore, the open buffers and their places brought back
      on the next start (unsaved changes are the crash journal's, Phase 2)
- [ ] Saving a file you cannot write (owned by root) without restarting
      the editor
- [ ] Android under termux, checked in CI or by hand
- [ ] An integrated terminal and remote control over a socket (flow has
      both): decide whether caca wants them
- [ ] Plugins: programs the editor starts, over a bounded, versioned
      message protocol shared with shell filters, the language server
      client and remote control. Plugin edits are change sets against a
      buffer version, always undoable. Custom motions and text objects
      come from the configuration file, not from plugins.
- [ ] Persistent undo: history saved beside the file (bounded, checked
      against the file's contents before use, never trusted blindly)
- [ ] Command palette: every `:` command and key action, searchable by
      name, showing its binding
- [x] Local installs for everyday use: `make install` (ReleaseSafe
      with LTO) and `make optimized-install` (also laid out by
      `llvm-bolt` from scripted sessions, `scripts/bolt.sh`)
- **PR: weekly releases**, brought ahead of the phase at the
  maintainer's request (2026-11-15). Versions follow the phases: each
  weekly release bumps the patch, and a phase closing sets the minor
  through a `Release-As:` footer (Phase 2 gives 0.2.0, Phase 3 0.3.0,
  Phase 4 1.0.0); a security fix (`fix(security): …`) releases at once.
  - [x] M: the release tool, `zig build release` (`src/release/`): whether
        a run releases (weekly, at once for a security fix, a
        `Release-As:` footer or a missed week), the next version, the
        changelog section from the Conventional Commits, and the version
        in build.zig.zon, the Homebrew formula and the PKGBUILD
  - [ ] M: publishing: CHANGELOG.md, the release job on a weekly
        schedule, a write deploy key the `main` ruleset lets through,
        Debian and RPM packages from the static musl builds, a Homebrew
        formula and an Arch PKGBUILD, each built and installed in CI; a
        field validation pass with the 1 GB log (`BIG=1`) and the
        measurement against the other editors before every major release
  - [ ] S: the release builds laid out by BOLT, as `make
        optimized-install` lays out the local one
- [ ] The field validation pass that closes Phase 4 (`docs/field-validation.md`), with
      its measurement against the other editors

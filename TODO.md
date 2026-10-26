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
| Files past 256 MiB (it opens 1 GiB in 44 s, in 7.1 GiB) | Phase 2: large files |
| Less memory at startup (7.7 MiB, neocaca 11.0) | Phase 2: startup memory |
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

**Measured.** `zig build compare -Dflow=<path>` runs both editors on a
120x40 pseudo-terminal with the same files and answers the queries a
terminal would (x86_64 Linux, neocaca's ReleaseSafe build against flow
0.7.2's release binary at its default frame rate; medians, with p90 and
max). A frame is timed to its last byte, once the screen has been quiet
for 60 ms:

| | neocaca | flow |
|---|---:|---:|
| startup to first frame (10 runs) | 3.37 ms (p90 6.77 ms, max 49.8 ms) | 13.3 ms (p90 19.4 ms, max 19.7 ms) |
| memory at startup | 11.0 MiB | 7.7 MiB |
| keypress to frame (200 Down, 1 MiB file) | 0.66 ms (p90 0.91 ms, max 4.29 ms) | 1.94 ms (p90 2.73 ms, max 33.4 ms) |
| open 1 MiB (5 runs) | 7.26 ms (p90 64.3 ms, max 64.3 ms) | 19.9 ms (p90 20.4 ms, max 20.4 ms) |
| memory, 1 MiB | 17.9 MiB | 15.6 MiB |
| open 100 MiB (3 runs) | 403.0 ms (p90 1.34 s, max 1.34 s) | 875.9 ms (p90 3.78 s, max 3.78 s) |
| memory, 100 MiB | 231.9 MiB | 702.6 MiB |
| open 1 GiB | refused | 43.61 s |
| memory, 1 GiB | refused | 7091.5 MiB |
| open a 10 MiB line (3 runs) | 17.1 ms (p90 18.5 ms, max 18.5 ms) | 94.7 ms (p90 188.1 ms, max 188.1 ms) |
| memory, 10 MiB line | 27.8 MiB | 77.3 MiB |
| make 10,000 selections | 4.81 ms | 93.2 ms |
| type at 10,000 selections: first key | 2.18 ms | 1.24 s |
| type at 10,000 selections: next 10 keys | 4.72 ms (p90 22.6 ms, max 26.9 ms) | 495.8 ms (p90 830.0 ms, max 887.7 ms) |
| memory, 10,000 selections | 55.5 MiB | 152.3 MiB |

The pass that closes each phase, and every pass before a release,
measures again against flow's latest release and replaces this table
("Against flow" in `docs/dogfooding.md`); the aim is a table with no row
neocaca loses. neocaca is ahead on time everywhere it runs, and on memory
from 100 MiB up. It is behind in two places, each an item below: it refuses files
past `max_file` (256 MiB), which flow opens (Phase 2: large files), and
it starts in 3.3 MiB more memory (Phase 2: startup memory).

- **PR: measured against flow.**
  - [x] M: `zig build compare -Dflow=<path>` runs both editors on a
        pseudo-terminal with the same files and reports, for each: startup
        to the first frame, keypress to frame, open time and peak memory on
        1 MB, 100 MB and 1 GB files, a 10 MB single line, and 10,000
        selections. The numbers are in the table above.

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

Done on 2026-10-23, when the short pass of the second dogfood pass came
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
  - [x] S: messages name Zig errors (`cannot open ".": IsDir`, `cannot
        write "…": FileNotFound`); say it in words ("is a directory",
        "no such file or directory"). Files, recovery, bad patterns and
        the error printed when the terminal fails now all say why in
        words (`fs.describe`, `regex.describe`). Testing it found a
        crash: a path part over 255 bytes made the standard library
        panic in Debug builds; `fs/file.zig` now refuses it first.
  - [x] S: `neocaca <directory>` opens an empty buffer named after the
        directory; refuse it at startup with an exit code instead. A file
        in a directory that does not exist says "new file" and fails only
        at `:w`; say so when it opens. So does a path through a file
        (`:e f/x`) on macOS, where Linux says it is not a directory. Any
        file that cannot be read (a directory, one over the size limit,
        an unreadable one) now stops `neocaca` before the terminal is
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
- **PR: the dogfood pass that closes Phase 1**
  - [x] M: every scenario of `docs/dogfooding.md` on its corpus, once the
        fixes above are in; its findings become pieces, and Phase 1 is done
        when none of them is a crash, lost data or raw terminal bytes.
        Run on 2026-10-23 as a user who is not root, under tmux. It found
        one crash (a file size limit kills the editor) and four rough
        edges, all in the pull request below; nothing raw reached the
        terminal. The rest is already on the roadmap, with the numbers
        added to its items.
- **PR: fixes from the second dogfood pass.** The crash goes first;
  Phase 1 is done once this pull request is in and its short pass is
  clean.
  - [x] S: a save past the file size limit kills the editor. `ulimit -f 1`
        in the shell, then `:w` on `unicode.txt` (9 KB): `SIGXFSZ` ends
        neocaca with exit code 153, the unsaved edit is lost, the
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
  - [x] S: the short pass: scenarios 8, 9 and 10 of `docs/dogfooding.md`
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
- **PR: keys typed during a load keep their pauses.**
  - [ ] S: an Escape typed while `:e` is still reading the file, then
        `:` or another key, is read as Alt plus that key when the held
        bytes are decoded after the load, because the pause after the
        Escape is lost (`session.zig` holds raw bytes). `:e f` then
        `ox`, Esc, `:w` typed quickly inserts `xw`. Hold the decoded keys,
        or the timeout, instead. Found by the CRLF tests.
- **PR: quit after a save in flight.**
  - [ ] S: `:q` (and `:e`) typed while a save is still being written
        waits for it to finish, then quits (or opens), instead of
        refusing with "a save is still being written". Today `:w` then
        `:q` typed quickly, or mapped to one key, is refused; the
        pseudo-terminal test hit it under load.
- **PR: tidy-ups from the 2026-10-26 scan.** Small rule breaks; nothing
  wrong in behavior.
  - [ ] S: `term/tty.zig` drops the error of the self-pipe drain read
        (`catch {}`) without the comment AGENTS.md asks for; say why it
        is safe (a short read only leaves a wake byte for the next wait)
  - [ ] S: `app/editor.zig` (404 lines) and `fs/file_test.zig` (438) are
        past the ~400-line limit: move a concern out of the editor, and
        split the file tests by topic
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
  `max_steps`, which caps how much of a large file one search can cover:
  on the 100 MB log, a pattern that starts with a class (`[0-9]+ZZ`,
  `\d+ZZ`) stops after 1.5 s with "too much work for this regex" where
  the answer is "not found", while a literal one misses all 100 MB in
  129 ms.
  - [ ] M: `/`, `?`, `s`, `S` and `Alt-k` run on their own thread
  - [ ] S: `Esc` cancels them; raise the step bound
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
        refused today; flow opens it in 44 s and 7.1 GiB, see "Measured"),
        with the new limit tested at it and one past it, and the
        `zig build compare` row again
- **PR: startup memory.** neocaca starts in 11.0 MiB, flow in 7.7 MiB,
  and holds a 1 MiB file in 17.9 MiB to flow's 15.6 ("Measured").
  - [ ] S: find where the 11 MiB goes (mimalloc's reservations, the two
        screens, the line index) and cut what is not needed, measured with
        `zig build compare`
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
- **PR: the dogfood pass that closes Phase 2**
  - [ ] M: every scenario of `docs/dogfooding.md`, with those Phase 2 added
  - [ ] S: against flow's latest release ("Against flow" in
        `docs/dogfooding.md`): "Measured" and "Still behind" redone, an
        item for every row neocaca loses

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
- [ ] The dogfood pass that closes Phase 3 (`docs/dogfooding.md`), with
      its measurement against flow

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
      1 GB log (`BIG=1`) and a measurement against flow
- [ ] The dogfood pass that closes Phase 4 (`docs/dogfooding.md`), with
      its measurement against flow

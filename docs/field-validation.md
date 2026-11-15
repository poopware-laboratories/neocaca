# Field validation

Unit and integration tests establish that each piece of neocaca does what
its tests specify. Field validation establishes something the tests
cannot: that a person can carry out real work in the editor. During a
**field validation pass**, neocaca is the only editor used, for one
sitting, on real tasks, in the build that users run, and every obstacle
encountered is recorded.

> [!NOTE]
> The first pass found five problems that several hundred tests had
> missed. The results of every pass are kept in the [log](#log) at the
> end of this document.

**Contents:** [When a pass is due](#when-a-pass-is-due) ·
[Preparation](#preparation) · [The scenarios](#the-scenarios) ·
[Against flow](#against-flow) · [Reporting](#reporting) · [Log](#log)

## When a pass is due

A pass is a roadmap piece in its own right (size M, about an hour) and is
listed in [`TODO.md`](../TODO.md). It is due:

| Occasion | Scope | Measured against flow |
|----------|-------|:---------------------:|
| Before a phase is marked complete; the last item of every phase is its pass | Every scenario | Yes |
| Before every release | Every scenario | Yes |
| After a piece that changes how files are opened, saved or shown | The scenarios that piece affects | No |

A change to rendering alone is covered instead by "Verifying UI changes"
in [`AGENTS.md`](../AGENTS.md#verifying-ui-changes).

## Preparation

### The build and the corpus

```sh
zig build -Doptimize=safe                                # the build users run
make optimized-install                                   # or the installed build: LTO and BOLT
scripts/field-validation-corpus.sh ~/validation          # the same files on every pass
BIG=1 scripts/field-validation-corpus.sh ~/validation    # with a 1 GB log, before a release
```

The corpus contains:

- a clone of this repository;
- a 100 MB server log, a 20 MB minified JSON line and a CSV file of one
  million rows;
- files from other systems: CRLF line ends, a byte order mark, a
  `Makefile`, and a file without a final newline;
- text that is difficult to measure: wide characters, emoji, combining
  marks and right-to-left text;
- hostile content: escape sequences, invalid UTF-8 and an executable;
- paths that are not plain files: symbolic links (one dangling), a hard
  link, read-only and unreadable files, and a directory.

The corpus must be created and used by a user other than root, so that
its permissions take effect.

### The terminal

A real terminal is preferred, and each pass should also use a second one
at least once (another emulator, tmux, or a terminal over SSH). An agent
without a screen drives tmux instead; the `field-validation` skill lists
the commands and the pitfalls (Esc followed at once by a key arrives as
Alt plus that key, and tmux treats a trailing `;` as a command separator).

## The scenarios

Each scenario is a task, not a key sequence. Carry it out as it would be
done at work, and record whatever is slow, surprising, unsightly or
impossible. A shortcoming the roadmap already lists is recorded once, with
its roadmap item, and not reported again.

1. **Changing the code.** In `repo/`, make a real change using neocaca
   alone: rename an identifier throughout a file (`%`, `s`, `c`), reorder
   a block of imports and correct a doc comment; then suspend with
   `Ctrl-z`, build and run the tests from the shell, and return with `fg`.
2. **Serving as the Git editor.** Run `GIT_EDITOR=neocaca git commit` in
   `repo/` (`GIT_EDITOR` takes precedence over `core.editor` and `EDITOR`),
   write the message, save and quit. Repeat, quitting without saving: the
   commit must be aborted. Repeat once more with `:w` and `:q` typed in
   quick succession: the quit waits for the save and the commit goes
   through.
3. **Reading a log.** Open `server.log`, go to the end, search backwards
   for an `ERROR`, keep only the error lines (`%`, `Alt-s`, `Alt-k`) and
   inspect a stack trace. Time the opening and every search.
4. **Editing data.** In `data.csv`, change one column on a thousand rows
   at once with multiple selections. In `minified.json`, find a key on the
   single 20 MB line and change it. Repeat both with `:wrap`: the rows of
   `data.csv` wrap under their numbers and the cursor stays in view down
   them; `Ctrl-f`, `Ctrl-b` and `vt` page and place by rows, never past
   what fits; and the 20 MB line, past the 1 MiB limit, still scrolls
   sideways without slowing typing.
5. **Files from other systems.** Edit `windows.txt`, `bom.txt`,
   `no-final-newline.txt` and the `Makefile`, save them, and compare the
   bytes with `cmp` or `od -c`: only the edit may differ.
   - In `windows.txt`, no `^M` is shown, and added lines (Enter, `o`, a
     paste) end in CRLF like the others.
   - In `bom.txt`, no glyph appears before the first character, and the
     mark is still first on disk after `%d` and `:w`.
   - `no-final-newline.txt` still ends without a newline after an edit,
     and an empty file saved unchanged remains empty.
6. **Hostile files.** Open `escapes.txt` and `binary`. Nothing may reach
   the terminal raw (its title, colors and screen remain as they were),
   and moving through the files must not crash the editor.
7. **Text that is difficult to measure.** Move through `unicode.txt` one
   character at a time. The cursor must never land inside a character or
   be drawn over its neighbor.
8. **Paths that are not plain files.**
   - `a-directory`: open it, and write to it: `:w a-directory/` must
     report that it is a directory.
   - `link-to-unicode.txt`: saving keeps the link. Open
     `dangling-link.txt` as well.
   - `read-only.txt`: `:w` is refused with the reason, and `:w!` writes
     the file and leaves it read-only.
   - `hard-link-to-unicode.txt`: `:w` is refused because the file has
     other links, and `:w!` writes it while leaving `unicode.txt` as it
     was.
   - `unreadable.txt`, and a file in a directory that does not exist.
   - A file given another of the user's groups (`chgrp`) and the
     set-group-ID bit (`chmod g+s`): both remain after `:w`.
9. **A misbehaving terminal.**
   - Resize down to a single cell and back, and paste a large block.
   - Close the terminal window with unsaved changes: the recovery file
     must hold them. Repeat with `kill <pid>` from another shell: the
     terminal must be restored as it was.
   - Suspend in the middle of a prompt and in insert mode, with `Ctrl-z`
     and with `kill -TSTP <pid>` from another shell: the shell's prompt
     must appear clean, and `fg` must return to the same mode, redrawn and
     in raw mode, with nothing typed.
   - Stop the editor once with `kill -STOP <pid>`: after `fg` it must be
     redrawn and in raw mode as well.
10. **Disk and file system faults.**
    - Save while the disk is full or a size limit applies (`ulimit -f 1`
      in the shell that starts neocaca; its `SIGXFSZ` must not end the
      editor): the original file must be untouched and the error shown.
    - Kill the editor (`kill -9`) while it saves `server.log`: the
      original must be intact, and any temporary file left beside it must
      be named after it (`.server.log.<random>.tmp`).
    - Append a line to an open file from another shell: `:w` must refuse
      and report that the file changed on disk, keeping the line, and
      `:w!` must write over it.
    - Append again, switch to another window and back: the editor must
      report the change as soon as it regains the focus, before any key is
      typed (in a terminal that sends focus events; tmux requires
      `set -g focus-events on`).
11. **What the phase added.** Every pass also exercises the features
    merged since the previous pass, in the same task-oriented way.

> [!IMPORTANT]
> The scenarios grow with the editor. A piece that adds something users do
> (a command, a mode, a file type, a protocol) adds its scenario here in
> the same pull request, so that the next pass covers it. A scenario that
> no longer applies is rewritten rather than left to become obsolete.

## Against flow

neocaca aims to surpass [flow](https://flow-control.dev) in every
respect, and that aim is a measurement, not an impression. Every pass that
closes a phase, and every pass before a release, measures the two editors
against each other; a short pass after a single piece does not.

1. **Run the comparison** against the binary of flow's latest release,
   downloaded from its releases page with its checksum verified:
   `zig build compare -Dflow=path/to/flow`. Use the same machine as the
   previous pass where possible. The command builds neocaca in
   ReleaseSafe itself.
2. **Replace the "Measured" table** in the yardstick section of
   [`TODO.md`](../TODO.md) with the new figures and flow's version, and
   state beneath it which rows changed since the previous pass, and why,
   where known.
3. **Update "Still behind"** from flow's user-facing documentation only
   (its README, manual, devlog and release notes since the previous pass;
   never its source code). A feature flow has added becomes a row with its
   roadmap item; a feature neocaca has shipped moves to "Already ahead".
4. **Give every lost row a roadmap item.** A measurement in which neocaca
   is slower, uses more memory or refuses what flow opens, and any row
   that worsened since the previous pass, becomes a piece in the current
   phase under a "behind flow" pull request, unless an existing item
   already covers it. A feature only flow offers receives its row in
   "Still behind". A phase is not closed while a lost row lacks an item.

## Reporting

- **Every finding becomes a roadmap piece** in [`TODO.md`](../TODO.md),
  under a "fixes from the field validation pass" pull request in the
  current phase, stating what was done, what happened and what should
  have happened. Measurements are added to the existing item they
  concern. Nothing is fixed during the pass itself.
- **Severe findings take priority.** A crash, lost data, or bytes reaching
  the terminal raw is never a minor issue: it is fixed before anything
  else on the roadmap.
- **Every pass adds a row to the log** below, so that results can be
  compared across passes. Measurements are taken in ReleaseSafe on the
  same corpus. The flow column names the flow release measured and the
  number of rows of "Measured" that neocaca still loses, or "not run" for
  a short pass.

## Log

| Date | Phase | Open 100 MB / 50 MB | Typing (ms per key) | `%` `s` on the large file | Against flow | Findings |
|------|-------|---------------------|---------------------|---------------------------|--------------|----------|
| 2026-10-22 | 1 | 50 MB: under 1 s | 50 on 50 MB, instant on small files | 9.6 million selections, 5 s frozen, 830 MB | not run | 5 minor issues ([#12](https://github.com/poopware-laboratories/neocaca/pull/12)); this guide was written afterwards, from a hand-made corpus |
| 2026-10-23 | 1 | 100 MB: 1.0 s, 231 MB | 100 on 100 MB, 35 on the 31 MB CSV, 50 there with 1000 cursors | `a`: 2.8 million selections, 1.5 s, 457 MB | not run | 1 crash (`SIGXFSZ`), 4 minor issues ([#14](https://github.com/poopware-laboratories/neocaca/pull/14)); tmux only, as a user other than root |
| 2026-10-23 | 1 (short: 8, 9, 10) | not measured | not measured | not measured | not run | nothing new; the known overwrite of a file changed on disk (Phase 2) observed again ([#15](https://github.com/poopware-laboratories/neocaca/pull/15)); a fresh corpus, tmux, as a user other than root |
| 2026-10-23 | 1 (flow only) | 100 MB: 403 ms, 232 MB | 0.66 on 1 MB | 10,000 selections: 4.8 ms, 2.2 ms for the first key | flow 0.7.2: 4 of 15 rows lost (memory at startup and on 1 MB, the 1 GB file refused) | the first measurement, without scenarios ([#16](https://github.com/poopware-laboratories/neocaca/pull/16)) |

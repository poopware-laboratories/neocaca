# Dogfooding

Tests prove that each piece does what its test says. A dogfood pass checks
something different: whether a person can get real work done in neocaca.
For one sitting, use it as your only editor on real tasks, in the build
users run, and write down everything that gets in the way. The first pass
found five problems that hundreds of tests had missed (see the log at the
end).

## When

A pass is a piece of its own (M, about an hour), listed in `TODO.md`:

- **before a phase is ticked done**: the last item of every phase is its
  dogfood pass;
- **before every release**. These two passes also measure neocaca
  against flow ("Against flow" below);
- **after a piece that changes how files are opened, saved or shown**, a
  shorter pass over the scenarios that piece touched. A rendering change
  alone is covered by "Verifying UI changes" in `AGENTS.md`.

## Setting up

```sh
zig build -Doptimize=safe                    # the build users run
scripts/dogfood-corpus.sh ~/dogfood          # the same files every pass
BIG=1 scripts/dogfood-corpus.sh ~/dogfood    # with a 1 GB log, before a release
```

The corpus is a clone of this repository, a 100 MB server log, a 20 MB
minified JSON line, a CSV of a million rows, CRLF, BOM and Makefile
files, a file without a final newline, wide, emoji, combining and
right-to-left text, escape sequences and invalid UTF-8, an executable,
symlinks (one dangling), a hard link, read-only and unreadable files,
and a directory.
Run it as a user who is not root, so the permissions mean something.

Use a real terminal when you can, and at least once a pass a second one
(another emulator, tmux, or a terminal over ssh). An agent without a
screen drives tmux instead: the `dogfooding` skill has the commands and
the traps (Esc then a key sent at once arrives as Alt plus the key; tmux
treats a trailing `;` as a command separator).

## The scenarios

Each scenario is a task, not a key: do it the way you would at work and
note what was slow, surprising, ugly or impossible. A gap the roadmap
already lists is noted once with its item, not reported again.

1. **Change the code.** In `repo/`, make a real change with neocaca alone:
   rename an identifier everywhere in a file (`%`, `s`, `c`), reorder a
   block of imports, fix a doc comment, then build and run the tests from
   the shell after `Ctrl-z`, and come back with `fg`.
2. **Be the Git editor.** `GIT_EDITOR=neocaca git commit` in `repo/`
   (`GIT_EDITOR`, which wins over `core.editor` and `EDITOR`): write the
   message, save and quit; then once more and quit without saving, which
   must abort the commit.
3. **Read a log.** Open `server.log`: jump to the end, search back for an
   `ERROR`, keep only the error lines (`%`, `Alt-s`, `Alt-k`), and look at
   a stack trace. Time the open and every search.
4. **Edit data.** In `data.csv`, change one column on a thousand rows at
   once with multiple selections; in `minified.json`, find a key on the one
   20 MB line and change it.
5. **Files from elsewhere.** Edit `windows.txt`, `bom.txt`,
   `no-final-newline.txt` and the `Makefile`, save, and compare the bytes
   with `cmp` or `od -c`: only your edit may differ. In `windows.txt` no
   `^M` shows, and the lines you add (Enter, `o`, a paste) end in CRLF
   like the others. In `bom.txt` no glyph shows before the first
   character, and the mark is still first on disk after `%d` and `:w`.
   `no-final-newline.txt` still ends without a newline after an edit,
   and an empty file saved untouched stays empty.
6. **Hostile files.** Open `escapes.txt` and `binary`: nothing may reach
   the terminal raw (the title, colors and screen stay as they were), and
   moving through them must not crash.
7. **Text that is hard to measure.** Move through `unicode.txt` a
   character at a time; the cursor must never land inside a character or
   draw over its neighbor.
8. **Paths that are not plain files.** Open `a-directory`,
   `link-to-unicode.txt` (saving keeps the link), `dangling-link.txt`,
   `read-only.txt` (`:w` must refuse and say why, `:w!` must write it
   and leave it read-only), `hard-link-to-unicode.txt` (`:w` must
   refuse and say it has other links, `:w!` must write it and leave
   `unicode.txt` as it was), `unreadable.txt`, and a file in a
   directory that does not exist. Give a file another of your groups
   (`chgrp`) and the set-group-ID bit (`chmod g+s`): both are still
   there after `:w`.
9. **The terminal misbehaves.** Resize down to one cell and back; paste a
   large block; close the terminal window with unsaved changes (the
   recovery file must hold them), and again with `kill <pid>` from another
   shell (the terminal must come back as it was); suspend in the middle of a prompt and
   in insert mode (`fg` must come back to the same mode, nothing typed).
10. **Disk and filesystem trouble.** Save while the disk is full or a size
    limit applies (`ulimit -f 1` in the shell that starts neocaca; its
    `SIGXFSZ` must not kill the editor): the original file must be
    untouched and the error shown. Kill the editor (`kill -9`) while it
    saves `server.log`: the original must be whole, and a temporary file
    left beside it must be named after it (`.server.log.<random>.tmp`).
    Append a line to an open file from another shell: `:w` must refuse
    and say the file changed on disk, keeping the line, and `:w!` must
    write over it.
11. **What this phase added.** Every pass also works through the features
    merged since the last one, in the same task-first way.

Scenarios grow with the editor. A piece that adds something users do (a
command, a mode, a file type, a protocol) adds its scenario here in the
same pull request, so the next pass covers it without anyone remembering
to. A scenario that no longer applies is rewritten, not left to rot.

## Against flow

neocaca aims to be ahead of [flow](https://flow-control.dev) in every
way, and "ahead" is a measurement, not a feeling. A pass that closes a
phase, and every pass before a release, also measures the two against
each other; a short pass after a single piece does not.

1. **Run the comparison** against flow's latest release binary (from its
   releases page, its checksum checked): `zig build compare
   -Dflow=path/to/flow`, on the same machine as the last pass when you
   can, which builds neocaca in ReleaseSafe on its own.
2. **Replace the "Measured" table** in the yardstick section of `TODO.md`
   with the new numbers and flow's version, and say under it which rows
   moved since the last pass, and why if you know.
3. **Bring "Still behind" up to date** from flow's user-facing
   documentation only (its README, manual, devlog and release notes since
   the last pass; never its source): a feature flow added becomes a row
   with its item, one neocaca shipped moves to "Already ahead".
4. **Every row neocaca loses gets an item.** A measurement where it is
   slower, uses more memory or refuses what flow opens, and a row that got
   worse since the last pass, becomes a piece in the current phase under a
   "behind flow" pull request, unless an item already covers it. A
   feature only flow has gets its row in "Still behind". A phase is not
   closed with a lost row that has no item.

## Reporting

- Every finding becomes a piece in `TODO.md`, under a "fixes from the
  dogfood pass" pull request in the current phase, with what was done,
  what happened and what should have; measured numbers go into the
  existing item they belong to. Nothing is fixed during the pass itself.
- A crash, lost data or bytes reaching the terminal raw is never a rough
  edge: it is fixed before anything else on the roadmap.
- The pass adds a line to the log below, so the numbers can be compared
  across passes. Measure in ReleaseSafe on the same corpus. The flow
  column says which flow release the pass measured against and how many
  rows of "Measured" neocaca still loses, or "not run" for a short pass.

## Log

| Date | Phase | Open 100 MB / 50 MB | Typing (ms a key) | `%` `s` on the big file | Against flow | Findings |
|------|-------|---------------------|-------------------|--------------------------|--------------|----------|
| 2026-10-22 | 1 | 50 MB: under 1 s | 50 on 50 MB, instant on small files | 9.6 million selections, 5 s frozen, 830 MB | not run | 5 rough edges ([#12](https://github.com/poopware-laboratories/neocaca/pull/12)); this guide written after it, from a hand-made corpus |
| 2026-10-23 | 1 | 100 MB: 1.0 s, 231 MB | 100 on 100 MB, 35 on the 31 MB CSV, 50 there with 1000 cursors | `a`: 2.8 million selections, 1.5 s, 457 MB | not run | 1 crash (`SIGXFSZ`), 4 rough edges ([#14](https://github.com/poopware-laboratories/neocaca/pull/14)); tmux only, as a user who is not root |
| 2026-10-23 | 1 (short: 8, 9, 10) | not measured | not measured | not measured | not run | nothing new; the known change-on-disk overwrite (Phase 2) seen again ([#15](https://github.com/poopware-laboratories/neocaca/pull/15)); a fresh corpus, tmux, as a user who is not root |
| 2026-10-23 | 1 (flow only) | 100 MB: 403 ms, 232 MB | 0.66 on 1 MB | 10,000 selections: 4.8 ms, 2.2 ms the first key | flow 0.7.2: 4 of 15 rows lost (memory at startup and on 1 MB, the 1 GB file refused) | the first measurement, no scenarios ([#16](https://github.com/poopware-laboratories/neocaca/pull/16)) |

---
name: dogfooding
description: Use when doing a neocaca dogfood pass (the last item of a phase, before a release, or after a piece that changes how files are opened, saved or shown), or when asked to try the editor on real work.
---

# A dogfood pass

`docs/dogfooding.md` is the reference: when a pass is due, the scenarios
and how to report. This is how to run it without a screen.

## 1. Set up

```sh
zig build -Doptimize=safe
scripts/dogfood-corpus.sh "$SCRATCH/dogfood"   # an empty directory
```

`$SCRATCH` is your scratch directory: the corpus never goes in the
repository.

## 2. Drive it through tmux

```sh
B="$PWD/zig-out/bin/neocaca"
tmux new-session -d -s nc -x 80 -y 24 "cd $SCRATCH/dogfood && $B server.log; echo EXIT=\$?; sleep 600"
tmux send-keys -t nc -l '%'                # -l: the text as it is
tmux send-keys -t nc Enter                 # named keys without -l
tmux capture-pane -t nc -p                 # the screen as text (-e for colors)
tmux resize-window -t nc -x 20 -y 5
```

The traps, each of which looks like an editor bug the first time:

- **Esc, then a key, sent at once arrive as Alt plus the key**, because
  the legacy encoding cannot tell them apart within 25 ms. Send `Escape`,
  wait (`sleep 0.1`), then the next key.
- **A trailing `;` ends the tmux command.** Send `';'` on its own with
  `-l`, or put it mid-string.
- **Read the status line, not the last row.** The last row is the
  message line; the status is the one above.
- **Wait on the screen, not a guess.** Time an action by polling
  `capture-pane` for the expected status (`grep -q ' 1:1$'`), and check
  the pattern matches before trusting a long time as slow.
- **`echo EXIT=$?; sleep` in the session** keeps the pane after neocaca
  exits, so the exit code and anything printed stay readable.
- **Set `GIT_EDITOR`, not `EDITOR`,** for the Git scenario: a session
  may export `GIT_EDITOR=true`, which makes `git commit` abort at once
  without starting neocaca.
- **Root ignores file permissions.** As root, `unreadable.txt` behaves
  like a plain file (`read-only.txt` is refused by its mode, even for
  root, but nothing else about permissions is). Make a user and run the
  corpus script, the editor and tmux as that user, or say in the report
  that these were not checked:

  ```sh
  useradd -m dog && cp zig-out/bin/neocaca /home/dog/
  runuser -u dog -- scripts/dogfood-corpus.sh /home/dog/dogfood
  runuser -u dog -- tmux new-session -d -s nc -x 80 -y 24 "cd ~/dogfood && exec sh"
  ```

- **A full disk is a small tmpfs** (as root): `mount -t tmpfs -o
  size=64k,mode=0777 tmpfs /home/dog/full`, a file to edit in it, then
  fill the rest with `dd if=/dev/zero of=/home/dog/full/filler`.

Memory: `ps -o rss= -C neocaca` while the scenario holds the state.

## 3. Work the scenarios

Every scenario in `docs/dogfooding.md`, as tasks, plus what the phase
added. Note each surprise with its file, its keys from a fresh start,
what happened and what should have.

## 4. Against flow (phase or release passes)

Download flow's latest release, check its checksum, unpack it in its own
empty directory under `$SCRATCH`, and run:

```sh
zig build compare -Dflow="$SCRATCH/flow/flow"
```

Then follow "Against flow" in `docs/dogfooding.md`: the "Measured" table
in `TODO.md` replaced, "Still behind" updated from flow's documentation
(never its source), and an item for every row neocaca loses.

## 5. Report

- Each finding a `TODO.md` piece; numbers into the items they measure;
  a line in the log of `docs/dogfooding.md`, its flow column included;
  the pass ticked in `TODO.md`.
- Crashes, lost data and raw bytes on the terminal go first, before any
  other piece.
- Fix nothing during the pass. The pull request is docs only.

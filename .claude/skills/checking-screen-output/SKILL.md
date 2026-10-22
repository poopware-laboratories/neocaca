---
name: checking-screen-output
description: Use when changing anything neocaca shows (src/render, src/ui, the status line, gutter, cursor, colors, scrolling, wrapping, wide characters) or the escape bytes it writes, before claiming the change looks right.
---

# Checking screen output

A rendering change is verified three ways: `Screen` tests, escape-output
tests, and looking at the editor in a real terminal.

## 1. Screen tests

Drawing produces a `render.Screen`, a grid of cells. Assert on it a row
at a time, as text, so failures show a readable diff. A drawing function
is tested on its own (`src/ui/status_test.zig`):

```zig
test "status: modified buffers, several selections and pending keys" {
    var info = base;
    info.modified = true;
    info.selections = 4;
    info.pending = "2\"a";
    info.mode = .insert;
    try expectStatus(40, info, " INSERT  main.zig [+]  2\"a  4 sels  3:7 ");
}
```

and a whole session through `tests/harness.zig`, which types keys and
reads back rows:

```zig
test "display: escape sequences in a file are shown, never sent" {
    var h: Harness = undefined;
    try h.init("evil", "\x1b]0;owned\x07\x1b[2J\x9b1m\n", 40, 3);
    defer h.deinit();
    try expect(!contains(h.written(), "\x1b]"));
    try h.expectRow(0, " 1 ^[]0;owned^G^[[2J\u{fffd}1m                 ");
}
```

Cover: the narrowest size that should still work, one column and one row,
a resize, wide and combining characters at the right edge, tabs, and long
lines (scrolled or wrapped). Style assertions (colors, reverse video) use a
style dump beside the text dump.

## 2. Escape-output tests

`render.diff(old, new, writer)` turns two screens into bytes
(`src/render/diff_test.zig`). Test the exact bytes for small cases, that an
unchanged screen writes nothing, that a new size redraws everything, and
that hostile cell text never reaches the terminal as control bytes. Whole
sessions check the same through `h.written()`.

## 3. Look at it

```sh
zig build
tmux new-session -d -s nc -x 80 -y 24 'zig-out/bin/neocaca /tmp/sample.txt'
tmux send-keys -t nc 'ihello' Escape
tmux capture-pane -t nc -p -e > after.txt   # -e keeps colors
tmux resize-window -t nc -x 40 -y 10        # check the resize path
tmux kill-session -t nc
```

Use a sample file with a wide character, a combining mark,
a tab, a control byte and a line longer than the window. Capture before
and after your change and diff them; every difference must be intended.
Also check, once, in a real terminal with a light and a dark theme, and
that quitting restores the terminal (`stty -a` shows cooked mode, no
alternate screen left behind).

## Also

- Never rely on color alone to carry meaning (modified, errors,
  selection); add a character or attribute too.
- Put before/after captures in the pull request.

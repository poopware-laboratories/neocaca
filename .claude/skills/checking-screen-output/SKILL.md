---
name: checking-screen-output
description: Use when changing anything neocaca shows (src/render, src/ui, the status line, gutter, cursor, colors, scrolling, wrapping, wide characters) or the escape bytes it writes, before claiming the change looks right.
---

# Checking screen output

A rendering change is verified three ways: `Screen` tests, escape-output
tests, and looking at the editor in a real terminal.

## 1. Screen tests

Layout and drawing produce a `render.Screen`, a grid of cells. Assert on
it as text, one string per row, so failures show a readable diff:

```zig
test "status line shows a modified marker" {
    var screen = try renderFor(std.testing.allocator, .{ .text = "x", .modified = true }, .{ .cols = 20, .rows = 3 });
    defer screen.deinit();
    try std.testing.expectEqualStrings("x                   \n" ++
        "~                   \n" ++
        "[+] untitled    1:1 ", try screen.dumpText(std.testing.allocator));
}
```

Cover: the narrowest size that should still work, one column and one row,
a resize, wide and combining characters at the right edge, tabs, and long
lines (scrolled or wrapped). Style assertions (colors, reverse video) use a
style dump beside the text dump.

## 2. Escape-output tests

`render.diff(old, new, writer)` turns two screens into bytes. Test the
exact bytes for small cases, and the invariant for random ones: applying
the diff output to `old` (with the test-only screen interpreter) gives
`new`, and an unchanged screen writes nothing. Partial redraws must equal a
full redraw.

## 3. Look at it

```sh
zig build
tmux new-session -d -s nc -x 80 -y 24 'zig-out/bin/neocaca /tmp/sample.txt'
tmux send-keys -t nc 'ihello' Escape
tmux capture-pane -t nc -p -e > after.txt   # -e keeps colors
tmux resize-window -t nc -x 40 -y 10        # check the resize path
tmux kill-session -t nc
```

Use a sample file with styled syntax, a wide character, a combining mark,
a tab, a control byte and a line longer than the window. Capture before
and after your change and diff them; every difference must be intended.
Also check, once, in a real terminal with a light and a dark theme, and
that quitting restores the terminal (`stty -a` shows cooked mode, no
alternate screen left behind).

## Also

- Never rely on color alone to carry meaning (modified, errors,
  selection); add a character or attribute too.
- Put before/after captures in the pull request.

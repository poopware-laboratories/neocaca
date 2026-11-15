# Key reference

This document is the reference for caca's modal key bindings. The
editing model (selection first, verb second, multiple selections) is
described in [`AGENTS.md`](../AGENTS.md#keybinding-model-kakoune-inspired).
The bindings are implemented in `src/input/keymap.zig`, and every binding
listed here is tested in `src/input/keymap_test.zig` (the verbs in
`keymap_verb_test.zig`). Bindings not yet implemented are listed on the
roadmap in [`TODO.md`](../TODO.md).

**Contents:** [Normal mode](#normal-mode) · [Insert mode](#insert-mode) ·
[Prompt](#prompt) · [Commands](#commands) · [Mappings](#mappings)

> [!NOTE]
> **Notation.** `Alt-x` is the Alt key with `x` (or Esc followed by `x`);
> `Ctrl-x` is the Control key with `x`. A *selection* spans from its
> *anchor* to its *cursor*, both inclusive, and always holds at least one
> character. Moves **replace** each selection; the Shift form (the
> upper-case key, or Shift with an arrow) **extends** it from its anchor.

## Normal mode

### Counts and registers

| Keys | Action |
|------|--------|
| `0`–`9` | count for the next command (`3w`, `5j`), at most 1000000 |
| `"x` | use register `x` (a printable ASCII character) for the next yank, delete, change or paste (default `"`) |
| Esc | cancel a count, register or unfinished key |

### Moving and selecting

| Keys | Action |
|------|--------|
| `h` `j` `k` `l`, arrows | one character left, down, up, right (`H J K L` extend) |
| `w` / `W` | select to the start of the next word / extend |
| `e` / `E` | select to the end of the word / extend |
| `b` / `B` | select back to the start of the word / extend |
| `Alt-w` `Alt-e` `Alt-b` | the same over WORDs (runs of non-blanks); add Shift to extend |
| `x` | select the whole line (again: the next line too) |
| `X` | select every line the selection touches (again: the next line too) |
| `%` | select the whole buffer |
| `f<c>` / `F<c>` | select to the next `c`, inclusive / extend |
| `t<c>` / `T<c>` | select up to the next `c`, exclusive / extend |
| `Alt-f<c>` `Alt-t<c>` | the same, backwards |
| `m` / `M` | select to the matching bracket / extend |
| `gh` `gl`, Home, End | line start / end (Shift-Home, Shift-End extend) |
| `gi` | first non-blank of the line |
| `gg` `gk` | buffer start |
| `ge` `gj` | last line |
| `G` + one of the above | extend instead of move |
| `<count>g` | go to line `count` |
| `Ctrl-d` `Ctrl-u` | half a page down / up |
| `Ctrl-f` `Ctrl-b`, PageDown, PageUp | a page down / up |
| `vc` `vv` / `vt` / `vb` | put the cursor's line in the middle / at the top / at the bottom of the view |
| `vj` / `vk` | scroll the view a line down / up (with a count, that many), the cursor moving only to stay in view |
| `vh` / `vl` | scroll the view a column left / right (with a count, that many), the cursor moving along its line only to stay in view; only with `:nowrap`, or on a line too long to wrap |

Lines wrap by default, and then the page keys and `vj` `vk` `vt` `vc`
`vb` count screen rows rather than lines: a page is the rows of the
window, `vt` `vc` `vb` place the cursor's row, and `vj` `vk` scroll by
rows. The cursor moves along a long line from row to row, keeping its
column within the row. With `:nowrap` they count lines.

### Shaping the selections

| Keys | Action |
|------|--------|
| `;` | reduce each selection to its cursor |
| `Alt-;` | swap anchor and cursor |
| `Alt-:` | make every selection forward (anchor before cursor) |
| `,` | keep only the main selection |
| `Alt-,` | drop the main selection |
| `C` / `Alt-C` | copy the main selection's shape to the next / previous line |
| `(` / `)` | make the previous / next selection the main one |
| `Alt-)` / `Alt-(` | rotate the selections' contents forward / backward: each takes the text of the one before (after) it |
| `s` | prompt for a regex; select its matches inside the selections |
| `S` | prompt for a regex; split the selections at its matches |
| `Alt-s` | split the selections into lines |
| `Alt-k` / `Alt-K` | keep / drop the selections that match a regex |
| `Alt-i<o>` | select inside object `o` |
| `Alt-a<o>` | select around object `o` |
| `Alt-x` | trim each selection to the whole lines inside it; those without one are dropped |

Objects: `w` word, `W` WORD, `(` `)` `b` parentheses, `[` `]` brackets,
`{` `}` `B` braces, `<` `>` angle brackets, `"` `'` `` ` `` quotes, `p`
paragraph. A selection with no such object around it stays as it is; when
none of them has one, the message line says "no object here".

There are at most 1,048,576 selections, one for every line of a CSV of a
million rows and its header. `s`, `S`, `Alt-s`, `C` and `N` that would
make more change nothing, and the message line says "too many selections
(more than 1048576)".

### Search

| Keys | Action |
|------|--------|
| `/` / `?` | prompt for a regex; select the next / previous match |
| `n` / `N` | select the next match / add the next match as a new selection |
| `Alt-n` | select the previous match |
| `*` | use the main selection, escaped, as the search pattern |

### Verbs

| Keys | Action |
|------|--------|
| `d` | yank and delete the selections |
| `Alt-d` | delete without yanking |
| `c` | yank, delete, enter insert mode |
| `Alt-c` | change without yanking |
| `y` | yank the selections |
| `p` / `P` | paste after / before each selection |
| `R` | replace the selections with the register |
| `r<c>` | replace every character of the selections with `c` |
| `~` / `` ` `` / `` Alt-` `` | upper case / lower case / swap case |
| `>` / `<` | indent / dedent the selected lines |
| `Alt-j` | join the selected lines (`J` extends down) |
| `u` / `U` | undo / redo |
| `i` / `a` | insert before / after each selection |
| `I` / `A` | insert at the line start (first non-blank) / line end |
| `o` / `O` | open a new line below / above and insert |
| `:` | command prompt |
| `Ctrl-z` | suspend: give the terminal back to the shell until `fg` (in every mode, which `fg` comes back to); `kill -TSTP` does the same |

## Insert mode

| Keys | Action |
|------|--------|
| text | inserted at every cursor |
| Enter | new line, keeping the current line's indentation |
| Tab | a tab character |
| Backspace / Delete | delete the character before / under every cursor |
| arrows, Home, End | move every cursor |
| Esc | back to normal mode (the insert session is one undo step) |
| bracketed paste | inserted literally at every cursor |
| `Ctrl-z` | suspend, as in normal mode |

## Prompt

| Keys | Action |
|------|--------|
| text, Backspace, Delete, Left, Right, Home, End | edit the prompt line (Tab types a space) |
| bracketed paste | inserted at the prompt's cursor, line ends and tabs as spaces, other control characters dropped |
| Enter | run it |
| Esc, Backspace on an empty prompt | cancel |
| `Ctrl-u` | clear the prompt line |
| `Ctrl-z` | suspend, keeping the prompt as typed |

### Commands

| Command | Action |
|---------|--------|
| `:w [file]`, `:write` | write the buffer (atomically), optionally to `file`; refused for a read-only file, and for the open file once something else changed it on disk |
| `:w! [file]` | write, a read-only file (it stays read-only), one changed on disk or one with other hard links (only this name gets the new text) too |
| `:q`, `:quit` | quit; refused while any open buffer has unsaved changes (when it is not the current one, the message names it). Typed while a save of the text is still being written, it waits for the save (keys typed meanwhile are dropped), then quits, or stays if the save failed |
| `:q!` | quit, discarding the changes in every buffer |
| `:wq [file]` | write, optionally to `file`, then quit, unless another buffer has unsaved changes |
| `:x` | write only if there are unsaved changes, then quit, unless another buffer has unsaved changes |
| `:e <file>`, `:edit` | open `file` in a new buffer after the others and make it current, keeping the unsaved changes of the one left; switch to it if it is already open (the path as typed). An empty, unmodified buffer without a file gives its place to it. `:e` of the current file reloads it, refused while there are unsaved changes. During a save it waits, as `:q` does |
| `:e! [file]` | reload the current file from disk, discarding changes; with another `file`, as `:e` |
| `:bn`, `:bnext` | switch to the next buffer, from the last to the first; refused while the current buffer is being saved |
| `:bp`, `:bprevious` | switch to the previous buffer, from the first to the last; likewise |
| `:<n>` | go to line `n` |
| `:map <mode> <key> <keys>` | in `normal` or `insert` mode, typing `key` types `keys` instead |
| `:unmap <mode> <key>` | forget the mapping of `key` in that mode |
| `:wrap` | wrap long lines onto the rows below, breaking after a blank where one fits; the view follows the cursor by rows (the default). A line over 1 MiB stays one row, scrolled sideways |
| `:nowrap` | show long lines on one row, scrolled sideways |

When the terminal window gets the focus back (terminals that send xterm
focus events, mode 1004), the editor looks at the open file on disk and
says so at once if something else changed it, before an edit is made on
the old text: `:e!` reloads it, `:w!` writes over it.

## Mappings

`:map normal <c-s> :w<ret>` makes Ctrl-S write the file. The keys a
mapping types are not mapped again, so a key can be mapped to itself or to
keys that are mapped too. A key that completes a prefix (the character
after `f`, the register name after `"`) and keys typed at the prompt are
never mapped; a count typed before a mapped key reaches the first key it
types. At most 256 keys are mapped at once, each to at most 32 keys;
mapping a key again replaces what it typed.

Keys are written in this notation, whose names stay stable:

| Notation | Key |
|----------|-----|
| `a`, `A`, `é`, `;` | that character (Shift is part of the character) |
| `<ret>` `<tab>` `<bs>` `<esc>` `<del>` `<ins>` | Enter, Tab, Backspace, Escape, Delete, Insert |
| `<up>` `<down>` `<left>` `<right>` | the arrows |
| `<home>` `<end>` `<pageup>` `<pagedown>` | Home, End, Page Up, Page Down |
| `<f1>` … `<f12>` | the function keys |
| `<lt>` `<gt>` `<space>` | `<`, `>`, a space |
| `<c-x>` `<a-x>` `<s-left>` | with Ctrl, Alt, Shift; combined as `<c-a-left>` |

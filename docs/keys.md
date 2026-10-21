# Keys

The reference for neocaca's modal keybindings. The model (selection first,
verb second, multiple selections) is described in `AGENTS.md`; the code is
`src/input/keymap.zig`, and every binding here has a test there. Bindings
marked *(planned)* are on the roadmap in `TODO.md`.

Notation: `Alt-x` is Alt (or Esc then x), `Ctrl-x` is Control. A *selection*
spans from its *anchor* to its *cursor*, both inclusive, and always holds at
least one character. Moves **replace** each selection; the Shift form (the
upper-case key, or Shift with an arrow) **extends** it from its anchor.

## Normal mode

### Counts and registers

| Keys | Action |
|------|--------|
| `0`–`9` | count for the next command (`3w`, `5j`) |
| `"x` | use register `x` for the next yank, delete, change or paste (default `"`) |

### Moving and selecting

| Keys | Action |
|------|--------|
| `h` `j` `k` `l`, arrows | one character left, down, up, right (`H J K L` extend) |
| `w` / `W` | select to the start of the next word / extend |
| `e` / `E` | select to the end of the word / extend |
| `b` / `B` | select back to the start of the word / extend |
| `Alt-w` `Alt-e` `Alt-b` | the same over WORDs (runs of non-blanks); add Shift to extend |
| `x` | select the whole line (again: the next line too) |
| `X` | extend to the whole line |
| `%` | select the whole buffer |
| `f<c>` / `F<c>` | select to the next `c`, inclusive / extend |
| `t<c>` / `T<c>` | select up to the next `c`, exclusive / extend |
| `Alt-f<c>` `Alt-t<c>` | the same, backwards |
| `m` / `M` | select to the matching bracket / extend |
| `gh` `gl` | line start / end |
| `gi` | first non-blank of the line |
| `gg` `gk` | buffer start |
| `ge` `gj` | last line |
| `G` + one of the above | extend instead of move |
| `<count>g` | go to line `count` |
| `Ctrl-d` `Ctrl-u` | half a page down / up |
| `Ctrl-f` `Ctrl-b`, PageDown, PageUp | a page down / up |

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
| `Alt-(` `Alt-)` | rotate the selections' contents *(planned)* |
| `s` | prompt for a regex; select its matches inside the selections |
| `S` | prompt for a regex; split the selections at its matches |
| `Alt-s` | split the selections into lines |
| `Alt-k` / `Alt-K` | keep / drop the selections that match a regex |
| `Alt-i<o>` | select inside object `o` |
| `Alt-a<o>` | select around object `o` |
| `Alt-x` | trim each selection to whole lines *(planned)* |

Objects: `w` word, `W` WORD, `(` `)` `b` parentheses, `[` `]` brackets,
`{` `}` `B` braces, `<` `>` angle brackets, `"` `'` `` ` `` quotes, `p`
paragraph.

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
| `Alt-j` | join the selected lines *(planned: `J` remains free)* |
| `u` / `U` | undo / redo |
| `i` / `a` | insert before / after each selection |
| `I` / `A` | insert at the line start (first non-blank) / line end |
| `o` / `O` | open a new line below / above and insert |
| `:` | command prompt |

## Insert mode

| Keys | Action |
|------|--------|
| text | inserted at every cursor |
| Enter | new line, keeping the current line's indentation |
| Tab | a tab character |
| Backspace / Delete | delete the character before / under every cursor |
| arrows | move every cursor |
| Esc | back to normal mode (the insert session is one undo step) |
| bracketed paste | inserted literally at every cursor |

## Prompt

| Keys | Action |
|------|--------|
| text, Backspace, Left, Right, Home, End | edit the prompt line |
| Enter | run it |
| Esc | cancel |

### Commands

| Command | Action |
|---------|--------|
| `:w [file]` | write the buffer (atomically), optionally to `file` |
| `:q` | quit; refused while there are unsaved changes |
| `:q!` | quit, discarding changes |
| `:wq`, `:x` | write, then quit |
| `:e <file>` | edit another file; refused while there are unsaved changes |
| `:e!` | reload the file from disk, discarding changes |
| `:<n>` | go to line `n` |

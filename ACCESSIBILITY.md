# Accessibility

neocaca runs inside your terminal emulator, so much of its accessibility
comes from the terminal: font, size, colors, contrast, zoom and screen
reader support are the terminal's, and neocaca is built to work with them
rather than against them. This page says what neocaca does, where it falls
short today, and how to tell us what gets in your way.

## What works today

**Keyboard only.** Every feature is a key or a `:` command; nothing needs
a mouse. Each binding is listed in [`docs/keys.md`](docs/keys.md).

**No racing the clock.** Prefix keys such as `g` and `v` wait for as long
as you need. The only timer is the 25 ms that separates a lone Esc from an
Alt key, and it only affects keys a terminal sends as one burst.

**Your own keys.** `:map` rebinds keys in normal and insert mode, for
example to move a binding that is hard to reach or to make one key do a
sequence (see "Mappings" in `docs/keys.md`).

**Your terminal's colors.** The interface uses only the sixteen basic
terminal colors, plus bold and reverse video. A light, dark or
high-contrast palette set in your terminal applies to neocaca too. It sets
no fixed RGB colors and never changes the terminal's palette.

**State in words, not only color.** The status line spells out the mode
(`NORMAL`, `INSERT`, `PROMPT`), the file name, `[+]` when there are unsaved
changes, the number of selections (`3 sels`) and the cursor position
(`line:column`). Errors and confirmations are text on the last line.

**A real cursor.** The terminal's own cursor sits on the main selection's
cursor, so screen magnifiers and screen readers that follow the cursor
follow your editing.

**Visible special characters.** Control characters show as `^[`-style
text and invalid bytes as U+FFFD, instead of blank or shifting space. Wide
characters, combining marks and tabs line up by display column.

**Small screens.** The layout adapts to any terminal size and to resizes,
so large fonts and zoomed terminals with few columns stay usable.

## Known gaps

These are open problems, not decisions:

- **Selections are told apart mostly by color.** The main selection and
  the others use different background colors; only the main cursor uses
  reverse video. The selection count and cursor position are in the status
  line, but which text is selected is not available without color.
- **No `NO_COLOR` support yet**, and no theme setting: there is no
  configuration file yet (see [`TODO.md`](TODO.md), Phase 2 and Phase 4).
- **No screen reader mode.** A screen reader reads the terminal's grid,
  gutter and status line included; there is no mode that announces only
  the text that changed or describes the selections.
- **Long lines do not wrap yet.** Text past the right edge is scrolled to
  rather than wrapped, which is harder to follow at large font sizes.
- **No mouse support yet**, for people for whom a pointer is easier than
  keys.

The roadmap items that close these gaps are in [`TODO.md`](TODO.md).

## Tell us what gets in your way

If you use a screen reader, a magnifier, switch access, an alternative
keyboard layout, a high-contrast theme or anything else that neocaca does
not work well with, please
[open an issue](https://github.com/poopware-laboratories/neocaca/issues)
and say:

- what you use (terminal emulator, assistive technology, operating
  system);
- what you tried to do and what happened instead.

Accessibility bugs are bugs. They are fixed the same way as others, with a
test first, and a fix that only one group of users notices is still worth
making.

## For contributors

When you change what the screen shows (see
[Verifying UI changes](AGENTS.md#verifying-ui-changes)):

- never make color the only sign of a state: give it a word or a symbol
  too;
- use the theme's styles (`src/ui/theme.zig`), which stay within the
  sixteen basic colors, rather than fixed colors;
- keep the terminal cursor on the main cursor;
- check a narrow terminal, and both a light and a dark theme;
- add nothing that depends on timing beyond the Esc timeout.

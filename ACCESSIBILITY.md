# Accessibility

neocaca runs inside a terminal emulator, so much of its accessibility
comes from the terminal: font, size, colors, contrast, zoom and screen
reader support all belong to the terminal, and neocaca is designed to
work with them rather than against them. This document describes what
neocaca provides, where it currently falls short, and how to report an
obstacle.

**Contents:** [Current support](#current-support) ·
[Known gaps](#known-gaps) · [Reporting an obstacle](#reporting-an-obstacle) ·
[Guidance for contributors](#guidance-for-contributors)

## Current support

| Area | Support |
|------|---------|
| **Keyboard only** | Every feature is a key or a `:` command; nothing requires a mouse. Each binding is listed in [`docs/keys.md`](docs/keys.md). |
| **No time pressure** | Prefix keys such as `g` and `v` wait indefinitely. The only timer is the 25 ms that distinguishes a lone Esc from an Alt key, and it affects only keys that a terminal sends as a single burst. |
| **Custom keys** | `:map` rebinds keys in normal and insert mode, for example to move a binding that is hard to reach, or to make one key type a sequence (see "Mappings" in [`docs/keys.md`](docs/keys.md#mappings)). |
| **The terminal's colors** | The interface uses only the sixteen basic terminal colors, with bold and reverse video. A light, dark or high-contrast palette configured in the terminal applies to neocaca as well. neocaca sets no fixed RGB colors and never changes the terminal's palette. |
| **State in words, not only color** | The status line states the mode (`NORMAL`, `INSERT`, `PROMPT`), the file name, `[+]` when there are unsaved changes, the number of selections (`3 sels`) and the cursor position (`line:column`). Errors and confirmations appear as text on the last line. |
| **A real cursor** | The terminal's own cursor is placed on the main selection's cursor, so magnifiers and screen readers that follow the cursor follow the editing. |
| **Visible special characters** | Control characters are shown as `^[`-style text and invalid bytes as U+FFFD, rather than as blank or shifting space. Wide characters, combining marks and tabs align by display column. |
| **Small screens** | The layout adapts to any terminal size and to resizes, so large fonts and zoomed terminals with few columns remain usable. |

## Known gaps

The following are open problems, not design decisions:

- **Selections are distinguished mostly by color.** The main selection
  and the others use different background colors, and only the main
  cursor uses reverse video. The selection count and cursor position are
  shown in the status line, but which text is selected cannot be
  determined without color.
- **`NO_COLOR` is not yet honored**, and there is no theme setting: a
  configuration file does not exist yet (see [`TODO.md`](TODO.md),
  Phases 2 and 4).
- **There is no screen reader mode.** A screen reader reads the terminal's
  whole grid, gutter and status line included; no mode announces only the
  text that changed or describes the selections.
- **Long lines do not wrap yet.** Text beyond the right edge is scrolled
  to rather than wrapped, which is harder to follow at large font sizes.
- **There is no mouse support yet**, for people who find a pointer easier
  than keys.

The roadmap items that address these gaps are listed in
[`TODO.md`](TODO.md).

## Reporting an obstacle

Users of a screen reader, a magnifier, switch access, an alternative
keyboard layout, a high-contrast theme, or any other setup with which
neocaca does not work well are invited to
[open an issue](https://github.com/poopware-laboratories/neocaca/issues)
stating:

- the setup in use (terminal emulator, assistive technology, operating
  system);
- what was attempted, and what happened instead.

> [!NOTE]
> Accessibility bugs are bugs. They are fixed in the same way as any
> other, starting with a test, and a fix that only one group of users
> notices is still worth making.

## Guidance for contributors

When changing what the screen shows (see
[Verifying UI changes](AGENTS.md#verifying-ui-changes)):

- never make color the only indication of a state; add a word or a symbol
  as well;
- use the theme's styles (`src/ui/theme.zig`), which stay within the
  sixteen basic colors, rather than fixed colors;
- keep the terminal cursor on the main cursor;
- check a narrow terminal, and both a light and a dark theme;
- add nothing that depends on timing beyond the Esc timeout.

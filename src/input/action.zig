//! `Action`: what a key or key sequence asks the editor to do, as plain
//! data. The keymap produces actions; the app applies them to the
//! document with the `edit` functions named in each comment.

const edit = @import("../edit.zig");

pub const Motion = edit.selecting.Motion;
pub const Direction = edit.search.Direction;

/// The prompts a key opens; Enter in the prompt runs the action.
pub const Prompt = enum {
    /// `:`
    command,
    /// `s`: select the matches inside the selections.
    select,
    /// `S`: split the selections at the matches.
    split,
    /// `Alt-k`: keep the selections that match.
    keep,
    /// `Alt-K`: drop the selections that match.
    drop,
    /// `/`
    search_forward,
    /// `?`
    search_backward,
};

pub const Scroll = enum { half_down, half_up, page_down, page_up };

/// The `v` prefix: where to put the main cursor's line, or which way to
/// scroll the view by `count` lines.
pub const View = struct {
    to: enum { center, top, bottom, down, up },
    count: usize = 1,
};

pub const Action = union(enum) {
    /// `selecting.move`
    move: struct { motion: Motion, count: usize = 1, extend: bool = false },
    /// `selecting.selectLines`
    select_lines: struct { count: usize = 1, every_line: bool = false },
    select_all,
    reduce,
    flip,
    forward,
    keep_main,
    drop_main,
    /// `selecting.rotateMain`
    rotate_main: isize,
    /// `selecting.copyToLine`
    copy_to_line: struct { down: bool, count: usize = 1 },
    select_object: struct { kind: edit.object.Kind, inner: bool },
    split_lines,
    prompt: Prompt,
    /// `search.next` with the last pattern.
    search_next: struct { dir: Direction, add: bool = false },
    /// `*`: the main selection, escaped, becomes the search pattern.
    search_selection,
    /// `d` and `Alt-d`, `c` and `Alt-c`: `change` enters insert mode after.
    delete: struct { yank: bool = true, reg: u8 = '"', change: bool = false },
    yank: u8,
    paste: struct { reg: u8 = '"', before: bool },
    /// `R`
    replace: u8,
    replace_char: u21,
    case: edit.verbs.Case,
    indent,
    dedent,
    join,
    undo,
    redo,
    insert: edit.insert.Where,
    scroll: Scroll,
    view: View,

    // Insert mode.
    /// A character typed at every cursor.
    text: u21,
    newline,
    backspace,
    delete_forward,
    /// Escape: back to normal mode, closing the insert session.
    leave_insert,
};

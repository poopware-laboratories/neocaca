//! Editing: selections (`edit/selection.zig`), the document they live in
//! with its undo history (`edit/document.zig`, `edit/history.zig`), the
//! selection changes (`edit/motion.zig`, `edit/object.zig`,
//! `edit/selecting.zig`, `edit/search.zig`, counted by `edit/repeat.zig`),
//! the text changes (`edit/verbs.zig`, `edit/insert.zig`) and registers
//! (`edit/registers.zig`).

pub const selection = @import("edit/selection.zig");
pub const history = @import("edit/history.zig");
pub const registers = @import("edit/registers.zig");
pub const motion = @import("edit/motion.zig");
pub const object = @import("edit/object.zig");
pub const selecting = @import("edit/selecting.zig");
pub const verbs = @import("edit/verbs.zig");
pub const insert = @import("edit/insert.zig");
pub const search = @import("edit/search.zig");
const document = @import("edit/document.zig");

pub const Selection = selection.Selection;
pub const Selections = selection.Selections;
pub const Document = document.Document;
pub const Registers = registers.Registers;

test {
    _ = selection;
    _ = history;
    _ = registers;
    _ = motion;
    _ = @import("edit/repeat.zig");
    _ = object;
    _ = selecting;
    _ = @import("edit/selecting_test.zig");
    _ = @import("edit/selecting_count_test.zig");
    _ = @import("edit/stopped_test.zig");
    _ = verbs;
    _ = @import("edit/verbs_test.zig");
    _ = @import("edit/mapped_test.zig");
    _ = insert;
    _ = @import("edit/insert_test.zig");
    _ = search;
    _ = @import("edit/search_test.zig");
    _ = @import("edit/motion_test.zig");
    _ = @import("edit/repeat_test.zig");
    _ = @import("edit/object_test.zig");
    _ = @import("edit/fixture_test.zig");
    _ = document;
    _ = @import("edit/selection_test.zig");
    _ = @import("edit/document_test.zig");
}

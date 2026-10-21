//! Editing: selections (`edit/selection.zig`), the document they live in
//! with its undo history (`edit/document.zig`, `edit/history.zig`) and
//! registers (`edit/registers.zig`).

pub const selection = @import("edit/selection.zig");
pub const history = @import("edit/history.zig");
pub const registers = @import("edit/registers.zig");
pub const motion = @import("edit/motion.zig");
pub const object = @import("edit/object.zig");
pub const selecting = @import("edit/selecting.zig");
pub const verbs = @import("edit/verbs.zig");
pub const insert = @import("edit/insert.zig");
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
    _ = object;
    _ = selecting;
    _ = @import("edit/selecting_test.zig");
    _ = verbs;
    _ = @import("edit/verbs_test.zig");
    _ = insert;
    _ = @import("edit/insert_test.zig");
    _ = @import("edit/motion_test.zig");
    _ = @import("edit/object_test.zig");
    _ = @import("edit/fixture_test.zig");
    _ = document;
    _ = @import("edit/selection_test.zig");
    _ = @import("edit/document_test.zig");
}

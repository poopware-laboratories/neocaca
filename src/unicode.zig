//! Unicode for the editor: never-failing UTF-8 (`utf8.zig`), display width
//! (`width.zig`), character boundaries (`chars.zig`), the word and blank
//! classes (`class.zig`), how file contents are drawn (`display.zig`) and
//! text written where the screen does not draw it, as stderr (`visible.zig`).

pub const utf8 = @import("unicode/utf8.zig");
pub const width = @import("unicode/width.zig");
pub const chars = @import("unicode/chars.zig");
pub const class = @import("unicode/class.zig");
pub const display = @import("unicode/display.zig");
pub const visible = @import("unicode/visible.zig");

test {
    _ = utf8;
    _ = width;
    _ = chars;
    _ = class;
    _ = display;
    _ = visible;
    _ = @import("unicode/utf8_test.zig");
    _ = @import("unicode/width_test.zig");
    _ = @import("unicode/chars_test.zig");
    _ = @import("unicode/class_test.zig");
    _ = @import("unicode/display_test.zig");
    _ = @import("unicode/visible_test.zig");
}

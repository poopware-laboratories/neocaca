//! Unicode for the editor: never-failing UTF-8 (`utf8.zig`), display width
//! (`width.zig`), character boundaries (`chars.zig`), the word and blank
//! classes (`class.zig`) and how file contents are drawn (`display.zig`).

pub const utf8 = @import("unicode/utf8.zig");
pub const width = @import("unicode/width.zig");
pub const chars = @import("unicode/chars.zig");
pub const class = @import("unicode/class.zig");
pub const display = @import("unicode/display.zig");

test {
    _ = utf8;
    _ = width;
    _ = chars;
    _ = class;
    _ = display;
    _ = @import("unicode/utf8_test.zig");
    _ = @import("unicode/width_test.zig");
    _ = @import("unicode/chars_test.zig");
}

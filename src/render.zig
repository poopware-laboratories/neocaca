//! Rendering: `render/style.zig` (cell styles and their SGR sequences),
//! `render/screen.zig` (the grid of cells a frame draws into) and
//! `render/diff.zig` (the escape bytes that turn one screen into the next).

pub const style = @import("render/style.zig");
pub const screen = @import("render/screen.zig");
pub const diff = @import("render/diff.zig").diff;

pub const Style = style.Style;
pub const Color = style.Color;
pub const Screen = screen.Screen;

test {
    _ = style;
    _ = @import("render/style_test.zig");
    _ = screen;
    _ = @import("render/screen_test.zig");
    _ = @import("render/diff.zig");
    _ = @import("render/diff_test.zig");
}

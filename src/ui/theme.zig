//! `Theme`: the styles the interface draws with. The default uses only the
//! sixteen basic colors and reverse video, so it reads on light and dark
//! terminals alike.

const render = @import("../render.zig");

const Style = render.Style;

pub const Theme = struct {
    text: Style = .{},
    /// Characters drawn in a visible form: `^[`, U+FFFD.
    special: Style = .{ .fg = .{ .index = 1 } },
    selection: Style = .{ .fg = .{ .index = 15 }, .bg = .{ .index = 4 } },
    main_selection: Style = .{ .fg = .{ .index = 0 }, .bg = .{ .index = 6 } },
    cursor: Style = .{ .fg = .{ .index = 0 }, .bg = .{ .index = 3 } },
    main_cursor: Style = .{ .reverse = true },
    gutter: Style = .{ .fg = .{ .index = 8 } },
    gutter_current: Style = .{ .bold = true },
    /// `~` on the rows past the end of the buffer.
    filler: Style = .{ .fg = .{ .index = 8 } },
    status: Style = .{ .reverse = true },
    mode_normal: Style = .{ .bold = true, .reverse = true },
    mode_insert: Style = .{ .bold = true, .fg = .{ .index = 0 }, .bg = .{ .index = 2 } },
    mode_prompt: Style = .{ .bold = true, .fg = .{ .index = 0 }, .bg = .{ .index = 3 } },
    message: Style = .{},
    @"error": Style = .{ .bold = true, .fg = .{ .index = 1 } },
};

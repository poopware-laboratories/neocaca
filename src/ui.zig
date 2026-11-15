//! The pure user interface: `ui/view.zig` (scrolling), `ui/wrap.zig`
//! (the rows a long line wraps into), `ui/theme.zig`
//! (styles), `ui/document.zig` (a document drawn into an area),
//! `ui/status.zig` (the status and message lines), `ui/prompt.zig` (the
//! prompt line editor).

pub const view = @import("ui/view.zig");
pub const wrap = @import("ui/wrap.zig");
pub const theme = @import("ui/theme.zig");
pub const document = @import("ui/document.zig");
pub const status = @import("ui/status.zig");
pub const prompt = @import("ui/prompt.zig");

pub const View = view.View;
pub const Theme = theme.Theme;

test {
    _ = view;
    _ = @import("ui/view_test.zig");
    _ = @import("ui/view_rows_test.zig");
    _ = @import("ui/view_scroll_test.zig");
    _ = wrap;
    _ = @import("ui/wrap_test.zig");
    _ = theme;
    _ = document;
    _ = @import("ui/document_test.zig");
    _ = @import("ui/document_wrap_test.zig");
    _ = status;
    _ = @import("ui/status_test.zig");
    _ = prompt;
    _ = @import("ui/prompt_test.zig");
}

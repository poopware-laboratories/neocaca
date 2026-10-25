//! Text storage: `Buffer` (`buffer.zig`), the change sets it applies
//! (`change.zig`), its line index (`lines.zig`), and the form of the file
//! it came from (`form.zig`): its byte order mark, line ends
//! (`endings.zig`) and final newline. No I/O, no terminal.

const buffer = @import("buffer/buffer.zig");
pub const change = @import("buffer/change.zig");
pub const lines = @import("buffer/lines.zig");
pub const endings = @import("buffer/endings.zig");
pub const form = @import("buffer/form.zig");

pub const Buffer = buffer.Buffer;
pub const Change = change.Change;
pub const ApplyError = buffer.ApplyError;

test {
    _ = buffer;
    _ = change;
    _ = lines;
    _ = endings;
    _ = form;
    _ = @import("buffer/buffer_test.zig");
    _ = @import("buffer/change_test.zig");
    _ = @import("buffer/lines_test.zig");
    _ = @import("buffer/endings_test.zig");
    _ = @import("buffer/form_test.zig");
}

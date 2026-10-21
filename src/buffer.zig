//! Text storage: `Buffer` (`buffer.zig`), the change sets it applies
//! (`change.zig`) and its line index (`lines.zig`). No I/O, no terminal.

const buffer = @import("buffer/buffer.zig");
pub const change = @import("buffer/change.zig");
pub const lines = @import("buffer/lines.zig");

pub const Buffer = buffer.Buffer;
pub const Change = change.Change;
pub const ApplyError = buffer.ApplyError;

test {
    _ = buffer;
    _ = change;
    _ = lines;
    _ = @import("buffer/buffer_test.zig");
    _ = @import("buffer/change_test.zig");
}

//! Integration tests: whole editor sessions driven from scripted input
//! bytes, asserting on the final screen, the buffers and the files written
//! (`editing_test.zig` and `commands_test.zig`, through `harness.zig`), and
//! the editor run on a pseudo-terminal end to end (`terminal_test.zig`).

test {
    _ = @import("harness.zig");
    _ = @import("editing_test.zig");
    _ = @import("commands_test.zig");
    _ = @import("messages_test.zig");
    _ = @import("display_test.zig");
    _ = @import("counts_test.zig");
    _ = @import("random_test.zig");
    _ = @import("terminal_test.zig");
}

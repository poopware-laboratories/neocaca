//! The editor application. For now: running a command line to an exit
//! code (`run.zig`), with the codes in `exit.zig`. The event loop goes here.

pub const exit = @import("app/exit.zig");
pub const run = @import("app/run.zig").run;

test {
    _ = exit;
    _ = @import("app/run.zig");
}

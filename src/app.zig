//! The editor application. For now: running a command line to an exit
//! code (`run.zig`), with the codes in `exit.zig`. The event loop goes here.

pub const exit = @import("app/exit.zig");
pub const run = @import("app/run.zig").run;
pub const commands = @import("app/commands.zig");
pub const editor = @import("app/editor.zig");
pub const Editor = editor.Editor;
pub const session = @import("app/session.zig");
pub const Session = session.Session;

test {
    _ = exit;
    _ = @import("app/run.zig");
    _ = commands;
    _ = @import("app/commands_test.zig");
    _ = editor;
    _ = @import("app/editor_test.zig");
    _ = @import("app/prompting.zig");
    _ = @import("app/layout.zig");
    _ = @import("app/layout_test.zig");
    _ = session;
    _ = @import("app/session_test.zig");
}

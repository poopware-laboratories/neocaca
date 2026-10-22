//! The editor application: a command line to an exit code (`run.zig`,
//! codes in `exit.zig`); the editor state (`editor.zig`) with its `:`
//! commands (`commands.zig`), prompts (`prompting.zig`) and screen layout
//! (`layout.zig`); a session joining it to bytes, files and frames
//! (`session.zig`); the event loop (`loop.zig`); and editing in the real
//! terminal (`edit.zig`).

pub const exit = @import("app/exit.zig");
pub const run = @import("app/run.zig").run;
pub const Env = @import("app/run.zig").Env;
pub const commands = @import("app/commands.zig");
pub const editor = @import("app/editor.zig");
pub const Editor = editor.Editor;
pub const session = @import("app/session.zig");
pub const Session = session.Session;
pub const loop = @import("app/loop.zig");
pub const edit = @import("app/edit.zig");

test {
    _ = exit;
    _ = @import("app/run.zig");
    _ = commands;
    _ = @import("app/commands_test.zig");
    _ = editor;
    _ = @import("app/editor_test.zig");
    _ = @import("app/editor_view_test.zig");
    _ = @import("app/editor_map_test.zig");
    _ = @import("app/prompting.zig");
    _ = @import("app/layout.zig");
    _ = @import("app/layout_test.zig");
    _ = session;
    _ = @import("app/session_test.zig");
    _ = @import("app/session_save_test.zig");
    _ = @import("app/saving_test.zig");
    _ = loop;
    _ = @import("app/loop_test.zig");
    _ = edit;
}

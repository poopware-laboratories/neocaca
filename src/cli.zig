//! The command line: what it can ask for (`command.zig`), how it is parsed
//! (`parse.zig`) and the help text (`usage.zig`).

const command = @import("cli/command.zig");

pub const Command = command.Command;
pub const Error = command.Error;
pub const describe = command.describe;
pub const parse = @import("cli/parse.zig").parse;
pub const usage = @import("cli/usage.zig").text;

test {
    _ = command;
    _ = @import("cli/parse.zig");
    _ = @import("cli/usage.zig");
}

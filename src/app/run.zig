//! Everything after process setup: the arguments in, the exit code out,
//! over plain writers and a terminal given by the caller, so tests can run
//! it (`run_test.zig`).

const std = @import("std");
const build_options = @import("build_options");
const cli = @import("../cli.zig");
const exit = @import("exit.zig");
const editing = @import("edit.zig");

pub const Env = editing.Env;

/// `args` excludes the program name. Editing runs in the terminal `env`
/// names.
pub fn run(env: Env, args: []const []const u8, out: *std.Io.Writer, err: *std.Io.Writer) std.Io.Writer.Error!exit.Code {
    const command = cli.parse(args) catch |e| {
        try err.print("neocaca: {s}\n\n{s}", .{ cli.describe(e), cli.usage });
        return .usage;
    };
    switch (command) {
        .help => try out.writeAll(cli.usage),
        .version => try out.print("neocaca {s}\n", .{build_options.version}),
        .edit => |files| return editing.edit(env, files, err),
    }
    return .ok;
}

test {
    _ = @import("run_test.zig");
}

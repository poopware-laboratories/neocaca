//! Everything after process setup: the arguments in, the exit code out,
//! over plain writers so tests can run it (`run_test.zig`).

const std = @import("std");
const build_options = @import("build_options");
const cli = @import("../cli.zig");
const exit = @import("exit.zig");

/// `args` excludes the program name.
pub fn run(args: []const []const u8, out: *std.Io.Writer, err: *std.Io.Writer) std.Io.Writer.Error!exit.Code {
    const command = cli.parse(args) catch |e| {
        try err.print("neocaca: {s}\n\n{s}", .{ cli.describe(e), cli.usage });
        return .usage;
    };
    switch (command) {
        .help => try out.writeAll(cli.usage),
        .version => try out.print("neocaca {s}\n", .{build_options.version}),
        .edit => {
            try err.writeAll("neocaca: the editor is not written yet; see the open issues\n");
            return .failure;
        },
    }
    return .ok;
}

test {
    _ = @import("run_test.zig");
}

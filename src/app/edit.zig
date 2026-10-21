//! Editing in the real terminal: open the tty, run the session's loop on
//! it, and put the terminal back however the loop ends, before any error
//! is printed.

const std = @import("std");
const term = @import("../term.zig");
const exit = @import("exit.zig");
const loop = @import("loop.zig");
const Session = @import("session.zig").Session;

/// What editing needs from the process.
pub const Env = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    /// Relative paths are opened from here.
    dir: std.Io.Dir,
    /// The terminal: keys come from `in`, frames go to `out`.
    in: std.posix.fd_t,
    out: std.posix.fd_t,
};

/// The size used when the terminal does not report one.
pub const fallback_size: term.Size = .{ .width = 80, .height = 24 };

/// Edits the first of `files` (none: a scratch buffer) until the editor
/// quits or the terminal goes away. Errors are reported on `err`.
pub fn edit(env: Env, files: []const []const u8, err: *std.Io.Writer) std.Io.Writer.Error!exit.Code {
    var tty = term.Tty.open(env.in, env.out) catch |e| {
        try err.print("neocaca: {s}\n", .{describeOpen(e)});
        return .failure;
    };
    defer tty.restore();
    const size = tty.size() orelse fallback_size;
    const path: ?[]const u8 = if (files.len > 0) files[0] else null;
    var session = Session.init(env.gpa, env.io, env.dir, path, size.width, size.height) catch {
        tty.restore();
        try err.writeAll("neocaca: out of memory\n");
        return .failure;
    };
    defer session.deinit();
    if (files.len > 1) session.ed.message.set(false, "editing the first of {d} files", .{files.len});

    var buf: [8192]u8 = undefined;
    var out: std.Io.File.Writer = .init(.{ .handle = env.out, .flags = .{ .nonblocking = false } }, env.io, &buf);
    loop.run(&session, &tty, &out.interface) catch |e| {
        tty.restore();
        try err.print("neocaca: the terminal failed: {s}\n", .{@errorName(e)});
        return .failure;
    };
    return .ok;
}

fn describeOpen(e: term.tty.OpenError) []const u8 {
    return switch (e) {
        error.NotATerminal => "standard input is not a terminal",
        error.ProcessOrphaned => "the terminal is not ours (orphaned process group)",
        error.SystemResources => "out of system resources",
        else => "cannot set up the terminal",
    };
}

test "edit: describing each terminal error" {
    try std.testing.expectEqualStrings("standard input is not a terminal", describeOpen(error.NotATerminal));
    try std.testing.expectEqualStrings("out of system resources", describeOpen(error.SystemResources));
    try std.testing.expectEqualStrings("cannot set up the terminal", describeOpen(error.Unexpected));
}

test "edit: standard input that is not a terminal is a failure, said plainly" {
    var p: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    const env: Env = .{ .gpa = std.testing.allocator, .io = std.testing.io, .dir = std.Io.Dir.cwd(), .in = p[0], .out = p[1] };
    try std.testing.expectEqual(.failure, try edit(env, &.{"x"}, &err));
    try std.testing.expectEqualStrings("neocaca: standard input is not a terminal\n", err.buffered());
}

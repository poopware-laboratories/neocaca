//! Editing in the real terminal: open the tty, run the session's loop on
//! it, and put the terminal back however the loop ends, before any error
//! is printed.

const std = @import("std");
const fs = @import("../fs.zig");
const term = @import("../term.zig");
const exit = @import("exit.zig");
const loop = @import("loop.zig");
const Session = @import("session.zig").Session;
const recovery = @import("recovery.zig");

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
    // The file is read before the terminal is touched, so a file that
    // cannot be opened is said plainly on the shell's own screen.
    const path: ?[]const u8 = if (files.len > 0) files[0] else null;
    var session = Session.init(env.gpa, env.io, env.dir, path, fallback_size.width, fallback_size.height) catch |e| {
        switch (e) {
            error.OutOfMemory => try err.writeAll("neocaca: out of memory\n"),
            else => try err.print("neocaca: cannot open \"{s}\": {s}\n", .{ path.?, fs.describe(e) }),
        }
        return .failure;
    };
    defer session.deinit();
    var tty = term.Tty.open(env.in, env.out) catch |e| {
        try err.print("neocaca: {s}\n", .{describeOpen(e)});
        return .failure;
    };
    defer tty.restore();
    const size = tty.size() orelse fallback_size;
    session.resize(size.width, size.height);
    session.notify = tty.wakeFd();
    if (files.len > 1) session.ed.message.set(false, "editing the first of {d} files", .{files.len});

    var buf: [8192]u8 = undefined;
    var out: std.Io.File.Writer = .init(.{ .handle = env.out, .flags = .{ .nonblocking = false } }, env.io, &buf);
    loop.run(&session, &tty, &out.interface) catch |e| {
        tty.restore();
        try stopped(&session, e, err);
        return .failure;
    };
    tty.restore();
    return recover(&session, err);
}

/// Says what stopped the loop, then saves what can be saved.
fn stopped(session: *Session, e: anyerror, err: *std.Io.Writer) std.Io.Writer.Error!void {
    if (stopDetail(e)) |detail| {
        try err.print("neocaca: {s}: {s}\n", .{ describeStop(e), detail });
    } else {
        try err.print("neocaca: {s}\n", .{describeStop(e)});
    }
    _ = try recover(session, err);
}

/// After the terminal went away rather than the editor quitting, writes
/// the unsaved changes to a recovery file and says where; a failure when
/// they could not be written.
fn recover(session: *Session, err: *std.Io.Writer) std.Io.Writer.Error!exit.Code {
    if (session.done()) return .ok;
    var buf: [recovery.max_name]u8 = undefined;
    switch (session.recover(&buf)) {
        .none => return .ok,
        .written => |where| {
            try err.print("neocaca: unsaved changes written to \"{s}\"\n", .{where});
            return .ok;
        },
        .failed => |e| {
            try err.print("neocaca: the unsaved changes could not be written: {s}\n", .{recovery.describe(e)});
            return .failure;
        },
    }
}

/// What stopped the loop: the terminal, memory, or a bug in the editor.
fn describeStop(e: anyerror) []const u8 {
    return switch (e) {
        error.OutOfMemory => "out of memory",
        error.FinalNewline, error.OutOfOrder, error.OutOfBounds => "an internal error stopped the editor (please report it)",
        else => "the terminal failed",
    };
}

/// What follows `describeStop`: the terminal's error in words, a bug's
/// own name for its report, nothing for memory.
fn stopDetail(e: anyerror) ?[]const u8 {
    return switch (e) {
        error.OutOfMemory => null,
        error.FinalNewline, error.OutOfOrder, error.OutOfBounds => @errorName(e),
        else => fs.describe(e),
    };
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

test "edit: describing why the loop stopped" {
    try std.testing.expectEqualStrings("the terminal failed", describeStop(error.InputOutput));
    try std.testing.expectEqualStrings("the terminal failed", describeStop(error.BrokenPipe));
    try std.testing.expectEqualStrings("out of memory", describeStop(error.OutOfMemory));
    // An edit built wrongly is a bug in the editor, not the terminal.
    try std.testing.expectEqualStrings("an internal error stopped the editor (please report it)", describeStop(error.FinalNewline));
    try std.testing.expectEqualStrings("an internal error stopped the editor (please report it)", describeStop(error.OutOfOrder));
    try std.testing.expectEqualStrings("an internal error stopped the editor (please report it)", describeStop(error.OutOfBounds));
}

test "edit: what follows why the loop stopped" {
    try std.testing.expectEqualStrings("an input/output error", stopDetail(error.InputOutput).?);
    try std.testing.expectEqualStrings("the pipe is broken", stopDetail(error.BrokenPipe).?);
    try std.testing.expectEqual(null, stopDetail(error.OutOfMemory));
    // A bug keeps its name, which the report needs.
    try std.testing.expectEqualStrings("FinalNewline", stopDetail(error.FinalNewline).?);
    try std.testing.expectEqualStrings("OutOfBounds", stopDetail(error.OutOfBounds).?);
}

test "edit: a bug that stops the loop is reported, and the changes kept" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var session: Session = try .init(std.testing.allocator, std.testing.io, tmp.dir, "f", 20, 4);
    defer session.deinit();
    try session.feed("ix\x1b");
    try session.timeout();
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    try stopped(&session, error.FinalNewline, &err);
    try std.testing.expectEqualStrings(
        \\neocaca: an internal error stopped the editor (please report it): FinalNewline
        \\neocaca: unsaved changes written to "f.recovered"
        \\
    , err.buffered());
    var text: [16]u8 = undefined;
    try std.testing.expectEqualStrings("x\n", try tmp.dir.readFile(std.testing.io, "f.recovered", &text));
}

test "edit: a terminal that fails after :q has nothing to recover" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var session: Session = try .init(std.testing.allocator, std.testing.io, tmp.dir, "f", 20, 4);
    defer session.deinit();
    try session.feed(":q\r");
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    try stopped(&session, error.InputOutput, &err);
    try std.testing.expectEqualStrings("neocaca: the terminal failed: an input/output error\n", err.buffered());
}

test "edit: changes that cannot be recovered are said to be lost" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var session: Session = try .init(std.testing.allocator, std.testing.io, tmp.dir, "gone/f", 20, 4);
    defer session.deinit();
    try session.feed("ix\x1b");
    try session.timeout();
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    try stopped(&session, error.OutOfMemory, &err);
    try std.testing.expectEqualStrings(
        \\neocaca: out of memory
        \\neocaca: the unsaved changes could not be written: no such file or directory
        \\
    , err.buffered());
}

test "edit: after a hang-up, the exit fails only when changes were lost" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    // Nothing to recover.
    var clean: Session = try .init(std.testing.allocator, std.testing.io, tmp.dir, "c", 20, 4);
    defer clean.deinit();
    try std.testing.expectEqual(.ok, try recover(&clean, &err));
    // Recovered.
    var kept: Session = try .init(std.testing.allocator, std.testing.io, tmp.dir, "k", 20, 4);
    defer kept.deinit();
    try kept.feed("ix\x1b");
    try kept.timeout();
    try std.testing.expectEqual(.ok, try recover(&kept, &err));
    // Lost: the directory has gone.
    var lost: Session = try .init(std.testing.allocator, std.testing.io, tmp.dir, "gone/f", 20, 4);
    defer lost.deinit();
    try lost.feed("ix\x1b");
    try lost.timeout();
    try std.testing.expectEqual(.failure, try recover(&lost, &err));
    try std.testing.expectEqualStrings(
        \\neocaca: unsaved changes written to "k.recovered"
        \\neocaca: the unsaved changes could not be written: no such file or directory
        \\
    , err.buffered());
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

test "edit: a file that cannot be read is refused before the terminal is touched" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "d", .default_dir);
    var p: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    const env: Env = .{ .gpa = std.testing.allocator, .io = std.testing.io, .dir = tmp.dir, .in = p[0], .out = p[1] };
    try std.testing.expectEqual(.failure, try edit(env, &.{"d"}, &err));
    try std.testing.expectEqualStrings("neocaca: cannot open \"d\": is a directory\n", err.buffered());
}

test "edit: a name too long to open is refused with its reason whole" {
    const long: []const u8 = &@as([300]u8, @splat('n'));
    var err_buf: [512]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    const env: Env = .{ .gpa = std.testing.allocator, .io = std.testing.io, .dir = std.Io.Dir.cwd(), .in = -1, .out = -1 };
    try std.testing.expectEqual(.failure, try edit(env, &.{long}, &err));
    try std.testing.expectEqualStrings("neocaca: cannot open \"" ++ long ++ "\": the name is too long\n", err.buffered());
}

test "edit: a file in a missing directory is not refused, it goes on to the terminal" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var p: [2]std.posix.fd_t = undefined;
    try std.testing.expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    var err_buf: [256]u8 = undefined;
    var err: std.Io.Writer = .fixed(&err_buf);
    const env: Env = .{ .gpa = std.testing.allocator, .io = std.testing.io, .dir = tmp.dir, .in = p[0], .out = p[1] };
    try std.testing.expectEqual(.failure, try edit(env, &.{"gone/f"}, &err));
    try std.testing.expectEqualStrings("neocaca: standard input is not a terminal\n", err.buffered());
}

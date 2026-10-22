//! Tests for the saves of `session.zig`, which run off the event loop:
//! keys go on being typed while a file is written, and the result is
//! reported once it is collected.

const std = @import("std");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Types `keys` one byte per read; a save they start runs on.
fn feedKeys(s: *Session, keys: []const u8) !void {
    for (keys) |*b| {
        try s.feed(b[0..1]);
        try s.timeout();
    }
}

fn readFile(dir: std.Io.Dir, path: []const u8, buf: []u8) ![]const u8 {
    return dir.readFile(io, path, buf);
}

test "session: a save runs while keys go on editing its copy of the text" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "a\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r");
    try expect(s.saving != null);
    try expectEqualStrings("writing \"f\"", s.ed.message.text());
    try feedKeys(&s, "iy\x1b");
    try expectEqualStrings("xya\n", s.ed.doc.text());
    s.settle();
    try expectEqual(null, s.saving);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("xa\n", try readFile(tmp.dir, "f", &buf));
    try expectEqualStrings("\"f\" written, 1 line", s.ed.message.text());
    // The text typed during the save is not in the file.
    try expect(s.ed.doc.isModified());
    try feedKeys(&s, "u");
    try expect(!s.ed.doc.isModified());
}

test "session: collect reports a finished save and does nothing without one" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.collect();
    try expectEqual(null, s.saving);
    try feedKeys(&s, "ix\x1b:w\r");
    const job = s.saving.?;
    while (!job.isFinished()) try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    try s.collect();
    try expectEqual(null, s.saving);
    try expectEqualStrings("\"f\" written, 1 line", s.ed.message.text());
    try expect(!s.ed.doc.isModified());
}

test "session: a finished save wakes the loop through the notify pipe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var p: [2]std.posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    s.notify = p[1];
    try feedKeys(&s, ":w\r");
    var fds = [_]std.posix.pollfd{.{ .fd = p[0], .events = std.posix.POLL.IN, .revents = 0 }};
    try expectEqual(1, try std.posix.poll(&fds, 10_000));
    try s.collect();
    try expectEqual(null, s.saving);
    try expectEqualStrings("\"f\" written, 1 line", s.ed.message.text());
}

test "session: keys after :wq are ignored while it writes, and it quits after" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:wq\rihello\x1b");
    try expectEqualStrings("x\n", s.ed.doc.text());
    s.settle();
    try expect(s.done());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: a failed :wq takes keys again" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "missing/f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:wq\r");
    s.settle();
    try expect(!s.done());
    try expect(std.mem.startsWith(u8, s.ed.message.text(), "cannot write \"missing/f\": "));
    try feedKeys(&s, "iy\x1b");
    try expectEqualStrings("xy\n", s.ed.doc.text());
}

test "session: a save asked for during another waits for it, then writes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\riy\x1b:w\r");
    s.settle();
    var buf: [16]u8 = undefined;
    try expectEqualStrings("xy\n", try readFile(tmp.dir, "f", &buf));
    try expect(!s.ed.doc.isModified());
}

test "session: :e and :q during a save say so; :e! waits for it, then loads" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "g\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:e g\r");
    try expectEqualStrings("a save is still being written", s.ed.message.text());
    try feedKeys(&s, ":q\r");
    try expectEqualStrings("a save is still being written", s.ed.message.text());
    try expect(!s.done());
    try feedKeys(&s, ":e! g\r");
    // The save was reported before the load began.
    try expectEqual(null, s.saving);
    s.settle();
    try expectEqualStrings("g\n", s.ed.doc.text());
    try expectEqualStrings("\"g\" 1 line", s.ed.message.text());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: closing the session finishes the save in flight" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
        defer s.deinit();
        try feedKeys(&s, "ix\x1b:w\r");
    }
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: a save that cannot copy the text says so and writes nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:wq");
    failing.fail_index = failing.alloc_index;
    try feedKeys(&s, "\r");
    failing.fail_index = std.math.maxInt(usize);
    try expectEqual(null, s.saving);
    try expectEqualStrings("out of memory", s.ed.message.text());
    try expect(!s.done());
    try expect(s.ed.doc.isModified());
    // Not quitting: keys edit again.
    try feedKeys(&s, "iy\x1b");
    try expectEqualStrings("xy\n", s.ed.doc.text());
    var buf: [16]u8 = undefined;
    try std.testing.expectError(error.FileNotFound, readFile(tmp.dir, "f", &buf));
}

test "session: the report counts the lines that were written, not those typed since" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ia\rb\x1b:w\roc\rd\x1b");
    try expectEqual(4, s.ed.doc.buffer.lineCount());
    s.settle();
    try expectEqualStrings("\"f\" written, 2 lines", s.ed.message.text());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("a\nb\n", try readFile(tmp.dir, "f", &buf));
}

test "session: a save to another file leaves the buffer modified and its name alone" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w g\r");
    s.settle();
    try expectEqualStrings("\"g\" written, 1 line", s.ed.message.text());
    try expect(s.ed.doc.isModified());
    try expectEqualStrings("f", s.ed.path.?);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "g", &buf));
    try std.testing.expectError(error.FileNotFound, readFile(tmp.dir, "f", &buf));
}

test "session: an unnamed buffer takes the name it was written to" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w g\r");
    // Named once the save is reported, not before.
    try expectEqual(null, s.ed.path);
    s.settle();
    try expectEqualStrings("g", s.ed.path.?);
    try expect(!s.ed.doc.isModified());
    try feedKeys(&s, "iy\x1b:w\r");
    s.settle();
    var buf: [16]u8 = undefined;
    try expectEqualStrings("xy\n", try readFile(tmp.dir, "g", &buf));
}

test "session: out of memory naming an unnamed buffer leaves it unnamed and modified" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w g\r");
    s.saving.?.wait();
    // The next allocation is the name, taken when the save is reported.
    failing.fail_index = failing.alloc_index;
    s.settle();
    failing.fail_index = std.math.maxInt(usize);
    try expectEqualStrings("out of memory", s.ed.message.text());
    try expectEqual(null, s.ed.path);
    try expect(s.ed.doc.isModified());
    try expect(!s.ed.doc.saving);
    // The file itself was written.
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "g", &buf));
}

test "session: :q! during a save quits, and the save still finishes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    {
        var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
        defer s.deinit();
        try feedKeys(&s, "ix\x1b:w\r:q!\r");
        try expect(s.done());
    }
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: a paste after :wq is ignored while it writes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:wq\r");
    try s.feed("\x1b[200~pasted\x1b[201~");
    try expectEqualStrings("x\n", s.ed.doc.text());
    s.settle();
    try expect(s.done());
}

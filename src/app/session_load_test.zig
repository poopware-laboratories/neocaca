//! Tests for the loads of `session.zig`, which run off the event loop:
//! keys typed while a file is read wait for it, then edit what it holds.

const std = @import("std");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn withFile(tmp: *std.testing.TmpDir, path: []const u8, data: []const u8) !void {
    try tmp.dir.writeFile(io, .{ .sub_path = path, .data = data });
}

/// Waits for the load in flight and reports it as the loop would.
fn finishLoad(s: *Session) !void {
    const job = s.loading.?;
    while (!job.isFinished()) try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    try s.collect();
}

test "session: :e reads the file off the event loop" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\r");
    try expect(s.loading != null);
    try expectEqualStrings("reading \"g\"", s.ed.message.text());
    try finishLoad(&s);
    try expectEqual(null, s.loading);
    try expectEqualStrings("g\n", s.ed.doc.text());
    try expectEqualStrings("g", s.ed.path.?);
    try expectEqualStrings("\"g\" 1 line", s.ed.message.text());
}

test "session: keys typed while a file is read edit it once it is in" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    // The keys after Enter, in the same read, wait as well.
    try s.feed(":e g\rix");
    try s.feed("y");
    try expectEqualStrings("\n", s.ed.doc.text());
    try finishLoad(&s);
    try expectEqualStrings("xyg\n", s.ed.doc.text());
}

test "session: no Escape timeout is due while a file is read" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\rix\x1b");
    try expect(!s.waiting());
    try s.timeout();
    try finishLoad(&s);
    // Insert mode, with the Escape waiting for its timeout now.
    try expect(s.waiting());
    try s.timeout();
    try s.feed("iy");
    try expectEqualStrings("xyg\n", s.ed.doc.text());
}

test "session: keys past what a load holds are dropped, and it says so" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    s.max_held = 8;
    // Held: `i` and seven more bytes, the most there is room for.
    try s.feed(":e g\ri");
    try s.feed("abcdefg");
    try s.feed("h");
    try finishLoad(&s);
    try expectEqualStrings("abcdefgg\n", s.ed.doc.text());
    try expectEqualStrings("keys typed while reading were dropped", s.ed.message.text());
    // Insert mode still: the bytes after the drop are typed again.
    try s.feed("h");
    try expectEqualStrings("abcdefghg\n", s.ed.doc.text());
}

test "session: a drop is told once, not after the next load" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    s.max_held = 1;
    try s.feed(":e g\r");
    try s.feed("ab");
    try finishLoad(&s);
    try expectEqualStrings("keys typed while reading were dropped", s.ed.message.text());
    try s.feed(":e! g\r");
    try finishLoad(&s);
    try expectEqualStrings("\"g\" 1 line", s.ed.message.text());
}

test "session: keys typed during a failed load edit the buffer it kept" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try withFile(&tmp, "f", "f\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e d\r");
    try finishLoad(&s);
    try expect(std.mem.startsWith(u8, s.ed.message.text(), "cannot open \"d\": "));
    try s.feed("ix");
    try expectEqualStrings("xf\n", s.ed.doc.text());
    try expectEqualStrings("f", s.ed.path.?);
}

test "session: settle finishes a load and leaves the held keys for later" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\rix");
    s.settle();
    try expectEqual(null, s.loading);
    try expectEqualStrings("g\n", s.ed.doc.text());
    try expect(s.waiting());
    try s.timeout();
    try expectEqualStrings("xg\n", s.ed.doc.text());
}

test "session: closing the session during a load frees it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    try s.feed(":e g\rix");
    // The testing allocator fails the test on a leak.
    s.deinit();
}

test "session: a load that cannot start says so, and keys go on" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g");
    // The first allocation copies the path into the request; the next is
    // the load.
    failing.fail_index = failing.alloc_index + 1;
    try s.feed("\r");
    failing.fail_index = std.math.maxInt(usize);
    try expectEqual(null, s.loading);
    try expectEqualStrings("out of memory", s.ed.message.text());
    try s.feed("ix");
    try expectEqualStrings("x\n", s.ed.doc.text());
}

test "session: a load waits for the save in flight, and the save is reported" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed("ix\x1b");
    try s.timeout();
    try s.feed(":w\r:e! g\r");
    try expectEqual(null, s.saving);
    try finishLoad(&s);
    try expectEqualStrings("g\n", s.ed.doc.text());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try tmp.dir.readFile(io, "f", &buf));
}

test "session: a finished load wakes the loop through the notify pipe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var p: [2]std.posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&p));
    defer _ = std.c.close(p[0]);
    defer _ = std.c.close(p[1]);
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    s.notify = p[1];
    try s.feed(":e g\rix");
    var fds = [_]std.posix.pollfd{.{ .fd = p[0], .events = std.posix.POLL.IN, .revents = 0 }};
    try expectEqual(1, try std.posix.poll(&fds, 10_000));
    try s.collect();
    try expectEqual(null, s.loading);
    try expectEqualStrings("xg\n", s.ed.doc.text());
}

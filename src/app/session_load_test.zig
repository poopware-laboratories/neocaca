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
    try waitLoad(s);
    try s.collect();
}

/// Waits for the load's thread to end, without reporting the load: its
/// allocations are over, so a failing allocator's next one is the test's.
fn waitLoad(s: *Session) !void {
    const job = s.loading.?;
    while (!job.isFinished()) try std.Io.sleep(io, .fromMilliseconds(1), .awake);
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

test "session: an Escape typed while a file is read keeps its pause" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\rix\x1b");
    // The Escape waits for its timeout during the load as well.
    try expect(s.waiting());
    try s.timeout();
    try expect(!s.waiting());
    // Typed after the pause: `i`, not Alt-i.
    try s.feed("iy");
    try expectEqualStrings("\n", s.ed.doc.text());
    try finishLoad(&s);
    try expectEqualStrings("xyg\n", s.ed.doc.text());
}

test "session: an Escape and a key typed together during a load stay Alt and the key" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    // Alt-x, with no pause between its bytes, is not Escape then `x`.
    try s.feed(":e g\r\x1bx");
    try s.timeout();
    try finishLoad(&s);
    try expectEqualStrings("g\n", s.ed.doc.text());
    try expect(!s.waiting());
}

test "session: :e, then typing with pauses before the load is in, as quickly as a person types" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    // The roadmap's case: `:e g`, then `ox`, Esc, `:w` inserted `xw`.
    try s.feed(":e g\r");
    try s.feed("ox");
    try s.feed("\x1b");
    try s.timeout();
    try s.feed(":");
    try s.feed("w");
    try finishLoad(&s);
    try expectEqualStrings("g\nx\n", s.ed.doc.text());
    try expectEqual(.prompt, s.ed.mode);
    try expectEqualStrings("w", s.ed.prompt.text());
}

test "session: keys decoded during a load count toward what it holds" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    s.max_held = 8;
    try s.feed(":e g\ri");
    try s.feed("abc");
    try s.timeout();
    // Four bytes held as keys and four more fit; a fifth does not.
    try s.feed("xyzw");
    try s.feed("v");
    try finishLoad(&s);
    try expectEqualStrings("keys typed while reading were dropped", s.ed.message.text());
    try expectEqualStrings("abcxyzwg\n", s.ed.doc.text());
}

test "session: a paste decoded during a load is typed once it is in" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\ri\x1b[200~one\x1b[201~");
    try s.feed("\x1b");
    try s.timeout();
    try s.feed("i\x1b[200~two\x1b[201~");
    try s.timeout();
    try finishLoad(&s);
    try expectEqualStrings("onetwog\n", s.ed.doc.text());
}

test "session: closing the session during a load frees the keys it decoded" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    try s.feed(":e g\ri\x1b[200~kept\x1b[201~x\x1b");
    try s.timeout();
    // The testing allocator fails the test on a leak.
    s.deinit();
}

test "session: a paste that cannot be copied during a load is dropped, and it says so" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    // A first paste held grows every buffer, so the second one's copy is
    // the next allocation.
    try s.feed(":e g\ri\x1b[200~ab\x1b[201~");
    try s.timeout();
    try s.feed("\x1b[200~cd\x1b[201~");
    try waitLoad(&s);
    failing.fail_index = failing.alloc_index;
    try s.timeout();
    failing.fail_index = std.math.maxInt(usize);
    try s.feed("x");
    try s.timeout();
    try finishLoad(&s);
    try expectEqualStrings("keys typed while reading were dropped", s.ed.message.text());
    try expectEqualStrings("abxg\n", s.ed.doc.text());
}

test "session: keys held for a load that settle finished are still due" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\rix");
    try s.timeout();
    s.settle();
    // Nothing pending in the decoder, but the held keys wait to be typed.
    try expect(s.waiting());
    try expectEqualStrings("g\n", s.ed.doc.text());
    try s.timeout();
    try expect(!s.waiting());
    try expectEqualStrings("xg\n", s.ed.doc.text());
}

test "session: keys held after a :q typed during a load are freed with the session" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\r:q\ri\x1b[200~never\x1b[201~");
    try s.timeout();
    try finishLoad(&s);
    try expect(s.done());
    try expectEqualStrings("g\n", s.ed.doc.text());
}

test "session: keys decoded during a load come before a second load's" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    try withFile(&tmp, "h", "h\n");
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\r:e h\rix\x1b");
    try s.timeout();
    try s.feed("iy");
    try finishLoad(&s);
    // The held `:e h` started a second load; the keys after it wait.
    try expect(s.loading != null);
    try finishLoad(&s);
    try expectEqualStrings("h", s.ed.path.?);
    try expectEqualStrings("xyh\n", s.ed.doc.text());
}

test "session: running out of memory while decoding during a load keeps the bytes" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try withFile(&tmp, "g", "g\n");
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed(":e g\rix\x1b");
    try waitLoad(&s);
    failing.fail_index = failing.alloc_index;
    try s.timeout();
    failing.fail_index = std.math.maxInt(usize);
    try expectEqualStrings("out of memory", s.ed.message.text());
    // Nothing was lost: the next timeout decodes them.
    try s.timeout();
    try s.feed("iy");
    try finishLoad(&s);
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
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try s.feed("ix\x1b");
    try s.timeout();
    try s.feed(":w\r:e!\r");
    try expectEqual(null, s.saving);
    try finishLoad(&s);
    // Reloaded as written.
    try expectEqualStrings("x\n", s.ed.doc.text());
    try expect(!s.ed.doc.isModified());
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

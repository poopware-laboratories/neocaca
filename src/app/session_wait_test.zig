//! Tests for `:q` and `:e` typed while a save of `session.zig` is still
//! being written: they wait for it, then quit or open, unless the text
//! changed since the save began or the save fails.

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

test "session: :q during a save waits for it, then quits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:q\r");
    try expect(!s.done());
    s.settle();
    try expect(s.done());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: keys typed while :q waits for a save are dropped" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:q\riy\x1b");
    try expectEqualStrings("x\n", s.ed.doc.text());
    s.settle();
    try expect(s.done());
}

test "session: a mapping that writes and quits quits once the save is written" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, ":map normal Q :w<ret>:q<ret>\rix\x1bQ");
    s.settle();
    try expect(s.done());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: :q after an edit made since the save began is refused at once" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\riy\x1b:q\r");
    try expectEqualStrings("unsaved changes; :q! discards them", s.ed.message.text());
    // Keys still edit.
    try feedKeys(&s, "iz\x1b");
    try expectEqualStrings("xyz\n", s.ed.doc.text());
    s.settle();
    try expect(!s.done());
}

test "session: :q waiting for a save that fails stays, and says why" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "missing/f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:q\r");
    s.settle();
    try expect(!s.done());
    try expect(std.mem.startsWith(u8, s.ed.message.text(), "cannot write \"missing/f\": "));
    try feedKeys(&s, "iy\x1b");
    try expectEqualStrings("xy\n", s.ed.doc.text());
}

test "session: :q waiting for a save to another file finds the changes unsaved" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w g\r:q\r");
    s.settle();
    try expect(!s.done());
    try expectEqualStrings("unsaved changes; :q! discards them", s.ed.message.text());
    try feedKeys(&s, "iy\x1b");
    try expectEqualStrings("xy\n", s.ed.doc.text());
}

test "session: :e during a save waits for it, then opens the file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "g\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:e g\r");
    s.settle();
    try expectEqual(null, s.saving);
    try expectEqual(null, s.loading);
    try expectEqualStrings("g\n", s.ed.doc.text());
    try expectEqualStrings("g", s.ed.path.?);
    try expectEqualStrings("\"g\" 1 line", s.ed.message.text());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: :e waiting for a save starts the load when the save is collected" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "g\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:e g\r");
    s.saving.?.wait();
    try s.collect();
    try expectEqual(null, s.saving);
    // The load started; `collect` reports it too if it is already over.
    try expect(s.loading != null or std.mem.eql(u8, s.ed.doc.text(), "g\n"));
    s.settle();
    try expectEqualStrings("g\n", s.ed.doc.text());
}

test "session: :e that cannot copy its path to wait says so and waits for nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "g\n" });
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var s: Session = try .init(failing.allocator(), io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:e g");
    failing.fail_index = failing.alloc_index;
    try feedKeys(&s, "\r");
    failing.fail_index = std.math.maxInt(usize);
    try expectEqualStrings("out of memory", s.ed.message.text());
    // Keys still edit, and the save ends with no load after it.
    try feedKeys(&s, "iy\x1b");
    s.settle();
    try expectEqualStrings("xy\n", s.ed.doc.text());
    try expectEqualStrings("f", s.ed.path.?);
}

test "session: :e after an edit made since the save began opens the file beside it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "g\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\riy\x1b:e g\r");
    s.settle();
    try expectEqualStrings("g\n", s.ed.doc.text());
    const f = s.ed.buffer(0);
    try expectEqualStrings("xy\n", f.doc.text());
    // The edit after the save is still unsaved.
    try expect(f.doc.isModified());
}

test "session: :e of the current file after an edit made since the save began is refused at once" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\riy\x1b:e f\r");
    try expectEqualStrings("unsaved changes; :e! discards them", s.ed.message.text());
    s.settle();
    try expectEqualStrings("xy\n", s.ed.doc.text());
}

test "session: :e waiting for a save that fails keeps the text" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "g\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "missing/f", 20, 5);
    defer s.deinit();
    try feedKeys(&s, "ix\x1b:w\r:e g\r");
    s.settle();
    try expectEqualStrings("x\n", s.ed.doc.text());
    try expectEqualStrings("missing/f", s.ed.path.?);
    try expect(std.mem.startsWith(u8, s.ed.message.text(), "cannot write \"missing/f\": "));
}

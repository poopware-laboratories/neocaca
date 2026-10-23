//! Tests for the saves of `session.zig` over a file that something else
//! changed on disk since it was read or written: `:w` refuses, `:w!`
//! writes anyway.

const std = @import("std");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Types `keys` one byte per read, then waits for the save or load they
/// start.
fn typeKeys(s: *Session, keys: []const u8) !void {
    for (keys) |*b| {
        try s.feed(b[0..1]);
        try s.timeout();
    }
    s.settle();
    try s.collect();
}

fn expectFile(dir: std.Io.Dir, path: []const u8, want: []const u8) !void {
    var buf: [64]u8 = undefined;
    try expectEqualStrings(want, try dir.readFile(io, path, &buf));
}

const refused = "cannot write \"log\": the file changed on disk; :w! writes it anyway";

test "session: :w refuses a file appended to since it was opened, and :w! writes it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    // Another program appends a line while the file is open.
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    try typeKeys(&s, "ix\x1b:w\r");
    try expectEqualStrings(refused, s.ed.message.text());
    try expect(s.ed.message.is_error);
    try expect(s.ed.doc.isModified());
    try expectFile(tmp.dir, "log", "one\ntwo\n");
    try typeKeys(&s, ":w!\r");
    try expectEqualStrings("\"log\" written, 1 line", s.ed.message.text());
    try expect(!s.ed.doc.isModified());
    try expectFile(tmp.dir, "log", "xone\n");
    // The file is ours again: a plain :w writes.
    try typeKeys(&s, "iy\x1b:w\r");
    try expectFile(tmp.dir, "log", "xyone\n");
}

test "session: :wq over a file changed on disk neither writes nor quits" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    try typeKeys(&s, "ix\x1b:wq\r");
    try expectEqualStrings(refused, s.ed.message.text());
    try expect(!s.done());
    try expectFile(tmp.dir, "log", "one\ntwo\n");
}

test "session: saves one after another, none waited for, all write" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    // Each save expects the file the one before it wrote.
    for ("abc") |*c| {
        try s.feed("i");
        try s.feed(c[0..1]);
        try s.feed("\x1b");
        try s.timeout();
        try s.feed(":w\r");
    }
    s.settle();
    try expectEqualStrings("\"log\" written, 1 line", s.ed.message.text());
    try expectFile(tmp.dir, "log", "abcone\n");
}

test "session: a file opened with :e is checked too" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a", .data = "a\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "a", 80, 5);
    defer s.deinit();
    try typeKeys(&s, ":e log\r");
    try expectEqualStrings("one\n", s.ed.doc.text());
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    try typeKeys(&s, "ix\x1b:w\r");
    try expectEqualStrings(refused, s.ed.message.text());
    try expectFile(tmp.dir, "log", "one\ntwo\n");
}

test "session: a new file that another program made meanwhile is not written over" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "theirs\n" });
    try typeKeys(&s, "ix\x1b:w\r");
    try expectEqualStrings(refused, s.ed.message.text());
    try expectFile(tmp.dir, "log", "theirs\n");
}

test "session: a scratch buffer's file is checked once it is written" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 80, 5);
    defer s.deinit();
    try typeKeys(&s, "ix\x1b:w log\r");
    try expectFile(tmp.dir, "log", "x\n");
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "x\ntwo\n" });
    try typeKeys(&s, "iy\x1b:w\r");
    try expectEqualStrings(refused, s.ed.message.text());
    try expectFile(tmp.dir, "log", "x\ntwo\n");
}

test "session: a file written under another name is not checked against the open one" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "copy", .data = "old\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "log", 80, 5);
    defer s.deinit();
    try typeKeys(&s, ":w copy\r");
    try expectFile(tmp.dir, "copy", "one\n");
    // Writing the copy says nothing of the open file, which is unchanged.
    try typeKeys(&s, "ix\x1b:w\r");
    try expectFile(tmp.dir, "log", "xone\n");
}

//! Tests for what a `Session` opens: a file it cannot read is refused,
//! one whose directory is missing opens new with a warning.

const std = @import("std");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;

fn expectText(s: *const Session, want: []const u8) !void {
    try expectEqualStrings(want, s.ed.doc.text());
}

fn expectMessage(s: *const Session, want: []const u8) !void {
    try expectEqualStrings(want, s.ed.message.text());
}

/// Types `keys` one byte per read, then waits for a save they started.
fn typeKeys(s: *Session, keys: []const u8) !void {
    for (keys) |*b| {
        try s.feed(b[0..1]);
        try s.timeout();
    }
    s.settle();
}

test "session: a file that cannot be read is refused, not opened empty" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try std.testing.expectError(error.IsDir, Session.init(gpa, io, tmp.dir, "d", 20, 5));
}

test "session: a file in a missing directory opens new, and says the directory is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "gone/f", 20, 5);
    defer s.deinit();
    try expectText(&s, "\n");
    try expectEqualStrings("gone/f", s.ed.path.?);
    try expectMessage(&s, "\"gone/f\" new file; its directory does not exist");
    try expect(s.ed.message.is_error);
    try typeKeys(&s, "ix\x1b:w\r");
    try expectMessage(&s, "cannot write \"gone/f\": no such file or directory");
    try expect(!s.done());
}

test "session: a device is refused, not opened empty" {
    try std.testing.expectError(error.NotAFile, Session.init(gpa, io, std.Io.Dir.cwd(), "/dev/null", 20, 5));
}

test "session: opening in a missing directory leaks nothing when memory runs short" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.checkAllAllocationFailures(gpa, openMissing, .{tmp.dir});
}

fn openMissing(a: std.mem.Allocator, dir: std.Io.Dir) !void {
    var s: Session = try .init(a, io, dir, "gone/f", 20, 5);
    defer s.deinit();
    try expectMessage(&s, "\"gone/f\" new file; its directory does not exist");
}

//! Tests for `session.zig` with several buffers open: each one's unsaved
//! changes recovered beside its own file, in its own form.

const std = @import("std");
const Session = @import("session.zig").Session;
const recovery = @import("recovery.zig");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Types `keys` with a pause after each, as a person does.
fn typeKeys(s: *Session, keys: []const u8) !void {
    for (keys) |*b| {
        try s.feed(b[0..1]);
        try s.timeout();
    }
    s.settle();
}

test "session buffers: each buffer is recovered beside its own file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "a", 20, 4);
    defer s.deinit();
    try s.ed.open("b", "beta\n");
    try typeKeys(&s, "ix\x1b");
    try s.ed.open("c", "gamma\n");
    s.ed.switchTo(0);
    try typeKeys(&s, "iy\x1b");
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("a.recovered", s.recover(0, &buf).written);
    try expectEqualStrings("b.recovered", s.recover(1, &buf).written);
    // Unchanged: nothing to recover.
    try expectEqual(.none, s.recover(2, &buf));
    var text: [16]u8 = undefined;
    try expectEqualStrings("y\n", try tmp.dir.readFile(io, "a.recovered", &text));
    try expectEqualStrings("xbeta\n", try tmp.dir.readFile(io, "b.recovered", &text));
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFile(io, "c.recovered", &text));
}

test "session buffers: a buffer not current is recovered in its own form" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "a", 20, 4);
    defer s.deinit();
    try s.ed.open("b", "beta\n");
    s.ed.form.ending = .crlf;
    try typeKeys(&s, "ix\x1b");
    s.ed.switchTo(0);
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("b.recovered", s.recover(1, &buf).written);
    var text: [16]u8 = undefined;
    try expectEqualStrings("xbeta\r\n", try tmp.dir.readFile(io, "b.recovered", &text));
}

test "session buffers: two buffers without a file take the next free name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 4);
    defer s.deinit();
    try typeKeys(&s, "ione\x1b");
    try s.ed.open(null, "");
    try typeKeys(&s, "itwo\x1b");
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("caca.recovered", s.recover(0, &buf).written);
    try expectEqualStrings("caca.recovered.1", s.recover(1, &buf).written);
    var text: [16]u8 = undefined;
    try expectEqualStrings("one\n", try tmp.dir.readFile(io, "caca.recovered", &text));
    try expectEqualStrings("two\n", try tmp.dir.readFile(io, "caca.recovered.1", &text));
}

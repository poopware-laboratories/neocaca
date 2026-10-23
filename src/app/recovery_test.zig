//! Tests for `recovery.zig`: where the unsaved text of a lost terminal is
//! written, and that nothing there is ever replaced.

const std = @import("std");
const recovery = @import("recovery.zig");

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "recovery: the names tried, in order" {
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("notes.txt.recovered", try recovery.name(&buf, "notes.txt", 0));
    try expectEqualStrings("notes.txt.recovered.1", try recovery.name(&buf, "notes.txt", 1));
    try expectEqualStrings("d/f.recovered.99", try recovery.name(&buf, "d/f", 99));
    // A scratch buffer has no file of its own.
    try expectEqualStrings("neocaca.recovered", try recovery.name(&buf, null, 0));
    try expectEqualStrings("neocaca.recovered.2", try recovery.name(&buf, null, 2));
}

test "recovery: a path too long for a name fails" {
    var buf: [recovery.max_name]u8 = undefined;
    const fits: [recovery.max_name - ".recovered.99".len]u8 = @splat('p');
    try expectEqual(recovery.max_name, (try recovery.name(&buf, &fits, 99)).len);
    try std.testing.expectError(error.NameTooLong, recovery.name(&buf, fits ++ "p", 99));
    const long: [recovery.max_name]u8 = @splat('q');
    try std.testing.expectError(error.NameTooLong, recovery.name(&buf, &long, 0));
}

test "recovery: writes the text beside its file and says where" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "saved\n" });
    var buf: [recovery.max_name]u8 = undefined;
    const where = try recovery.write(io, tmp.dir, "f", "unsaved\n", &buf);
    try expectEqualStrings("f.recovered", where);
    var text: [16]u8 = undefined;
    try expectEqualStrings("unsaved\n", try tmp.dir.readFile(io, "f.recovered", &text));
    // The file itself is left alone.
    try expectEqualStrings("saved\n", try tmp.dir.readFile(io, "f", &text));
}

test "recovery: an earlier recovery is kept, the next name is taken" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f.recovered", .data = "first\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "f.recovered.1", .data = "second\n" });
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("f.recovered.2", try recovery.write(io, tmp.dir, "f", "third\n", &buf));
    var text: [16]u8 = undefined;
    try expectEqualStrings("first\n", try tmp.dir.readFile(io, "f.recovered", &text));
    try expectEqualStrings("second\n", try tmp.dir.readFile(io, "f.recovered.1", &text));
    try expectEqualStrings("third\n", try tmp.dir.readFile(io, "f.recovered.2", &text));
}

test "recovery: a scratch buffer is written in the directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [recovery.max_name]u8 = undefined;
    try expectEqualStrings("neocaca.recovered", try recovery.write(io, tmp.dir, null, "x\n", &buf));
    var text: [16]u8 = undefined;
    try expectEqualStrings("x\n", try tmp.dir.readFile(io, "neocaca.recovered", &text));
}

test "recovery: the last name is still tried" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [recovery.max_name]u8 = undefined;
    for (0..recovery.max_tries - 1) |i| {
        try tmp.dir.writeFile(io, .{ .sub_path = try recovery.name(&buf, "f", i), .data = "" });
    }
    try std.testing.expectEqualStrings("f.recovered.99", try recovery.write(io, tmp.dir, "f", "x\n", &buf));
}

test "recovery: when every name is taken it gives up" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [recovery.max_name]u8 = undefined;
    for (0..recovery.max_tries) |i| {
        try tmp.dir.writeFile(io, .{ .sub_path = try recovery.name(&buf, "f", i), .data = "" });
    }
    try std.testing.expectError(error.NoFreeName, recovery.write(io, tmp.dir, "f", "x\n", &buf));
}

test "recovery: a directory it cannot write in is an error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [recovery.max_name]u8 = undefined;
    try std.testing.expectError(error.FileNotFound, recovery.write(io, tmp.dir, "gone/f", "x\n", &buf));
}

test "recovery: why it failed reads as words" {
    try std.testing.expectEqualStrings("every recovery file name is taken", recovery.describe(error.NoFreeName));
    try std.testing.expectEqualStrings("the name is too long", recovery.describe(error.NameTooLong));
    try std.testing.expectEqualStrings("no space left on the device", recovery.describe(error.NoSpaceLeft));
}

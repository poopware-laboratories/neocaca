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

test "recovery: a name too long for its suffix is cut to fit" {
    var buf: [recovery.max_name]u8 = undefined;
    const fits: [255 - ".recovered.99".len]u8 = @splat('p');
    try expectEqualStrings(fits ++ ".recovered.99", try recovery.name(&buf, &fits, 99));
    // One byte more, and the name loses one byte to keep its suffix.
    try expectEqualStrings(fits ++ ".recovered.99", try recovery.name(&buf, fits ++ "p", 99));
    const longest: [255]u8 = @splat('q');
    const first = try recovery.name(&buf, &longest, 0);
    try expectEqual(255, first.len);
    try expect(std.mem.endsWith(u8, first, "q.recovered"));
    try expectEqual(255, (try recovery.name(&buf, &longest, 7)).len);
}

test "recovery: only the file's own name is cut, never its directories" {
    var buf: [recovery.max_name]u8 = undefined;
    const long: [250]u8 = @splat('n');
    const got = try recovery.name(&buf, "some/dir/" ++ long, 1);
    try expect(std.mem.startsWith(u8, got, "some/dir/nnn"));
    try expectEqual("some/dir/".len + 255, got.len);
    try expect(std.mem.endsWith(u8, got, "n.recovered.1"));
}

test "recovery: a cut name keeps its characters whole" {
    var buf: [recovery.max_name]u8 = undefined;
    // 122 two-byte characters: 244 bytes, cut to 245 - 1 for `.recovered`.
    const wide: [244]u8 = comptime blk: {
        var b: [244]u8 = undefined;
        for (0..122) |i| b[2 * i ..][0..2].* = "é".*;
        break :blk b;
    };
    const got = try recovery.name(&buf, "a" ++ wide, 0);
    try expect(got.len <= 255);
    try expect(std.unicode.utf8ValidateSlice(got));
    try expect(std.mem.endsWith(u8, got, "é.recovered"));
}

test "recovery: a path past the system's limit still fails" {
    var buf: [recovery.max_name]u8 = undefined;
    const dirs: [recovery.max_name - 4]u8 = @splat('d');
    try std.testing.expectError(error.NameTooLong, recovery.name(&buf, dirs ++ "/f", 0));
}

test "recovery: a file with the longest name there is gets its text recovered" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const longest: [255]u8 = @splat('l');
    try tmp.dir.writeFile(io, .{ .sub_path = &longest, .data = "saved\n" });
    var buf: [recovery.max_name]u8 = undefined;
    const where = try recovery.write(io, tmp.dir, &longest, "unsaved\n", &buf);
    try expectEqual(255, where.len);
    var text: [16]u8 = undefined;
    try expectEqualStrings("unsaved\n", try tmp.dir.readFile(io, where, &text));
    try expectEqualStrings("saved\n", try tmp.dir.readFile(io, &longest, &text));
    // A second recovery takes the next name, also cut to fit.
    const again = try recovery.write(io, tmp.dir, &longest, "later\n", &buf);
    try expect(std.mem.endsWith(u8, again, ".recovered.1"));
    try expectEqualStrings("later\n", try tmp.dir.readFile(io, again, &text));
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

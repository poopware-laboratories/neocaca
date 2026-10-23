//! Tests for `temp.zig`, in a temporary directory.

const std = @import("std");
const temp = @import("temp.zig");

const io = std.testing.io;
const expect = std.testing.expect;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "temp: the name says which file it was for, and hides it" {
    var buf: [temp.max_name]u8 = undefined;
    try expectEqualStrings(".unicode.txt.4efc61bb66dd3e91.tmp", temp.name(&buf, "unicode.txt", 0x4efc61bb66dd3e91));
    try expectEqualStrings(".f.0000000000000001.tmp", temp.name(&buf, "f", 1));
}

test "temp: a hidden file's name is not given a second dot" {
    var buf: [temp.max_name]u8 = undefined;
    try expectEqualStrings(".bashrc.ffffffffffffffff.tmp", temp.name(&buf, ".bashrc", std.math.maxInt(u64)));
}

test "temp: a long name is cut to fit, and keeps its random part" {
    var buf: [temp.max_name]u8 = undefined;
    const long: [temp.max_name]u8 = @splat('a');
    const got = temp.name(&buf, &long, 2);
    try std.testing.expectEqual(temp.max_name, got.len);
    try expect(std.mem.startsWith(u8, got, ".aaaa"));
    try expect(std.mem.endsWith(u8, got, "a.0000000000000002.tmp"));
    // One short of the cut keeps the whole name.
    const fits = long[0 .. temp.max_name - 22];
    try std.testing.expectEqual(temp.max_name, temp.name(&buf, fits, 2).len);
    try expect(std.mem.startsWith(u8, temp.name(&buf, fits, 2)[1..], fits));
}

test "temp: a long name is cut between characters, never inside one" {
    var buf: [temp.max_name]u8 = undefined;
    // 'é' is two bytes; 117 of them put the cut at 233 bytes inside one.
    var long: [234]u8 = undefined;
    for (0..117) |i| long[2 * i ..][0..2].* = "é".*;
    const got = temp.name(&buf, &long, 3);
    try expect(std.unicode.utf8ValidateSlice(got));
    try expectEqualStrings(long[0..232], got[1 .. got.len - 21]);
}

test "temp: a cut through an emoji backs off to its start" {
    var buf: [temp.max_name]u8 = undefined;
    // 232 bytes, then a four-byte emoji the cut at 233 lands in.
    const long = @as([232]u8, @splat('a')) ++ "😀".*;
    const got = temp.name(&buf, &long, 4);
    try expectEqualStrings(".", got[0..1]);
    try expectEqualStrings(long[0..232], got[1 .. got.len - 21]);
    try expect(std.unicode.utf8ValidateSlice(got));
}

test "temp: a long name of invalid UTF-8 is cut, not emptied" {
    var buf: [temp.max_name]u8 = undefined;
    // Nothing but continuation bytes: no character start to back off to.
    const long: [temp.max_name]u8 = @splat(0x80);
    const got = temp.name(&buf, &long, 5);
    try expect(got.len >= temp.max_name - 3);
    try expect(std.mem.endsWith(u8, got, ".0000000000000005.tmp"));
}

test "temp: create makes a new file beside the one it is for" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "sub", .default_dir);
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const t = try temp.create(io, tmp.dir, "sub/f.txt", &buf);
    t.file.close(io);
    try expect(std.mem.startsWith(u8, t.path, "sub/.f.txt."));
    try expect(std.mem.endsWith(u8, t.path, ".tmp"));
    try std.testing.expectEqual(("sub/.f.txt.".len + 16 + ".tmp".len), t.path.len);
    const st = try tmp.dir.statFile(io, t.path, .{});
    try std.testing.expectEqual(0, st.size);
}

test "temp: create never opens a file that is already there" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var a_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var b_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const a = try temp.create(io, tmp.dir, "f", &a_buf);
    try a.file.writePositionalAll(io, "first", 0);
    a.file.close(io);
    const b = try temp.create(io, tmp.dir, "f", &b_buf);
    b.file.close(io);
    try expect(!std.mem.eql(u8, a.path, b.path));
    var got: [8]u8 = undefined;
    try expectEqualStrings("first", try tmp.dir.readFile(io, a.path, &got));
}

test "temp: create in a missing directory fails and makes nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try expectError(error.FileNotFound, temp.create(io, tmp.dir, "missing/f", &buf));
    try expectError(error.FileNotFound, tmp.dir.access(io, "missing", .{}));
}

test "temp: a path with no room for the temporary name is refused" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    // Directories `d/d/…/f`, short enough to name, too long to name its
    // temporary file beside it.
    var deep: [std.Io.Dir.max_path_bytes - 10]u8 = undefined;
    for (&deep, 0..) |*c, i| c.* = if (i % 2 == 0) 'd' else '/';
    deep[deep.len - 1] = 'f';
    try expectError(error.NameTooLong, temp.create(io, tmp.dir, &deep, &buf));
}

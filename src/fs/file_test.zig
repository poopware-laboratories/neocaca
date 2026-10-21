//! Tests for `file.zig`, in a temporary directory.

const std = @import("std");
const file = @import("file.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "file: load reads the whole file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "one\ntwo\n" });
    const got = (try file.load(io, gpa, tmp.dir, "a.txt", file.max_file)).?;
    defer gpa.free(got);
    try expectEqualStrings("one\ntwo\n", got);
}

test "file: a missing file loads as null, a new buffer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectEqual(null, try file.load(io, gpa, tmp.dir, "new.txt", file.max_file));
}

test "file: load keeps any bytes, invalid UTF-8 and NULs included" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const bytes = "\x00\xff\x1b[2J\r\n";
    try tmp.dir.writeFile(io, .{ .sub_path = "b", .data = bytes });
    const got = (try file.load(io, gpa, tmp.dir, "b", file.max_file)).?;
    defer gpa.free(got);
    try expectEqualStrings(bytes, got);
}

test "file: load refuses a file over the limit, and takes one at it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "big", .data = "12345" });
    try expectError(error.FileTooBig, file.load(io, gpa, tmp.dir, "big", 4));
    const got = (try file.load(io, gpa, tmp.dir, "big", 5)).?;
    defer gpa.free(got);
    try expectEqualStrings("12345", got);
}

test "file: load refuses a directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try expectError(error.IsDir, file.load(io, gpa, tmp.dir, "d", file.max_file));
}

test "file: save creates a new file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try file.save(io, tmp.dir, "n.txt", "hello\n");
    var buf: [64]u8 = undefined;
    try expectEqualStrings("hello\n", try tmp.dir.readFile(io, "n.txt", &buf));
}

test "file: save replaces the contents and leaves no temporary file" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "a much longer old text\n" });
    try file.save(io, tmp.dir, "f", "new\n");
    var buf: [64]u8 = undefined;
    try expectEqualStrings("new\n", try tmp.dir.readFile(io, "f", &buf));
    var it = tmp.dir.iterate();
    var count: usize = 0;
    while (try it.next(io)) |entry| {
        try expectEqualStrings("f", entry.name);
        count += 1;
    }
    try std.testing.expectEqual(1, count);
}

test "file: save keeps the permissions of the file it replaces" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "x.sh", .data = "#!/bin/sh\n" });
    try tmp.dir.setFilePermissions(io, "x.sh", .fromMode(0o751), .{});
    try file.save(io, tmp.dir, "x.sh", "#!/bin/sh\nexit 0\n");
    const st = try tmp.dir.statFile(io, "x.sh", .{});
    try std.testing.expectEqual(0o751, st.permissions.toMode() & 0o7777);
}

test "file: a failed save leaves the original untouched" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    // A directory cannot be replaced by a file: the rename fails.
    if (file.save(io, tmp.dir, "d", "text\n")) |_| {
        return error.TestUnexpectedResult;
    } else |_| {}
    const st = try tmp.dir.statFile(io, "d", .{});
    try std.testing.expectEqual(.directory, st.kind);
}

test "file: save into a missing directory fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try expectError(error.FileNotFound, file.save(io, tmp.dir, "no/such/f", "x\n"));
}

test "file: a saved file loads back byte for byte" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    try file.save(io, tmp.dir, "all", &bytes);
    const got = (try file.load(io, gpa, tmp.dir, "all", file.max_file)).?;
    defer gpa.free(got);
    try std.testing.expectEqualSlices(u8, &bytes, got);
}

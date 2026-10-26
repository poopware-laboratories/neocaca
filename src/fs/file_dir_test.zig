//! Tests for `file.save` on a path that names a directory: refused as
//! one, with nothing made beside it or in it.

const std = @import("std");
const file = @import("file.zig");

const io = std.testing.io;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

/// The names in `dir`, in `buf`, sorted.
fn entries(dir: std.Io.Dir, buf: *[8][]const u8, names: *[8][64]u8) ![]const []const u8 {
    var it = dir.iterate();
    var n: usize = 0;
    while (try it.next(io)) |entry| {
        @memcpy(names[n][0..entry.name.len], entry.name);
        buf[n] = names[n][0..entry.name.len];
        n += 1;
    }
    std.mem.sort([]const u8, buf[0..n], {}, struct {
        fn less(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.less);
    return buf[0..n];
}

/// Fails unless `dir` holds exactly `want`.
fn expectEntries(dir: std.Io.Dir, want: []const []const u8) !void {
    var buf: [8][]const u8 = undefined;
    var names: [8][64]u8 = undefined;
    const got = try entries(dir, &buf, &names);
    try expectEqual(want.len, got.len);
    for (want, got) |w, g| try expectEqualStrings(w, g);
}

test "file: save to a directory named with a final slash is refused as a directory" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try expectError(error.IsDir, file.save(io, tmp.dir, "d/", "x\n", .{}));
    try expectEntries(tmp.dir, &.{"d"});
    var d = try tmp.dir.openDir(io, "d", .{ .iterate = true });
    defer d.close(io);
    try expectEntries(d, &.{});
}

test "file: save to a directory named without a slash is refused as a directory" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try expectError(error.IsDir, file.save(io, tmp.dir, "d", "x\n", .{}));
    try expectEntries(tmp.dir, &.{"d"});
}

test "file: save to a missing name with a final slash is refused, and makes nothing" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try expectError(error.IsDir, file.save(io, tmp.dir, "new/", "x\n", .{}));
    try expectEntries(tmp.dir, &.{});
}

test "file: save through a link to a directory is refused, and keeps the link" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.symLink(io, "d", "l", .{});
    try expectError(error.IsDir, file.save(io, tmp.dir, "l", "x\n", .{}));
    try expectEntries(tmp.dir, &.{ "d", "l" });
    var buf: [8]u8 = undefined;
    const n = try tmp.dir.readLink(io, "l", &buf);
    try expectEqualStrings("d", buf[0..n]);
}

test "file: a forced save to a directory is refused all the same" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try expectError(error.IsDir, file.save(io, tmp.dir, "d", "x\n", .{ .force = true }));
    try expectError(error.IsDir, file.save(io, tmp.dir, "d/", "x\n", .{ .force = true }));
    try expectEntries(tmp.dir, &.{"d"});
}

test "file: a file in a subdirectory still saves" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    _ = try file.save(io, tmp.dir, "d/f", "x\n", .{});
    var buf: [8]u8 = undefined;
    try expectEqualStrings("x\n", try tmp.dir.readFile(io, "d/f", &buf));
    try expectEntries(tmp.dir, &.{"d"});
}

test "file: save to . or .. is refused as a directory, and makes nothing" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    var d = try tmp.dir.openDir(io, "d", .{ .iterate = true });
    defer d.close(io);
    for ([_][]const u8{ ".", "..", "./", "../d" }) |path| {
        try expectError(error.IsDir, file.save(io, d, path, "x\n", .{}));
        try expectEntries(d, &.{});
        try expectEntries(tmp.dir, &.{"d"});
    }
}

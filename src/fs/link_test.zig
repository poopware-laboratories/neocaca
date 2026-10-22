//! Tests for `link.zig`, on links made in a temporary directory.

const std = @import("std");
const link = @import("link.zig");

const io = std.testing.io;
const expectEqualStrings = std.testing.expectEqualStrings;

var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;

test "link: a path that is no link names itself" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "" });
    try expectEqualStrings("f", try link.resolve(io, tmp.dir, "f", &buf));
    try expectEqualStrings("missing", try link.resolve(io, tmp.dir, "missing", &buf));
}

test "link: a relative target is taken from the link's directory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.symLink(io, "t", "d/l", .{});
    try expectEqualStrings("d/t", try link.resolve(io, tmp.dir, "d/l", &buf));
    try tmp.dir.symLink(io, "../t", "d/up", .{});
    try expectEqualStrings("d/../t", try link.resolve(io, tmp.dir, "d/up", &buf));
}

test "link: a chain is followed to the file at its end" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "d/c", .data = "" });
    try tmp.dir.symLink(io, "d/b", "a", .{});
    try tmp.dir.symLink(io, "c", "d/b", .{});
    try expectEqualStrings("d/c", try link.resolve(io, tmp.dir, "a", &buf));
}

test "link: a dangling link names the file a save would make" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "new", "l", .{});
    try expectEqualStrings("new", try link.resolve(io, tmp.dir, "l", &buf));
}

test "link: an absolute target replaces the whole path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var abs: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &abs);
    const target = try std.fmt.bufPrint(abs[n..], "{s}/t", .{abs[0..n]});
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.symLink(io, target, "d/l", .{});
    try expectEqualStrings(target, try link.resolve(io, tmp.dir, "d/l", &buf));
}

test "link: links that point at each other fail" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "b", "a", .{});
    try tmp.dir.symLink(io, "a", "b", .{});
    try std.testing.expectError(error.SymLinkLoop, link.resolve(io, tmp.dir, "a", &buf));
    try tmp.dir.symLink(io, "self", "self", .{});
    try std.testing.expectError(error.SymLinkLoop, link.resolve(io, tmp.dir, "self", &buf));
}

/// Links `l0` → `l1` → … → `l<n>`, the last of them a file.
fn chain(dir: std.Io.Dir, n: usize) !void {
    var name: [16]u8 = undefined;
    var next: [16]u8 = undefined;
    for (0..n) |i| {
        try dir.symLink(io, try std.fmt.bufPrint(&next, "l{d}", .{i + 1}), try std.fmt.bufPrint(&name, "l{d}", .{i}), .{});
    }
    try dir.writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name, "l{d}", .{n}), .data = "" });
}

test "link: max_links links are followed, one more fails" {
    var at = std.testing.tmpDir(.{});
    defer at.cleanup();
    try chain(at.dir, link.max_links);
    try expectEqualStrings(std.fmt.comptimePrint("l{d}", .{link.max_links}), try link.resolve(io, at.dir, "l0", &buf));
    var past = std.testing.tmpDir(.{});
    defer past.cleanup();
    try chain(past.dir, link.max_links + 1);
    try std.testing.expectError(error.SymLinkLoop, link.resolve(io, past.dir, "l0", &buf));
}

test "link: a target that makes the path too long fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    // Fits as a target, not behind `d/`.
    const long: [255]u8 = @splat('x');
    var small: [200]u8 = undefined;
    try tmp.dir.symLink(io, &long, "d/l", .{});
    try std.testing.expectError(error.NameTooLong, link.resolve(io, tmp.dir, "d/l", &small));
}

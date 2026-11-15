//! Tests for the paths `file.zig` is given: saves through symbolic links,
//! names too long for the system, missing directories told apart from new
//! files, and names cut between characters to fit.

const std = @import("std");
const file = @import("file.zig");

const gpa = std.testing.allocator;
const io = std.testing.io;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

test "file: save through a link replaces the file it names, and keeps the link" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "d/t", .data = "old\n" });
    try tmp.dir.symLink(io, "d/t", "l", .{});
    _ = try file.save(io, tmp.dir, "l", "new\n", .{});
    var got: [16]u8 = undefined;
    try expectEqualStrings("new\n", try tmp.dir.readFile(io, "d/t", &got));
    const n = try tmp.dir.readLink(io, "l", &got);
    try expectEqualStrings("d/t", got[0..n]);
}

test "file: save through a dangling link makes the file it names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "t", "l", .{});
    _ = try file.save(io, tmp.dir, "l", "x\n", .{});
    var got: [16]u8 = undefined;
    try expectEqualStrings("x\n", try tmp.dir.readFile(io, "t", &got));
}

test "file: save through a link loop fails and makes nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "b", "a", .{});
    try tmp.dir.symLink(io, "a", "b", .{});
    try expectError(error.SymLinkLoop, file.save(io, tmp.dir, "a", "x\n", .{}));
    var got: [16]u8 = undefined;
    const n = try tmp.dir.readLink(io, "a", &got);
    try expectEqualStrings("b", got[0..n]);
}

test "file: a name of 255 bytes is a name, one of 256 is refused before the system sees it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const longest: []const u8 = &@as([file.max_name]u8, @splat('n'));
    const over: []const u8 = &@as([file.max_name + 1]u8, @splat('n'));
    try std.testing.expectEqual(null, try file.load(io, gpa, tmp.dir, longest, file.max_file));
    _ = try file.save(io, tmp.dir, longest, "x\n", .{});
    try expectError(error.NameTooLong, file.load(io, gpa, tmp.dir, over, file.max_file));
    try expectError(error.NameTooLong, file.save(io, tmp.dir, over, "x\n", .{}));
    try expectError(error.NameTooLong, file.create(io, tmp.dir, over, "x\n"));
}

test "file: a long name is refused in any part of the path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    const over: [file.max_name + 1]u8 = @splat('n');
    try expectError(error.NameTooLong, file.load(io, gpa, tmp.dir, "d/" ++ over, file.max_file));
    try expectError(error.NameTooLong, file.save(io, tmp.dir, over ++ "/f", "x\n", .{}));
    try expectError(error.NameTooLong, file.create(io, tmp.dir, "./" ++ over, "x\n"));
}

test "file: a file whose directory is missing is told apart from a new file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "x" });
    try std.testing.expectEqual(null, try file.load(io, gpa, tmp.dir, "d/new", file.max_file));
    try expectError(error.NoDirectory, file.load(io, gpa, tmp.dir, "gone/new", file.max_file));
    try expectError(error.NoDirectory, file.load(io, gpa, tmp.dir, "d/gone/new", file.max_file));
    // A path through a file: Linux and macOS report it differently.
    try expectError(error.NoDirectory, file.load(io, gpa, tmp.dir, "f/new", file.max_file));
}

test "file: an absolute path in a missing directory is told apart too" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try expectError(error.NoDirectory, file.load(io, gpa, std.Io.Dir.cwd(), "/neocaca-no-such-directory/f", file.max_file));
    try std.testing.expectEqual(null, try file.load(io, gpa, tmp.dir, "./new", file.max_file));
}

test "file: a name that fits is kept whole" {
    try std.testing.expectEqualStrings("notes.txt", file.fitName("notes.txt", 9));
    try std.testing.expectEqualStrings("notes.txt", file.fitName("notes.txt", 255));
    try std.testing.expectEqualStrings("", file.fitName("", 0));
}

test "file: a name is cut to its room, between characters" {
    try std.testing.expectEqualStrings("note", file.fitName("notes.txt", 4));
    try std.testing.expectEqualStrings("", file.fitName("notes.txt", 0));
    // é is two bytes, € three, 😀 four: a cut inside one backs off to its start.
    try std.testing.expectEqualStrings("a", file.fitName("aé", 2));
    try std.testing.expectEqualStrings("aé", file.fitName("aé", 3));
    try std.testing.expectEqualStrings("a", file.fitName("a€", 3));
    try std.testing.expectEqualStrings("a", file.fitName("a😀", 4));
    try std.testing.expectEqualStrings("a😀", file.fitName("a😀b", 5));
}

test "file: invalid UTF-8 is cut at its room, never emptied" {
    // Continuation bytes with no start: no character to keep whole.
    const bad = "\x80\x80\x80\x80\x80\x80";
    try std.testing.expectEqualStrings("\x80\x80", file.fitName(bad, 2));
    try std.testing.expectEqualStrings("a\x80\x80\x80\x80", file.fitName("a" ++ bad, 5));
}

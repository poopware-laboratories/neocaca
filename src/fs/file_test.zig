//! Tests for `file.zig`, in a temporary directory.

const std = @import("std");
const builtin = @import("builtin");
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

test "file: load refuses a named pipe instead of waiting for a writer" {
    if (builtin.target.os.tag != .linux) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const linux = std.os.linux;
    const rc = linux.mknodat(tmp.dir.handle, "p", linux.S.IFIFO | 0o600, 0);
    try std.testing.expectEqual(.SUCCESS, linux.errno(rc));
    try expectError(error.NotAFile, file.load(io, gpa, tmp.dir, "p", file.max_file));
}

test "file: load refuses a device, whose reads may never end" {
    try expectError(error.NotAFile, file.load(io, gpa, std.Io.Dir.cwd(), "/dev/null", file.max_file));
    try expectError(error.NotAFile, file.load(io, gpa, std.Io.Dir.cwd(), "/dev/zero", 1));
}

test "file: load follows a link to a regular file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "real", .data = "x\n" });
    try tmp.dir.symLink(io, "real", "l", .{});
    const got = (try file.load(io, gpa, tmp.dir, "l", file.max_file)).?;
    defer gpa.free(got);
    try expectEqualStrings("x\n", got);
}

test "file: save creates a new file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try file.save(io, tmp.dir, "n.txt", "hello\n", .{});
    var buf: [64]u8 = undefined;
    try expectEqualStrings("hello\n", try tmp.dir.readFile(io, "n.txt", &buf));
}

test "file: save replaces the contents and leaves no temporary file" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "a much longer old text\n" });
    try file.save(io, tmp.dir, "f", "new\n", .{});
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
    try file.save(io, tmp.dir, "x.sh", "#!/bin/sh\nexit 0\n", .{});
    const st = try tmp.dir.statFile(io, "x.sh", .{});
    try std.testing.expectEqual(0o751, st.permissions.toMode() & 0o7777);
}

test "file: save refuses a read-only file and leaves it as it was" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "r", .data = "old\n" });
    try tmp.dir.setFilePermissions(io, "r", .fromMode(0o444), .{});
    try expectError(error.ReadOnly, file.save(io, tmp.dir, "r", "new\n", .{}));
    var buf: [16]u8 = undefined;
    try expectEqualStrings("old\n", try tmp.dir.readFile(io, "r", &buf));
    var it = tmp.dir.iterate();
    while (try it.next(io)) |entry| try expectEqualStrings("r", entry.name);
}

test "file: a forced save replaces a read-only file, which stays read-only" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "r", .data = "old\n" });
    try tmp.dir.setFilePermissions(io, "r", .fromMode(0o444), .{});
    try file.save(io, tmp.dir, "r", "new\n", .{ .force = true });
    var buf: [16]u8 = undefined;
    try expectEqualStrings("new\n", try tmp.dir.readFile(io, "r", &buf));
    const st = try tmp.dir.statFile(io, "r", .{});
    try std.testing.expectEqual(0o444, st.permissions.toMode() & 0o7777);
}

test "file: a file anyone may write is not read-only, and a link to a read-only one is" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "old\n" });
    // Only the others may write it: the save is left to the system.
    try tmp.dir.setFilePermissions(io, "g", .fromMode(0o446), .{});
    try file.save(io, tmp.dir, "g", "new\n", .{});
    try tmp.dir.writeFile(io, .{ .sub_path = "r", .data = "old\n" });
    try tmp.dir.setFilePermissions(io, "r", .fromMode(0o400), .{});
    try tmp.dir.symLink(io, "r", "l", .{});
    try expectError(error.ReadOnly, file.save(io, tmp.dir, "l", "new\n", .{}));
    var buf: [16]u8 = undefined;
    try expectEqualStrings("old\n", try tmp.dir.readFile(io, "r", &buf));
}

test "file: a failed save leaves the original untouched" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    // A directory cannot be replaced by a file: the rename fails.
    if (file.save(io, tmp.dir, "d", "text\n", .{})) |_| {
        return error.TestUnexpectedResult;
    } else |_| {}
    const st = try tmp.dir.statFile(io, "d", .{});
    try std.testing.expectEqual(.directory, st.kind);
}

test "file: a save past the file size limit fails, keeps the original and leaves no temporary file" {
    // The editor ignores SIGXFSZ while the terminal is open (`term.Tty`);
    // without that the write would end the process.
    const ignore: std.posix.Sigaction = .{ .handler = .{ .handler = std.posix.SIG.IGN }, .mask = std.posix.sigemptyset(), .flags = 0 };
    var old: std.posix.Sigaction = undefined;
    std.posix.sigaction(std.posix.SIG.XFSZ, &ignore, &old);
    defer std.posix.sigaction(std.posix.SIG.XFSZ, &old, null);
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "old\n" });
    const limit = try std.posix.getrlimit(.FSIZE);
    try std.posix.setrlimit(.FSIZE, .{ .cur = 4096, .max = limit.max });
    const saved = file.save(io, tmp.dir, "f", &@as([8192]u8, @splat('x')), .{});
    try std.posix.setrlimit(.FSIZE, limit);
    try expectError(error.FileTooBig, saved);
    var buf: [64]u8 = undefined;
    try expectEqualStrings("old\n", try tmp.dir.readFile(io, "f", &buf));
    var it = tmp.dir.iterate();
    while (try it.next(io)) |entry| try expectEqualStrings("f", entry.name);
}

test "file: save into a missing directory fails" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try expectError(error.FileNotFound, file.save(io, tmp.dir, "no/such/f", "x\n", .{}));
}

test "file: a saved file loads back byte for byte" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var bytes: [256]u8 = undefined;
    for (&bytes, 0..) |*b, i| b.* = @intCast(i);
    try file.save(io, tmp.dir, "all", &bytes, .{});
    const got = (try file.load(io, gpa, tmp.dir, "all", file.max_file)).?;
    defer gpa.free(got);
    try std.testing.expectEqualSlices(u8, &bytes, got);
}

test "file: create writes a new file readable by its owner only" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try file.create(io, tmp.dir, "r", "unsaved\n");
    var buf: [16]u8 = undefined;
    try expectEqualStrings("unsaved\n", try tmp.dir.readFile(io, "r", &buf));
    if (!std.Io.File.Permissions.has_executable_bit) return;
    const st = try tmp.dir.statFile(io, "r", .{});
    try std.testing.expectEqual(0, st.permissions.toMode() & 0o077);
}

test "file: create never replaces a file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "r", .data = "older\n" });
    try expectError(error.PathAlreadyExists, file.create(io, tmp.dir, "r", "newer\n"));
    var buf: [16]u8 = undefined;
    try expectEqualStrings("older\n", try tmp.dir.readFile(io, "r", &buf));
}

test "file: create writes empty and binary contents byte for byte" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try file.create(io, tmp.dir, "empty", "");
    const bytes = "\x00\xff\x1b[2J\r\n";
    try file.create(io, tmp.dir, "bin", bytes);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("", try tmp.dir.readFile(io, "empty", &buf));
    try expectEqualStrings(bytes, try tmp.dir.readFile(io, "bin", &buf));
}

test "file: create into a missing directory fails and makes nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try expectError(error.FileNotFound, file.create(io, tmp.dir, "no/such/r", "x\n"));
}

test "file: save through a link replaces the file it names, and keeps the link" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "d/t", .data = "old\n" });
    try tmp.dir.symLink(io, "d/t", "l", .{});
    try file.save(io, tmp.dir, "l", "new\n", .{});
    var got: [16]u8 = undefined;
    try expectEqualStrings("new\n", try tmp.dir.readFile(io, "d/t", &got));
    const n = try tmp.dir.readLink(io, "l", &got);
    try expectEqualStrings("d/t", got[0..n]);
}

test "file: save through a dangling link makes the file it names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "t", "l", .{});
    try file.save(io, tmp.dir, "l", "x\n", .{});
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
    try file.save(io, tmp.dir, longest, "x\n", .{});
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

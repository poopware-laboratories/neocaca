//! Tests for `disk.zig`, and for the saves that check a file has not
//! changed on disk since it was read, in a temporary directory.

const std = @import("std");
const disk = @import("disk.zig");
const file = @import("file.zig");

const io = std.testing.io;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;

/// Whether `name` is the only entry of `dir`: no temporary file is left.
fn alone(dir: std.Io.Dir, name: []const u8) !void {
    var it = dir.iterate();
    var count: usize = 0;
    while (try it.next(io)) |entry| {
        try expectEqualStrings(name, entry.name);
        count += 1;
    }
    try expectEqual(1, count);
}

test "disk: a missing file, or one in a missing directory, is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try expectEqual(disk.Disk.missing, try disk.read(io, tmp.dir, "new.txt"));
    try expectEqual(disk.Disk.missing, try disk.read(io, tmp.dir, "no/such/dir/new.txt"));
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "x" });
    try expectEqual(disk.Disk.missing, try disk.read(io, tmp.dir, "f/through-a-file"));
}

test "disk: a name too long is refused before the system sees it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const long: [file.max_name + 1]u8 = @splat('a');
    try expectError(error.NameTooLong, disk.read(io, tmp.dir, &long));
}

test "disk: a file's stamp has its size, and is the same read twice" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "hello\n" });
    const a = try disk.read(io, tmp.dir, "f");
    try expectEqual(6, a.stamp.size);
    try expect(!disk.changed(a, try disk.read(io, tmp.dir, "f")));
}

test "disk: a link's stamp is the stamp of the file it names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "t", .data = "four" });
    try tmp.dir.symLink(io, "t", "l", .{});
    try expectEqual(try disk.read(io, tmp.dir, "t"), try disk.read(io, tmp.dir, "l"));
}

test "disk: what counts as a change" {
    const s: disk.Stamp = .{ .inode = 7, .size = 10, .mtime = .{ .nanoseconds = 1000 } };
    const at: disk.Disk = .{ .stamp = s };
    var bigger = s;
    bigger.size = 11;
    var touched = s;
    touched.mtime = .{ .nanoseconds = 1001 };
    var replaced = s;
    replaced.inode = 8;
    try expect(!disk.changed(at, at));
    try expect(disk.changed(at, .{ .stamp = bigger }));
    try expect(disk.changed(at, .{ .stamp = touched }));
    try expect(disk.changed(at, .{ .stamp = replaced }));
    // A file deleted since is no one else's text to keep.
    try expect(!disk.changed(at, .missing));
    // A new file that something else made meanwhile is.
    try expect(disk.changed(.missing, at));
    try expect(!disk.changed(.missing, .missing));
    // Nothing known, nothing to compare.
    try expect(!disk.changed(.unknown, at));
    try expect(!disk.changed(.unknown, .missing));
}

test "disk: a save returns the stamp the file then has" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "old\n" });
    const got = try file.save(io, tmp.dir, "f", "new text\n", .{});
    try expectEqual(disk.Disk{ .stamp = got }, try disk.read(io, tmp.dir, "f"));
    try expectEqual(9, got.size);
}

test "disk: a save over the file as it was read writes it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "old\n" });
    const at = try disk.read(io, tmp.dir, "f");
    const first = try file.save(io, tmp.dir, "f", "one\n", .{ .expect = at });
    // The stamp a save returns is what the next one expects.
    _ = try file.save(io, tmp.dir, "f", "two\n", .{ .expect = .{ .stamp = first } });
    var buf: [16]u8 = undefined;
    try expectEqualStrings("two\n", try tmp.dir.readFile(io, "f", &buf));
}

test "disk: a save over a file appended to since it was read is refused, and keeps it" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    const at = try disk.read(io, tmp.dir, "log");
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    try expectError(error.ChangedOnDisk, file.save(io, tmp.dir, "log", "mine\n", .{ .expect = at }));
    var buf: [16]u8 = undefined;
    try expectEqualStrings("one\ntwo\n", try tmp.dir.readFile(io, "log", &buf));
    try alone(tmp.dir, "log");
}

test "disk: a forced save writes over a file changed since it was read" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    const at = try disk.read(io, tmp.dir, "log");
    try tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    _ = try file.save(io, tmp.dir, "log", "mine\n", .{ .expect = at, .force = true });
    var buf: [16]u8 = undefined;
    try expectEqualStrings("mine\n", try tmp.dir.readFile(io, "log", &buf));
}

test "disk: a save over a file rewritten with as many bytes is refused" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "aaaa" });
    const at = try disk.read(io, tmp.dir, "f");
    // Same size and inode: only the time it was written tells.
    const f = try tmp.dir.openFile(io, "f", .{ .mode = .read_write });
    defer f.close(io);
    try f.writePositionalAll(io, "bbbb", 0);
    try f.setTimestamps(io, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = at.stamp.mtime.nanoseconds + std.time.ns_per_s } } });
    try expectError(error.ChangedOnDisk, file.save(io, tmp.dir, "f", "mine", .{ .expect = at }));
    var buf: [16]u8 = undefined;
    try expectEqualStrings("bbbb", try tmp.dir.readFile(io, "f", &buf));
}

test "disk: a save of a new file that something else made meanwhile is refused" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const at = try disk.read(io, tmp.dir, "new");
    try tmp.dir.writeFile(io, .{ .sub_path = "new", .data = "theirs\n" });
    try expectError(error.ChangedOnDisk, file.save(io, tmp.dir, "new", "mine\n", .{ .expect = at }));
    var buf: [16]u8 = undefined;
    try expectEqualStrings("theirs\n", try tmp.dir.readFile(io, "new", &buf));
}

test "disk: a save of a file still missing, or deleted since it was read, makes it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try file.save(io, tmp.dir, "new", "a\n", .{ .expect = .missing });
    const at = try disk.read(io, tmp.dir, "new");
    try tmp.dir.deleteFile(io, "new");
    _ = try file.save(io, tmp.dir, "new", "b\n", .{ .expect = at });
    var buf: [16]u8 = undefined;
    try expectEqualStrings("b\n", try tmp.dir.readFile(io, "new", &buf));
}

test "disk: a save through a link checks the file it names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "t", .data = "old\n" });
    try tmp.dir.symLink(io, "t", "l", .{});
    const at = try disk.read(io, tmp.dir, "l");
    try tmp.dir.writeFile(io, .{ .sub_path = "t", .data = "old\nmore\n" });
    try expectError(error.ChangedOnDisk, file.save(io, tmp.dir, "l", "mine\n", .{ .expect = at }));
}

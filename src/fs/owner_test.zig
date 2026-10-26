//! Tests for `owner.zig`, and for the owner and group a save keeps
//! (`file.zig`), in a temporary directory. What a user may set
//! depends on who runs them: tests for root skip as anyone else, and those
//! for anyone else skip as root or without a second group.

const std = @import("std");
const owner = @import("owner.zig");
const file = @import("file.zig");

const io = std.testing.io;
const expectEqual = std.testing.expectEqual;

extern "c" fn getgroups(size: c_int, list: [*]std.c.gid_t) c_int;

/// The groups the user is a member of, besides their own.
fn otherGroups(buf: []std.c.gid_t) []const std.c.gid_t {
    const n = getgroups(@intCast(buf.len), buf.ptr);
    if (n < 0) return &.{};
    var kept: usize = 0;
    for (buf[0..@intCast(n)]) |g| if (g != std.c.getegid()) {
        buf[kept] = g;
        kept += 1;
    };
    return buf[0..kept];
}

/// A group the user is a member of besides their own, or a skip.
fn otherGroup() !std.c.gid_t {
    var buf: [256]std.c.gid_t = undefined;
    const others = otherGroups(&buf);
    if (others.len == 0) return error.SkipZigTest;
    return others[0];
}

/// A group the user is not a member of, or a skip.
fn foreignGroup() !std.c.gid_t {
    var buf: [256]std.c.gid_t = undefined;
    const others = otherGroups(&buf);
    var g: std.c.gid_t = 1;
    while (g < 65534) : (g += 1) {
        if (g == std.c.getegid() or std.mem.indexOfScalar(std.c.gid_t, others, g) != null) continue;
        return g;
    }
    return error.SkipZigTest;
}

fn skipAsRoot() !void {
    if (std.c.geteuid() == 0) return error.SkipZigTest;
}

fn makeFile(dir: std.Io.Dir, name: []const u8) !std.Io.File {
    return dir.createFile(io, name, .{ .read = true });
}

test "owner: a new file is the user's, in the user's group" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try makeFile(tmp.dir, "a");
    f.close(io);
    try expectEqual(owner.Owner{ .uid = std.c.geteuid(), .gid = std.c.getegid() }, try owner.read(tmp.dir, "a"));
}

test "owner: a missing file is not found" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(error.FileNotFound, owner.read(tmp.dir, "missing"));
    try std.testing.expectError(error.FileNotFound, owner.read(tmp.dir, "no/such/dir"));
}

test "owner: a symbolic link is read as itself, not the file it names" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.symLink(io, "missing", "link", .{});
    try expectEqual(std.c.geteuid(), (try owner.read(tmp.dir, "link")).uid);
}

test "owner: a name longer than a path is refused, not cut" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const long: [std.Io.Dir.max_path_bytes]u8 = @splat('a');
    try std.testing.expectError(error.NameTooLong, owner.read(tmp.dir, &long));
}

test "owner: give sets a group the user is a member of" {
    const other = try otherGroup();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try makeFile(tmp.dir, "a");
    defer f.close(io);
    try owner.give(io, f, .{ .uid = std.c.geteuid(), .gid = other });
    try expectEqual(owner.Owner{ .uid = std.c.geteuid(), .gid = other }, try owner.read(tmp.dir, "a"));
}

test "owner: give keeps the group when the owner is not the user's to give" {
    try skipAsRoot();
    const other = try otherGroup();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try makeFile(tmp.dir, "a");
    defer f.close(io);
    try owner.give(io, f, .{ .uid = 0, .gid = other });
    try expectEqual(owner.Owner{ .uid = std.c.geteuid(), .gid = other }, try owner.read(tmp.dir, "a"));
}

test "owner: give leaves a file be, without an error, where the user may set nothing" {
    try skipAsRoot();
    const foreign = try foreignGroup();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try makeFile(tmp.dir, "a");
    defer f.close(io);
    try owner.give(io, f, .{ .uid = 0, .gid = foreign });
    try expectEqual(owner.Owner{ .uid = std.c.geteuid(), .gid = std.c.getegid() }, try owner.read(tmp.dir, "a"));
}

test "owner: as root, give sets any owner and group" {
    if (std.c.geteuid() != 0) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const f = try makeFile(tmp.dir, "a");
    defer f.close(io);
    try owner.give(io, f, .{ .uid = 65534, .gid = 65533 });
    try expectEqual(owner.Owner{ .uid = 65534, .gid = 65533 }, try owner.read(tmp.dir, "a"));
}

/// Makes `name` with `data`, in `group`.
fn makeInGroup(dir: std.Io.Dir, name: []const u8, data: []const u8, group: std.c.gid_t) !void {
    try dir.writeFile(io, .{ .sub_path = name, .data = data });
    const f = try dir.openFile(io, name, .{});
    defer f.close(io);
    try f.setOwner(io, null, group);
}

test "owner: a save keeps the group of the file it replaces" {
    const other = try otherGroup();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try makeInGroup(tmp.dir, "a", "old\n", other);
    _ = try file.save(io, tmp.dir, "a", "new\n", .{});
    var got: [8]u8 = undefined;
    try std.testing.expectEqualStrings("new\n", try tmp.dir.readFile(io, "a", &got));
    try expectEqual(owner.Owner{ .uid = std.c.geteuid(), .gid = other }, try owner.read(tmp.dir, "a"));
}

test "owner: a save keeps the set-group-ID bit that changing the group clears" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    const other = try otherGroup();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try makeInGroup(tmp.dir, "x", "old\n", other);
    try tmp.dir.setFilePermissions(io, "x", .fromMode(0o2755), .{});
    _ = try file.save(io, tmp.dir, "x", "new\n", .{});
    const st = try tmp.dir.statFile(io, "x", .{});
    try expectEqual(0o2755, st.permissions.toMode() & 0o7777);
    try expectEqual(other, (try owner.read(tmp.dir, "x")).gid);
}

test "owner: a save keeps the set-user-ID and set-group-ID bits that writing clears" {
    if (!std.Io.File.Permissions.has_executable_bit) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_]std.posix.mode_t{ 0o4755, 0o2755, 0o6750 }) |mode| {
        try tmp.dir.writeFile(io, .{ .sub_path = "x", .data = "old\n" });
        try tmp.dir.setFilePermissions(io, "x", .fromMode(mode), .{});
        _ = try file.save(io, tmp.dir, "x", "new\n", .{});
        const st = try tmp.dir.statFile(io, "x", .{});
        try expectEqual(mode, st.permissions.toMode() & 0o7777);
    }
}

test "owner: a save through a link keeps the group of the file it names" {
    const other = try otherGroup();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try makeInGroup(tmp.dir, "t", "old\n", other);
    try tmp.dir.symLink(io, "t", "l", .{});
    _ = try file.save(io, tmp.dir, "l", "new\n", .{});
    try expectEqual(other, (try owner.read(tmp.dir, "t")).gid);
}

test "owner: a new file a save makes is the user's own" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    _ = try file.save(io, tmp.dir, "new", "x\n", .{});
    try expectEqual(owner.Owner{ .uid = std.c.geteuid(), .gid = std.c.getegid() }, try owner.read(tmp.dir, "new"));
}

test "owner: as root, a save keeps another user's file theirs" {
    if (std.c.geteuid() != 0) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a", .data = "old\n" });
    const f = try tmp.dir.openFile(io, "a", .{});
    try f.setOwner(io, 65534, 65533);
    f.close(io);
    _ = try file.save(io, tmp.dir, "a", "new\n", .{});
    try expectEqual(owner.Owner{ .uid = 65534, .gid = 65533 }, try owner.read(tmp.dir, "a"));
}

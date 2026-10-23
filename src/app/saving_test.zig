//! Tests for `saving.zig`: a save on its own thread, its result, its copy
//! of the text, and the byte that wakes the loop.

const std = @import("std");
const fs = @import("../fs.zig");
const Saving = @import("saving.zig").Saving;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "saving: writes the text and says it has finished" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const job = try Saving.start(gpa, io, tmp.dir, .{ .path = "f", .quit = true, .lines = 2 }, "a\nb\n", null);
    job.wait();
    defer job.destroy();
    try expect(job.isFinished());
    // What the file is once written, for the next save to expect.
    try expectEqual(try fs.disk.read(io, tmp.dir, "f"), try job.result);
    try expectEqualStrings("f", job.save.path);
    try expect(job.save.quit);
    try expectEqual(2, job.save.lines);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("a\nb\n", try tmp.dir.readFile(io, "f", &buf));
}

test "saving: writes the copy taken when it began" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var text = "old\n".*;
    var path = "f".*;
    const job = try Saving.start(gpa, io, tmp.dir, .{ .path = &path, .quit = false }, &text, null);
    // The caller's text and path change while the thread writes.
    @memcpy(&text, "new\n");
    path[0] = 'g';
    job.wait();
    defer job.destroy();
    _ = try job.result;
    try expectEqualStrings("f", job.save.path);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("old\n", try tmp.dir.readFile(io, "f", &buf));
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFile(io, "g", &buf));
}

test "saving: a save that fails keeps its error and leaves no file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const job = try Saving.start(gpa, io, tmp.dir, .{ .path = "no/such/dir/f", .quit = false }, "x\n", null);
    job.wait();
    defer job.destroy();
    try expect(job.isFinished());
    try std.testing.expectError(error.FileNotFound, job.result);
    var buf: [16]u8 = undefined;
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFile(io, "no/such/dir/f", &buf));
}

test "saving: a finished save writes one byte to the notify pipe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fds: [2]std.posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&fds));
    defer for (fds) |fd| {
        _ = std.c.close(fd);
    };
    const job = try Saving.start(gpa, io, tmp.dir, .{ .path = "f", .quit = false }, "x\n", fds[1]);
    job.wait();
    defer job.destroy();
    var buf: [4]u8 = undefined;
    try expectEqual(1, std.c.read(fds[0], &buf, buf.len));
    try expectEqual('s', buf[0]);
    // Only one: nothing more is waiting.
    var poll = [_]std.posix.pollfd{.{ .fd = fds[0], .events = std.posix.POLL.IN, .revents = 0 }};
    try expectEqual(0, try std.posix.poll(&poll, 0));
}

test "saving: waiting twice is waiting once" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const job = try Saving.start(gpa, io, tmp.dir, .{ .path = "f", .quit = false }, "", null);
    job.wait();
    job.wait();
    defer job.destroy();
    try expectEqual(null, job.thread);
    var buf: [16]u8 = undefined;
    try expectEqualStrings("", try tmp.dir.readFile(io, "f", &buf));
}

fn startAndFinish(alloc: std.mem.Allocator, dir: std.Io.Dir) !void {
    const job = try Saving.start(alloc, io, dir, .{ .path = "f", .quit = false }, "abc\n", null);
    job.wait();
    job.destroy();
}

test "saving: out of memory while starting leaks nothing and writes nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.checkAllAllocationFailures(gpa, startAndFinish, .{tmp.dir});
}

test "saving: out of memory on each copy starts no save" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    for (0..3) |i| {
        var failing: std.testing.FailingAllocator = .init(gpa, .{ .fail_index = i });
        try std.testing.expectError(error.OutOfMemory, Saving.start(failing.allocator(), io, tmp.dir, .{ .path = "f", .quit = false }, "x\n", null));
        try expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
    var buf: [16]u8 = undefined;
    try std.testing.expectError(error.FileNotFound, tmp.dir.readFile(io, "f", &buf));
}

test "saving: a save expecting the file as it was is refused once it changed, unless forced" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "old\n" });
    const was = try fs.disk.read(io, tmp.dir, "f");
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "theirs\n" });
    const refused = try Saving.start(gpa, io, tmp.dir, .{ .path = "f", .quit = false, .expect = was }, "mine\n", null);
    refused.wait();
    defer refused.destroy();
    try std.testing.expectError(error.ChangedOnDisk, refused.result);
    const forced = try Saving.start(gpa, io, tmp.dir, .{ .path = "f", .quit = false, .force = true, .expect = was }, "mine\n", null);
    forced.wait();
    defer forced.destroy();
    _ = try forced.result;
    var buf: [16]u8 = undefined;
    try expectEqualStrings("mine\n", try tmp.dir.readFile(io, "f", &buf));
}

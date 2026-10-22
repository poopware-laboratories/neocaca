//! Tests for `loading.zig`: a load on its own thread, the contents it hands
//! over, and the byte that wakes the loop.

const std = @import("std");
const Loading = @import("loading.zig").Loading;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "loading: reads the file and hands its contents over" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "a\nb\n" });
    const job = try Loading.start(gpa, io, tmp.dir, "f", 64, null);
    job.wait();
    defer job.destroy();
    try expect(job.isFinished());
    try expectEqualStrings("f", job.path);
    const contents = (try job.take()).?;
    defer gpa.free(contents);
    try expectEqualStrings("a\nb\n", contents);
    // Handed over once: what is left is a missing file, owned by no one.
    try expectEqual(null, try job.take());
}

test "loading: a missing file is null, a failed load keeps its error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const missing = try Loading.start(gpa, io, tmp.dir, "new", 64, null);
    missing.wait();
    defer missing.destroy();
    try expectEqual(null, try missing.take());
    try tmp.dir.writeFile(io, .{ .sub_path = "big", .data = "12345" });
    const big = try Loading.start(gpa, io, tmp.dir, "big", 4, null);
    big.wait();
    defer big.destroy();
    try std.testing.expectError(error.FileTooBig, big.take());
}

test "loading: contents never taken are freed with the job" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "abc\n" });
    const job = try Loading.start(gpa, io, tmp.dir, "f", 64, null);
    job.wait();
    // The testing allocator fails the test on a leak.
    job.destroy();
}

test "loading: reads the path given when it began" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "f\n" });
    var path = "f".*;
    const job = try Loading.start(gpa, io, tmp.dir, &path, 64, null);
    path[0] = 'g';
    job.wait();
    defer job.destroy();
    try expectEqualStrings("f", job.path);
    const contents = (try job.take()).?;
    defer gpa.free(contents);
    try expectEqualStrings("f\n", contents);
}

test "loading: a finished load writes one byte to the notify pipe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var fds: [2]std.posix.fd_t = undefined;
    try expectEqual(0, std.c.pipe(&fds));
    defer for (fds) |fd| {
        _ = std.c.close(fd);
    };
    const job = try Loading.start(gpa, io, tmp.dir, "f", 64, fds[1]);
    job.wait();
    defer job.destroy();
    var poll = [_]std.posix.pollfd{.{ .fd = fds[0], .events = std.posix.POLL.IN, .revents = 0 }};
    try expectEqual(1, try std.posix.poll(&poll, 0));
    var buf: [4]u8 = undefined;
    try expectEqual(1, std.c.read(fds[0], &buf, buf.len));
    try expectEqual('l', buf[0]);
    try expectEqual(0, try std.posix.poll(&poll, 0));
}

test "loading: waiting twice is waiting once" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const job = try Loading.start(gpa, io, tmp.dir, "f", 64, null);
    job.wait();
    job.wait();
    defer job.destroy();
    try expectEqual(null, job.thread);
}

fn startAndFinish(alloc: std.mem.Allocator, dir: std.Io.Dir) !void {
    const job = try Loading.start(alloc, io, dir, "f", 64, null);
    job.wait();
    defer job.destroy();
    // The read's own allocation fails on the thread, as its result.
    const contents = (job.take() catch |e| return e).?;
    alloc.free(contents);
}

test "loading: out of memory, starting or reading, leaks nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "abc\n" });
    try std.testing.checkAllAllocationFailures(gpa, startAndFinish, .{tmp.dir});
}

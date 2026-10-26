//! The editor end to end on a pseudo-terminal: `app.edit.edit` runs on the
//! terminal side in a thread, as the process would, while the test plays
//! the terminal emulator on the controlling side, typing keys and reading
//! every byte the editor writes.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");

const posix = std.posix;
const io = std.testing.io;
const modes = neocaca.term.modes;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

extern "c" fn posix_openpt(flags: c_int) c_int;
extern "c" fn grantpt(fd: c_int) c_int;
extern "c" fn unlockpt(fd: c_int) c_int;
extern "c" fn ptsname(fd: c_int) ?[*:0]const u8;

/// TIOCSWINSZ, or its BSD encoding where std lacks it (macOS).
const set_winsize: u32 = if (@hasDecl(posix.T, "IOCSWINSZ"))
    @truncate(posix.T.IOCSWINSZ)
else
    0x8000_0000 | @as(u32, @sizeOf(posix.winsize)) << 16 | @as(u32, 't') << 8 | 103;

/// One editing session on a fresh pseudo-terminal.
const Run = struct {
    master: posix.fd_t,
    slave: posix.fd_t,
    tmp: std.testing.TmpDir,
    /// The editor's thread, until it is joined.
    thread: ?std.Thread = null,
    code: neocaca.app.exit.Code = .failure,
    /// Room for a message naming a file of the longest name there is.
    err_buf: [1024]u8 = undefined,
    err: std.Io.Writer = undefined,
    /// Everything the editor wrote, in order.
    seen: std.ArrayList(u8) = .empty,

    fn open(self: *Run, cols: u16, rows: u16) !void {
        const flags: posix.O = .{ .ACCMODE = .RDWR, .NOCTTY = true };
        const master = posix_openpt(@bitCast(@as(u32, @bitCast(flags))));
        if (master < 0) return error.SkipZigTest;
        errdefer _ = std.c.close(master);
        if (grantpt(master) != 0 or unlockpt(master) != 0) return error.SkipZigTest;
        const name = ptsname(master) orelse return error.SkipZigTest;
        const slave = try posix.openatZ(posix.AT.FDCWD, name, flags, 0);
        const ws: posix.winsize = .{ .row = rows, .col = cols, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(master, @as(c_int, @bitCast(set_winsize)), &ws);
        self.* = .{ .master = master, .slave = slave, .tmp = std.testing.tmpDir(.{}) };
        self.err = .fixed(&self.err_buf);
    }

    /// Hangs up on an editor still running (a failed test), then frees.
    fn close(self: *Run) void {
        if (self.thread) |t| {
            hangUp(self);
            t.join();
        }
        self.seen.deinit(std.testing.allocator);
        self.tmp.cleanup();
        _ = std.c.close(self.slave);
        _ = std.c.close(self.master);
    }

    fn start(self: *Run, files: []const []const u8) !void {
        self.thread = try .spawn(.{}, edit, .{ self, files });
    }

    /// Closes the emulator's side, as a closed terminal window does.
    fn hangUp(self: *Run) void {
        _ = std.c.close(self.master);
        self.master = posix.openatZ(posix.AT.FDCWD, "/dev/null", .{ .ACCMODE = .RDONLY }, 0) catch -1;
    }

    fn edit(self: *Run, files: []const []const u8) void {
        const env: neocaca.app.Env = .{
            .gpa = std.testing.allocator,
            .io = io,
            .dir = self.tmp.dir,
            .in = self.slave,
            .out = self.slave,
        };
        self.code = neocaca.app.edit.edit(env, files, &self.err) catch .failure;
    }

    /// Reads what the editor writes until it has been quiet for `quiet_ms`.
    fn drain(self: *Run, quiet_ms: i32) !void {
        var buf: [4096]u8 = undefined;
        while (true) {
            var fds = [_]posix.pollfd{.{ .fd = self.master, .events = posix.POLL.IN, .revents = 0 }};
            if (try posix.poll(&fds, quiet_ms) == 0) return;
            const n = posix.read(self.master, &buf) catch return;
            if (n == 0) return;
            try self.seen.appendSlice(std.testing.allocator, buf[0..n]);
        }
    }

    /// Types `keys` one at a time, as a person types, reading the frames.
    /// After an Escape it waits until the editor shows normal mode, so the
    /// next key never arrives within the Escape timeout and reads as Alt
    /// plus that key, however slowly the editor runs.
    fn typeKeys(self: *Run, keys: []const u8) !void {
        for (0..keys.len) |i| {
            const before = self.seen.items.len;
            _ = std.c.write(self.master, keys[i..].ptr, 1);
            try self.drain(60);
            if (keys[i] == 0x1b) try self.waitFor(before, "NORMAL");
        }
    }

    /// Reads until `needle` appears in what the editor wrote from `from` on,
    /// failing after 10 seconds.
    fn waitFor(self: *Run, from: usize, needle: []const u8) !void {
        const deadline = std.Io.Clock.awake.now(io).addDuration(.fromSeconds(10));
        while (std.mem.indexOf(u8, self.seen.items[from..], needle) == null) {
            if (std.Io.Clock.awake.now(io).compare(.gte, deadline)) return error.Timeout;
            try self.drain(20);
        }
    }

    /// Waits for the editor to finish; its exit code.
    fn finish(self: *Run) !neocaca.app.exit.Code {
        // Keep reading so the editor's last writes never block on a full
        // terminal.
        var done = std.atomic.Value(bool).init(false);
        const reader = try std.Thread.spawn(.{}, struct {
            fn f(r: *Run, d: *std.atomic.Value(bool)) void {
                while (!d.load(.acquire)) r.drain(20) catch return;
            }
        }.f, .{ self, &done });
        self.thread.?.join();
        self.thread = null;
        done.store(true, .release);
        reader.join();
        try self.drain(20);
        return self.code;
    }

    fn sawCount(self: *const Run, needle: []const u8) usize {
        return std.mem.count(u8, self.seen.items, needle);
    }
};

test "terminal: edit a file, write it and quit, leaving the terminal as it was" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(40, 8);
    defer r.close();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "world\n" });
    const before = try neocaca.term.attr.get(r.slave);

    try r.start(&.{"a.txt"});
    try r.drain(200);
    try expect(std.mem.startsWith(u8, r.seen.items, modes.enter));
    // The cursor's cell is drawn apart from the rest of the word.
    try expect(r.sawCount("orld") >= 1);
    try expect(r.sawCount("NORMAL") >= 1);

    try r.typeKeys("ihello \x1b");
    try expect(r.sawCount("INSERT") >= 1);
    try r.typeKeys(":wq\r");
    try expectEqual(.ok, try r.finish());

    var buf: [64]u8 = undefined;
    try expectEqualStrings("hello world\n", try r.tmp.dir.readFile(io, "a.txt", &buf));
    try expect(std.mem.endsWith(u8, r.seen.items, modes.leave));
    try expectEqual(1, r.sawCount(modes.enter));
    try expectEqual(1, r.sawCount(modes.leave));
    const after = try neocaca.term.attr.get(r.slave);
    try expectEqual(before.lflag, after.lflag);
    try expectEqual(before.iflag, after.iflag);
    try expectEqual(before.oflag, after.oflag);
    try expectEqualStrings("", r.err.buffered());
}

test "terminal: Enter, Backspace and Ctrl keys arrive untranslated" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(40, 8);
    defer r.close();
    try r.start(&.{"new.txt"});
    try r.drain(200);
    // Enter as CR must become a newline, not be turned into LF by the
    // terminal; Ctrl-C must reach the editor, not stop it.
    try r.typeKeys("iab\rcdx\x7f\x03\x1b");
    // `:wq`, not `:w` then `:q`: a `:q` typed while the save is still
    // being written is refused.
    try r.typeKeys(":wq\r");
    try expectEqual(.ok, try r.finish());
    var buf: [64]u8 = undefined;
    try expectEqualStrings("ab\ncd\n", try r.tmp.dir.readFile(io, "new.txt", &buf));
}

test "terminal: a resize redraws at the new size" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    try r.start(&.{});
    try r.drain(200);
    const ws: posix.winsize = .{ .row = 10, .col = 50, .xpixel = 0, .ypixel = 0 };
    _ = std.c.ioctl(r.master, @as(c_int, @bitCast(set_winsize)), &ws);
    // The kernel signals the foreground process group, which this test
    // process may not lead; signal it directly as well.
    try posix.raise(.WINCH);
    const before = r.seen.items.len;
    try r.drain(200);
    // The status line moved to row 9 of the bigger screen.
    try expect(std.mem.indexOf(u8, r.seen.items[before..], "\x1b[9;1H") != null);
    try r.typeKeys(":q\r");
    try expectEqual(.ok, try r.finish());
}

test "terminal: the terminal closing keeps the file and recovers the changes beside it" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "keep", .data = "safe\n" });
    try r.start(&.{"keep"});
    try r.drain(200);
    const before = r.seen.items.len;
    try r.typeKeys("ix");
    // Hang up only once the edit shows (`[+]`): keys the editor has not
    // read yet are lost with the terminal, however slow the machine.
    try r.waitFor(before, "[+]");
    r.hangUp();
    r.thread.?.join();
    r.thread = null;
    var buf: [64]u8 = undefined;
    try expectEqualStrings("safe\n", try r.tmp.dir.readFile(io, "keep", &buf));
    try expectEqualStrings("xsafe\n", try r.tmp.dir.readFile(io, "keep.recovered", &buf));
    try expect(std.mem.indexOf(u8, r.err.buffered(), "unsaved changes written to \"keep.recovered\"") != null);
}

test "terminal: being asked to end (SIGTERM) restores the terminal and recovers the changes" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "keep", .data = "safe\n" });
    const before = try neocaca.term.attr.get(r.slave);
    try r.start(&.{"keep"});
    try r.drain(200);
    const typed = r.seen.items.len;
    try r.typeKeys("ix");
    try r.waitFor(typed, "[+]");
    // Sent to the whole process, as `kill` does; the editor's handler takes it.
    try posix.raise(.TERM);
    try expectEqual(.ok, try r.finish());
    var buf: [64]u8 = undefined;
    try expectEqualStrings("safe\n", try r.tmp.dir.readFile(io, "keep", &buf));
    try expectEqualStrings("xsafe\n", try r.tmp.dir.readFile(io, "keep.recovered", &buf));
    try expect(std.mem.indexOf(u8, r.err.buffered(), "unsaved changes written to \"keep.recovered\"") != null);
    // The terminal is as it was: the modes left, the settings back.
    try expect(std.mem.endsWith(u8, r.seen.items, modes.leave));
    const after = try neocaca.term.attr.get(r.slave);
    try expectEqual(before.lflag, after.lflag);
    try expectEqual(before.iflag, after.iflag);
}

test "terminal: the terminal closing recovers a file with the longest name there is" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    const longest: [255]u8 = @splat('k');
    try r.tmp.dir.writeFile(io, .{ .sub_path = &longest, .data = "safe\n" });
    try r.start(&.{&longest});
    try r.drain(200);
    const before = r.seen.items.len;
    try r.typeKeys("ix");
    try r.waitFor(before, "[+]");
    r.hangUp();
    r.thread.?.join();
    r.thread = null;
    try expectEqual(.ok, r.code);
    const recovered = longest[0 .. 255 - ".recovered".len] ++ ".recovered";
    var buf: [64]u8 = undefined;
    try expectEqualStrings("xsafe\n", try r.tmp.dir.readFile(io, recovered, &buf));
    try expectEqualStrings("safe\n", try r.tmp.dir.readFile(io, &longest, &buf));
    try expect(std.mem.indexOf(u8, r.err.buffered(), "unsaved changes written to") != null);
}

test "terminal: the terminal closing over no changes recovers nothing" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "keep", .data = "safe\n" });
    try r.start(&.{"keep"});
    try r.drain(200);
    r.hangUp();
    r.thread.?.join();
    r.thread = null;
    var buf: [64]u8 = undefined;
    try std.testing.expectError(error.FileNotFound, r.tmp.dir.readFile(io, "keep.recovered", &buf));
    try expect(std.mem.indexOf(u8, r.err.buffered(), "recovered") == null);
}

test "terminal: a file that cannot be opened is named on stderr with its control bytes drawn" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    const name = "x\x1b]0;T\x07y";
    try r.tmp.dir.createDir(io, name, .default_dir);
    try r.start(&.{name});
    try expectEqual(.failure, try r.finish());
    try expectEqualStrings("neocaca: cannot open \"x^[]0;T^Gy\": is a directory\n", r.err.buffered());
}

test "terminal: a recovery file named with control bytes is named on stderr with them drawn" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(30, 6);
    defer r.close();
    const name = "a\x1b[2Jb";
    try r.tmp.dir.writeFile(io, .{ .sub_path = name, .data = "safe\n" });
    try r.start(&.{name});
    try r.drain(200);
    const before = r.seen.items.len;
    try r.typeKeys("ix");
    try r.waitFor(before, "[+]");
    r.hangUp();
    r.thread.?.join();
    r.thread = null;
    var buf: [64]u8 = undefined;
    try expectEqualStrings("xsafe\n", try r.tmp.dir.readFile(io, name ++ ".recovered", &buf));
    try expectEqualStrings("neocaca: unsaved changes written to \"a^[[2Jb.recovered\"\n", r.err.buffered());
}

test "terminal: getting the focus back says the file changed on disk" {
    if (builtin.target.os.tag == .windows) return error.SkipZigTest;
    var r: Run = undefined;
    try r.open(80, 6);
    defer r.close();
    try r.tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\n" });
    try r.start(&.{"log"});
    try r.drain(200);
    // Another program appends while the window is in the background.
    try r.tmp.dir.writeFile(io, .{ .sub_path = "log", .data = "one\ntwo\n" });
    const before = r.seen.items.len;
    _ = std.c.write(r.master, "\x1b[O\x1b[I", 6);
    try r.waitFor(before, "changed on disk; :e! reloads it");
    try r.typeKeys(":q\r");
    try expectEqual(.ok, try r.finish());
    var buf: [64]u8 = undefined;
    try expectEqualStrings("one\ntwo\n", try r.tmp.dir.readFile(io, "log", &buf));
}

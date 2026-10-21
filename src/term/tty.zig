//! `Tty`: the real terminal. Raw mode on and off, its size, waiting for
//! input with a timeout, and the resize signal (SIGWINCH), which wakes the
//! wait through a pipe its handler writes to. POSIX only.

const std = @import("std");
const attr = @import("attr.zig");
const raw = @import("raw.zig");
const modes = @import("modes.zig");

const posix = std.posix;
const fd_t = posix.fd_t;

pub const Size = struct { width: usize, height: usize };

pub const OpenError = attr.SetError || error{SystemResources};
pub const WaitError = posix.PollError;
pub const ReadError = posix.ReadError;

/// What `wait` saw.
pub const Ready = struct {
    input: bool = false,
    resized: bool = false,
};

pub const Tty = struct {
    in: fd_t,
    out: fd_t,
    /// The settings to put back.
    original: raw.Termios,
    /// Written by the resize handler, read by `wait`.
    wake: [2]fd_t,

    /// Puts the terminal on `in` into raw mode, writes `modes.enter` to
    /// `out`, and starts watching for resizes. `restore` undoes all of it.
    /// One `Tty` is open at a time.
    pub fn open(in: fd_t, out: fd_t) OpenError!Tty {
        const original = try attr.get(in);
        var wake: [2]fd_t = undefined;
        if (std.c.pipe(&wake) != 0) return error.SystemResources;
        errdefer closePipe(wake);
        setNonBlocking(wake[1]);
        try attr.set(in, raw.makeRaw(original));
        const self: Tty = .{ .in = in, .out = out, .original = original, .wake = wake };
        writeAll(out, modes.enter);
        wake_fd.store(wake[1], .release);
        watchResize(true);
        active = self;
        return self;
    }

    /// Puts the terminal back as `open` found it. Safe to call again, and
    /// from the panic handler.
    pub fn restore(self: *Tty) void {
        if (active == null) return;
        active = null;
        watchResize(false);
        wake_fd.store(-1, .release);
        writeAll(self.out, modes.leave);
        // Nothing more can be done if this fails: the terminal is ours no
        // longer, and the caller is leaving.
        attr.set(self.in, self.original) catch {};
        closePipe(self.wake);
    }

    /// The size in cells, or null if the terminal does not say.
    pub fn size(self: *const Tty) ?Size {
        return sizeOf(self.out) orelse sizeOf(self.in);
    }

    /// Waits up to `timeout_ms` (negative: without limit) for input or a
    /// resize.
    pub fn wait(self: *Tty, timeout_ms: i32) WaitError!Ready {
        var fds = [_]posix.pollfd{
            .{ .fd = self.in, .events = posix.POLL.IN, .revents = 0 },
            .{ .fd = self.wake[0], .events = posix.POLL.IN, .revents = 0 },
        };
        _ = try posix.poll(&fds, timeout_ms);
        var ready: Ready = .{};
        const gone = posix.POLL.HUP | posix.POLL.ERR;
        ready.input = fds[0].revents & (posix.POLL.IN | gone) != 0;
        if (fds[1].revents & posix.POLL.IN != 0) {
            var drain: [64]u8 = undefined;
            _ = posix.read(self.wake[0], &drain) catch {};
            ready.resized = true;
        }
        return ready;
    }

    /// Reads what the terminal sent; 0 when it has gone.
    pub fn read(self: *Tty, buf: []u8) ReadError!usize {
        return posix.read(self.in, buf);
    }
};

/// The open `Tty`, for the panic handler.
var active: ?Tty = null;

/// Restores the open terminal, if any. For the panic handler and fatal
/// error paths, which cannot reach the `Tty` itself.
pub fn restoreActive() void {
    if (active) |*t| {
        var copy = t.*;
        copy.restore();
    }
}

var wake_fd: std.atomic.Value(fd_t) = .init(-1);

fn onResize(_: posix.SIG) callconv(.c) void {
    const fd = wake_fd.load(.acquire);
    // A full pipe already holds a wakeup; losing this byte is harmless.
    if (fd >= 0) _ = std.c.write(fd, "w", 1);
}

fn watchResize(on: bool) void {
    const act: posix.Sigaction = .{
        .handler = .{ .handler = if (on) onResize else posix.SIG.DFL },
        .mask = posix.sigemptyset(),
        .flags = posix.SA.RESTART,
    };
    posix.sigaction(posix.SIG.WINCH, &act, null);
}

fn sizeOf(fd: fd_t) ?Size {
    var ws: posix.winsize = undefined;
    if (std.c.ioctl(fd, @as(c_int, @bitCast(@as(u32, @truncate(posix.T.IOCGWINSZ)))), &ws) != 0) return null;
    if (ws.col == 0 or ws.row == 0) return null;
    return .{ .width = ws.col, .height = ws.row };
}

fn setNonBlocking(fd: fd_t) void {
    const flags = std.c.fcntl(fd, posix.F.GETFL);
    var o: posix.O = @bitCast(@as(u32, @bitCast(flags)));
    o.NONBLOCK = true;
    _ = std.c.fcntl(fd, posix.F.SETFL, @as(c_int, @bitCast(o)));
}

fn closePipe(p: [2]fd_t) void {
    _ = std.c.close(p[0]);
    _ = std.c.close(p[1]);
}

/// Writes all of `bytes`, giving up on an error: what is written here only
/// sets modes, and a terminal that refuses them has gone.
fn writeAll(fd: fd_t, bytes: []const u8) void {
    var rest = bytes;
    while (rest.len > 0) {
        const n = std.c.write(fd, rest.ptr, rest.len);
        if (n <= 0) {
            if (n < 0 and posix.errno(n) == .INTR) continue;
            return;
        }
        rest = rest[@intCast(n)..];
    }
}

test {
    _ = @import("tty_test.zig");
}

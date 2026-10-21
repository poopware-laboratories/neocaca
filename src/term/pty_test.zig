//! `Pty`: a pseudo-terminal for the tests of `term/`. The editor's side
//! (`slave`) is the terminal under test; the controlling side (`master`)
//! plays the terminal emulator.

const std = @import("std");

const posix = std.posix;

extern "c" fn posix_openpt(flags: c_int) c_int;
extern "c" fn grantpt(fd: c_int) c_int;
extern "c" fn unlockpt(fd: c_int) c_int;
extern "c" fn ptsname(fd: c_int) ?[*:0]const u8;

/// TIOCSWINSZ. Where std lacks it (macOS), the BSD ioctl encoding of
/// `_IOW('t', 103, struct winsize)`: copy-in bit, 8-byte argument.
const set_winsize: u32 = if (@hasDecl(posix.T, "IOCSWINSZ"))
    @truncate(posix.T.IOCSWINSZ)
else
    0x8000_0000 | @as(u32, @sizeOf(posix.winsize)) << 16 | @as(u32, 't') << 8 | 103;

pub const Pty = struct {
    /// The emulator's side.
    master: posix.fd_t,
    /// The terminal the editor opens.
    slave: posix.fd_t,

    pub fn open() !Pty {
        const flags: posix.O = .{ .ACCMODE = .RDWR, .NOCTTY = true };
        const master = posix_openpt(@bitCast(@as(u32, @bitCast(flags))));
        if (master < 0) return error.SkipZigTest;
        errdefer _ = std.c.close(master);
        if (grantpt(master) != 0 or unlockpt(master) != 0) return error.SkipZigTest;
        const name = ptsname(master) orelse return error.SkipZigTest;
        const slave = try posix.openatZ(posix.AT.FDCWD, name, flags, 0);
        return .{ .master = master, .slave = slave };
    }

    pub fn close(self: Pty) void {
        _ = std.c.close(self.slave);
        _ = std.c.close(self.master);
    }

    /// What the editor wrote, waiting briefly for it.
    pub fn output(self: Pty, buf: []u8) ![]const u8 {
        var n: usize = 0;
        while (n < buf.len) {
            var fds = [_]posix.pollfd{.{ .fd = self.master, .events = posix.POLL.IN, .revents = 0 }};
            if (try posix.poll(&fds, 200) == 0) break;
            const got = posix.read(self.master, buf[n..]) catch break;
            if (got == 0) break;
            n += got;
        }
        return buf[0..n];
    }

    pub fn send(self: Pty, bytes: []const u8) void {
        _ = std.c.write(self.master, bytes.ptr, bytes.len);
    }

    pub fn setSize(self: Pty, cols: u16, rows: u16) void {
        const ws: posix.winsize = .{ .row = rows, .col = cols, .xpixel = 0, .ypixel = 0 };
        _ = std.c.ioctl(self.master, @as(c_int, @bitCast(set_winsize)), &ws);
    }
};

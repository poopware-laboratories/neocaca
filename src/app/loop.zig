//! The event loop: draw a frame, wait for the terminal, hand what it sent
//! to the session, until the editor quits or the terminal goes away.
//! Generic over the terminal (`wait`, `read`, `size`, `suspendProcess`, as
//! `term.Tty` has them), so tests drive it with a script.

const std = @import("std");
const Session = @import("session.zig").Session;

/// How long a lone Escape waits for the rest of a key, in milliseconds.
/// Terminals send a key's bytes together; a person types slower than this.
pub const escape_timeout_ms = 25;

/// The most bytes taken from the terminal per read.
pub const read_size = 4096;

/// Runs `session` on `terminal`, writing frames to `out`. Returns once the
/// editor quits or the terminal reports end of input or hangs up; a save
/// or load still running is finished first. A finished save or load wakes
/// the wait through the session's `notify` pipe.
pub fn run(session: *Session, terminal: anytype, out: *std.Io.Writer) !void {
    defer session.settle();
    var buf: [read_size]u8 = undefined;
    while (true) {
        try session.render(out);
        try out.flush();
        if (session.done()) return;
        const timeout: i32 = if (session.waiting()) escape_timeout_ms else -1;
        const ready = try terminal.wait(timeout);
        try session.collect();
        if (ready.hung_up) return;
        if (ready.woken) {
            if (terminal.size()) |s| session.resize(s.width, s.height);
        }
        if (ready.input) {
            const n = try terminal.read(&buf);
            if (n == 0) return;
            try session.feed(buf[0..n]);
            if (session.takeSuspend()) {
                terminal.suspendProcess();
                session.redrawAll();
                if (terminal.size()) |s| session.resize(s.width, s.height);
            }
        } else if (!ready.woken and session.waiting()) {
            try session.timeout();
        }
    }
}

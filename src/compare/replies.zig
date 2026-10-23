//! The answers a terminal gives to the queries an editor writes, so an
//! editor run on a bare pseudo-terminal starts as it would in a terminal
//! emulator instead of waiting for replies that never come. Sequences are
//! read as ECMA-48 frames them (section 5.4: a control sequence's parameter
//! and intermediate bytes, then its final byte),
//! and answered as xterm's ctlseqs and the kitty keyboard protocol define:
//!
//! - DA1 (`CSI c`): a VT220 with ANSI color, `CSI ? 62 ; 22 c`;
//! - DSR (`CSI 5 n`): no malfunction, `CSI 0 n`; CPR (`CSI 6 n`): the
//!   cursor at home, since no screen is kept;
//! - DECRQM (`CSI ? Ps $ p`, `CSI Ps $ p`): mode not recognized;
//! - the kitty keyboard query (`CSI ? u`): the protocol is there, no flags
//!   set yet.
//!
//! Everything else is drawing and asks for nothing. A string (OSC, DCS,
//! APC) needs no state of its own: its text holds no escape, since an
//! escape there ends it and starts a sequence, as in a terminal.

const std = @import("std");

/// Longer parameters than a query has: the sequence is passed over.
const max_params = 16;

pub const Replies = struct {
    state: enum { ground, escape, csi } = .ground,
    params: [max_params]u8 = undefined,
    len: usize = 0,
    too_long: bool = false,

    /// Scans what the editor wrote and writes the replies to its queries.
    /// A query split across calls is answered once it is whole.
    pub fn feed(self: *Replies, bytes: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
        for (bytes) |b| {
            switch (self.state) {
                .ground => if (b == 0x1b) {
                    self.state = .escape;
                },
                .escape => switch (b) {
                    '[' => {
                        self.state = .csi;
                        self.len = 0;
                        self.too_long = false;
                    },
                    0x1b => {},
                    else => self.state = .ground,
                },
                .csi => switch (b) {
                    0x1b => self.state = .escape,
                    0x20...0x3f => if (self.len < max_params) {
                        self.params[self.len] = b;
                        self.len += 1;
                    } else {
                        self.too_long = true;
                    },
                    0x40...0x7e => {
                        self.state = .ground;
                        if (!self.too_long) try reply(self.params[0..self.len], b, w);
                    },
                    // Control bytes inside a sequence are carried out by a
                    // terminal and leave the sequence going.
                    else => {},
                },
            }
        }
    }
};

fn reply(params: []const u8, final: u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (final) {
        'c' => if (params.len == 0 or std.mem.eql(u8, params, "0")) try w.writeAll("\x1b[?62;22c"),
        'n' => if (std.mem.eql(u8, params, "5")) {
            try w.writeAll("\x1b[0n");
        } else if (std.mem.eql(u8, params, "6")) {
            try w.writeAll("\x1b[1;1R");
        },
        'p' => {
            const mode = std.mem.cutSuffix(u8, params, "$") orelse return;
            const private = std.mem.startsWith(u8, mode, "?");
            const number = if (private) mode[1..] else mode;
            if (number.len == 0) return;
            for (number) |d| if (!std.ascii.isDigit(d)) return;
            try w.print("\x1b[{s};0$y", .{mode});
        },
        'u' => if (std.mem.eql(u8, params, "?")) try w.writeAll("\x1b[?0u"),
        else => {},
    }
}

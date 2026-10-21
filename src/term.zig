//! The real terminal, the only code that touches it: `term/attr.zig`
//! (reading and setting its settings), `term/raw.zig` (the
//! raw-mode settings), `term/modes.zig` (the modes entered and left) and
//! `term/tty.zig` (raw mode, size, input waits and resizes; POSIX only).

pub const attr = @import("term/attr.zig");
pub const raw = @import("term/raw.zig");
pub const modes = @import("term/modes.zig");
pub const tty = @import("term/tty.zig");

pub const Tty = tty.Tty;
pub const Size = tty.Size;

test {
    _ = attr;
    _ = raw;
    _ = modes;
    _ = tty;
}

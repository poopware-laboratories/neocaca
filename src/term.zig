//! The real terminal, the only code that touches it: `term/raw.zig` (the
//! raw-mode settings), `term/modes.zig` (the modes entered and left) and
//! `term/tty.zig` (raw mode, size, input waits and resizes; POSIX only).

pub const raw = @import("term/raw.zig");
pub const modes = @import("term/modes.zig");
pub const tty = @import("term/tty.zig");

pub const Tty = tty.Tty;
pub const Size = tty.Size;

test {
    _ = raw;
    _ = modes;
    _ = tty;
}

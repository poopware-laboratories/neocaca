//! Counting the 3:1 rule of AGENTS.md over a diff, for `zig build ratio`
//! (`src/tools/ratio.zig` runs it): `ratio/diff.zig` (the lines a diff
//! adds and removes), `ratio/path.zig` (which files count, and how),
//! `ratio/lines.zig` (which lines of a Zig file are test code) and
//! `ratio/check.zig` (the tally and its report).

pub const diff = @import("ratio/diff.zig");
pub const path = @import("ratio/path.zig");
pub const lines = @import("ratio/lines.zig");
pub const check = @import("ratio/check.zig");

pub const Tally = check.Tally;

test {
    _ = diff;
    _ = @import("ratio/diff_test.zig");
    _ = path;
    _ = @import("ratio/path_test.zig");
    _ = lines;
    _ = @import("ratio/lines_test.zig");
    _ = check;
    _ = @import("ratio/check_test.zig");
}

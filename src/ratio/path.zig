//! Which files the 3:1 rule counts, and how. AGENTS.md: test lines are
//! those in `test` blocks, in `*_test.zig` files and under `tests/`;
//! `build.zig` and the benchmarks in `src/bench/` are not counted, nor is
//! anything that is not Zig.

const std = @import("std");

pub const Rule = enum {
    /// Not counted at all.
    skip,
    /// Every line is test code.
    test_file,
    /// Test code in its `test` blocks, production code elsewhere.
    scan,
};

/// How the file at `p` (relative to the repository, `/`-separated) counts.
pub fn rule(p: []const u8) Rule {
    if (!std.mem.endsWith(u8, p, ".zig")) return .skip;
    if (std.mem.eql(u8, p, "build.zig") or std.mem.startsWith(u8, p, "src/bench/")) return .skip;
    if (std.mem.startsWith(u8, p, "tests/") or std.mem.endsWith(u8, p, "_test.zig")) return .test_file;
    return .scan;
}

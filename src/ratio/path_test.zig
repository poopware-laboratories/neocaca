//! Tests for `path.zig`: which files the 3:1 rule counts, and how.

const std = @import("std");
const path = @import("path.zig");

const expectEqual = std.testing.expectEqual;

test "path: integration tests and *_test.zig files are test files" {
    try expectEqual(.test_file, path.rule("tests/editing_test.zig"));
    try expectEqual(.test_file, path.rule("tests/harness.zig"));
    try expectEqual(.test_file, path.rule("src/edit/selecting_count_test.zig"));
}

test "path: other Zig sources are scanned for test blocks" {
    try expectEqual(.scan, path.rule("src/term/tty.zig"));
    try expectEqual(.scan, path.rule("src/root.zig"));
    try expectEqual(.scan, path.rule("src/main.zig"));
    // Only a name ending in `_test.zig` is a test file.
    try expectEqual(.scan, path.rule("src/test.zig"));
    try expectEqual(.scan, path.rule("src/attests/x.zig"));
}

test "path: the build script, benchmarks and everything not Zig are not counted" {
    try expectEqual(.skip, path.rule("build.zig"));
    try expectEqual(.skip, path.rule("build.zig.zon"));
    try expectEqual(.skip, path.rule("src/bench/compare.zig"));
    try expectEqual(.skip, path.rule("src/bench/pty.zig"));
    try expectEqual(.skip, path.rule("TODO.md"));
    try expectEqual(.skip, path.rule(".github/workflows/ci.yml"));
    try expectEqual(.skip, path.rule("scripts/dogfood-corpus.sh"));
    try expectEqual(.skip, path.rule("src/x.zig.orig"));
}

test "path: only the top-level build script and bench folder are skipped" {
    try expectEqual(.scan, path.rule("src/app/build.zig"));
    try expectEqual(.scan, path.rule("src/benchmark.zig"));
    try expectEqual(.scan, path.rule("src/app/bench/x.zig"));
}

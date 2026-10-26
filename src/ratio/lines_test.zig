//! Tests for `lines.zig`: which lines of a Zig file are test code.

const std = @import("std");
const lines = @import("lines.zig");

const Kind = lines.Kind;
const gpa = std.testing.allocator;

fn expectKinds(source: []const u8, whole_file_is_test: bool, want: []const Kind) !void {
    const got = try lines.classify(gpa, source, whole_file_is_test);
    defer gpa.free(got);
    try std.testing.expectEqualSlices(Kind, want, got);
}

test "lines: code outside a test block is production, inside it test, from its first line to its last" {
    try expectKinds(
        \\fn add(a: u8) u8 {
        \\    return a + 1;
        \\}
        \\test "add" {
        \\    try expect(add(1) == 2);
        \\}
        \\const x = 1;
    , false, &.{ .production, .production, .production, .test_code, .test_code, .test_code, .production });
}

test "lines: blank lines and comments count for neither side, in a test block or out" {
    try expectKinds(
        \\//! A file.
        \\
        \\/// Doc.
        \\fn f() void {}
        \\   
        \\test {
        \\    // why
        \\
        \\    f();
        \\}
    , false, &.{ .none, .none, .none, .production, .none, .test_code, .none, .none, .test_code, .test_code });
}

test "lines: nested braces stay inside the test block until it closes" {
    try expectKinds(
        \\test "nested" {
        \\    const s = struct {
        \\        fn g() void {
        \\            if (true) {}
        \\        }
        \\    };
        \\}
        \\fn after() void {}
    , false, &.{ .test_code, .test_code, .test_code, .test_code, .test_code, .test_code, .test_code, .production });
}

test "lines: braces in strings, characters, comments and multiline strings do not open or close blocks" {
    try expectKinds(
        \\test "a { in the name" {
        \\    const s = "}}}";
        \\    const c = '}';
        \\    const e = "\"}";
        \\    // }
        \\    const m =
        \\        \\}
        \\    ;
        \\}
        \\const done = 1;
    , false, &.{ .test_code, .test_code, .test_code, .test_code, .none, .test_code, .test_code, .test_code, .test_code, .production });
}

test "lines: the word test in a string, a comment or an identifier opens nothing" {
    try expectKinds(
        \\const name = "test {";
        \\// test {
        \\const testing = @import("std").testing;
        \\fn attest() void {}
        \\const q = @"test";
    , false, &.{ .production, .none, .production, .production, .production });
}

test "lines: unnamed, identifier and multiline-headed test blocks, and one inside a struct" {
    try expectKinds(
        \\test {
        \\    _ = 1;
        \\}
        \\test add {
        \\}
        \\test "split"
        \\{
        \\}
        \\const S = struct {
        \\    test "inner" {}
        \\    fn m() void {}
        \\};
    , false, &.{ .test_code, .test_code, .test_code, .test_code, .test_code, .test_code, .test_code, .test_code, .production, .test_code, .production, .production });
}

test "lines: a whole test file is test code but for its blank lines and comments" {
    try expectKinds(
        \\//! Tests.
        \\const std = @import("std");
        \\
        \\fn helper() void {}
    , true, &.{ .none, .test_code, .none, .test_code });
}

test "lines: a final line without a newline counts, and an empty file has no lines" {
    try expectKinds("fn f() void {}\nconst x = 1;", false, &.{ .production, .production });
    try expectKinds("fn f() void {}\n", false, &.{.production});
    try expectKinds("", false, &.{});
}

test "lines: a block left open at the end of the file stays test code" {
    try expectKinds("test {\n    x();\n", false, &.{ .test_code, .test_code });
}

test "lines: a closing brace on the line of the next test keeps both in test code" {
    try expectKinds("test {} test {\n}\nconst z = 0;", false, &.{ .test_code, .test_code, .production });
}

test "lines: without memory classifying fails cleanly" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn f(a: std.mem.Allocator) !void {
            const got = try lines.classify(a, "test {}\nfn f() void {}\n", false);
            a.free(got);
        }
    }.f, .{});
}

test "lines: a multiline string that starts after code on its line holds no braces" {
    try expectKinds(
        \\test {
        \\    const s = \\}}
        \\    ;
        \\    _ = s;
        \\}
        \\const after = \\{
        \\;
        \\fn f() void {}
    , false, &.{ .test_code, .test_code, .test_code, .test_code, .test_code, .production, .production, .production });
}

test "lines: quotes inside character literals and escapes at the end of a string" {
    try expectKinds(
        \\test {
        \\    const q = '"';
        \\    const a = '\'';
        \\    const b = "\\";
        \\    const c = "{\\";
        \\}
        \\const d = 1;
    , false, &.{ .test_code, .test_code, .test_code, .test_code, .test_code, .test_code, .production });
}

test "lines: a string left open at the end of a line ends there" {
    // Not valid Zig, but the scan must not run past the line or crash.
    try expectKinds("const s = \"{ test {\nconst t = 1;\n", false, &.{ .production, .production });
    try expectKinds("const c = '\\\n", false, &.{.production});
}

test "lines: a comment after code ends the scan of its line" {
    try expectKinds(
        \\test {
        \\    f(); // }
        \\}
        \\g(); // test {
        \\h();
    , false, &.{ .test_code, .test_code, .test_code, .production, .production });
}

test "lines: a test written on one line, and code after its closing brace" {
    try expectKinds(
        \\test "one" { try expect(true); }
        \\const after = 1;
        \\test { }
    , false, &.{ .test_code, .production, .test_code });
}

test "lines: comptime and other blocks outside tests stay production" {
    try expectKinds(
        \\comptime {
        \\    std.debug.assert(true);
        \\}
        \\fn f() void {
        \\    blk: {
        \\        break :blk;
        \\    }
        \\}
    , false, &.{ .production, .production, .production, .production, .production, .production, .production, .production });
}

test "lines: carriage returns at line ends change nothing" {
    try expectKinds("fn f() void {}\r\n\r\ntest {\r\n    // c\r\n    f();\r\n}\r\n", false, &.{ .production, .none, .test_code, .none, .test_code, .test_code });
}

test "lines: tabs before a comment or a multiline string are indentation" {
    try expectKinds("test {\n\t// c\n\tconst s =\n\t\t\\\\}\n\t;\n}\nconst x = 1;\n", false, &.{ .test_code, .none, .test_code, .test_code, .test_code, .test_code, .production });
}

test "lines: doc comments and module docs are never production, even in a test file" {
    try expectKinds("//! Module.\n/// Doc.\nconst x = 1;\n", false, &.{ .none, .none, .production });
    try expectKinds("//! Module.\n/// Doc.\nconst x = 1;\n", true, &.{ .none, .none, .test_code });
}

test "lines: the test keyword must stand alone, before a name, a string or a brace" {
    try expectKinds(
        \\const t = isTest(x);
        \\const u = my_test;
        \\const v = test_count;
        \\test"tight"{
        \\}
    , false, &.{ .production, .production, .production, .test_code, .test_code });
}

/// Real files of this repository, as zig fmt leaves them; the first four
/// hold test blocks of their own.
const real_files = [_][]const u8{
    @embedFile("../app/edit.zig"),
    @embedFile("../cli/parse.zig"),
    @embedFile("../unicode/display.zig"),
    @embedFile("../buffer/lines.zig"),
    @embedFile("../app/editor.zig"),
    @embedFile("../regex/vm.zig"),
    @embedFile("lines.zig"),
    @embedFile("diff.zig"),
    @embedFile("check.zig"),
    @embedFile("lines_test.zig"),
};

test "lines: in real files, declarations at the margin are production and tests at the margin are test code" {
    for (real_files, 0..) |source, n| {
        const kinds = try lines.classify(gpa, source, false);
        defer gpa.free(kinds);
        var it = std.mem.splitScalar(u8, source, '\n');
        var i: usize = 0;
        var in_test = false;
        while (it.next()) |line| : (i += 1) {
            if (i == kinds.len) break;
            errdefer std.debug.print("file {d}, line {d}: {s}\n", .{ n, i + 1, line });
            if (std.mem.startsWith(u8, line, "test ")) {
                try std.testing.expectEqual(.test_code, kinds[i]);
                in_test = !std.mem.endsWith(u8, line, "}");
            } else if (in_test and std.mem.eql(u8, line, "}")) {
                // zig fmt puts the closing brace of a top-level test alone
                // at the margin.
                try std.testing.expectEqual(.test_code, kinds[i]);
                in_test = false;
            } else if (in_test) {
                try std.testing.expect(kinds[i] != .production);
            } else if (std.mem.startsWith(u8, line, "pub fn ") or std.mem.startsWith(u8, line, "fn ") or
                std.mem.startsWith(u8, line, "const ") or std.mem.startsWith(u8, line, "pub const "))
            {
                try std.testing.expectEqual(.production, kinds[i]);
            } else if (std.mem.startsWith(u8, line, "//")) {
                try std.testing.expectEqual(.none, kinds[i]);
            }
        }
    }
}

test "lines: every real file has some of each kind, and as many kinds as lines" {
    for (real_files[0..4]) |source| {
        const kinds = try lines.classify(gpa, source, false);
        defer gpa.free(kinds);
        const newlines = std.mem.count(u8, source, "\n");
        try std.testing.expectEqual(newlines, kinds.len);
        try std.testing.expect(std.mem.indexOfScalar(Kind, kinds, .none) != null);
        try std.testing.expect(std.mem.indexOfScalar(Kind, kinds, .production) != null);
        try std.testing.expect(std.mem.indexOfScalar(Kind, kinds, .test_code) != null);
    }
}

test "lines: a test header split by a comment line still opens its block" {
    try expectKinds(
        \\/// What it checks.
        \\test "x" // a note
        \\{
        \\    f();
        \\}
        \\const y = 1;
    , false, &.{ .none, .test_code, .test_code, .test_code, .test_code, .production });
}

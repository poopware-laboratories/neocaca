//! Tests for `check.zig`: a diff joined to the files it names, tallied
//! and reported.

const std = @import("std");
const check = @import("check.zig");

const io = std.testing.io;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Runs the check over `diff` in `dir`, keeping the report.
const Run = struct {
    arena: std.heap.ArenaAllocator,
    out_buf: [2048]u8 = undefined,
    out: std.Io.Writer = undefined,
    tally: check.Tally = .{},

    fn go(self: *Run, dir: std.Io.Dir, diff: []const u8) !void {
        self.arena = .init(std.testing.allocator);
        self.out = .fixed(&self.out_buf);
        self.tally = try check.check(self.arena.allocator(), io, dir, diff, &self.out);
    }

    fn report(self: *Run) []const u8 {
        return self.out.buffered();
    }

    fn deinit(self: *Run) void {
        self.arena.deinit();
    }
};

test "check: added test and production lines are counted per file and in total" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/a.zig", .data = "fn f() u8 {\n    return 1;\n}\n\ntest {\n    try e(f() == 1);\n    try e(true);\n    try e(!false);\n}\n" });
    var r: Run = undefined;
    try r.go(tmp.dir,
        \\--- a/src/a.zig
        \\+++ b/src/a.zig
        \\@@ -0,0 +1,9 @@
        \\+fn f() u8 {
        \\+    return 1;
        \\+}
        \\+
        \\+test {
        \\+    try e(f() == 1);
        \\+    try e(true);
        \\+    try e(!false);
        \\+}
        \\
    );
    defer r.deinit();
    try expectEqual(5, r.tally.test_lines);
    try expectEqual(3, r.tally.production_lines);
    try expect(!r.tally.passes());
    try expectEqualStrings(
        \\  test   prod  file
        \\     5      3  src/a.zig
        \\     5      3  total
        \\3:1 fails: 5 test lines for 3 production lines, 9 needed
        \\
    , r.report());
}

test "check: test files, skipped files and the ratio held" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.createDirPath(io, "tests");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/b.zig", .data = "const x = 1;\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "tests/b_test.zig", .data = "const a = 1;\nconst b = 2;\n// note\nconst c = 3;\n" });
    var r: Run = undefined;
    try r.go(tmp.dir,
        \\--- a/src/b.zig
        \\+++ b/src/b.zig
        \\@@ -0,0 +1 @@
        \\+const x = 1;
        \\--- a/tests/b_test.zig
        \\+++ b/tests/b_test.zig
        \\@@ -0,0 +1,4 @@
        \\+const a = 1;
        \\+const b = 2;
        \\+// note
        \\+const c = 3;
        \\--- a/build.zig
        \\+++ b/build.zig
        \\@@ -0,0 +1 @@
        \\+const not_counted = 1;
        \\--- a/TODO.md
        \\+++ b/TODO.md
        \\@@ -0,0 +1 @@
        \\+- [x] done
        \\
    );
    defer r.deinit();
    try expectEqual(3, r.tally.test_lines);
    try expectEqual(1, r.tally.production_lines);
    try expect(r.tally.passes());
    try expectEqualStrings(
        \\  test   prod  file
        \\     0      1  src/b.zig
        \\     3      0  tests/b_test.zig
        \\     3      1  total
        \\3:1 holds: 3 test lines for 1 production line
        \\
    , r.report());
}

test "check: a line the diff also removes is moved, not added" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "new.zig", .data = "fn moved() void {\n    work();\n}\nconst fresh = 1;\n" });
    var r: Run = undefined;
    try r.go(tmp.dir,
        \\--- a/old.zig
        \\+++ b/old.zig
        \\@@ -1,3 +0,0 @@
        \\-  fn moved() void {
        \\-      work();
        \\-  }
        \\--- a/new.zig
        \\+++ b/new.zig
        \\@@ -0,0 +1,4 @@
        \\+fn moved() void {
        \\+    work();
        \\+}
        \\+const fresh = 1;
        \\
    );
    defer r.deinit();
    // Indented differently, the three moved lines are still the same lines.
    try expectEqual(1, r.tally.production_lines);
    try expectEqual(0, r.tally.test_lines);
    try expect(!r.tally.passes());
}

test "check: a line removed once excuses only one copy of it" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "c.zig", .data = "x();\nx();\n" });
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/c.zig\n+++ b/c.zig\n@@ -1 +1,2 @@\n-x();\n+x();\n+x();\n");
    defer r.deinit();
    try expectEqual(1, r.tally.production_lines);
}

test "check: a diff without production code passes, whatever its tests" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-old\n+new\n");
    defer r.deinit();
    try expect(r.tally.passes());
    try expectEqualStrings(
        \\  test   prod  file
        \\     0      0  total
        \\3:1 holds: no production code
        \\
    , r.report());
}

test "check: the ratio at exactly three to one passes, one test line short fails" {
    try expect((check.Tally{ .test_lines = 3, .production_lines = 1 }).passes());
    try expect((check.Tally{ .test_lines = 300, .production_lines = 100 }).passes());
    try expect(!(check.Tally{ .test_lines = 299, .production_lines = 100 }).passes());
    try expect((check.Tally{}).passes());
    try expect(!(check.Tally{ .production_lines = 1 }).passes());
}

test "check: a diff naming a file that is not there is an error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var r: Run = undefined;
    try std.testing.expectError(error.FileNotFound, r.go(tmp.dir, "--- a/x.zig\n+++ b/x.zig\n@@ -0,0 +1 @@\n+a\n"));
    r.deinit();
}

test "check: an added line past the end of its file is an error" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "s.zig", .data = "a\n" });
    var r: Run = undefined;
    try std.testing.expectError(error.DiffNotOfThisTree, r.go(tmp.dir, "--- a/s.zig\n+++ b/s.zig\n@@ -0,0 +1,2 @@\n+a\n+b\n"));
    r.deinit();
}

test "check: a path that leaves the tree is refused before anything is read" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "x.zig", .data = "const a = 1;\n" });
    const sub = try tmp.dir.openDir(io, "sub", .{});
    defer sub.close(io);
    var r: Run = undefined;
    try std.testing.expectError(error.PathOutsideTree, r.go(sub, "--- a/../x.zig\n+++ b/../x.zig\n@@ -0,0 +1 @@\n+const a = 1;\n"));
    r.deinit();
    try std.testing.expectError(error.PathOutsideTree, r.go(sub, "--- a/x\n+++ b//etc/x.zig\n@@ -0,0 +1 @@\n+a\n"));
    r.deinit();
    try std.testing.expectError(error.PathOutsideTree, r.go(sub, "--- a/x\n+++ b/a/../../x.md\n@@ -0,0 +1 @@\n+a\n"));
    r.deinit();
    // A name that only starts with dots is a name.
    try sub.writeFile(io, .{ .sub_path = "..x.zig", .data = "const a = 1;\n" });
    try r.go(sub, "--- a/..x.zig\n+++ b/..x.zig\n@@ -0,0 +1 @@\n+const a = 1;\n");
    defer r.deinit();
    try expectEqual(1, r.tally.production_lines);
}

test "check: a file is read up to its limit, and one byte more is refused" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const big = try std.testing.allocator.alloc(u8, check.max_file_bytes + 1);
    defer std.testing.allocator.free(big);
    @memset(big, 'x');
    big[0] = 'a';
    big[1] = '\n';
    try tmp.dir.writeFile(io, .{ .sub_path = "at.zig", .data = big[0..check.max_file_bytes] });
    try tmp.dir.writeFile(io, .{ .sub_path = "past.zig", .data = big });
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/at.zig\n+++ b/at.zig\n@@ -0,0 +1 @@\n+a\n");
    try expectEqual(1, r.tally.production_lines);
    r.deinit();
    try std.testing.expectError(error.StreamTooLong, r.go(tmp.dir, "--- a/past.zig\n+++ b/past.zig\n@@ -0,0 +1 @@\n+a\n"));
    r.deinit();
}

test "check: a diff file is read up to its limit, and one byte more is refused" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const head = "--- a/README.md\n+++ b/README.md\n@@ -0,0 +1 @@\n+";
    const big = try std.testing.allocator.alloc(u8, check.max_diff_bytes + 1);
    defer std.testing.allocator.free(big);
    @memcpy(big[0..head.len], head);
    @memset(big[head.len..], 'x');
    try tmp.dir.writeFile(io, .{ .sub_path = "at.diff", .data = big[0..check.max_diff_bytes] });
    try tmp.dir.writeFile(io, .{ .sub_path = "past.diff", .data = big });
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var buf: [256]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    const t = try check.checkFile(arena.allocator(), io, tmp.dir, "at.diff", &out);
    try expect(t.passes());
    try std.testing.expectError(error.StreamTooLong, check.checkFile(arena.allocator(), io, tmp.dir, "past.diff", &out));
    try std.testing.expectError(error.FileNotFound, check.checkFile(arena.allocator(), io, tmp.dir, "none.diff", &out));
}

test "check: lines moved between a test block and production code count for neither" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "m.zig", .data = "const shared = 1;\ntest {\n    const shared = 1;\n}\n" });
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/m.zig\n+++ b/m.zig\n@@ -1,2 +1,4 @@\n-const shared = 1;\n-const shared = 1;\n+const shared = 1;\n+test {\n+    const shared = 1;\n+}\n");
    defer r.deinit();
    try expectEqual(2, r.tally.test_lines);
    try expectEqual(0, r.tally.production_lines);
}

test "check: blank lines and comments added alone leave a file out of the table" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "c.zig", .data = "// one\n\nconst x = 1;\n" });
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/c.zig\n+++ b/c.zig\n@@ -0,0 +1,2 @@\n+// one\n+\n");
    defer r.deinit();
    try expectEqualStrings(
        \\  test   prod  file
        \\     0      0  total
        \\3:1 holds: no production code
        \\
    , r.report());
}

test "check: the verdict counts production lines in the plural, and the lines needed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "p.zig", .data = "const a = 1;\nconst b = 2;\ntest {\n    a();\n    b();\n    c();\n    d();\n    e();\n}\n" });
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/p.zig\n+++ b/p.zig\n@@ -0,0 +1,9 @@\n+const a = 1;\n+const b = 2;\n+test {\n+    a();\n+    b();\n+    c();\n+    d();\n+    e();\n+}\n");
    defer r.deinit();
    try expectEqual(7, r.tally.test_lines);
    try expect(std.mem.endsWith(u8, r.report(), "3:1 fails: 7 test lines for 2 production lines, 6 needed\n") == false);
    try expect(r.tally.passes());
    try expect(std.mem.endsWith(u8, r.report(), "3:1 holds: 7 test lines for 2 production lines\n"));
}

test "check: added lines of a deleted or renamed file are not looked up" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var r: Run = undefined;
    try r.go(tmp.dir, "diff --git a/gone.zig b/gone.zig\n--- a/gone.zig\n+++ /dev/null\n@@ -1 +0,0 @@\n-const a = 1;\ndiff --git a/a.zig b/b.zig\nsimilarity index 100%\nrename from a.zig\nrename to b.zig\n");
    defer r.deinit();
    try expect(r.tally.passes());
    try expectEqual(0, r.tally.production_lines);
}

test "check: a writer that fills up is an error, not a short report" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var buf: [8]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, check.check(arena.allocator(), io, tmp.dir, "", &out));
}

test "check: a renamed file that also changed counts its added lines at its new path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/new.zig", .data = "fn f() void {}\nfn g() void {}\n" });
    var r: Run = undefined;
    try r.go(tmp.dir,
        \\diff --git a/src/old.zig b/src/new.zig
        \\similarity index 60%
        \\rename from src/old.zig
        \\rename to src/new.zig
        \\--- a/src/old.zig
        \\+++ b/src/new.zig
        \\@@ -1,0 +2 @@
        \\+fn g() void {}
        \\
    );
    defer r.deinit();
    try expectEqual(1, r.tally.production_lines);
    try expect(std.mem.indexOf(u8, r.report(), "src/new.zig") != null);
}

test "check: a test file's test blocks and helpers are all test code" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "src/x");
    try tmp.dir.writeFile(io, .{ .sub_path = "src/x/y_test.zig", .data = "fn helper() void {}\ntest {\n    helper();\n}\n" });
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/src/x/y_test.zig\n+++ b/src/x/y_test.zig\n@@ -0,0 +1,4 @@\n+fn helper() void {}\n+test {\n+    helper();\n+}\n");
    defer r.deinit();
    try expectEqual(4, r.tally.test_lines);
    try expectEqual(0, r.tally.production_lines);
}

test "check: benchmarks and the build script are not read, even when missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var r: Run = undefined;
    try r.go(tmp.dir, "--- a/src/bench/main.zig\n+++ b/src/bench/main.zig\n@@ -0,0 +1 @@\n+const a = 1;\n--- a/build.zig\n+++ b/build.zig\n@@ -0,0 +1 @@\n+const b = 2;\n");
    defer r.deinit();
    try expectEqual(0, r.tally.production_lines);
    try expect(r.tally.passes());
}

test "check: a broken diff is an error, not a pass" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var r: Run = undefined;
    try std.testing.expectError(error.BadHunk, r.go(tmp.dir, "--- a/f.zig\n+++ b/f.zig\n@@ -0,0 +1,3 @@\n+a\n"));
    r.deinit();
    try std.testing.expectError(error.QuotedPath, r.go(tmp.dir, "--- \"a/\\tf.zig\"\n+++ \"b/\\tf.zig\"\n"));
    r.deinit();
}

//! Tests for `diff.zig`: the lines a unified diff adds and removes.

const std = @import("std");
const diff = @import("diff.zig");

const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn parse(arena: *std.heap.ArenaAllocator, text: []const u8) !diff.Diff {
    return diff.parse(arena.allocator(), text);
}

test "diff: added lines carry their number in the new file and their text" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena,
        \\diff --git a/src/a.zig b/src/a.zig
        \\index 1111111..2222222 100644
        \\--- a/src/a.zig
        \\+++ b/src/a.zig
        \\@@ -3,0 +4,2 @@ fn f() void {
        \\+    one();
        \\+    two();
        \\@@ -10 +12 @@
        \\-    old();
        \\+    new();
        \\
    );
    try expectEqual(1, d.files.len);
    try expectEqualStrings("src/a.zig", d.files[0].path);
    const added = d.files[0].added;
    try expectEqual(3, added.len);
    try expectEqual(4, added[0].number);
    try expectEqualStrings("    one();", added[0].text);
    try expectEqual(5, added[1].number);
    try expectEqual(12, added[2].number);
    try expectEqualStrings("    new();", added[2].text);
    try expectEqual(1, d.removed.len);
    try expectEqualStrings("    old();", d.removed[0]);
}

test "diff: a new file, a deleted file and several files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena,
        \\diff --git a/new.zig b/new.zig
        \\new file mode 100644
        \\index 0000000..3333333
        \\--- /dev/null
        \\+++ b/new.zig
        \\@@ -0,0 +1,2 @@
        \\+const a = 1;
        \\+const b = 2;
        \\diff --git a/gone.zig b/gone.zig
        \\deleted file mode 100644
        \\index 4444444..0000000
        \\--- a/gone.zig
        \\+++ /dev/null
        \\@@ -1 +0,0 @@
        \\-const gone = 1;
        \\diff --git a/b.zig b/b.zig
        \\--- a/b.zig
        \\+++ b/b.zig
        \\@@ -1,0 +2 @@
        \\+const c = 3;
        \\
    );
    try expectEqual(2, d.files.len);
    try expectEqualStrings("new.zig", d.files[0].path);
    try expectEqual(2, d.files[0].added.len);
    try expectEqual(2, d.files[0].added[1].number);
    try expectEqualStrings("b.zig", d.files[1].path);
    try expectEqual(2, d.files[1].added[0].number);
    try expectEqual(1, d.removed.len);
    try expectEqualStrings("const gone = 1;", d.removed[0]);
}

test "diff: renames, mode changes and binary files add no lines of their own" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena,
        \\diff --git a/old.zig b/moved.zig
        \\similarity index 100%
        \\rename from old.zig
        \\rename to moved.zig
        \\diff --git a/run.sh b/run.sh
        \\old mode 100644
        \\new mode 100755
        \\diff --git a/logo.png b/logo.png
        \\index 5555555..6666666 100644
        \\Binary files a/logo.png and b/logo.png differ
        \\
    );
    try expectEqual(0, d.files.len);
    try expectEqual(0, d.removed.len);
}

test "diff: a line that looks like a header inside a hunk is text" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena,
        \\diff --git a/m.md b/m.md
        \\--- a/m.md
        \\+++ b/m.md
        \\@@ -1 +1,2 @@
        \\---- a/x
        \\++++ b/y
        \\+@@ -1 +1 @@
        \\
    );
    try expectEqual(1, d.files.len);
    try expectEqual(2, d.files[0].added.len);
    try expectEqualStrings("+++ b/y", d.files[0].added[0].text);
    try expectEqualStrings("@@ -1 +1 @@", d.files[0].added[1].text);
    try expectEqual(2, d.files[0].added[1].number);
    try expectEqualStrings("--- a/x", d.removed[0]);
}

test "diff: the no-newline marker is not a line, and a diff need not end in a newline" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "diff --git a/f.zig b/f.zig\n--- a/f.zig\n+++ b/f.zig\n@@ -1 +1 @@\n-a\n\\ No newline at end of file\n+b\n\\ No newline at end of file");
    try expectEqual(1, d.files[0].added.len);
    try expectEqualStrings("b", d.files[0].added[0].text);
    try expectEqual(1, d.files[0].added[0].number);
    try expectEqual(1, d.removed.len);
}

test "diff: lines end at a carriage return too" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "diff --git a/f.zig b/f.zig\r\n--- a/f.zig\r\n+++ b/f.zig\r\n@@ -0,0 +1 @@\r\n+a\r\n");
    try expectEqualStrings("f.zig", d.files[0].path);
    try expectEqualStrings("a", d.files[0].added[0].text);
}

test "diff: an empty diff has no files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "");
    try expectEqual(0, d.files.len);
}

test "diff: a quoted path, a broken hunk header and a hunk outside a file are refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.QuotedPath, parse(&arena, "diff --git \"a/x\\ty\" \"b/x\\ty\"\n--- \"a/x\\ty\"\n+++ \"b/x\\ty\"\n@@ -0,0 +1 @@\n+a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +x @@\n+a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0\n+a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "@@ -0,0 +1 @@\n+a\n"));
    // More lines than the hunk header said.
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +1 @@\n+a\n+b\n"));
}

test "diff: a context line in a hunk advances the new line numbers" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "--- a/f\n+++ b/f\n@@ -1,2 +1,3 @@\n keep\n+add\n same\n");
    try expectEqual(1, d.files[0].added.len);
    try expectEqual(2, d.files[0].added[0].number);
}

test "diff: without memory parsing fails cleanly" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
        fn f(a: std.mem.Allocator) !void {
            var arena: std.heap.ArenaAllocator = .init(a);
            defer arena.deinit();
            _ = try diff.parse(arena.allocator(), "--- a/f\n+++ b/f\n@@ -1 +1,2 @@\n-x\n+y\n+z\n");
        }
    }.f, .{});
}

test "diff: a diff that ends partway through a hunk is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +1,2 @@\n+a"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +1,2 @@\n+a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1,1 +0,0 @@\n"));
}

test "diff: line numbers at the top of their range, and one past it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const max = std.math.maxInt(u32);
    const at_top = try parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +4294967294,1 @@\n+a\n");
    try expectEqual(max - 1, at_top.files[0].added[0].number);
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +4294967295,1 @@\n+a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +4294967296 @@\n+a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -0,0 +1,-1 @@\n+a\n"));
}

test "diff: hunk headers with a section name, or a missing part, or extra signs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const named = try parse(&arena, "--- a/f\n+++ b/f\n@@ -1 +1 @@ pub fn main() void {\n-a\n+b\n");
    try expectEqual(1, named.files[0].added[0].number);
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1 @@\n-a\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ 1 +1 @@\n-a\n+b\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1 1 @@\n-a\n+b\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1, +1 @@\n-a\n+b\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ - +1 @@\n+b\n"));
}

test "diff: a hunk line with no sign, or an empty one, is refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1 +1 @@\nx\n"));
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1,2 +1,2 @@\n a\n\n"));
    // A removed line past the old count, while new lines are still due.
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1 +1,2 @@\n-a\n-b\n+c\n"));
    // A context line once the old side is used up.
    try std.testing.expectError(error.BadHunk, parse(&arena, "--- a/f\n+++ b/f\n@@ -1 +1,2 @@\n-a\n b\n"));
}

test "diff: a path with spaces, and one without git's b/ prefix" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "--- a/my file.zig\n+++ b/my file.zig\n@@ -0,0 +1 @@\n+a\n--- plain.zig\n+++ plain.zig\n@@ -0,0 +1 @@\n+b\n");
    try expectEqual(2, d.files.len);
    try expectEqualStrings("my file.zig", d.files[0].path);
    try expectEqualStrings("plain.zig", d.files[1].path);
}

test "diff: removed lines of a deleted file are kept, its path is not" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "--- a/gone.zig\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-one\n-two\n");
    try expectEqual(0, d.files.len);
    try expectEqual(2, d.removed.len);
    try expectEqualStrings("two", d.removed[1]);
}

test "diff: a file's hunks may be split by a no-newline marker between files" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena,
        \\diff --git a/x b/x
        \\--- a/x
        \\+++ b/x
        \\@@ -1 +1 @@
        \\-a
        \\+b
        \\\ No newline at end of file
        \\diff --git a/y b/y
        \\--- a/y
        \\+++ b/y
        \\@@ -0,0 +1 @@
        \\+c
        \\
    );
    try expectEqual(2, d.files.len);
    try expectEqualStrings("y", d.files[1].path);
    try expectEqualStrings("c", d.files[1].added[0].text);
}

test "diff: a git diff with context, a changed rename, a new file and a mode change" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena,
        \\diff --git a/src/old_name.zig b/src/new_name.zig
        \\similarity index 91%
        \\rename from src/old_name.zig
        \\rename to src/new_name.zig
        \\index 1234567..89abcde 100644
        \\--- a/src/old_name.zig
        \\+++ b/src/new_name.zig
        \\@@ -8,7 +8,8 @@ pub fn f() void {
        \\     a();
        \\     b();
        \\     c();
        \\-    d();
        \\+    d(1);
        \\+    e();
        \\     g();
        \\     h();
        \\     i();
        \\diff --git a/src/fresh.zig b/src/fresh.zig
        \\new file mode 100644
        \\index 0000000..1111111
        \\--- /dev/null
        \\+++ b/src/fresh.zig
        \\@@ -0,0 +1,3 @@
        \\+//! Fresh.
        \\+
        \\+const x = 1;
        \\diff --git a/src/empty.zig b/src/empty.zig
        \\new file mode 100644
        \\index 0000000..e69de29
        \\diff --git a/run.sh b/run.sh
        \\old mode 100644
        \\new mode 100755
        \\index 2222222..3333333
        \\--- a/run.sh
        \\+++ b/run.sh
        \\@@ -1 +1,2 @@
        \\ #!/bin/sh
        \\+exit 0
        \\
    );
    try expectEqual(3, d.files.len);
    try expectEqualStrings("src/new_name.zig", d.files[0].path);
    try expectEqual(2, d.files[0].added.len);
    try expectEqual(11, d.files[0].added[0].number);
    try expectEqualStrings("    d(1);", d.files[0].added[0].text);
    try expectEqual(12, d.files[0].added[1].number);
    try expectEqualStrings("src/fresh.zig", d.files[1].path);
    try expectEqual(3, d.files[1].added[2].number);
    try expectEqualStrings("", d.files[1].added[1].text);
    try expectEqualStrings("run.sh", d.files[2].path);
    try expectEqual(2, d.files[2].added[0].number);
    try expectEqual(1, d.removed.len);
    try expectEqualStrings("    d();", d.removed[0]);
}

test "diff: a hunk that empties a file, and one that adds to an empty file" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "--- a/e\n+++ b/e\n@@ -1,2 +0,0 @@\n-a\n-b\n--- a/f\n+++ b/f\n@@ -0,0 +1 @@\n+c\n");
    try expectEqual(1, d.files.len);
    try expectEqualStrings("f", d.files[0].path);
    try expectEqual(2, d.removed.len);
}

test "diff: two hunks of one file keep their own numbering" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const d = try parse(&arena, "--- a/f\n+++ b/f\n@@ -1 +1,2 @@\n a\n+b\n@@ -40,0 +41,2 @@\n+c\n+d\n");
    try expectEqual(1, d.files.len);
    const added = d.files[0].added;
    try expectEqual(3, added.len);
    try expectEqual(2, added[0].number);
    try expectEqual(41, added[1].number);
    try expectEqual(42, added[2].number);
}

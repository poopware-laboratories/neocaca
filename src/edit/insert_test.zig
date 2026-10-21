//! Tests for `insert.zig`. In insert mode every selection is one
//! character, the one typed text goes in front of.

const std = @import("std");
const fx = @import("fixture_test.zig");
const insert = @import("insert.zig");

const gpa = std.testing.allocator;
const expect = std.testing.expect;

fn expectEnter(before: []const u8, where: insert.Where, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try insert.enter(&d, where);
    try fx.expectDoc(&d, after);
}

test "insert: i and a put the cursor before and after each selection" {
    try expectEnter("a«bc»d\n", .before, "a«b»cd\n");
    try expectEnter("a«|bc»d\n", .before, "a«b»cd\n");
    try expectEnter("a«bc»d\n", .after, "abc«d»\n");
    try expectEnter("ab«\n»", .after, "ab«\n»");
    try expectEnter("«a» ‹b›\n", .after, "a« »b‹\n›");
}

test "insert: I and A go to the first non-blank and the line end" {
    try expectEnter("  ab«c»\n", .line_start, "  «a»bc\n");
    try expectEnter("«a»bc\n", .line_end, "abc«\n»");
    try expectEnter("«a\nb»c\n", .line_end, "a\nbc«\n»");
}

test "insert: o and O open an indented line" {
    try expectEnter("  a«b»\ncd\n", .below, "  ab\n  «\n»cd\n");
    try expectEnter("  a«b»\n", .above, "  «\n»  ab\n");
    try expectEnter("\t«a»\n", .below, "\ta\n\t«\n»");
    try expectEnter("«a»‹b›\n", .below, "ab\n«\n»");
    try expectEnter("«a»\n‹b›\n", .below, "a\n«\n»b\n‹\n›");
    try expectEnter("«a\nb»\n", .below, "a\nb\n«\n»");
    try expectEnter("a\n«b\nc»\n", .above, "a\n«\n»b\nc\n");
}

fn expectTyping(before: []const u8, text: []const u8, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try insert.text(&d, text);
    try fx.expectDoc(&d, after);
}

test "insert: text goes in front of every cursor" {
    try expectTyping("a«b»c\n", "XY", "aXY«b»c\n");
    try expectTyping("«a»‹b›\n", "-", "-«a»-‹b›\n");
    try expectTyping("«a»\n", "中", "中«a»\n");
    try expectTyping("ab«\n»", "\n", "ab\n«\n»");
}

test "insert: a session is one undo step" {
    var d = try fx.doc("«a»\n");
    defer d.deinit();
    d.beginSession();
    try insert.enter(&d, .below);
    try insert.text(&d, "x");
    try insert.text(&d, "y");
    try insert.newline(&d);
    d.endSession();
    try fx.expectDoc(&d, "a\nxy\n«\n»");
    try expect(try d.undo());
    try fx.expectDoc(&d, "«a»\n");
    try expect(try d.redo());
    try fx.expectDoc(&d, "a\nxy\n«\n»");
}

fn expectKey(before: []const u8, comptime f: anytype, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try f(&d);
    try fx.expectDoc(&d, after);
}

test "insert: Enter keeps the indent before the cursor" {
    try expectKey("  ab«c»\n", insert.newline, "  ab\n  «c»\n");
    try expectKey("  «a»b\n", insert.newline, "  \n  «a»b\n");
    try expectKey("« » a\n", insert.newline, "\n« » a\n");
    try expectKey("«a»\n ‹b›\n", insert.newline, "\n«a»\n \n ‹b›\n");
    try expectKey("\t x«y»\n", insert.newline, "\t x\n\t «y»\n");
}

test "insert: Backspace deletes the character before every cursor" {
    try expectKey("a«b»c\n", insert.backspace, "«b»c\n");
    try expectKey("a\n«b»\n", insert.backspace, "a«b»\n");
    try expectKey("中«a»\n", insert.backspace, "«a»\n");
    try expectKey("e\u{301}«a»\n", insert.backspace, "«a»\n");
    try expectKey("a«b»‹c›\n", insert.backspace, "«c»\n");
}

test "insert: Backspace at the buffer start changes nothing" {
    var d = try fx.doc("«a»\n");
    defer d.deinit();
    try insert.backspace(&d);
    try fx.expectDoc(&d, "«a»\n");
    try expect(!d.isModified());
}

test "insert: Delete removes the character under every cursor but the final newline" {
    try expectKey("a«b»c\n", insert.deleteForward, "a«c»\n");
    try expectKey("ab«\n»", insert.deleteForward, "ab«\n»");
    try expectKey("a«\n»b\n", insert.deleteForward, "a«b»\n");
    try expectKey("«中»a\n", insert.deleteForward, "«a»\n");
}

test "insert: pasted line ends become newlines" {
    const got = try insert.normalizePaste(gpa, "a\r\nb\rc\n\r");
    defer gpa.free(got);
    try std.testing.expectEqualStrings("a\nb\nc\n\n", got);
}

test "insert: typing fails atomically when allocation fails" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            const Document = @import("document.zig").Document;
            var d: Document = try .init(a, " ab\n");
            defer d.deinit();
            try d.select(&.{ .at(1), .at(2) }, 0);
            insert.newline(&d) catch |e| {
                try std.testing.expectEqualStrings(" ab\n", d.text());
                return e;
            };
            try std.testing.expectEqualStrings(" \n a\n b\n", d.text());
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

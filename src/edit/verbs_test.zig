//! Tests for `verbs.zig` (paste is in `paste_test.zig`), in the marked notation of `fixture_test.zig`.

const std = @import("std");
const fx = @import("fixture_test.zig");
const verbs = @import("verbs.zig");
const Registers = @import("registers.zig").Registers;
const Document = @import("document.zig").Document;

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

fn expectRegister(regs: *const Registers, name: u8, want: []const []const u8) !void {
    const got = regs.get(name);
    try expectEqual(want.len, got.len);
    for (want, got) |w, g| try std.testing.expectEqualStrings(w, g);
}

test "verbs: yank copies every selection into the register" {
    var d = try fx.doc("«ab» ‹c›d\n");
    defer d.deinit();
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    try verbs.yank(&d, &regs, 'a');
    try expectRegister(&regs, 'a', &.{ "ab", "c" });
    try fx.expectDoc(&d, "«ab» ‹c›d\n");
    try expect(!d.isModified());
}

/// Runs `delete` on `before`, yanking into `"`, and checks the result.
fn expectDelete(before: []const u8, after: []const u8, yanked: []const []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    try verbs.delete(&d, &regs, '"');
    try fx.expectDoc(&d, after);
    try expectRegister(&regs, '"', yanked);
}

test "verbs: delete removes the selections and yanks them" {
    try expectDelete("a«bc»d\n", "a«d»\n", &.{"bc"});
    try expectDelete("«a»b‹c›d\n", "«b»‹d›\n", &.{ "a", "c" });
    try expectDelete("«ab\n»cd\n", "«c»d\n", &.{"ab\n"});
    try expectDelete("«a»‹b›c\n", "«c»\n", &.{ "a", "b" }); // the cursors meet and merge
}

test "verbs: delete never removes the final newline" {
    try expectDelete("a«b\n»", "a«\n»", &.{"b\n"});
    try expectDelete("«ab\ncd\n»", "«\n»", &.{"ab\ncd\n"});
    try expectDelete("ab«\n»", "ab«\n»", &.{"\n"});
}

test "verbs: deleting whole last lines takes the newline before them instead" {
    try expectDelete("a\n«b\n»", "a«\n»", &.{"b\n"});
    try expectDelete("a\n«b\nc\n»", "a«\n»", &.{"b\nc\n"});
    try expectDelete("a\n«\n»", "a«\n»", &.{"\n"}); // an empty last line
    try expectDelete("ab\n«c\n»", "ab«\n»", &.{"c\n"});
    // Not from a line start: the line keeps its newline.
    try expectDelete("a\nb«c\n»", "a\nb«\n»", &.{"c\n"});
}

test "verbs: the newline before the last line is not taken twice" {
    // The first selection already removes it.
    try expectDelete("«a\n»‹b\n›", "«\n»", &.{ "a\n", "b\n" });
    try expectDelete("a«b\n»‹c\n›", "a«\n»", &.{ "b\n", "c\n" });
    // Another selection before it, elsewhere, does not stop it.
    try expectDelete("«a»b\n‹c\n›", "«b»‹\n›", &.{ "a", "c\n" });
}

test "verbs: whole last lines in several selections take the newline before them all" {
    try expectDelete("a\n«b\n»‹c\n›", "a«\n»", &.{ "b\n", "c\n" });
    try expectDelete("a\n«b\n»‹c\n›‹d\n›", "a«\n»", &.{ "b\n", "c\n", "d\n" });
    // An empty last line after them.
    try expectDelete("a\n«b\n»‹\n›", "a«\n»", &.{ "b\n", "\n" });
    // A gap between them: only the last run takes the newline before it.
    try expectDelete("«a\n»b\n‹c\n›", "«b»‹\n›", &.{ "a\n", "c\n" });
}

test "verbs: the last lines deleted one selection each, or as one, leave the same" {
    // Lines of different lengths, an empty one among them.
    const text = "one\n\nthree\nfour\nx\n";
    const starts = [_]usize{ 0, 4, 5, 11, 16 };
    for (1..starts.len + 1) |k| {
        const from = starts.len - k;
        var whole: Document = try .init(gpa, text);
        defer whole.deinit();
        try whole.select(&.{.span(starts[from], text.len - 1)}, 0);
        try verbs.delete(&whole, null, '"');
        var split: Document = try .init(gpa, text);
        defer split.deinit();
        var sels: [starts.len]@import("selection.zig").Selection = undefined;
        for (sels[0..k], starts[from..], from..) |*sel, start, i| {
            const end = if (i + 1 < starts.len) starts[i + 1] else text.len;
            sel.* = .span(start, end - 1);
        }
        try split.select(sels[0..k], 0);
        try verbs.delete(&split, null, '"');
        try std.testing.expectEqualStrings(whole.text(), split.text());
        try expectEqual(1, split.sels().len);
        try expectEqual(whole.primary(), split.primary());
    }
}

test "verbs: deleting to change several last lines keeps one empty line" {
    var d = try fx.doc("a\n«b\n»‹c\n›");
    defer d.deinit();
    try verbs.deleteToChange(&d, null, '"');
    try fx.expectDoc(&d, "a\n«\n»");
}

test "verbs: deleting to change keeps the last line to type into" {
    var d = try fx.doc("a\n«b\n»");
    defer d.deinit();
    try verbs.deleteToChange(&d, null, '"');
    try fx.expectDoc(&d, "a\n«\n»");
}

test "verbs: deleting the last line undoes to the text before" {
    var d = try fx.doc("a\n«b\n»");
    defer d.deinit();
    try verbs.delete(&d, null, '"');
    try fx.expectDoc(&d, "a«\n»");
    try expect(try d.undo());
    try fx.expectDoc(&d, "a\n«b\n»");
}

test "verbs: delete without registers leaves them alone, and undoes" {
    var d = try fx.doc("a«bc»d\n");
    defer d.deinit();
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    try regs.set('"', &.{"x"});
    try verbs.delete(&d, null, '"');
    try fx.expectDoc(&d, "a«d»\n");
    try expectRegister(&regs, '"', &.{"x"});
    try expect(try d.undo());
    try fx.expectDoc(&d, "a«bc»d\n");
}

/// Sets `"` to `values`, pastes on `before` and checks the result.
/// Sets `"` to `values`, replaces on `before` and checks the result.
fn expectReplace(values: []const []const u8, before: []const u8, ok: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    try regs.set('"', values);
    try expectEqual(ok, try verbs.replace(&d, &regs, '"'));
    try fx.expectDoc(&d, after);
}

test "verbs: R replaces the selections with the register" {
    try expectReplace(&.{"Z"}, "a«bc»d\n", true, "a«Z»d\n");
    try expectReplace(&.{"Z"}, "«ab\n»", true, "«Z»\n");
    try expectReplace(&.{""}, "a«b»c\n", true, "a«c»\n");
    try expectReplace(&.{ "1", "2" }, "«a» ‹b›\n", true, "«1» ‹2›\n");
    try expectReplace(&.{}, "«a»\n", false, "«a»\n");
}

test "verbs: R over the last line with a whole line adds no empty line" {
    try expectReplace(&.{"x\n"}, "a\n«b\n»", true, "a\n«x\n»");
    try expectReplace(&.{ "1\n", "2\n" }, "«a\n»‹b\n›", true, "«1\n»‹2\n›");
    // A value without a newline keeps the final one.
    try expectReplace(&.{"x"}, "a\n«b\n»", true, "a\n«x»\n");
}

fn expectReplaceChar(before: []const u8, cp: u21, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try verbs.replaceChar(&d, cp);
    try fx.expectDoc(&d, after);
}

test "verbs: r replaces every character but newlines" {
    try expectReplaceChar("a«bc»d\n", 'x', "a«xx»d\n");
    try expectReplaceChar("«ab\ncd»\n", '-', "«--\n--»\n");
    try expectReplaceChar("«中a»\n", 'x', "«xx»\n");
    try expectReplaceChar("«ab»\n", 0x4e2d, "«中中»\n");
    try expectReplaceChar("«|ab» ‹c›\n", 'x', "«|xx» ‹x›\n");
    try expectReplaceChar("«a\n»", 'x', "«x\n»");
    try expectReplaceChar("«e\u{301}»\n", 'x', "«x»\n"); // a mark is part of its character
}

fn expectCase(before: []const u8, case: verbs.Case, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try verbs.changeCase(&d, case);
    try fx.expectDoc(&d, after);
}

test "verbs: case changes are ASCII only" {
    try expectCase("«aB1é»\n", .upper, "«AB1é»\n");
    try expectCase("«aB»Z\n", .lower, "«ab»Z\n");
    try expectCase("«aB»c ‹D›\n", .swap, "«Ab»c ‹d›\n");
}

test "verbs: an unchanged case records nothing" {
    var d = try fx.doc("«AB»\n");
    defer d.deinit();
    try verbs.changeCase(&d, .upper);
    try expect(!d.isModified());
}

fn expectIndent(before: []const u8, in: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    if (in) try verbs.indent(&d, 4) else try verbs.dedent(&d, 4);
    try fx.expectDoc(&d, after);
}

test "verbs: > indents every selected line once, skipping empty ones" {
    try expectIndent("«a»b\ncd\n", true, "    «a»b\ncd\n");
    try expectIndent("«ab\ncd»\n", true, "    «ab\n    cd»\n");
    try expectIndent("«a\n\nb»\n", true, "    «a\n\n    b»\n");
    try expectIndent("«a» ‹b›\n", true, "    «a» ‹b›\n");
    try expectIndent("«a»\n‹b›\n", true, "    «a»\n    ‹b›\n");
}

test "verbs: < removes one tab or up to a width of spaces" {
    try expectIndent("    «a»b\n", false, "«a»b\n");
    try expectIndent("  «a»\n", false, "«a»\n");
    try expectIndent("\t\t«a»\n", false, "\t«a»\n");
    try expectIndent("      «a»\n", false, "  «a»\n");
    try expectIndent("« »  x\n", false, "«x»\n");
    try expectIndent("«a»\n", false, "«a»\n");
    try expectIndent(" \t«a»\n", false, "\t«a»\n");
}

fn expectJoin(before: []const u8, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try verbs.join(&d);
    try fx.expectDoc(&d, after);
}

test "verbs: Alt-j joins lines with one space" {
    try expectJoin("«a»b\n  cd\nef\n", "«a»b cd\nef\n");
    try expectJoin("«ab\ncd\ne»f\ng\n", "«ab cd e»f\ng\n");
    try expectJoin("«a»\n\nb\n", "«a»\nb\n");
    try expectJoin("a\n«b»\n", "a\n«b»\n");
    try expectJoin("«a»\n‹b›\nc\nd\n", "«a» ‹b› c\nd\n");
}

test "verbs: edits are atomic when allocation fails" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d: Document = try .init(a, "ab\ncd\n");
            defer d.deinit();
            try d.select(&.{ .at(0), .at(3) }, 0);
            var regs: Registers = .init(a);
            defer regs.deinit();
            try regs.set('"', &.{ "1", "2" });
            const text_before = try a.dupe(u8, d.text());
            defer a.free(text_before);
            verbs.indent(&d, 2) catch |e| {
                try std.testing.expectEqualStrings(text_before, d.text());
                return e;
            };
            _ = verbs.paste(&d, &regs, '"', false) catch |e| {
                try std.testing.expectEqualStrings("  ab\n  cd\n", d.text());
                return e;
            };
            try std.testing.expectEqualStrings("  a1b\n  c2d\n", d.text());
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

fn expectRotate(before: []const u8, delta: isize, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    try verbs.rotateContents(&d, delta);
    try fx.expectDoc(&d, after);
}

test "verbs: Alt-) and Alt-( rotate the selections' contents" {
    try expectRotate("«a» ‹bc› ‹d›\n", 1, "«d» ‹a› ‹bc›\n");
    try expectRotate("«a» ‹bc› ‹d›\n", -1, "«bc» ‹d› ‹a›\n");
    try expectRotate("«a» ‹bc› ‹d›\n", 2, "«bc» ‹d› ‹a›\n");
    // Counts past the number of selections wrap, both ways.
    try expectRotate("«a» ‹bc› ‹d›\n", -4, "«bc» ‹d› ‹a›\n");
    try expectRotate("«a» ‹bc› ‹d›\n", 5, "«bc» ‹d› ‹a›\n");
    // The main selection keeps its place, not its text.
    try expectRotate("‹a› «b»\n", 1, "‹b› «a»\n");
}

test "verbs: rotating whole lines keeps one final newline" {
    try expectRotate("«a\n»‹b\n›", 1, "«b\n»‹a\n›");
    // The last line's newline stays when a value without one comes.
    try expectRotate("«a»\n‹b\n›", 1, "«b\n»\n‹a›\n");
}

test "verbs: rotating multi-byte text selects whole characters" {
    try expectRotate("«ä» ‹日本›\n", 1, "«日本» ‹ä›\n");
    try expectRotate("«e\u{301}» ‹x›\n", -1, "«x» ‹e\u{301}›\n");
    // The cursor is on the start of the last character, not inside it.
    var d = try fx.doc("«ä» ‹日本›\n");
    defer d.deinit();
    try verbs.rotateContents(&d, 1);
    try expectEqual(3, d.sels()[0].cursor);
    try expectEqual(7, d.sels()[1].cursor);
}

test "verbs: a rotation that moves nothing changes nothing" {
    var d = try fx.doc("«ab»\n");
    defer d.deinit();
    try verbs.rotateContents(&d, 1);
    try fx.expectDoc(&d, "«ab»\n");
    try expect(!d.isModified());
    var e = try fx.doc("«a» ‹b›\n");
    defer e.deinit();
    try verbs.rotateContents(&e, -4);
    try fx.expectDoc(&e, "«a» ‹b›\n");
    try expect(!e.isModified());
}

test "verbs: one undo puts every rotated selection back" {
    var d = try fx.doc("«a» ‹b› ‹c›\n");
    defer d.deinit();
    try verbs.rotateContents(&d, 1);
    try expect(try d.undo());
    try fx.expectDoc(&d, "«a» ‹b› ‹c›\n");
}

test "verbs: a rotation that cannot allocate leaves the document as it was" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var d = try Document.init(a, "a b\n");
            defer d.deinit();
            try d.select(&.{ .at(0), .at(2) }, 0);
            verbs.rotateContents(&d, 1) catch |e| {
                try std.testing.expectEqualStrings("a b\n", d.text());
                try expect(!d.isModified());
                return e;
            };
            try std.testing.expectEqualStrings("b a\n", d.text());
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

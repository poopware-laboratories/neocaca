//! Tests for `verbs.zig`, in the marked notation of `fixture_test.zig`.

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
fn expectPaste(values: []const []const u8, before_sel: bool, before: []const u8, ok: bool, after: []const u8) !void {
    var d = try fx.doc(before);
    defer d.deinit();
    var regs: Registers = .init(gpa);
    defer regs.deinit();
    try regs.set('"', values);
    try expectEqual(ok, try verbs.paste(&d, &regs, '"', before_sel));
    try fx.expectDoc(&d, after);
}

test "verbs: paste after and before, selecting the pasted text" {
    try expectPaste(&.{"XY"}, false, "«a»b\n", true, "a«XY»b\n");
    try expectPaste(&.{"XY"}, true, "a«b»\n", true, "a«XY»b\n");
    try expectPaste(&.{"x"}, false, "ab«\n»", true, "ab«x»\n"); // stays before the final newline
    try expectPaste(&.{"中"}, false, "«a»\n", true, "a«中»\n");
}

test "verbs: values ending in a newline paste as whole lines" {
    try expectPaste(&.{"L\n"}, false, "a«b»\ncd\n", true, "ab\n«L\n»cd\n");
    try expectPaste(&.{"L\n"}, true, "ab\nc«d»\n", true, "ab\n«L\n»cd\n");
    try expectPaste(&.{"L\n"}, false, "«a»\n", true, "a\n«L\n»");
    try expectPaste(&.{"L\n"}, false, "«a» ‹b›\n", true, "a b\n«L\n»‹L\n›");
}

test "verbs: paste pairs values with selections" {
    try expectPaste(&.{ "1", "2" }, false, "«a» ‹b›\n", true, "a«1» b‹2›\n");
    try expectPaste(&.{"x"}, true, "«a»‹b›\n", true, "«x»a‹x›b\n");
    try expectPaste(&.{ "1", "2", "3" }, false, "‹a› «b»\n", true, "a‹1› b«2»\n");
    try expectPaste(&.{ "1", "2" }, false, "«a» ‹b› ‹c›\n", true, "a«1» b‹2› c‹2›\n");
}

test "verbs: paste from an empty register does nothing" {
    try expectPaste(&.{}, false, "«a»\n", false, "«a»\n");
    try expectPaste(&.{""}, false, "«a»\n", true, "«a»\n");
}

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

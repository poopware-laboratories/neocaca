//! Tests for the verbs of `keymap.zig` (`d c y p P R r`, case, indent,
//! join, undo, entering insert mode) and the registers they use, in the
//! key notation of `keymap_test.zig`.

const std = @import("std");
const keymap_test = @import("keymap_test.zig");
const Keymap = @import("keymap.zig").Keymap;
const Action = @import("action.zig").Action;

const expectNormal = keymap_test.expectNormal;

test "keymap: delete, change and yank use the register" {
    try expectNormal("d", .{ .delete = .{} });
    try expectNormal("<a-d>", .{ .delete = .{ .yank = false } });
    try expectNormal("c", .{ .delete = .{ .change = true } });
    try expectNormal("<a-c>", .{ .delete = .{ .yank = false, .change = true } });
    try expectNormal("\"ad", .{ .delete = .{ .reg = 'a' } });
    try expectNormal("\"zc", .{ .delete = .{ .reg = 'z', .change = true } });
    try expectNormal("y", .{ .yank = '"' });
    try expectNormal("\"by", .{ .yank = 'b' });
}

test "keymap: paste and replace use the register" {
    try expectNormal("p", .{ .paste = .{ .before = false } });
    try expectNormal("P", .{ .paste = .{ .before = true } });
    try expectNormal("\"qp", .{ .paste = .{ .reg = 'q', .before = false } });
    try expectNormal("R", .{ .replace = '"' });
    try expectNormal("\"xR", .{ .replace = 'x' });
}

test "keymap: a register that is no ASCII character is refused" {
    try expectNormal("\"中", null);
    try expectNormal("\"<up>", null);
    var map: Keymap = .{};
    _ = map.normal(.char('"'));
    _ = map.normal(.char(0x4e2d));
    try std.testing.expectEqualDeep(Action{ .yank = '"' }, map.normal(.char('y')).?);
}

test "keymap: a count and a register combine in either order" {
    var map: Keymap = .{};
    _ = map.normal(.char('2'));
    _ = map.normal(.char('"'));
    _ = map.normal(.char('a'));
    try std.testing.expectEqualDeep(Action{ .paste = .{ .reg = 'a', .before = false } }, map.normal(.char('p')).?);
    try std.testing.expectEqualDeep(Action{ .yank = '"' }, map.normal(.char('y')).?);
}

test "keymap: r takes the replacement character" {
    try expectNormal("rx", .{ .replace_char = 'x' });
    try expectNormal("r中", .{ .replace_char = '中' });
    try expectNormal("r<tab>", .{ .replace_char = '\t' });
    try expectNormal("r<up>", null);
}

test "keymap: the other verbs" {
    try expectNormal("~", .{ .case = .upper });
    try expectNormal("`", .{ .case = .lower });
    try expectNormal("<a-`>", .{ .case = .swap });
    try expectNormal(">", .indent);
    try expectNormal("<lt>", .dedent);
    try expectNormal("<a-j>", .join);
    try expectNormal("u", .undo);
    try expectNormal("U", .redo);
}

test "keymap: entering insert mode" {
    try expectNormal("i", .{ .insert = .before });
    try expectNormal("a", .{ .insert = .after });
    try expectNormal("I", .{ .insert = .line_start });
    try expectNormal("A", .{ .insert = .line_end });
    try expectNormal("o", .{ .insert = .below });
    try expectNormal("O", .{ .insert = .above });
}

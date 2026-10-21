//! Tests for `keymap.zig`, one per row group of `docs/keys.md`. Keys are
//! written as text, with `<a-x>` for Alt, `<c-x>` for Control, `<s-left>`
//! for Shift with an arrow, `<lt>` for `<`, and `<esc>`, `<ret>`, `<tab>`,
//! `<bs>`, `<del>`, `<up>`, `<down>`, `<left>`, `<right>`, `<pgup>`,
//! `<pgdn>`, `<home>`, `<end>` for the named keys.

const std = @import("std");
const keymap = @import("keymap.zig");
const key_mod = @import("key.zig");
const action = @import("action.zig");

const Keymap = keymap.Keymap;
const Key = key_mod.Key;
const Code = key_mod.Code;
const Action = action.Action;

fn named(name: []const u8) ?Code {
    const table = [_]struct { []const u8, Code }{
        .{ "esc", .escape },   .{ "ret", .enter },          .{ "tab", .tab },
        .{ "bs", .backspace }, .{ "del", .delete },         .{ "up", .up },
        .{ "down", .down },    .{ "left", .left },          .{ "right", .right },
        .{ "pgup", .page_up }, .{ "pgdn", .page_down },     .{ "home", .home },
        .{ "end", .end },      .{ "lt", .{ .char = '<' } },
    };
    for (table) |e| if (std.mem.eql(u8, e[0], name)) return e[1];
    return null;
}

/// The keys `text` names; at most 32.
fn keys(text: []const u8, out: *[32]Key) []Key {
    var n: usize = 0;
    var i: usize = 0;
    while (i < text.len) : (n += 1) {
        const close = if (text[i] == '<') std.mem.indexOfScalarPos(u8, text, i, '>') else null;
        if (close) |end| {
            var name = text[i + 1 .. end];
            var k: Key = .{ .code = .escape };
            if (name.len > 2 and name[1] == '-') {
                switch (name[0]) {
                    'a' => k.mods.alt = true,
                    'c' => k.mods.ctrl = true,
                    's' => k.mods.shift = true,
                    else => unreachable,
                }
                name = name[2..];
            }
            k.code = named(name) orelse .{ .char = std.unicode.utf8Decode(name) catch unreachable };
            out[n] = k;
            i = end + 1;
        } else {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch unreachable;
            out[n] = .char(std.unicode.utf8Decode(text[i..][0..len]) catch unreachable);
            i += len;
        }
    }
    return out[0..n];
}

/// Feeds `text` in normal mode: every key but the last is a prefix that
/// gives nothing, and the last gives `want` (null: nothing at all).
fn expectNormal(text: []const u8, want: ?Action) !void {
    var buf: [32]Key = undefined;
    const list = keys(text, &buf);
    var map: Keymap = .{};
    for (list[0 .. list.len - 1]) |k| {
        if (map.normal(k)) |got| {
            std.debug.print("{s}: a prefix gave {any}\n", .{ text, got });
            return error.TestUnexpectedAction;
        }
    }
    const got = map.normal(list[list.len - 1]);
    std.testing.expect(std.meta.eql(want, got)) catch |e| {
        std.debug.print("{s}: got {any}, wanted {any}\n", .{ text, got, want });
        return e;
    };
    try std.testing.expect(!map.isPending());
}

fn move(m: action.Motion, count: usize, extend: bool) Action {
    return .{ .move = .{ .motion = m, .count = count, .extend = extend } };
}

test "keymap: hjkl and the arrows move, and their Shift forms extend" {
    try expectNormal("h", move(.left, 1, false));
    try expectNormal("j", move(.down, 1, false));
    try expectNormal("k", move(.up, 1, false));
    try expectNormal("l", move(.right, 1, false));
    try expectNormal("H", move(.left, 1, true));
    try expectNormal("J", move(.down, 1, true));
    try expectNormal("K", move(.up, 1, true));
    try expectNormal("L", move(.right, 1, true));
    try expectNormal("<left>", move(.left, 1, false));
    try expectNormal("<down>", move(.down, 1, false));
    try expectNormal("<s-up>", move(.up, 1, true));
    try expectNormal("<s-right>", move(.right, 1, true));
}

test "keymap: word moves over words and WORDs" {
    try expectNormal("w", move(.{ .word_start = false }, 1, false));
    try expectNormal("W", move(.{ .word_start = false }, 1, true));
    try expectNormal("e", move(.{ .word_end = false }, 1, false));
    try expectNormal("E", move(.{ .word_end = false }, 1, true));
    try expectNormal("b", move(.{ .word_back = false }, 1, false));
    try expectNormal("B", move(.{ .word_back = false }, 1, true));
    try expectNormal("<a-w>", move(.{ .word_start = true }, 1, false));
    try expectNormal("<a-W>", move(.{ .word_start = true }, 1, true));
    try expectNormal("<a-e>", move(.{ .word_end = true }, 1, false));
    try expectNormal("<a-E>", move(.{ .word_end = true }, 1, true));
    try expectNormal("<a-b>", move(.{ .word_back = true }, 1, false));
    try expectNormal("<a-B>", move(.{ .word_back = true }, 1, true));
}

test "keymap: counts apply to the next move and then reset" {
    try expectNormal("3w", move(.{ .word_start = false }, 3, false));
    try expectNormal("12J", move(.down, 12, true));
    try expectNormal("0l", move(.right, 1, false));
    var map: Keymap = .{};
    _ = map.normal(.char('5'));
    try std.testing.expect(map.isPending());
    _ = map.normal(.char('j'));
    try std.testing.expectEqualDeep(move(.down, 1, false), map.normal(.char('j')).?);
}

test "keymap: a huge count is capped" {
    try expectNormal("99999999999999999999j", move(.down, keymap.max_count, false));
}

test "keymap: Escape cancels a count, a register and a prefix" {
    try expectNormal("5<esc>", null);
    try expectNormal("\"a<esc>", null);
    try expectNormal("g<esc>", null);
    try expectNormal("f<esc>", null);
    try expectNormal("<a-i><esc>", null);
    var map: Keymap = .{};
    _ = map.normal(.char('7'));
    _ = map.normal(.{ .code = .escape });
    try std.testing.expectEqualDeep(move(.down, 1, false), map.normal(.char('j')).?);
}

test "keymap: x and X select lines, % the buffer" {
    try expectNormal("x", .{ .select_lines = .{} });
    try expectNormal("2x", .{ .select_lines = .{ .count = 2 } });
    try expectNormal("X", .{ .select_lines = .{ .every_line = true } });
    try expectNormal("%", .select_all);
}

fn find(needle: u21, till: bool, backward: bool, extend: bool) Action {
    return move(.{ .find = .{ .needle = needle, .till = till, .backward = backward } }, 1, extend);
}

test "keymap: f t and their backward forms take the next key" {
    try expectNormal("fx", find('x', false, false, false));
    try expectNormal("Fx", find('x', false, false, true));
    try expectNormal("tx", find('x', true, false, false));
    try expectNormal("Tx", find('x', true, false, true));
    try expectNormal("<a-f>x", find('x', false, true, false));
    try expectNormal("<a-F>x", find('x', false, true, true));
    try expectNormal("<a-t>x", find('x', true, true, false));
    try expectNormal("<a-T>x", find('x', true, true, true));
    try expectNormal("f中", find('中', false, false, false));
    try expectNormal("f<tab>", find('\t', false, false, false));
    try expectNormal("f<ret>", find('\n', false, false, false));
    try expectNormal("2fa", move(.{ .find = .{ .needle = 'a', .till = false, .backward = false } }, 2, false));
}

test "keymap: a find with a key that is no character does nothing" {
    try expectNormal("f<up>", null);
    try expectNormal("f<a-x>", null);
}

test "keymap: m and M select to the matching bracket" {
    try expectNormal("m", move(.matching, 1, false));
    try expectNormal("M", move(.matching, 1, true));
}

test "keymap: g goes to places, G extends there" {
    try expectNormal("gh", move(.line_start, 1, false));
    try expectNormal("gl", move(.line_end, 1, false));
    try expectNormal("gi", move(.first_non_blank, 1, false));
    try expectNormal("gg", move(.buffer_start, 1, false));
    try expectNormal("gk", move(.buffer_start, 1, false));
    try expectNormal("ge", move(.buffer_end, 1, false));
    try expectNormal("gj", move(.buffer_end, 1, false));
    try expectNormal("Gh", move(.line_start, 1, true));
    try expectNormal("Gl", move(.line_end, 1, true));
    try expectNormal("Gg", move(.buffer_start, 1, true));
    try expectNormal("Ge", move(.buffer_end, 1, true));
    try expectNormal("<home>", move(.line_start, 1, false));
    try expectNormal("<end>", move(.line_end, 1, false));
}

test "keymap: an unknown key after g does nothing" {
    try expectNormal("gz", null);
    try expectNormal("G<up>", null);
}

test "keymap: a count before g goes to that line" {
    try expectNormal("42g", move(.{ .line = 42 }, 1, false));
    try expectNormal("7G", move(.{ .line = 7 }, 1, true));
}

test "keymap: scrolling by pages" {
    try expectNormal("<c-d>", .{ .scroll = .half_down });
    try expectNormal("<c-u>", .{ .scroll = .half_up });
    try expectNormal("<c-f>", .{ .scroll = .page_down });
    try expectNormal("<c-b>", .{ .scroll = .page_up });
    try expectNormal("<pgdn>", .{ .scroll = .page_down });
    try expectNormal("<pgup>", .{ .scroll = .page_up });
}

test "keymap: shaping the selections" {
    try expectNormal(";", .reduce);
    try expectNormal("<a-;>", .flip);
    try expectNormal("<a-:>", .forward);
    try expectNormal(",", .keep_main);
    try expectNormal("<a-,>", .drop_main);
    try expectNormal("C", .{ .copy_to_line = .{ .down = true } });
    try expectNormal("3C", .{ .copy_to_line = .{ .down = true, .count = 3 } });
    try expectNormal("<a-C>", .{ .copy_to_line = .{ .down = false } });
    try expectNormal("(", .{ .rotate_main = -1 });
    try expectNormal(")", .{ .rotate_main = 1 });
    try expectNormal("2)", .{ .rotate_main = 2 });
    try expectNormal("<a-s>", .split_lines);
}

test "keymap: prompts" {
    try expectNormal(":", .{ .prompt = .command });
    try expectNormal("s", .{ .prompt = .select });
    try expectNormal("S", .{ .prompt = .split });
    try expectNormal("<a-k>", .{ .prompt = .keep });
    try expectNormal("<a-K>", .{ .prompt = .drop });
    try expectNormal("/", .{ .prompt = .search_forward });
    try expectNormal("?", .{ .prompt = .search_backward });
}

test "keymap: objects after Alt-i and Alt-a" {
    try expectNormal("<a-i>w", .{ .select_object = .{ .kind = .word, .inner = true } });
    try expectNormal("<a-a>(", .{ .select_object = .{ .kind = .paren, .inner = false } });
    try expectNormal("<a-i>b", .{ .select_object = .{ .kind = .paren, .inner = true } });
    try expectNormal("<a-a>B", .{ .select_object = .{ .kind = .brace, .inner = false } });
    try expectNormal("<a-i>\"", .{ .select_object = .{ .kind = .double_quote, .inner = true } });
    try expectNormal("<a-i><lt>", .{ .select_object = .{ .kind = .angle, .inner = true } });
    try expectNormal("<a-a>p", .{ .select_object = .{ .kind = .paragraph, .inner = false } });
    try expectNormal("<a-i>z", null);
}

test "keymap: search keys" {
    try expectNormal("n", .{ .search_next = .{ .dir = .forward } });
    try expectNormal("N", .{ .search_next = .{ .dir = .forward, .add = true } });
    try expectNormal("<a-n>", .{ .search_next = .{ .dir = .backward } });
    try expectNormal("*", .search_selection);
}

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

test "keymap: unbound keys do nothing and clear the count" {
    try expectNormal("Z", null);
    try expectNormal("<c-z>", null);
    try expectNormal("<a-Z>", null);
    try expectNormal("<del>", null);
    var map: Keymap = .{};
    _ = map.normal(.char('4'));
    try std.testing.expectEqual(null, map.normal(.char('Z')));
    try std.testing.expectEqualDeep(move(.down, 1, false), map.normal(.char('j')).?);
}

test "keymap: the pending keys are shown while a command is incomplete" {
    var map: Keymap = .{};
    var buf: [keymap.max_pending_text]u8 = undefined;
    try std.testing.expectEqualStrings("", map.pendingText(&buf));
    _ = map.normal(.char('1'));
    _ = map.normal(.char('2'));
    try std.testing.expectEqualStrings("12", map.pendingText(&buf));
    _ = map.normal(.char('"'));
    try std.testing.expectEqualStrings("12\"", map.pendingText(&buf));
    _ = map.normal(.char('a'));
    try std.testing.expectEqualStrings("12\"a", map.pendingText(&buf));
    _ = map.normal(.char('F'));
    try std.testing.expectEqualStrings("12\"aF", map.pendingText(&buf));
    _ = map.normal(.{ .code = .escape });
    try std.testing.expectEqualStrings("", map.pendingText(&buf));
}

test "keymap: the longest pending text fits" {
    var map: Keymap = .{};
    var buf: [keymap.max_pending_text]u8 = undefined;
    for ("9999999999\"z") |c| _ = map.normal(.char(c));
    _ = map.normal(.alt('T'));
    try std.testing.expectEqualStrings("1000000\"z<a-T>", map.pendingText(&buf));
}

fn expectInsert(text: []const u8, want: ?Action) !void {
    var buf: [32]Key = undefined;
    const list = keys(text, &buf);
    try std.testing.expectEqual(1, list.len);
    const got = keymap.insertKey(list[0]);
    std.testing.expect(std.meta.eql(want, got)) catch |e| {
        std.debug.print("{s}: got {any}, wanted {any}\n", .{ text, got, want });
        return e;
    };
}

test "keymap: insert mode types characters" {
    try expectInsert("a", .{ .text = 'a' });
    try expectInsert("J", .{ .text = 'J' });
    try expectInsert("中", .{ .text = '中' });
    try expectInsert("<tab>", .{ .text = '\t' });
    try expectInsert("<ret>", .newline);
    try expectInsert("<bs>", .backspace);
    try expectInsert("<del>", .delete_forward);
    try expectInsert("<esc>", .leave_insert);
}

test "keymap: insert mode moves with the arrows" {
    try expectInsert("<left>", move(.left, 1, false));
    try expectInsert("<right>", move(.right, 1, false));
    try expectInsert("<up>", move(.up, 1, false));
    try expectInsert("<down>", move(.down, 1, false));
    try expectInsert("<home>", move(.line_start, 1, false));
    try expectInsert("<end>", move(.line_end, 1, false));
}

test "keymap: insert mode ignores Control and Alt chords" {
    try expectInsert("<c-x>", null);
    try expectInsert("<a-x>", null);
    try expectInsert("<pgup>", null);
}

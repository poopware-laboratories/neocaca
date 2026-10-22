//! Tests for `editor.zig`: keys in, document, mode, messages and requests
//! out. Keys are typed as text: every character is that key, Escape is
//! `\x1b`, Enter `\r` and Backspace `\x7f`.

const std = @import("std");
const input = @import("../input.zig");
const editor_mod = @import("editor.zig");

const Editor = editor_mod.Editor;
const Key = input.Key;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn keyOf(cp: u21) Key {
    return switch (cp) {
        0x1b => .{ .code = .escape },
        '\r' => .{ .code = .enter },
        0x7f => .{ .code = .backspace },
        else => .char(cp),
    };
}

fn typeKeys(ed: *Editor, keys: []const u8) !void {
    const view = try std.unicode.Utf8View.init(keys);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| try ed.key(keyOf(cp));
}

fn expectText(ed: *const Editor, want: []const u8) !void {
    try expectEqualStrings(want, ed.doc.text());
}

/// The main selection, as anchor and cursor offsets.
fn expectMain(ed: *const Editor, anchor: usize, cursor: usize) !void {
    const s = ed.doc.primary();
    try expectEqual(anchor, s.anchor);
    try expectEqual(cursor, s.cursor);
}

fn expectMessage(ed: *const Editor, text: []const u8, is_error: bool) !void {
    try expectEqualStrings(text, ed.message.text());
    try expectEqual(is_error, ed.message.is_error);
}

test "editor: starts in normal mode on the first character" {
    var ed: Editor = try .init(gpa, "a.txt", "hello\n");
    defer ed.deinit();
    try expectEqual(.normal, ed.mode);
    try expectMain(&ed, 0, 0);
    try expectEqualStrings("a.txt", ed.path.?);
    try expect(!ed.quit);
}

test "editor: selection first, then the verb" {
    var ed: Editor = try .init(gpa, null, "one two three\n");
    defer ed.deinit();
    try typeKeys(&ed, "wwd");
    try expectText(&ed, "one three\n");
    try expectEqualStrings("two ", ed.regs.get('"')[0]);
}

test "editor: counts and registers reach the verbs" {
    var ed: Editor = try .init(gpa, null, "a b c d\n");
    defer ed.deinit();
    try typeKeys(&ed, "2w\"ay");
    try expectEqualStrings("b ", ed.regs.get('a')[0]);
    try expectEqual(0, ed.regs.get('"').len);
}

test "editor: insert mode types at every cursor and Escape leaves it" {
    var ed: Editor = try .init(gpa, null, "ab\ncd\n");
    defer ed.deinit();
    try typeKeys(&ed, "C");
    try expectEqual(2, ed.doc.sels().len);
    try typeKeys(&ed, "i-");
    try expectEqual(.insert, ed.mode);
    try typeKeys(&ed, "\x1b");
    try expectEqual(.normal, ed.mode);
    try expectText(&ed, "-ab\n-cd\n");
}

test "editor: an insert session undoes as one step" {
    var ed: Editor = try .init(gpa, null, "x\n");
    defer ed.deinit();
    try typeKeys(&ed, "ohello\rworld\x1b");
    try expectText(&ed, "x\nhello\nworld\n");
    try typeKeys(&ed, "u");
    try expectText(&ed, "x\n");
    try typeKeys(&ed, "U");
    try expectText(&ed, "x\nhello\nworld\n");
}

test "editor: d on the last line removes it, c replaces it" {
    var ed: Editor = try .init(gpa, null, "a\nb\n");
    defer ed.deinit();
    try typeKeys(&ed, "jxd");
    try expectText(&ed, "a\n");
    try typeKeys(&ed, "u");
    try expectText(&ed, "a\nb\n");
    try typeKeys(&ed, "jxcz\x1b");
    try expectText(&ed, "a\nz\n");
}

test "editor: change deletes, then inserts, as one undo step" {
    var ed: Editor = try .init(gpa, null, "one two\n");
    defer ed.deinit();
    try typeKeys(&ed, "wwcTWO\x1b");
    try expectText(&ed, "one TWO\n");
    try expectEqualStrings("two", ed.regs.get('"')[0]);
    try typeKeys(&ed, "u");
    try expectText(&ed, "one two\n");
}

test "editor: insert mode Backspace, Delete and arrows" {
    var ed: Editor = try .init(gpa, null, "abc\n");
    defer ed.deinit();
    try typeKeys(&ed, "A");
    try ed.key(.{ .code = .backspace });
    try ed.key(.{ .code = .left });
    try ed.key(.{ .code = .delete });
    try typeKeys(&ed, "\x1b");
    try expectText(&ed, "a\n");
}

test "editor: undo with nothing to undo says so" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "u");
    try expectMessage(&ed, "nothing to undo", false);
    try typeKeys(&ed, "U");
    try expectMessage(&ed, "nothing to redo", false);
}

test "editor: a message lasts until the next key" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "u");
    try expect(ed.message.text().len > 0);
    try typeKeys(&ed, "l");
    try expectEqualStrings("", ed.message.text());
}

test "editor: pasting from an empty register says so" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "\"zp");
    try expectMessage(&ed, "register z is empty", true);
    try typeKeys(&ed, "\"zR");
    try expectMessage(&ed, "register z is empty", true);
    try expectText(&ed, "a\n");
}

test "editor: yank and paste" {
    var ed: Editor = try .init(gpa, null, "ab\n");
    defer ed.deinit();
    try typeKeys(&ed, "ypP");
    try expectText(&ed, "aaab\n");
}

test "editor: the other verbs" {
    var ed: Editor = try .init(gpa, null, "ab\ncd\n");
    defer ed.deinit();
    try typeKeys(&ed, "%~");
    try expectText(&ed, "AB\nCD\n");
    try typeKeys(&ed, "`");
    try expectText(&ed, "ab\ncd\n");
    try typeKeys(&ed, ">");
    try expectText(&ed, "    ab\n    cd\n");
    try typeKeys(&ed, "<");
    try expectText(&ed, "ab\ncd\n");
    try typeKeys(&ed, "rx");
    try expectText(&ed, "xx\nxx\n");
    try typeKeys(&ed, "gg");
    try ed.key(.alt('j'));
    try expectText(&ed, "xx xx\n");
}

test "editor: selections are shaped and reduced" {
    var ed: Editor = try .init(gpa, null, "a\nb\nc\n");
    defer ed.deinit();
    try typeKeys(&ed, "CC");
    try expectEqual(3, ed.doc.sels().len);
    try typeKeys(&ed, ")");
    try expectEqual(0, ed.doc.selections.main);
    try typeKeys(&ed, "(");
    try expectEqual(2, ed.doc.selections.main);
    try ed.key(.alt(','));
    try expectEqual(2, ed.doc.sels().len);
    try typeKeys(&ed, ",");
    try expectEqual(1, ed.doc.sels().len);
    try ed.key(.alt(','));
    try expectMessage(&ed, "the only selection cannot be dropped", true);
}

test "editor: x selects lines, ; reduces, Alt-; flips" {
    var ed: Editor = try .init(gpa, null, "ab\ncd\n");
    defer ed.deinit();
    try typeKeys(&ed, "x");
    try expectMain(&ed, 0, 2);
    try ed.key(.alt(';'));
    try expectMain(&ed, 2, 0);
    try ed.key(.alt(':'));
    try expectMain(&ed, 0, 2);
    try typeKeys(&ed, ";");
    try expectMain(&ed, 2, 2);
}

test "editor: objects" {
    var ed: Editor = try .init(gpa, null, "f(a, b)\n");
    defer ed.deinit();
    try typeKeys(&ed, "fa");
    try ed.key(.alt('i'));
    try typeKeys(&ed, "(");
    try expectMain(&ed, 2, 5);
    try ed.key(.alt('a'));
    try typeKeys(&ed, "(");
    try expectMain(&ed, 1, 6);
}

test "editor: Alt-s splits the selections into lines" {
    var ed: Editor = try .init(gpa, null, "a\nb\nc\n");
    defer ed.deinit();
    try typeKeys(&ed, "%");
    try ed.key(.alt('s'));
    try expectEqual(3, ed.doc.sels().len);
}

test "editor: a paste in normal mode goes before the selections as one step" {
    var ed: Editor = try .init(gpa, null, "ab\n");
    defer ed.deinit();
    try typeKeys(&ed, "l");
    try ed.paste("x\r\ny");
    try expectText(&ed, "ax\nyb\n");
    try expectEqual(.normal, ed.mode);
    try typeKeys(&ed, "u");
    try expectText(&ed, "ab\n");
}

test "editor: a paste in insert mode is typed at every cursor" {
    var ed: Editor = try .init(gpa, null, "a\nb\n");
    defer ed.deinit();
    try typeKeys(&ed, "Ci");
    try ed.paste("12");
    try typeKeys(&ed, "\x1b");
    try expectText(&ed, "12a\n12b\n");
}

test "editor: a paste in the prompt goes to the prompt" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":");
    try ed.paste("w x\ny");
    try expectEqualStrings("w x y", ed.prompt.text());
    try expectText(&ed, "a\n");
}

test "editor: out of memory is reported and leaves the text as it was" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{});
    var ed: Editor = try .init(failing.allocator(), null, "abc\n");
    defer ed.deinit();
    failing.fail_index = failing.alloc_index;
    try typeKeys(&ed, "%d");
    try expectText(&ed, "abc\n");
    try expectMessage(&ed, "out of memory", true);
}

test "editor: init fails cleanly when allocation fails" {
    const T = struct {
        fn run(a: std.mem.Allocator) !void {
            var ed: Editor = try .init(a, "f", "ab\ncd\n");
            defer ed.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, T.run, .{});
}

test "editor: a session survives an allocation failure at any point" {
    // Fails the n-th allocation after init, for every n the session makes:
    // nothing may leak or crash, and the editor keeps working afterwards.
    var n: usize = 0;
    while (true) : (n += 1) {
        var failing: std.testing.FailingAllocator = .init(gpa, .{});
        var ed: Editor = try .init(failing.allocator(), "f", "ab\ncd\n");
        defer ed.deinit();
        failing.fail_index = failing.alloc_index + n;
        try typeKeys(&ed, "Cwdix\x1b/c\r:w\r");
        if (ed.takeRequest()) |r| ed.finishSave(r.save, {});
        try ed.paste("p");
        try typeKeys(&ed, "uU:e g\r");
        if (ed.takeRequest()) |r| ed.finishLoad(r.load, null);
        if (!failing.has_induced_failure) break;
        failing.fail_index = std.math.maxInt(usize);
        try typeKeys(&ed, "%y");
        try expectEqual(1, ed.regs.get('"').len);
    }
}

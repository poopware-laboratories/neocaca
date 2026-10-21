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

test "editor: : opens the command prompt, Escape closes it" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":");
    try expectEqual(.prompt, ed.mode);
    try typeKeys(&ed, "q");
    try expectEqualStrings("q", ed.prompt.text());
    try typeKeys(&ed, "\x1b");
    try expectEqual(.normal, ed.mode);
    try expect(!ed.quit);
}

test "editor: Backspace on an empty prompt closes it" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":\x7f");
    try expectEqual(.normal, ed.mode);
}

test "editor: a reopened prompt starts empty" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":abc\x1b:");
    try expectEqualStrings("", ed.prompt.text());
}

test "editor: :q quits, but not over unsaved changes" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "d:q\r");
    try expect(!ed.quit);
    try expectEqual(.normal, ed.mode);
    try expectMessage(&ed, "unsaved changes; :q! discards them", true);
    try typeKeys(&ed, ":q!\r");
    try expect(ed.quit);
}

test "editor: :q quits an unmodified buffer" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":q\r");
    try expect(ed.quit);
}

test "editor: an unknown command is an error" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":nope\r");
    try expectMessage(&ed, "unknown command", true);
    try expectEqual(.normal, ed.mode);
}

test "editor: :<n> goes to line n" {
    var ed: Editor = try .init(gpa, null, "a\nb\nc\n");
    defer ed.deinit();
    try typeKeys(&ed, ":3\r");
    try expectMain(&ed, 4, 4);
    try typeKeys(&ed, ":99\r");
    try expectMain(&ed, 4, 4);
}

test "editor: :w asks the shell to save the buffer to its file" {
    var ed: Editor = try .init(gpa, "f.txt", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "d:w\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings("f.txt", r.save.path);
    try expect(!r.save.quit);
    try expectEqual(null, ed.takeRequest());
    ed.finishSave(r.save, {});
    try expect(!ed.doc.isModified());
    try expectMessage(&ed, "\"f.txt\" written, 1 line", false);
}

test "editor: :w without any file name is an error" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":w\r");
    try expectEqual(null, ed.takeRequest());
    try expectMessage(&ed, "no file name; :w <file>", true);
}

test "editor: :w <file> names a buffer that had no file" {
    var ed: Editor = try .init(gpa, null, "a\nb\n");
    defer ed.deinit();
    try typeKeys(&ed, ":w new.txt\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings("new.txt", r.save.path);
    ed.finishSave(r.save, {});
    try expectEqualStrings("new.txt", ed.path.?);
    try expectMessage(&ed, "\"new.txt\" written, 2 lines", false);
}

test "editor: :w <file> to another file keeps the buffer's own name and state" {
    var ed: Editor = try .init(gpa, "mine", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "d:w copy\r");
    const r = ed.takeRequest().?;
    ed.finishSave(r.save, {});
    try expectEqualStrings("mine", ed.path.?);
    try expect(ed.doc.isModified());
}

test "editor: a failed save is reported and keeps the changes marked" {
    var ed: Editor = try .init(gpa, "f", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "d:wq\r");
    const r = ed.takeRequest().?;
    try expect(r.save.quit);
    ed.finishSave(r.save, error.AccessDenied);
    try expect(!ed.quit);
    try expect(ed.doc.isModified());
    try expectMessage(&ed, "cannot write \"f\": AccessDenied", true);
}

test "editor: :wq quits once the save succeeds" {
    var ed: Editor = try .init(gpa, "f", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":wq\r");
    const r = ed.takeRequest().?;
    try expect(!ed.quit);
    ed.finishSave(r.save, {});
    try expect(ed.quit);
}

test "editor: :x writes only when there are changes" {
    var ed: Editor = try .init(gpa, "f", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":x\r");
    try expectEqual(null, ed.takeRequest());
    try expect(ed.quit);

    var ed2: Editor = try .init(gpa, "f", "a\n");
    defer ed2.deinit();
    try typeKeys(&ed2, "d:x\r");
    const r = ed2.takeRequest().?;
    ed2.finishSave(r.save, {});
    try expect(ed2.quit);
}

test "editor: :e asks for a file and takes its contents" {
    var ed: Editor = try .init(gpa, "a", "old\n");
    defer ed.deinit();
    try typeKeys(&ed, "w:e b.txt\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings("b.txt", r.load);
    const text = try gpa.dupe(u8, "one\ntwo\n");
    ed.finishLoad(r.load, text);
    try expectText(&ed, "one\ntwo\n");
    try expectEqualStrings("b.txt", ed.path.?);
    try expectMain(&ed, 0, 0);
    try expectMessage(&ed, "\"b.txt\" 2 lines", false);
}

test "editor: :e of a missing file opens a new, empty buffer" {
    var ed: Editor = try .init(gpa, "a", "old\n");
    defer ed.deinit();
    try typeKeys(&ed, ":e new\r");
    const r = ed.takeRequest().?;
    ed.finishLoad(r.load, null);
    try expectText(&ed, "\n");
    try expectMessage(&ed, "\"new\" new file", false);
}

test "editor: a failed load keeps the buffer" {
    var ed: Editor = try .init(gpa, "a", "old\n");
    defer ed.deinit();
    try typeKeys(&ed, ":e big\r");
    const r = ed.takeRequest().?;
    ed.finishLoad(r.load, error.FileTooBig);
    try expectText(&ed, "old\n");
    try expectEqualStrings("a", ed.path.?);
    try expectMessage(&ed, "cannot open \"big\": FileTooBig", true);
}

test "editor: :e is refused over unsaved changes, :e! reloads" {
    var ed: Editor = try .init(gpa, "a", "old\n");
    defer ed.deinit();
    try typeKeys(&ed, "d:e b\r");
    try expectEqual(null, ed.takeRequest());
    try expectMessage(&ed, "unsaved changes; :e! discards them", true);
    try typeKeys(&ed, ":e!\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings("a", r.load);
}

test "editor: :e! without a file name is an error" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":e!\r");
    try expectEqual(null, ed.takeRequest());
    try expectMessage(&ed, "no file name; :w <file>", true);
}

test "editor: / searches, n repeats, N adds" {
    var ed: Editor = try .init(gpa, null, "ab ab ab\n");
    defer ed.deinit();
    try typeKeys(&ed, "/ab\r");
    try expectMain(&ed, 3, 4);
    try typeKeys(&ed, "n");
    try expectMain(&ed, 6, 7);
    try typeKeys(&ed, "n");
    try expectMain(&ed, 0, 1);
    try expectMessage(&ed, "search wrapped", false);
    try typeKeys(&ed, "N");
    try expectEqual(2, ed.doc.sels().len);
    try expectEqualStrings("ab", ed.regs.get('/')[0]);
}

test "editor: ? searches backwards, Alt-n repeats backwards" {
    var ed: Editor = try .init(gpa, null, "x1 x2 x3\n");
    defer ed.deinit();
    try typeKeys(&ed, "gl?x\\d\r");
    try expectMain(&ed, 3, 4);
    try ed.key(.alt('n'));
    try expectMain(&ed, 0, 1);
}

test "editor: an empty search prompt reuses the last pattern" {
    var ed: Editor = try .init(gpa, null, "ab ab ab\n");
    defer ed.deinit();
    try typeKeys(&ed, "/b\r/\r");
    try expectMain(&ed, 4, 4);
}

test "editor: n before any search is an error" {
    var ed: Editor = try .init(gpa, null, "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "n");
    try expectMessage(&ed, "no search pattern", true);
}

test "editor: a search that finds nothing says so" {
    var ed: Editor = try .init(gpa, null, "abc\n");
    defer ed.deinit();
    try typeKeys(&ed, "/zz\r");
    try expectMessage(&ed, "not found: zz", true);
    try expectMain(&ed, 0, 0);
}

test "editor: a bad regex is reported and changes nothing" {
    var ed: Editor = try .init(gpa, null, "abc\n");
    defer ed.deinit();
    try typeKeys(&ed, "/a(\r");
    try expect(ed.message.is_error);
    try expect(std.mem.startsWith(u8, ed.message.text(), "bad regex: "));
    try typeKeys(&ed, "n");
    try expectMessage(&ed, "no search pattern", true);
}

test "editor: * searches for the main selection, literally" {
    var ed: Editor = try .init(gpa, null, "a.b axb a.b\n");
    defer ed.deinit();
    try typeKeys(&ed, "2L*n");
    try expectMain(&ed, 8, 10);
}

test "editor: s selects the matches inside the selections" {
    var ed: Editor = try .init(gpa, null, "a1 b2 c3\n");
    defer ed.deinit();
    try typeKeys(&ed, "%s\\d\r");
    try expectEqual(3, ed.doc.sels().len);
    try typeKeys(&ed, "d");
    try expectText(&ed, "a b c\n");
}

test "editor: s with no match keeps the selections and says so" {
    var ed: Editor = try .init(gpa, null, "abc\n");
    defer ed.deinit();
    try typeKeys(&ed, "%s\\d\r");
    try expectMessage(&ed, "no matches", true);
    try expectMain(&ed, 0, 3);
}

test "editor: S splits the selections at the matches" {
    var ed: Editor = try .init(gpa, null, "a,b,c\n");
    defer ed.deinit();
    try typeKeys(&ed, "xS,\r");
    try expectEqual(3, ed.doc.sels().len);
}

test "editor: Alt-k keeps and Alt-K drops the matching selections" {
    var ed: Editor = try .init(gpa, null, "a1\nb\nc2\n");
    defer ed.deinit();
    try typeKeys(&ed, "%");
    try ed.key(.alt('s'));
    try ed.key(.alt('k'));
    try typeKeys(&ed, "\\d\r");
    try expectEqual(2, ed.doc.sels().len);
    try ed.key(.alt('K'));
    try typeKeys(&ed, "1\r");
    try expectEqual(1, ed.doc.sels().len);
    try expectMain(&ed, 5, 7);
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

test "editor: scrolling moves the cursor by pages" {
    var text: [200]u8 = undefined;
    for (0..100) |i| {
        text[2 * i] = 'a';
        text[2 * i + 1] = '\n';
    }
    var ed: Editor = try .init(gpa, null, &text);
    defer ed.deinit();
    ed.resize(80, 12); // ten rows of text
    // The view moves by the page; the cursor moves with it and stays
    // outside the scroll margin.
    try ed.key(.ctrl('f'));
    try expectEqual(10, ed.view.top);
    try expectEqual(13, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try ed.key(.ctrl('d'));
    try expectEqual(15, ed.view.top);
    try expectEqual(18, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try ed.key(.ctrl('u'));
    try expectEqual(13, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    try ed.key(.ctrl('b'));
    try expectEqual(0, ed.view.top);
    try expectEqual(3, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
    for (0..20) |_| try ed.key(.ctrl('f'));
    try expectEqual(99, ed.view.top);
    try expectEqual(99, ed.doc.buffer.lineOf(ed.doc.primary().cursor));
}

fn hundredLines(text: *[200]u8) []const u8 {
    for (0..100) |i| {
        text[2 * i] = 'a';
        text[2 * i + 1] = '\n';
    }
    return text;
}

fn cursorLine(ed: *const Editor) usize {
    return ed.doc.buffer.lineOf(ed.doc.primary().cursor);
}

test "editor: the view prefix places the cursor line without moving it" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12); // ten rows of text, scrolloff 3
    try typeKeys(&ed, "50g");
    try typeKeys(&ed, "vt");
    try expectEqual(46, ed.view.top);
    try typeKeys(&ed, "vb");
    try expectEqual(43, ed.view.top);
    try typeKeys(&ed, "vc");
    try expectEqual(45, ed.view.top);
    try typeKeys(&ed, "vv");
    try expectEqual(45, ed.view.top);
    try expectEqual(49, cursorLine(&ed));
}

test "editor: vj and vk scroll the view, moving the cursor only out of the margin" {
    var text: [200]u8 = undefined;
    var ed: Editor = try .init(gpa, null, hundredLines(&text));
    defer ed.deinit();
    ed.resize(80, 12);
    try typeKeys(&ed, "5j");
    try typeKeys(&ed, "vj");
    try expectEqual(1, ed.view.top);
    try expectEqual(5, cursorLine(&ed));
    try typeKeys(&ed, "3vj");
    try expectEqual(4, ed.view.top);
    // The cursor is pushed down to stay out of the top margin.
    try expectEqual(7, cursorLine(&ed));
    try typeKeys(&ed, "vk");
    try expectEqual(3, ed.view.top);
    try expectEqual(7, cursorLine(&ed));
    try typeKeys(&ed, "9vk");
    try expectEqual(0, ed.view.top);
    // Pulled up to stay out of the bottom margin.
    try expectEqual(6, cursorLine(&ed));
    try typeKeys(&ed, "vk");
    try expectEqual(0, ed.view.top);
    try typeKeys(&ed, "200vj");
    try expectEqual(99, ed.view.top);
    try expectEqual(99, cursorLine(&ed));
    // The status line shows the pending prefix.
    try typeKeys(&ed, "v");
    try expect(ed.keymap.isPending());
    try typeKeys(&ed, "\x1b");
    try expect(!ed.keymap.isPending());
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

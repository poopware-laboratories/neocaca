//! Tests for the prompts of `editor.zig`: opening and closing them, the
//! `:` commands with the save and load requests they make, and the regex
//! prompts (`/`, `?`, `s`, `S`, `Alt-k`). Keys are typed as text, as in
//! `editor_test.zig`.

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
    ed.finishSave(r.save, .unknown);
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
    ed.finishSave(r.save, .unknown);
    try expectEqualStrings("new.txt", ed.path.?);
    try expectMessage(&ed, "\"new.txt\" written, 2 lines", false);
}

test "editor: :w <file> to another file keeps the buffer's own name and state" {
    var ed: Editor = try .init(gpa, "mine", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, "d:w copy\r");
    const r = ed.takeRequest().?;
    ed.finishSave(r.save, .unknown);
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
    try expectMessage(&ed, "cannot write \"f\": permission denied", true);
}

test "editor: :wq quits once the save succeeds" {
    var ed: Editor = try .init(gpa, "f", "a\n");
    defer ed.deinit();
    try typeKeys(&ed, ":wq\r");
    const r = ed.takeRequest().?;
    try expect(!ed.quit);
    ed.finishSave(r.save, .unknown);
    try expect(ed.quit);
}

test "editor: :x quits an unmodified buffer without a file name" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, ":x\r");
    try expect(ed.quit);
    try expectEqual(null, ed.takeRequest());
}

test "editor: :x on a modified buffer without a file name asks for one" {
    var ed: Editor = try .init(gpa, null, "abc");
    defer ed.deinit();
    try typeKeys(&ed, "d:x\r");
    try expect(!ed.quit);
    try expectEqual(null, ed.takeRequest());
    try expectMessage(&ed, "no file name; :w <file>", true);
    // `:wq` with a name writes and quits once written.
    try typeKeys(&ed, ":wq f\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings("f", r.save.path);
    try expect(r.save.quit);
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
    ed2.finishSave(r.save, .unknown);
    try expect(ed2.quit);
}

test "editor: :e asks for a file and takes its contents" {
    var ed: Editor = try .init(gpa, "a", "old\n");
    defer ed.deinit();
    try typeKeys(&ed, "w:e b.txt\r");
    const r = ed.takeRequest().?;
    try expectEqualStrings("b.txt", r.load);
    const text = try gpa.dupe(u8, "one\ntwo\n");
    ed.finishLoad(r.load, text, .unknown);
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
    ed.finishLoad(r.load, null, .unknown);
    try expectText(&ed, "\n");
    try expectMessage(&ed, "\"new\" new file", false);
}

test "editor: a failed load keeps the buffer" {
    var ed: Editor = try .init(gpa, "a", "old\n");
    defer ed.deinit();
    try typeKeys(&ed, ":e big\r");
    const r = ed.takeRequest().?;
    ed.finishLoad(r.load, error.FileTooBig, .unknown);
    try expectText(&ed, "old\n");
    try expectEqualStrings("a", ed.path.?);
    try expectMessage(&ed, "cannot open \"big\": the file is too big", true);
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
    try expectMessage(&ed, "bad regex: unbalanced parenthesis", true);
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

test "editor: S drops the selections its matches cover and keeps the rest" {
    var ed: Editor = try .init(gpa, null, "aa\nab\n");
    defer ed.deinit();
    try typeKeys(&ed, "%S[a\\n]\r");
    // Only the `b` is left between the matches.
    try expectEqual(1, ed.doc.sels().len);
    try expectMain(&ed, 4, 4);
    try std.testing.expectEqualStrings("", ed.message.text());
}

test "editor: S whose matches cover every selection keeps them and says so" {
    var ed: Editor = try .init(gpa, null, "aaa\nbbb\n");
    defer ed.deinit();
    try typeKeys(&ed, "xS[a\\n]\r");
    try expectMessage(&ed, "nothing left between the matches", true);
    try expectMain(&ed, 0, 3);
    // Without a match it is one piece, the selection as it was.
    try typeKeys(&ed, "Szz\r");
    try expectMain(&ed, 0, 3);
    try std.testing.expectEqualStrings("", ed.message.text());
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

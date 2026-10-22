//! Editing workflows from the first key to the file on disk: selections,
//! verbs, multiple cursors, search, registers, undo, and the `:` commands,
//! each typed as a person types it.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");
const Harness = @import("harness.zig").Harness;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "editing: select a word, delete it, write and quit" {
    var h: Harness = undefined;
    try h.init("a.txt", "hello brave world\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("wwd");
    try h.expectText("hello world\n");
    try h.typeKeys(":wq\r");
    try expect(h.session.done());
    var buf: [64]u8 = undefined;
    try expectEqualStrings("hello world\n", try h.file("a.txt", &buf));
}

test "editing: select every match in the buffer and change them all" {
    var h: Harness = undefined;
    try h.init("a.zig", "const std = @import(\"std\");\nstd.debug.print();\n", 50, 5);
    defer h.deinit();
    try h.typeKeys("%sstd\r");
    try h.expectSelections(&.{ "std", "std", "std" });
    try h.expectRow(3, " NORMAL  a.zig                        3 sels  1:9 ");
    try h.typeKeys("cSTD\x1b");
    try h.expectText("const STD = @import(\"STD\");\nSTD.debug.print();\n");
    try h.typeKeys("u");
    try h.expectText("const std = @import(\"std\");\nstd.debug.print();\n");
    try h.typeKeys("U");
    try h.expectText("const STD = @import(\"STD\");\nSTD.debug.print();\n");
}

test "editing: split a list at its commas and trim each item" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 4);
    defer h.deinit();
    try h.typeKeys("ia, b, c\x1b%");
    try h.typeKeys("S, \r");
    try h.expectSelections(&.{ "a", "b", "c\n" });
    try h.typeKeys("~");
    try h.expectText("A, B, C\n");
}

test "editing: keep and drop selections by pattern" {
    var h: Harness = undefined;
    try h.init("t", "fn a\nlet b\nfn c\nlet d\n", 30, 6);
    defer h.deinit();
    try h.typeKeys("%");
    try h.send("\x1bs");
    try h.expectSelections(&.{ "fn a\n", "let b\n", "fn c\n", "let d\n" });
    try h.send("\x1bk");
    try h.typeKeys("fn\r");
    try h.expectSelections(&.{ "fn a\n", "fn c\n" });
    try h.typeKeys("d");
    try h.expectText("let b\nlet d\n");
    try h.typeKeys("%");
    try h.send("\x1bs");
    try h.send("\x1bK");
    try h.typeKeys("let\r");
    try h.expectMessage("every selection matches");
    try expectEqual(2, h.session.ed.doc.sels().len);
}

test "editing: swap two words by rotating their contents, then undo" {
    var h: Harness = undefined;
    try h.init("t", "one two three\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("%s\\w+\r");
    try h.send("\x1b)");
    try h.expectText("three one two\n");
    try h.expectSelections(&.{ "three", "one", "two" });
    try h.send("\x1b(");
    try h.expectText("one two three\n");
    try h.typeKeys("2");
    try h.send("\x1b(");
    try h.expectText("three one two\n");
    try h.typeKeys("uu");
    try h.expectText("three one two\n");
    try h.typeKeys("u");
    try h.expectText("one two three\n");
}

test "editing: trim a selection to its whole lines, or say there are none" {
    var h: Harness = undefined;
    try h.init("t", "ab\ncd\nef\n", 30, 5);
    defer h.deinit();
    try h.typeKeys("lJJ");
    try h.send("\x1bx");
    try h.expectSelections(&.{"cd\n"});
    try h.typeKeys(";");
    try h.send("\x1bx");
    try h.expectMessage("no selection holds a whole line");
    try h.expectSelections(&.{"\n"});
}

test "editing: search forwards, repeat, and add the next match" {
    var h: Harness = undefined;
    try h.init("t", "one two one two one\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("/one\r");
    try h.expectSelections(&.{"one"});
    try expectEqual(10, h.session.ed.doc.sels()[0].cursor);
    try h.typeKeys("n");
    try expectEqual(18, h.session.ed.doc.sels()[0].cursor);
    try h.typeKeys("N");
    try h.expectSelections(&.{ "one", "one" });
    // The added match wrapped around to the first "one".
    try h.typeKeys("cX\x1b");
    try h.expectText("X two one two X\n");
}

test "editing: patterns that match empty at the end of the text find nothing" {
    var h: Harness = undefined;
    try h.init("t", "ab\n", 30, 4);
    defer h.deinit();
    // `^` matches only empty, the last time after the final newline.
    try h.typeKeys("/^\r");
    try h.expectMessage("not found: ^");
    try h.typeKeys("?^\r");
    try h.expectMessage("not found: ^");
    try h.typeKeys("%s^\r");
    try h.expectMessage("no matches");
    try h.typeKeys("%S^\r");
    try h.expectSelections(&.{"ab\n"});
    try h.typeKeys("%s^.\r");
    try h.expectSelections(&.{"a"});
}

test "editing: yank a line into a register and paste it twice below" {
    var h: Harness = undefined;
    try h.init("t", "first\nsecond\n", 30, 5);
    defer h.deinit();
    try h.typeKeys("x\"ay");
    try h.typeKeys("j");
    try h.typeKeys("\"ap\"ap");
    try h.expectText("first\nsecond\nfirst\nfirst\n");
    try h.typeKeys("uu");
    try h.expectText("first\nsecond\n");
}

test "editing: insert at a column of cursors made with C" {
    var h: Harness = undefined;
    try h.init("t", "a\nb\nc\n", 30, 6);
    defer h.deinit();
    try h.typeKeys("CC");
    try expectEqual(3, h.session.ed.doc.sels().len);
    try h.typeKeys("i- \x1b");
    try h.expectText("- a\n- b\n- c\n");
    try h.typeKeys(",");
    try expectEqual(1, h.session.ed.doc.sels().len);
}

test "editing: undo takes back a whole insert session, redo brings it again" {
    var h: Harness = undefined;
    try h.init("t", "x\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("iabc\x7f\x1b");
    try h.expectText("abx\n");
    try h.typeKeys("u");
    try h.expectText("x\n");
    try h.typeKeys("u");
    try h.expectMessage("nothing to undo");
    try h.typeKeys("U");
    try h.expectText("abx\n");
}

test "editing: a scratch buffer is written under the name :w gives it" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 4);
    defer h.deinit();
    try h.typeKeys("inotes\x1b:w\r");
    try h.expectMessage("no file name; :w <file>");
    try h.typeKeys(":w out.txt\r");
    var buf: [64]u8 = undefined;
    try expectEqualStrings("notes\n", try h.file("out.txt", &buf));
    try h.expectRow(2, " NORMAL  out.txt          1:6 ");
    try h.typeKeys(":q\r");
    try expect(h.session.done());
}

test "editing: :q refuses over changes, :q! leaves them unwritten" {
    var h: Harness = undefined;
    try h.init("a", "x\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("iy\x1b:q\r");
    try expect(!h.session.done());
    try h.typeKeys(":q!\r");
    try expect(h.session.done());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("x\n", try h.file("a", &buf));
}

test "editing: :e opens another file, refused over changes until written" {
    var h: Harness = undefined;
    try h.init("a", "first\n", 30, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b", .data = "second\n" });
    try h.typeKeys("d:e b\r");
    try h.expectText("irst\n");
    // Typed after the write is reported: `:e` waits for it.
    try h.typeKeys(":w\r");
    try h.typeKeys(":e b\r");
    try h.expectText("second\n");
    try h.expectRow(2, " NORMAL  b                1:1 ");
    var buf: [16]u8 = undefined;
    try expectEqualStrings("irst\n", try h.file("a", &buf));
}

test "editing: keys sent with :e edit the file it opens" {
    var h: Harness = undefined;
    try h.init("a", "first\n", 30, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b", .data = "second\n" });
    // One read: the keys after Enter wait for `b`, not edit `a`.
    try h.send(":e b\rd");
    try h.expectText("econd\n");
    try h.expectRow(2, " NORMAL  b [+]            1:1 ");
}

test "editing: :e on a named pipe is refused instead of waiting for a writer" {
    if (builtin.target.os.tag != .linux) return error.SkipZigTest;
    var h: Harness = undefined;
    try h.init("a", "first\n", 40, 4);
    defer h.deinit();
    const linux = std.os.linux;
    try expectEqual(.SUCCESS, linux.errno(linux.mknodat(h.tmp.dir.handle, "p", linux.S.IFIFO | 0o600, 0)));
    try h.typeKeys(":e p\r");
    try h.expectText("first\n");
    try h.expectRow(3, "cannot open \"p\": NotAFile               ");
    try h.typeKeys(":q\r");
    try expect(h.session.done());
}

test "editing: a write that fails keeps the changes and says why" {
    var h: Harness = undefined;
    try h.init("dir/a", null, 40, 4);
    defer h.deinit();
    try h.typeKeys("ix\x1b:wq\r");
    try expect(!h.session.done());
    try expect(h.session.ed.doc.isModified());
    try expect(h.session.ed.message.is_error);
    try h.expectText("x\n");
}

test "editing: deleting the last lines split into selections leaves no empty line" {
    var h: Harness = undefined;
    try h.init("t", "a\nb\nc\n", 30, 5);
    defer h.deinit();
    try h.typeKeys("jxX");
    try h.send("\x1bs"); // Alt-s: a selection on each line
    try expectEqual(2, h.session.ed.doc.sels().len);
    try h.typeKeys("d");
    try h.expectText("a\n");
    try expectEqual(1, h.session.ed.doc.sels().len);
    try h.typeKeys("u");
    try h.expectText("a\nb\nc\n");
}

test "editing: s on a combining mark selects and deletes the whole character" {
    var h: Harness = undefined;
    try h.init("t", "ae\u{301}b e\u{301}\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("%s");
    try h.send("\u{301}"); // a character arrives in one read
    try h.typeKeys("\r");
    try h.expectSelections(&.{ "e\u{301}", "e\u{301}" });
    try h.typeKeys("d");
    try h.expectText("ab \n");
    try h.typeKeys("u%S");
    try h.send("\u{301}");
    try h.typeKeys("\r");
    try h.expectSelections(&.{ "a", "b ", "\n" });
}

test "editing: inserting at an inner object's cursor keeps its last character whole" {
    var h: Harness = undefined;
    try h.init("a.txt", "(é) \"中\"\n", 30, 4);
    defer h.deinit();
    try h.send("\x1bi");
    try h.typeKeys("(;ix\x1b"); // reduced to the cursor: before é
    try h.expectText("(xé) \"中\"\n");
    try h.typeKeys("glh"); // onto 中
    try h.send("\x1bi");
    try h.typeKeys("\"cy\x1b");
    try h.expectText("(xé) \"y\"\n");
}

test "editing: pasting a line and a word on the last line puts each where it belongs" {
    var h: Harness = undefined;
    try h.init("a.txt", "a\nb c\n", 30, 4);
    defer h.deinit();
    try h.typeKeys("%sa\\n|c\ry");
    try h.expectSelections(&.{ "a\n", "c" });
    try h.typeKeys("%sb|c\rp");
    try h.expectText("a\nb cc\na\n");
    try h.typeKeys("u");
    try h.expectText("a\nb c\n");
}

test "editing: counts repeat moves and verbs" {
    var h: Harness = undefined;
    try h.init("t", "1\n2\n3\n4\n5\n", 30, 7);
    defer h.deinit();
    try h.typeKeys("3j");
    try h.expectSelections(&.{"4"});
    try h.typeKeys("x2d");
    try h.expectText("1\n2\n3\n5\n");
    try h.typeKeys(":2\r");
    try h.expectSelections(&.{"2"});
}

test "editing: a paste arrives as typed text, in one undo step" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 4);
    defer h.deinit();
    try h.send("i");
    try h.send("\x1b[200~line one\nline two\x1b[201~");
    try h.typeKeys("\x1b");
    try h.expectText("line one\nline two\n");
    try h.typeKeys("u");
    try h.expectText("\n");
}

test "editing: a pasted escape sequence is text, not keys" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 4);
    defer h.deinit();
    try h.send("i\x1b[200~\x1b:q!\r\x1b[201~");
    try expect(!h.session.done());
    try expectEqual(.insert, h.session.ed.mode);
    try h.expectText("\x1b:q!\n\n");
}

test "editing: map Ctrl-S to write, save with it, then unmap it" {
    var h: Harness = undefined;
    try h.init("a.txt", "hello\n", 40, 4);
    defer h.deinit();
    try h.typeKeys(":map normal <c-s> :w<ret>\r");
    try h.typeKeys("dihey \x1b");
    try h.send("\x13"); // Ctrl-S
    try h.expectMessage("\"a.txt\" written, 1 line");
    var buf: [64]u8 = undefined;
    try expectEqualStrings("hey ello\n", try h.file("a.txt", &buf));
    try h.typeKeys(":unmap normal <c-s>\r");
    try h.typeKeys("x");
    try h.send("\x13");
    try expectEqualStrings("hey ello\n", try h.file("a.txt", &buf));
}

test "editing: a mapping that writes two files writes both" {
    var h: Harness = undefined;
    try h.init("a.txt", "hello\n", 40, 4);
    defer h.deinit();
    try h.typeKeys(":map normal <c-s> :w<ret>:w<space>b.txt<ret>\r");
    try h.typeKeys("ix\x1b");
    try h.send("\x13"); // Ctrl-S
    var buf: [64]u8 = undefined;
    try expectEqualStrings("xhello\n", try h.file("a.txt", &buf));
    try expectEqualStrings("xhello\n", try h.file("b.txt", &buf));
    try h.expectMessage("\"b.txt\" written, 1 line");
    // a.txt is the file, and it holds the text.
    try expect(!h.session.ed.doc.isModified());
}

test "editing: a mapping that opens a file edits it with its next keys" {
    var h: Harness = undefined;
    try h.init("a", "first\n", 30, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b", .data = "second\n" });
    try h.typeKeys(":map normal Q :e<space>b<ret>d\r");
    try h.send("Q");
    try h.expectText("econd\n");
    try h.expectRow(2, " NORMAL  b [+]            1:1 ");
}

test "editing: an insert mode mapping leaves insert mode and moves" {
    var h: Harness = undefined;
    try h.init("b.txt", "one\ntwo\n", 40, 4);
    defer h.deinit();
    try h.typeKeys(":map insert <a-j> <esc>j\r");
    try h.typeKeys("i>");
    try h.send("\x1bj"); // Alt-j
    try h.expectRow(2, " NORMAL  b.txt [+]                  2:2 ");
    try h.expectText(">one\ntwo\n");
}

test "editing: indenting a line that starts with a mark keeps the selection on a character" {
    var h: Harness = undefined;
    try h.init("t", "\u{301}a\n", 30, 4);
    defer h.deinit();
    // The lone mark is selected; the indent gives it a base to join.
    try h.typeKeys(">");
    const sel = h.session.ed.doc.sels()[0];
    const text = h.text();
    try expectEqual(neocaca.unicode.chars.holding(text, sel.anchor), sel.anchor);
    try expectEqual(neocaca.unicode.chars.holding(text, sel.cursor), sel.cursor);
    // Deleting it takes whole characters, never half of one.
    try h.typeKeys("d");
    try h.expectText("   a\n");
    try h.typeKeys("uu");
    try h.expectText("\u{301}a\n");
}

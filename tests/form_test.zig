//! CRLF files, byte order marks and missing final newlines from the first
//! key to the bytes on disk: lines show no `^M` and the mark is not shown,
//! the lines typed into a CRLF file end in CRLF, the mark cannot be
//! deleted, a file that mixes line ends is written as it was read, and one
//! whose last line had no newline is written without one.

const std = @import("std");
const Harness = @import("harness.zig").Harness;

const expectEqualStrings = std.testing.expectEqualStrings;

/// The bytes of `path` in the session's directory, in `buf`.
fn expectFile(h: *const Harness, path: []const u8, want: []const u8) !void {
    var buf: [256]u8 = undefined;
    try expectEqualStrings(want, try h.file(path, &buf));
}

test "endings: a CRLF file shows its lines without ^M" {
    var h: Harness = undefined;
    try h.init("f", "ab\r\ncd\r\n", 12, 4);
    defer h.deinit();
    try h.expectRow(0, " 1 ab       ");
    try h.expectRow(1, " 2 cd       ");
    try h.expectMessage("\"f\" 2 lines");
}

test "endings: text appended at a CRLF line end goes before the line end" {
    var h: Harness = undefined;
    try h.init("f", "ab\r\ncd\r\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("gl");
    try h.expectSelections(&.{"b"});
    try h.typeKeys("ax\x1b:w\r");
    try expectFile(&h, "f", "abx\r\ncd\r\n");
}

test "endings: lines opened with o, O and Enter end in CRLF" {
    var h: Harness = undefined;
    try h.init("f", "a\r\nb\r\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("ox\x1bOy\x1bjjxiz\r\x1b:w\r");
    try expectFile(&h, "f", "a\r\ny\r\nx\r\nz\r\nb\r\n");
}

test "endings: pasted lines end in CRLF, whatever the terminal sent" {
    var h: Harness = undefined;
    try h.init("f", "a\r\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("i");
    try h.send("\x1b[200~p\r\nq\nr\r\x1b[201~");
    try h.typeKeys("\x1b:w\r");
    try expectFile(&h, "f", "p\r\nq\r\nr\r\na\r\n");
}

test "endings: lines yanked and put in a CRLF file end in CRLF" {
    var h: Harness = undefined;
    try h.init("f", "a\r\nb\r\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("xyjp:w\r");
    try expectFile(&h, "f", "a\r\nb\r\na\r\n");
}

test "endings: a CRLF file is written back byte for byte" {
    var h: Harness = undefined;
    const bytes = "a\rb\r\n\r\n\ra\r\r\n\x00\xff\r\n";
    try h.init("f", bytes, 20, 4);
    defer h.deinit();
    try h.typeKeys(":w\r");
    try expectFile(&h, "f", bytes);
}

test "endings: a CRLF file without a final line end is written without one" {
    var h: Harness = undefined;
    try h.init("f", "a\r\nb", 12, 4);
    defer h.deinit();
    try h.typeKeys("jox\x1b:w\r");
    try expectFile(&h, "f", "a\r\nb\r\nx");
    // A carriage return that ends the file is text, shown and kept.
    var g: Harness = undefined;
    try g.init("g", "a\r\nb\r", 12, 4);
    defer g.deinit();
    try g.expectRow(1, " 2 b^M      ");
    try g.typeKeys(":w\r");
    try expectFile(&g, "g", "a\r\nb\r");
}

test "endings: a file mixing line ends is edited and written as it is" {
    var h: Harness = undefined;
    try h.init("f", "a\r\nb\n", 12, 4);
    defer h.deinit();
    try h.expectRow(0, " 1 a^M      ");
    try h.typeKeys("jox\x1b:w\r");
    try expectFile(&h, "f", "a\r\nb\nx\n");
}

test "endings: :w to another name writes CRLF too" {
    var h: Harness = undefined;
    try h.init("f", "a\r\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("ox\x1b:w g\r");
    try expectFile(&h, "g", "a\r\nx\r\n");
    try expectFile(&h, "f", "a\r\n");
}

test "endings: :e takes the line ends of the file it opens" {
    var h: Harness = undefined;
    try h.init("lf", "a\n", 12, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "crlf", .data = "b\r\n" });
    try h.typeKeys(":e crlf\r");
    try h.typeKeys("ox\x1b:w\r");
    try expectFile(&h, "crlf", "b\r\nx\r\n");
    try h.typeKeys(":e lf\r");
    try h.typeKeys("oy\x1b:w\r");
    try expectFile(&h, "lf", "a\ny\n");
    // A new file has LF line ends, whatever was open before.
    try h.typeKeys(":e crlf\r");
    try h.typeKeys(":e new\r");
    try h.typeKeys("iz\x1b:w\r");
    try expectFile(&h, "new", "z\n");
}

test "endings: the recovery file of a CRLF file has CRLF line ends" {
    var h: Harness = undefined;
    try h.init("f", "a\r\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("ox\x1b");
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try expectEqualStrings("f.recovered", h.session.recover(&buf).written);
    try expectFile(&h, "f.recovered", "a\r\nx\r\n");
}

test "bom: the byte order mark is not shown, and the cursor starts on the text" {
    var h: Harness = undefined;
    try h.init("f", "\xef\xbb\xbfab\n", 20, 4);
    defer h.deinit();
    try h.expectRow(0, " 1 ab               ");
    try h.expectSelections(&.{"a"});
    try h.typeKeys("d:w\r");
    try expectFile(&h, "f", "\xef\xbb\xbfb\n");
}

test "bom: deleting all the text keeps the byte order mark" {
    var h: Harness = undefined;
    try h.init("f", "\xef\xbb\xbfab\ncd\n", 20, 4);
    defer h.deinit();
    try h.typeKeys("%d:w\r");
    try expectFile(&h, "f", "\xef\xbb\xbf\n");
    try h.typeKeys("ix\x1b:w\r");
    try expectFile(&h, "f", "\xef\xbb\xbfx\n");
}

test "bom: a file with a byte order mark and CRLF keeps both" {
    var h: Harness = undefined;
    try h.init("f", "\xef\xbb\xbfa\r\n", 20, 4);
    defer h.deinit();
    try h.expectRow(0, " 1 a                ");
    try h.typeKeys("Ox\x1b:w\r");
    try expectFile(&h, "f", "\xef\xbb\xbfx\r\na\r\n");
}

test "bom: :w to another name keeps the mark, :e of a file without one drops it" {
    var h: Harness = undefined;
    try h.init("f", "\xef\xbb\xbfa\n", 20, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "plain", .data = "b\n" });
    try h.typeKeys(":w g\r");
    try expectFile(&h, "g", "\xef\xbb\xbfa\n");
    try h.typeKeys(":e plain\r");
    try h.typeKeys("ox\x1b:w\r");
    try expectFile(&h, "plain", "b\nx\n");
}

test "bom: a mark that is not at the start is text, shown and kept" {
    var h: Harness = undefined;
    try h.init("f", "a\xef\xbb\xbf\n", 20, 4);
    defer h.deinit();
    try h.typeKeys("ox\x1b:w\r");
    try expectFile(&h, "f", "a\xef\xbb\xbf\nx\n");
}

test "bom: the recovery file keeps the byte order mark" {
    var h: Harness = undefined;
    try h.init("f", "\xef\xbb\xbfa\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("ox\x1b");
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try expectEqualStrings("f.recovered", h.session.recover(&buf).written);
    try expectFile(&h, "f.recovered", "\xef\xbb\xbfa\nx\n");
}

test "final newline: a file without one is written back without one" {
    var h: Harness = undefined;
    try h.init("f", "ab\ncd", 12, 4);
    defer h.deinit();
    try h.expectRow(1, " 2 cd       ");
    try h.typeKeys(":w\r");
    try expectFile(&h, "f", "ab\ncd");
    try h.typeKeys("jglax\x1b:w\r");
    try expectFile(&h, "f", "ab\ncdx");
}

test "final newline: lines added after the last one end, all but the last" {
    var h: Harness = undefined;
    try h.init("f", "a", 12, 4);
    defer h.deinit();
    try h.typeKeys("ob\rc\x1b:w\r");
    try expectFile(&h, "f", "a\nb\nc");
}

test "final newline: deleting all the text leaves the file empty" {
    var h: Harness = undefined;
    try h.init("f", "a\nb", 12, 4);
    defer h.deinit();
    try h.typeKeys("%d:w\r");
    try expectFile(&h, "f", "");
}

test "final newline: a file with one keeps it, and an empty file gets one once typed in" {
    var h: Harness = undefined;
    try h.init("f", "a\n", 12, 4);
    defer h.deinit();
    try h.typeKeys("ob\x1b:w\r");
    try expectFile(&h, "f", "a\nb\n");
    var g: Harness = undefined;
    try g.init("g", "", 12, 4);
    defer g.deinit();
    try g.typeKeys("ix\x1b:w\r");
    try expectFile(&g, "g", "x\n");
}

test "final newline: the mark, CRLF and no final newline are all kept" {
    var h: Harness = undefined;
    try h.init("f", "\xef\xbb\xbfa\r\nb", 12, 4);
    defer h.deinit();
    try h.typeKeys("Ox\x1b:w\r");
    try expectFile(&h, "f", "\xef\xbb\xbfx\r\na\r\nb");
}

test "final newline: :w to another name and :e keep each file's own" {
    var h: Harness = undefined;
    try h.init("f", "a", 12, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "g", .data = "b\n" });
    try h.typeKeys(":w copy\r");
    try expectFile(&h, "copy", "a");
    try h.typeKeys(":e g\r");
    try h.typeKeys("ox\x1b:w\r");
    try expectFile(&h, "g", "b\nx\n");
    try h.typeKeys(":e f\r");
    try h.typeKeys("oy\x1b:w\r");
    try expectFile(&h, "f", "a\ny");
}

test "final newline: the recovery file has none when the file had none" {
    var h: Harness = undefined;
    try h.init("f", "a", 12, 4);
    defer h.deinit();
    try h.typeKeys("ox\x1b");
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    try expectEqualStrings("f.recovered", h.session.recover(&buf).written);
    try expectFile(&h, "f.recovered", "a\nx");
}

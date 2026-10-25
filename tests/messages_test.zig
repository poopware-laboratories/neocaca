//! Why a file could not be opened or written, as the message line says it:
//! each failure made for real in a temporary directory, then read back in
//! words, never as an error's name.

const std = @import("std");
const Harness = @import("harness.zig").Harness;

const io = std.testing.io;
const expect = std.testing.expect;

/// A name longer than any file system allows for one path component.
const long: []const u8 = &@as([300]u8, @splat('n'));

/// A message about `long` fills the message line, its path shortened
/// from the start so the end of the name and the reason are kept whole.
fn expectAbout(h: *const Harness, comptime verb: []const u8) !void {
    const text = h.session.ed.message.text();
    try expect(h.session.ed.message.is_error);
    try expect(std.mem.startsWith(u8, text, verb ++ " \"…nnn"));
    try expect(std.mem.endsWith(u8, text, "nnn\": the name is too long"));
    try std.testing.expectEqual(256, text.len);
}

test "messages: opening a path through a file opens it new, and says its directory is missing" {
    var h: Harness = undefined;
    try h.init("f", "keep\n", 60, 4);
    defer h.deinit();
    try h.typeKeys(":e f/x\r");
    try h.expectMessage("\"f/x\" new file; its directory does not exist");
    try expect(h.session.ed.message.is_error);
    try h.expectText("\n");
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("keep\n", try h.file("f", &buf));
}

test "messages: opening a file in a missing directory says so" {
    var h: Harness = undefined;
    try h.init(null, null, 60, 4);
    defer h.deinit();
    try h.typeKeys(":e gone/f\r");
    try h.expectRow(3, "\"gone/f\" new file; its directory does not exist             ");
}

test "messages: opening a name that is too long fails without a crash" {
    var h: Harness = undefined;
    try h.init("f", "keep\n", 60, 4);
    defer h.deinit();
    try h.typeKeys(":e " ++ long ++ "\r");
    try expectAbout(&h, "cannot open");
    try h.expectRow(3, "cannot open \"…" ++ long[0..23] ++ "\": the name is too long");
    try h.expectText("keep\n");
}

test "messages: opening a link that names itself says there are too many links" {
    var h: Harness = undefined;
    try h.init("f", "keep\n", 60, 4);
    defer h.deinit();
    try h.tmp.dir.symLink(io, "loop", "loop", .{});
    try h.typeKeys(":e loop\r");
    try h.expectMessage("cannot open \"loop\": too many symbolic links");
    try h.expectText("keep\n");
}

test "messages: writing a path through a file keeps the changes and says why" {
    var h: Harness = undefined;
    try h.init("f", "keep\n", 60, 4);
    defer h.deinit();
    try h.typeKeys("ix\x1b:w f/x\r");
    try h.expectMessage("cannot write \"f/x\": a part of the path is not a directory");
    try expect(h.session.ed.doc.isModified());
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("keep\n", try h.file("f", &buf));
}

test "messages: writing a name that is too long fails and keeps the changes" {
    var h: Harness = undefined;
    try h.init("f", "keep\n", 60, 4);
    defer h.deinit();
    try h.typeKeys("ix\x1b:w " ++ long ++ "\r");
    try expectAbout(&h, "cannot write");
    // At 60 columns the path gives way, so the reason stays on screen.
    try h.expectRow(3, "cannot write \"…" ++ long[0..22] ++ "\": the name is too long");
    try expect(h.session.ed.doc.isModified());
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("keep\n", try h.file("f", &buf));
}

test "messages: writing through a link that names itself says why and keeps the link" {
    var h: Harness = undefined;
    try h.init(null, null, 60, 4);
    defer h.deinit();
    try h.tmp.dir.symLink(io, "loop", "loop", .{});
    try h.typeKeys("ix\x1b:w loop\r");
    try h.expectMessage("cannot write \"loop\": too many symbolic links");
    var buf: [16]u8 = undefined;
    const n = try h.tmp.dir.readLink(io, "loop", &buf);
    try std.testing.expectEqualStrings("loop", buf[0..n]);
}

test "messages: writing into a missing directory says it does not exist" {
    var h: Harness = undefined;
    try h.init("gone/f", null, 60, 4);
    defer h.deinit();
    try h.typeKeys("ix\x1b:w\r");
    try h.expectMessage("cannot write \"gone/f\": no such file or directory");
    try h.expectRow(3, "cannot write \"gone/f\": no such file or directory            ");
}

test "messages: a bad pattern says what is wrong with it on screen" {
    var h: Harness = undefined;
    try h.init("f", "abc\n", 40, 4);
    defer h.deinit();
    try h.typeKeys("/[a\r");
    try h.expectRow(3, "bad regex: a class without its ]        ");
    try h.typeKeys("s(b\r");
    try h.expectMessage("bad regex: unbalanced parenthesis");
    try h.typeKeys("/\\q\r");
    try h.expectMessage("bad regex: an unknown escape");
}

test "messages: writing a long name that is allowed keeps the line count on screen" {
    var h: Harness = undefined;
    try h.init(null, null, 40, 4);
    defer h.deinit();
    const name = long[0..200];
    try h.typeKeys("ix\x1b:w " ++ name ++ "\r");
    try std.testing.expectEqualStrings("\"" ++ name ++ "\" written, 1 line", h.session.ed.message.text());
    try h.expectRow(3, "\"…" ++ name[0..21] ++ "\" written, 1 line");
    var buf: [16]u8 = undefined;
    try std.testing.expectEqualStrings("x\n", try h.file(name, &buf));
}

test "messages: on a narrow window a failed write keeps its reason on screen" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 4);
    defer h.deinit();
    try h.typeKeys("ix\x1b:w a-very-long-dir/new.txt\r");
    // The message itself is whole; only its drawing is cut.
    try h.expectMessage("cannot write \"a-very-long-dir/new.txt\": no such file or directory");
    try h.expectRow(3, "…\": no such file or directory ");
    try h.expectText("x\n");
}

test "messages: on a narrow window a new file keeps the end of its warning on screen" {
    var h: Harness = undefined;
    try h.init(null, null, 30, 4);
    defer h.deinit();
    try h.typeKeys(":e a-very-long-dir/new.txt\r");
    try h.expectMessage("\"a-very-long-dir/new.txt\" new file; its directory does not exist");
    try h.expectRow(3, "… its directory does not exist");
}

/// A session on `contents` that allows `limit` selections.
fn limited(h: *Harness, contents: []const u8, limit: usize) !void {
    try h.init("f", contents, 60, 6);
    h.session.ed.doc.selection_limit = limit;
}

test "messages: s, S and Alt-s past the selection limit say so and change nothing" {
    var h: Harness = undefined;
    try limited(&h, "a a a\nb\nc\n", 2);
    defer h.deinit();
    try h.typeKeys("%sa\r");
    try h.expectMessage("too many selections (more than 2)");
    try expect(h.session.ed.message.is_error);
    try h.expectSelections(&.{"a a a\nb\nc\n"});
    try h.typeKeys("S\\n\r");
    try h.expectMessage("too many selections (more than 2)");
    try h.expectSelections(&.{"a a a\nb\nc\n"});
    try h.send("\x1bs");
    try h.expectMessage("too many selections (more than 2)");
    try h.expectSelections(&.{"a a a\nb\nc\n"});
    // Within the limit, they work as always.
    try h.typeKeys("xsa a\r");
    try h.expectSelections(&.{"a a"});
}

test "messages: C and N past the selection limit say so and change nothing" {
    var h: Harness = undefined;
    try limited(&h, "a\nb\nc\n", 2);
    defer h.deinit();
    try h.typeKeys("C");
    try h.expectSelections(&.{ "a", "b" });
    try h.typeKeys("C");
    try h.expectMessage("too many selections (more than 2)");
    try h.expectSelections(&.{ "a", "b" });
    try h.typeKeys("/c\r");
    try h.expectSelections(&.{"c"});
    try h.typeKeys("kN");
    try h.expectSelections(&.{ "b", "c" });
    try h.typeKeys("N");
    try h.expectMessage("too many selections (more than 2)");
    try h.expectSelections(&.{ "b", "c" });
}

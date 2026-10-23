//! The `:` commands from the first key to the file on disk: `:w` on a
//! scratch buffer, `:q` and `:q!` over changes, `:e` and the keys sent with
//! it, and writes and loads that fail, each typed as a person types it.

const std = @import("std");
const builtin = @import("builtin");
const Harness = @import("harness.zig").Harness;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

test "commands: a scratch buffer is written under the name :w gives it" {
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

test "commands: :q refuses over changes, :q! leaves them unwritten" {
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

test "commands: :e opens another file, refused over changes until written" {
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

test "commands: keys sent with :e edit the file it opens" {
    var h: Harness = undefined;
    try h.init("a", "first\n", 30, 4);
    defer h.deinit();
    try h.tmp.dir.writeFile(std.testing.io, .{ .sub_path = "b", .data = "second\n" });
    // One read: the keys after Enter wait for `b`, not edit `a`.
    try h.send(":e b\rd");
    try h.expectText("econd\n");
    try h.expectRow(2, " NORMAL  b [+]            1:1 ");
}

test "commands: :e on a named pipe is refused instead of waiting for a writer" {
    if (builtin.target.os.tag != .linux) return error.SkipZigTest;
    var h: Harness = undefined;
    try h.init("a", "first\n", 40, 4);
    defer h.deinit();
    const linux = std.os.linux;
    try expectEqual(.SUCCESS, linux.errno(linux.mknodat(h.tmp.dir.handle, "p", linux.S.IFIFO | 0o600, 0)));
    try h.typeKeys(":e p\r");
    try h.expectText("first\n");
    try h.expectRow(3, "cannot open \"p\": not a regular file     ");
    try h.typeKeys(":q\r");
    try expect(h.session.done());
}

test "commands: a write that fails keeps the changes and says why" {
    var h: Harness = undefined;
    try h.init("dir/a", null, 40, 4);
    defer h.deinit();
    try h.typeKeys("ix\x1b:wq\r");
    try expect(!h.session.done());
    try expect(h.session.ed.doc.isModified());
    try expect(h.session.ed.message.is_error);
    try h.expectText("x\n");
}

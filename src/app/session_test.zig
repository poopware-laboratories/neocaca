//! Tests for `session.zig`: terminal bytes in, files on disk and escape
//! bytes out, over a temporary directory and fixed writers.

const std = @import("std");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

fn expectText(s: *const Session, want: []const u8) !void {
    try expectEqualStrings(want, s.ed.doc.text());
}

fn expectMessage(s: *const Session, want: []const u8) !void {
    try expectEqualStrings(want, s.ed.message.text());
}

fn readFile(dir: std.Io.Dir, path: []const u8, buf: []u8) ![]const u8 {
    return dir.readFile(io, path, buf);
}

/// Types `keys` one byte per read, as a person does: a pause follows each.
/// Saves run on while the keys are typed.
fn feedKeys(s: *Session, keys: []const u8) !void {
    for (keys) |*b| {
        try s.feed(b[0..1]);
        try s.timeout();
    }
}

/// As `feedKeys`, then waits for a save they started.
fn typeKeys(s: *Session, keys: []const u8) !void {
    try feedKeys(s, keys);
    s.settle();
}

/// Renders a frame and returns the bytes written. Borrowed from `buf`.
fn frame(s: *Session, buf: []u8) ![]const u8 {
    var w: std.Io.Writer = .fixed(buf);
    try s.render(&w);
    return w.buffered();
}

test "session: an existing file is loaded and shown" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "a.txt", .data = "one\ntwo\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "a.txt", 20, 5);
    defer s.deinit();
    try expectText(&s, "one\ntwo\n");
    try expectMessage(&s, "\"a.txt\" 2 lines");
    try expectEqualStrings("a.txt", s.ed.path.?);
}

test "session: a missing file starts empty under its name" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "new.txt", 20, 5);
    defer s.deinit();
    try expectText(&s, "\n");
    try expectMessage(&s, "\"new.txt\" new file");
    try expectEqualStrings("new.txt", s.ed.path.?);
}

test "session: without a file, a scratch buffer" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try expectText(&s, "\n");
    try expectEqual(null, s.ed.path);
    try expectMessage(&s, "");
}

test "session: a file that cannot be read keeps its name and says why" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(io, "d", .default_dir);
    var s: Session = try .init(gpa, io, tmp.dir, "d", 20, 5);
    defer s.deinit();
    try expectText(&s, "\n");
    try expectEqualStrings("d", s.ed.path.?);
    try expectMessage(&s, "cannot open \"d\": IsDir");
    try typeKeys(&s, ":w\r");
    try expect(std.mem.startsWith(u8, s.ed.message.text(), "cannot write \"d\": "));
    try expect(!s.done());
}

test "session: Ctrl-z is taken once, and the next frame is drawn whole" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 4);
    defer s.deinit();
    var buf: [4096]u8 = undefined;
    _ = try frame(&s, &buf);
    try expect(!s.takeSuspend());
    try s.feed("\x1a");
    try expect(s.takeSuspend());
    try expect(!s.takeSuspend());
    // Nothing changed, so an ordinary frame writes no clear.
    try expect(std.mem.indexOf(u8, try frame(&s, &buf), "\x1b[2J") == null);
    // After a suspend the terminal holds the shell's output.
    s.redrawAll();
    try expect(std.mem.indexOf(u8, try frame(&s, &buf), "\x1b[2J") != null);
}

test "session: typed keys edit, and :w writes the file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "world\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try typeKeys(&s, "ihello \x1b:w\r");
    var buf: [64]u8 = undefined;
    try expectEqualStrings("hello world\n", try readFile(tmp.dir, "f", &buf));
    try expectMessage(&s, "\"f\" written, 1 line");
    try expect(!s.ed.doc.isModified());
    try expect(!s.done());
}

test "session: :wq writes and then quits; keys after it are ignored" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 20, 5);
    defer s.deinit();
    try typeKeys(&s, "ix\x1b:wq\rihello");
    try expect(s.done());
    try expectText(&s, "x\n");
    var buf: [64]u8 = undefined;
    try expectEqualStrings("x\n", try readFile(tmp.dir, "f", &buf));
}

test "session: a failed :wq does not quit" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "missing/f", 20, 5);
    defer s.deinit();
    try typeKeys(&s, "ix\x1b:wq\r");
    try expect(!s.done());
    try expect(std.mem.startsWith(u8, s.ed.message.text(), "cannot write \"missing/f\": "));
    try expect(s.ed.doc.isModified());
}

test "session: :e opens another file" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "g", .data = "gee\n" });
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try typeKeys(&s, ":e g\r");
    try expectText(&s, "gee\n");
    try expectEqualStrings("g", s.ed.path.?);
    try expectMessage(&s, "\"g\" 1 line");
}

test "session: a lone Escape waits for the timeout" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try s.feed("i\x1b");
    try expect(s.waiting());
    try expectEqual(.insert, s.ed.mode);
    try s.timeout();
    try expect(!s.waiting());
    try expectEqual(.normal, s.ed.mode);
    try s.timeout();
    try expectEqual(.normal, s.ed.mode);
}

test "session: a key split across reads is one key" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try typeKeys(&s, "iab\x1b");
    // Escape-[-D is Left: from the line end, where typing left the
    // cursor, to "b".
    try s.feed("\x1b[");
    try expect(s.waiting());
    try s.feed("D");
    try expect(!s.waiting());
    try expectEqual(1, s.ed.doc.primary().cursor);
}

test "session: Escape followed at once by a key is Alt with that key" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    // Alt-k opens the keep prompt; a plain Escape and k would not.
    try s.feed("\x1bk");
    try expectEqual(.prompt, s.ed.mode);
}

test "session: a bracketed paste is inserted as text" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, null, 20, 5);
    defer s.deinit();
    try s.feed("i\x1b[200~a\x1b:q\r\x1b[201~");
    try expectText(&s, "a\x1b:q\n\n");
    try expect(!s.done());
    try expectEqual(.insert, s.ed.mode);
}

test "session: the first frame clears the terminal, an unchanged one writes nothing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "abc\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 12, 3);
    defer s.deinit();
    var buf: [4096]u8 = undefined;
    const first = try frame(&s, &buf);
    try expect(std.mem.indexOf(u8, first, "\x1b[2J") != null);
    // "a" is under the main cursor, in its own style.
    try expect(std.mem.indexOf(u8, first, "bc") != null);
    try expectEqual(0, (try frame(&s, &buf)).len);
}

test "session: a frame after a key writes only what changed" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "abc\n" });
    var s: Session = try .init(gpa, io, tmp.dir, "f", 12, 6);
    defer s.deinit();
    var buf: [4096]u8 = undefined;
    try expect(std.mem.indexOf(u8, try frame(&s, &buf), "~") != null);
    try s.feed("ix");
    const next = try frame(&s, &buf);
    try expect(std.mem.indexOf(u8, next, "\x1b[2J") == null);
    try expect(std.mem.indexOf(u8, next, "x") != null);
    // The empty rows below the text are as they were.
    try expect(std.mem.indexOf(u8, next, "~") == null);
    try expect(std.mem.indexOf(u8, next, "INSERT") != null);
}

test "session: a resize draws the whole screen again at the new size" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 12, 3);
    defer s.deinit();
    var buf: [4096]u8 = undefined;
    _ = try frame(&s, &buf);
    s.resize(20, 4);
    try expectEqual(20, s.ed.width);
    try expectEqual(4, s.ed.height);
    const next = try frame(&s, &buf);
    try expect(std.mem.indexOf(u8, next, "\x1b[2J") != null);
    try expectEqual(20, s.front.width);
    try expectEqual(4, s.front.height);
}

test "session: after a failed write the next frame redraws everything" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 12, 3);
    defer s.deinit();
    var small: [8]u8 = undefined;
    var w: std.Io.Writer = .fixed(&small);
    try std.testing.expectError(error.WriteFailed, s.render(&w));
    var buf: [4096]u8 = undefined;
    const next = try frame(&s, &buf);
    try expect(std.mem.indexOf(u8, next, "\x1b[2J") != null);
}

test "session: a zero-sized terminal renders nothing and does not crash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var s: Session = try .init(gpa, io, tmp.dir, "f", 0, 0);
    defer s.deinit();
    var buf: [256]u8 = undefined;
    _ = try frame(&s, &buf);
    try s.feed("ix");
    _ = try frame(&s, &buf);
    try expectText(&s, "x\n");
}

test "session: init fails cleanly under allocation failure" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "f", .data = "abc\n" });
    const Init = struct {
        fn run(a: std.mem.Allocator, dir: std.Io.Dir) !void {
            var s: Session = try .init(a, io, dir, "f", 12, 3);
            s.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(gpa, Init.run, .{tmp.dir});
}

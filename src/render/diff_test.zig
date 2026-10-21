//! Tests for `diff.zig`: the bytes that turn one screen into the next.

const std = @import("std");
const diff = @import("diff.zig").diff;
const Screen = @import("screen.zig").Screen;

const gpa = std.testing.allocator;

/// The bytes `diff(old, new)` writes. Caller owns the result.
fn bytesOf(old: ?*const Screen, new: *const Screen) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try diff(old, new, &out.writer);
    return out.toOwnedSlice();
}

fn expectDiff(old: ?*const Screen, new: *const Screen, want: []const u8) !void {
    const got = try bytesOf(old, new);
    defer gpa.free(got);
    try std.testing.expectEqualStrings(want, got);
}

test "diff: a first frame clears, then writes only what is not blank" {
    var new: Screen = try .init(gpa, 4, 2);
    defer new.deinit();
    _ = new.text(0, 0, "ab", .{});
    _ = new.text(2, 1, "c", .{});
    try expectDiff(null, &new, "\x1b[?25l\x1b[0m\x1b[2J\x1b[1;1Hab\x1b[2;3Hc");
}

test "diff: an unchanged screen writes nothing" {
    var old: Screen = try .init(gpa, 4, 2);
    defer old.deinit();
    var new: Screen = try .init(gpa, 4, 2);
    defer new.deinit();
    _ = old.text(0, 0, "ab", .{ .bold = true });
    _ = new.text(0, 0, "ab", .{ .bold = true });
    old.cursor = .{ .x = 1, .y = 1 };
    new.cursor = .{ .x = 1, .y = 1 };
    try expectDiff(&old, &new, "");
}

test "diff: changed cells, one cursor move per run" {
    var old: Screen = try .init(gpa, 6, 1);
    defer old.deinit();
    var new: Screen = try .init(gpa, 6, 1);
    defer new.deinit();
    _ = old.text(0, 0, "abcdef", .{});
    _ = new.text(0, 0, "aXYdeZ", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;2H\x1b[0mXY\x1b[1;6HZ");
}

test "diff: the style is set only when it changes, and reset at the end" {
    var old: Screen = try .init(gpa, 4, 1);
    defer old.deinit();
    var new: Screen = try .init(gpa, 4, 1);
    defer new.deinit();
    _ = new.text(0, 0, "ab", .{ .reverse = true });
    _ = new.text(2, 0, "cd", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;1H\x1b[0;7mab\x1b[0mcd");
    var bold: Screen = try .init(gpa, 4, 1);
    defer bold.deinit();
    _ = bold.text(3, 0, "x", .{ .bold = true });
    try expectDiff(&old, &bold, "\x1b[?25l\x1b[1;4H\x1b[0;1mx\x1b[0m");
}

test "diff: a style change alone redraws the cell" {
    var old: Screen = try .init(gpa, 2, 1);
    defer old.deinit();
    var new: Screen = try .init(gpa, 2, 1);
    defer new.deinit();
    new.setStyle(1, 0, .{ .underline = true });
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;2H\x1b[0;4m \x1b[0m");
}

test "diff: a wide character moves the cursor two columns" {
    var old: Screen = try .init(gpa, 5, 1);
    defer old.deinit();
    var new: Screen = try .init(gpa, 5, 1);
    defer new.deinit();
    _ = new.text(0, 0, "中ab", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;1H\x1b[0m中ab");
}

test "diff: a wide character replaced by two narrow ones" {
    var old: Screen = try .init(gpa, 3, 1);
    defer old.deinit();
    var new: Screen = try .init(gpa, 3, 1);
    defer new.deinit();
    _ = old.text(0, 0, "中", .{});
    _ = new.text(0, 0, "ab", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;1H\x1b[0mab");
    try expectDiff(&new, &old, "\x1b[?25l\x1b[1;1H\x1b[0m中");
}

test "diff: after the last column the next row needs a cursor move" {
    var old: Screen = try .init(gpa, 2, 2);
    defer old.deinit();
    var new: Screen = try .init(gpa, 2, 2);
    defer new.deinit();
    _ = new.text(0, 0, "ab", .{});
    _ = new.text(0, 1, "cd", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;1H\x1b[0mab\x1b[2;1Hcd");
}

test "diff: the cursor is placed and shown last" {
    var old: Screen = try .init(gpa, 3, 2);
    defer old.deinit();
    var new: Screen = try .init(gpa, 3, 2);
    defer new.deinit();
    new.cursor = .{ .x = 2, .y = 1 };
    try expectDiff(&old, &new, "\x1b[2;3H\x1b[?25h");
    _ = new.text(0, 0, "x", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[1;1H\x1b[0mx\x1b[2;3H\x1b[?25h");
}

test "diff: a cursor that goes away is hidden" {
    var old: Screen = try .init(gpa, 3, 2);
    defer old.deinit();
    var new: Screen = try .init(gpa, 3, 2);
    defer new.deinit();
    old.cursor = .{ .x = 0, .y = 0 };
    try expectDiff(&old, &new, "\x1b[?25l");
}

test "diff: a new size redraws the whole screen" {
    var old: Screen = try .init(gpa, 3, 1);
    defer old.deinit();
    var new: Screen = try .init(gpa, 4, 1);
    defer new.deinit();
    _ = old.text(0, 0, "abc", .{});
    _ = new.text(0, 0, "abc", .{});
    try expectDiff(&old, &new, "\x1b[?25l\x1b[0m\x1b[2J\x1b[1;1Habc");
}

/// Checks that `bytes` holds no control byte outside the sequences the
/// renderer writes: CSI with digits, `;` and `?`, ending in H, J, m, h or l.
fn expectOnlyOwnSequences(bytes: []const u8) !void {
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const b = bytes[i];
        if (b == 0x1b) {
            try std.testing.expect(i + 1 < bytes.len and bytes[i + 1] == '[');
            i += 2;
            while (i < bytes.len and (std.ascii.isDigit(bytes[i]) or bytes[i] == ';' or bytes[i] == '?')) i += 1;
            try std.testing.expect(i < bytes.len and std.mem.indexOfScalar(u8, "HJmhl", bytes[i]) != null);
        } else {
            try std.testing.expect(b >= 0x20 and b != 0x7f);
        }
    }
}

test "diff: hostile text never reaches the terminal as control bytes" {
    var new: Screen = try .init(gpa, 40, 3);
    defer new.deinit();
    _ = new.text(0, 0, "\x1b]52;c;aGk=\x07\x1b[2J\x9b31m", .{});
    _ = new.text(0, 1, "\u{202e}evil\r\n\x08\x00\xc2\x9b\xff", .{ .bold = true });
    var prng: std.Random.DefaultPrng = .init(0x5eed);
    var noise: [40]u8 = undefined;
    prng.random().bytes(&noise);
    _ = new.text(0, 2, &noise, .{});
    const got = try bytesOf(null, &new);
    defer gpa.free(got);
    try expectOnlyOwnSequences(got);
}

test "diff: write errors are returned" {
    var new: Screen = try .init(gpa, 4, 1);
    defer new.deinit();
    _ = new.text(0, 0, "abcd", .{});
    var buf: [8]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try std.testing.expectError(error.WriteFailed, diff(null, &new, &w));
}

//! Tests for `form.zig`: a file's byte order mark, line ends and missing
//! final newline taken off on load and put back on save, byte for byte.

const std = @import("std");
const form = @import("form.zig");

const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Decodes a copy of `bytes`, expecting `text` in `want` form.
fn expectDecode(text: []const u8, want: form.Form, bytes: []const u8) !void {
    const copy = try gpa.dupe(u8, bytes);
    defer gpa.free(copy);
    const got = form.decode(copy);
    try expectEqualStrings(text, got.text);
    try expectEqual(want, got.form);
}

fn expectEncode(want: []const u8, text: []const u8, f: form.Form) !void {
    const got = try form.encode(gpa, text, f);
    defer gpa.free(got);
    try expectEqualStrings(want, got);
}

test "form: a plain file is its own text" {
    try expectDecode("a\nb\n", .{}, "a\nb\n");
    try expectDecode("", .{}, "");
    try expectEqual(form.Form{ .ending = .lf, .bom = false }, form.Form{});
}

test "form: a byte order mark at the start is taken off and remembered" {
    try expectDecode("a\n", .{ .bom = true }, "\xef\xbb\xbfa\n");
    try expectDecode("", .{ .bom = true }, "\xef\xbb\xbf");
    try expectDecode("\n", .{ .bom = true }, "\xef\xbb\xbf\n");
}

test "form: a byte order mark with CRLF line ends takes off both" {
    try expectDecode("a\nb\n", .{ .ending = .crlf, .bom = true }, "\xef\xbb\xbfa\r\nb\r\n");
    try expectDecode("a\nb\n", .{ .ending = .crlf }, "a\r\nb\r\n");
}

test "form: only a whole mark at the very start counts" {
    // Cut short, it is two bytes of text (shown as invalid UTF-8).
    try expectDecode("\xef\xbb", .{ .final_newline = false }, "\xef\xbb");
    try expectDecode("\xef\xbba\n", .{}, "\xef\xbba\n");
    try expectDecode("a\xef\xbb\xbf\n", .{}, "a\xef\xbb\xbf\n");
    // A second mark is text, kept.
    try expectDecode("\xef\xbb\xbfa\n", .{ .bom = true }, "\xef\xbb\xbf\xef\xbb\xbfa\n");
}

test "form: a file whose last line has no line end is remembered" {
    try expectDecode("a\nb", .{ .final_newline = false }, "a\nb");
    try expectDecode("a", .{ .final_newline = false }, "a");
    try expectDecode("a\nb", .{ .ending = .crlf, .final_newline = false }, "a\r\nb");
    try expectDecode("a", .{ .bom = true, .final_newline = false }, "\xef\xbb\xbfa");
}

test "form: an empty file, or one with only a mark, has no last line to end" {
    try expectDecode("", .{}, "");
    try expectDecode("", .{ .bom = true }, "\xef\xbb\xbf");
}

test "form: a carriage return ending a CRLF file is text, its line has no end" {
    try expectDecode("a\nb\r", .{ .ending = .crlf, .final_newline = false }, "a\r\nb\r");
}

test "form: decode works in place, inside its input" {
    var bytes = "\xef\xbb\xbfa\r\n".*;
    const got = form.decode(&bytes);
    try expect(@intFromPtr(got.text.ptr) >= @intFromPtr(&bytes));
    try expect(@intFromPtr(got.text.ptr) + got.text.len <= @intFromPtr(&bytes) + bytes.len);
    try expectEqualStrings("a\n", got.text);
}

test "form: encode puts back the mark and the line ends" {
    try expectEncode("a\n", "a\n", .{});
    try expectEncode("\xef\xbb\xbfa\n", "a\n", .{ .bom = true });
    try expectEncode("\xef\xbb\xbfa\r\n\r\n", "a\n\n", .{ .ending = .crlf, .bom = true });
    try expectEncode("a\r\n", "a\n", .{ .ending = .crlf });
    try expectEncode("\xef\xbb\xbf", "", .{ .bom = true });
}

test "form: encode drops the buffer's final newline when the file had none" {
    try expectEncode("a\nb", "a\nb\n", .{ .final_newline = false });
    try expectEncode("", "\n", .{ .final_newline = false });
    try expectEncode("a\n", "a\n\n", .{ .final_newline = false });
    try expectEncode("\xef\xbb\xbfa\r\nb", "a\nb\n", .{ .ending = .crlf, .bom = true, .final_newline = false });
    try expectEncode("\xef\xbb\xbf", "\n", .{ .bom = true, .final_newline = false });
}

test "form: every file round-trips byte for byte" {
    const files = [_][]const u8{
        "a\nb\n",
        "\xef\xbb\xbfa\n",
        "\xef\xbb\xbfa\r\nb\r\n",
        "\xef\xbb\xbf\xef\xbb\xbf\r\n",
        "\xef\xbbx\r\n",
        "a\r\nb\n",
        "\xef\xbb\xbfa\r\nb\n",
        "a\nb",
        "a\r\nb",
        "a\r\nb\r",
        "\xef\xbb\xbfa\r\nb",
        "a\r\nb\n\r",
    };
    for (files) |file| {
        const copy = try gpa.dupe(u8, file);
        defer gpa.free(copy);
        const got = form.decode(copy);
        try expectEncode(file, got.text, got.form);
        // As the buffer holds it, with a newline added where none ends it.
        const held = try std.mem.concat(gpa, u8, &.{ got.text, "\n" });
        defer gpa.free(held);
        const text = if (std.mem.endsWith(u8, got.text, "\n")) got.text else held;
        try expectEncode(file, text, got.form);
    }
}

test "form: encoding that cannot allocate leaks nothing" {
    const T = struct {
        fn run(a: std.mem.Allocator, f: form.Form) !void {
            const got = try form.encode(a, "a\nb\n", f);
            a.free(got);
        }
    };
    const forms = [_]form.Form{
        .{},
        .{ .bom = true },
        .{ .ending = .crlf },
        .{ .ending = .crlf, .bom = true },
        .{ .ending = .crlf, .bom = true, .final_newline = false },
    };
    for (forms) |f| try std.testing.checkAllAllocationFailures(gpa, T.run, .{f});
}

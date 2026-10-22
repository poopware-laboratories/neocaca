//! Tests for `screen.zig`: writing text into the cell grid.

const std = @import("std");
const screen_mod = @import("screen.zig");
const Style = @import("style.zig").Style;

const Screen = screen_mod.Screen;
const gpa = std.testing.allocator;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

/// Row `y` as text: wide characters once, continuation cells skipped.
fn row(s: *const Screen, y: usize, buf: []u8) []const u8 {
    var n: usize = 0;
    for (0..s.width) |x| {
        const c = s.at(x, y);
        @memcpy(buf[n..][0..c.text().len], c.text());
        n += c.text().len;
    }
    return buf[0..n];
}

fn expectRow(s: *const Screen, y: usize, want: []const u8) !void {
    var buf: [256]u8 = undefined;
    try expectEqualStrings(want, row(s, y, &buf));
}

test "screen: a new screen is blank" {
    var s: Screen = try .init(gpa, 4, 2);
    defer s.deinit();
    try expectRow(&s, 0, "    ");
    try expectRow(&s, 1, "    ");
    try expectEqual(1, s.at(3, 1).width);
    try std.testing.expect(s.at(0, 0).style.eql(.{}));
    try expectEqual(null, s.cursor);
}

test "screen: text fills cells and returns the columns used" {
    var s: Screen = try .init(gpa, 6, 1);
    defer s.deinit();
    try expectEqual(3, s.text(1, 0, "abc", .{ .bold = true }));
    try expectRow(&s, 0, " abc  ");
    try std.testing.expect(s.at(2, 0).style.bold);
    try std.testing.expect(!s.at(4, 0).style.bold);
}

test "screen: text is cut at the right edge" {
    var s: Screen = try .init(gpa, 4, 1);
    defer s.deinit();
    try expectEqual(2, s.text(2, 0, "abcdef", .{}));
    try expectRow(&s, 0, "  ab");
    try expectEqual(0, s.text(4, 0, "x", .{}));
    try expectEqual(0, s.text(0, 1, "x", .{})); // below the screen
}

test "screen: text stops at a limit column" {
    var s: Screen = try .init(gpa, 8, 1);
    defer s.deinit();
    try expectEqual(3, s.textUntil(1, 0, "abcdef", .{}, 4));
    try expectRow(&s, 0, " abc    ");
}

test "screen: a wide character takes two cells" {
    var s: Screen = try .init(gpa, 5, 1);
    defer s.deinit();
    try expectEqual(5, s.text(0, 0, "中a文", .{}));
    try expectRow(&s, 0, "中a文");
    try expectEqual(2, s.at(0, 0).width);
    try expectEqual(0, s.at(1, 0).width);
    try expectEqual(1, s.at(2, 0).width);
}

test "screen: a wide character that does not fit leaves a space" {
    var s: Screen = try .init(gpa, 3, 1);
    defer s.deinit();
    try expectEqual(3, s.text(0, 0, "ab中", .{}));
    try expectRow(&s, 0, "ab ");
    try expectEqual(1, s.at(2, 0).width);
}

test "screen: combining marks stay with their character" {
    var s: Screen = try .init(gpa, 3, 1);
    defer s.deinit();
    try expectEqual(2, s.text(0, 0, "e\u{301}x", .{}));
    try expectEqualStrings("e\u{301}", s.at(0, 0).text());
    try expectEqualStrings("x", s.at(1, 0).text());
}

test "screen: a character with too many marks becomes a replacement" {
    var s: Screen = try .init(gpa, 2, 1);
    defer s.deinit();
    var many: [42]u8 = undefined;
    many[0] = 'a';
    for (0..20) |i| many[1 + 2 * i ..][0..2].* = "\u{301}".*;
    many[41] = 'b';
    try expectEqual(2, s.text(0, 0, &many, .{}));
    try expectEqualStrings("\u{fffd}", s.at(0, 0).text());
    try expectEqualStrings("b", s.at(1, 0).text());
}

test "screen: control characters are drawn in caret form" {
    var s: Screen = try .init(gpa, 8, 1);
    defer s.deinit();
    try expectEqual(7, s.text(0, 0, "a\x1b\x00\x7f", .{}));
    try expectRow(&s, 0, "a^[^@^? ");
}

test "screen: invalid bytes, C1 controls and bidi overrides become replacements" {
    var s: Screen = try .init(gpa, 6, 1);
    defer s.deinit();
    try expectEqual(4, s.text(0, 0, "\xff\u{9b}\u{202e}z", .{}));
    try expectRow(&s, 0, "\u{fffd}\u{fffd}\u{fffd}z  ");
}

test "screen: a tab in text is one space" {
    var s: Screen = try .init(gpa, 4, 1);
    defer s.deinit();
    try expectEqual(3, s.text(0, 0, "a\tb", .{}));
    try expectRow(&s, 0, "a b ");
}

test "screen: overwriting half of a wide character blanks the other half" {
    var s: Screen = try .init(gpa, 4, 1);
    defer s.deinit();
    _ = s.text(0, 0, "中文", .{});
    _ = s.text(1, 0, "x", .{});
    try expectRow(&s, 0, " x文");
    _ = s.text(2, 0, "y", .{});
    try expectRow(&s, 0, " xy ");
    try expectEqual(1, s.at(3, 0).width);
}

test "screen: a wide character over a wide character's second half" {
    var s: Screen = try .init(gpa, 4, 1);
    defer s.deinit();
    _ = s.text(0, 0, "中文", .{});
    _ = s.text(1, 0, "字", .{});
    try expectRow(&s, 0, " 字 ");
}

test "screen: fill paints a run of cells" {
    var s: Screen = try .init(gpa, 5, 2);
    defer s.deinit();
    _ = s.text(0, 1, "中abc", .{});
    s.fill(1, 1, 3, ' ', .{ .reverse = true });
    try expectRow(&s, 1, "    c");
    try std.testing.expect(s.at(1, 1).style.reverse);
    try std.testing.expect(s.at(3, 1).style.reverse);
    try std.testing.expect(!s.at(4, 1).style.reverse);
    s.fill(3, 0, 10, '-', .{});
    try expectRow(&s, 0, "   --");
}

test "screen: clear blanks every cell and hides the cursor" {
    var s: Screen = try .init(gpa, 3, 2);
    defer s.deinit();
    _ = s.text(0, 0, "abc", .{ .bold = true });
    s.cursor = .{ .x = 1, .y = 1 };
    s.clear();
    try expectRow(&s, 0, "   ");
    try std.testing.expect(!s.at(0, 0).style.bold);
    try expectEqual(null, s.cursor);
}

test "screen: setStyle restyles cells and keeps their text" {
    var s: Screen = try .init(gpa, 3, 1);
    defer s.deinit();
    _ = s.text(0, 0, "abc", .{});
    s.setStyle(1, 0, .{ .reverse = true });
    try expectRow(&s, 0, "abc");
    try std.testing.expect(s.at(1, 0).style.reverse);
    try std.testing.expect(!s.at(0, 0).style.reverse);
}

test "screen: setStyle on half of a wide character styles both halves" {
    var s: Screen = try .init(gpa, 3, 1);
    defer s.deinit();
    _ = s.text(0, 0, "中", .{});
    s.setStyle(1, 0, .{ .reverse = true });
    try std.testing.expect(s.at(0, 0).style.reverse);
    try std.testing.expect(s.at(1, 0).style.reverse);
}

test "screen: resize keeps nothing and blanks the new grid" {
    var s: Screen = try .init(gpa, 2, 2);
    defer s.deinit();
    _ = s.text(0, 0, "ab", .{});
    try s.resize(5, 3);
    try expectEqual(5, s.width);
    try expectEqual(3, s.height);
    try expectRow(&s, 2, "     ");
    try expectRow(&s, 0, "     ");
}

test "screen: a zero-sized screen accepts every call" {
    var s: Screen = try .init(gpa, 0, 0);
    defer s.deinit();
    try expectEqual(0, s.text(0, 0, "abc", .{}));
    s.fill(0, 0, 3, ' ', .{});
    s.clear();
}

test "screen: resize fails cleanly when allocation fails" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{ .fail_index = 1 });
    var s: Screen = try .init(failing.allocator(), 2, 1);
    defer s.deinit();
    _ = s.text(0, 0, "ab", .{});
    try std.testing.expectError(error.OutOfMemory, s.resize(100, 100));
    try expectEqual(2, s.width);
    try expectRow(&s, 0, "ab");
}

test "screen: fitWithin takes the largest size its cells allow, without memory" {
    var failing: std.testing.FailingAllocator = .init(gpa, .{ .fail_index = 1 });
    var s: Screen = try .init(failing.allocator(), 4, 3);
    defer s.deinit();
    _ = s.text(0, 0, "abcd", .{});
    _ = s.text(0, 2, "wxyz", .{});
    s.cursor = .{ .x = 1, .y = 1 };
    // Smaller: exactly that size, blank.
    s.fitWithin(3, 2);
    try expectEqual(3, s.width);
    try expectEqual(2, s.height);
    try expectRow(&s, 0, "   ");
    try expectRow(&s, 1, "   ");
    try expectEqual(null, s.cursor);
    _ = s.text(0, 1, "xyz", .{});
    try expectRow(&s, 1, "xyz");
    // Narrower and taller than the 12 cells: every column, then the rows.
    s.fitWithin(2, 20);
    try expectEqual(2, s.width);
    try expectEqual(6, s.height);
    try expectRow(&s, 5, "  ");
    // Wider: no more columns than cells, one row.
    s.fitWithin(50, 3);
    try expectEqual(12, s.width);
    try expectEqual(1, s.height);
    // Each side stays within what was asked.
    s.fitWithin(5, 5);
    try expectEqual(5, s.width);
    try expectEqual(2, s.height);
    s.fitWithin(0, 7);
    try expectEqual(0, s.width);
    try expectEqual(0, s.cells.len);
    // Its cells are still all there for a later resize.
    s.fitWithin(4, 3);
    try expectRow(&s, 2, "    ");
    try std.testing.expectError(error.OutOfMemory, s.resize(5, 3));
    try expectEqual(4, s.width);
}

test "screen: a huge size is refused" {
    try std.testing.expectError(error.OutOfMemory, Screen.init(gpa, screen_mod.max_side + 1, 1));
    // Each side within bounds, but too many cells in all.
    try std.testing.expectError(error.OutOfMemory, Screen.init(gpa, screen_mod.max_side, screen_mod.max_side));
    const tall = screen_mod.max_cells / screen_mod.max_side;
    try std.testing.expectError(error.OutOfMemory, Screen.init(gpa, screen_mod.max_side, tall + 1));
}

test "screen: fit keeps a size that is allowed" {
    try expectEqual(screen_mod.Size{ .width = 80, .height = 24 }, screen_mod.fit(80, 24));
    try expectEqual(screen_mod.Size{ .width = 0, .height = 0 }, screen_mod.fit(0, 0));
    try expectEqual(screen_mod.Size{ .width = 0, .height = 50 }, screen_mod.fit(0, 50));
    const tall = screen_mod.max_cells / screen_mod.max_side;
    try expectEqual(screen_mod.Size{ .width = screen_mod.max_side, .height = tall }, screen_mod.fit(screen_mod.max_side, tall));
}

test "screen: fit cuts a huge size to every column it may and the rows that fit" {
    const max = screen_mod.max_side;
    try expectEqual(screen_mod.Size{ .width = max, .height = 1 }, screen_mod.fit(max + 1, 1));
    try expectEqual(screen_mod.Size{ .width = 1, .height = max }, screen_mod.fit(1, max + 1));
    try expectEqual(screen_mod.Size{ .width = max, .height = screen_mod.max_cells / max }, screen_mod.fit(100_000, 100_000));
    try expectEqual(screen_mod.Size{ .width = 1000, .height = screen_mod.max_cells / 1000 }, screen_mod.fit(1000, 4000));
    try expectEqual(screen_mod.Size{ .width = 1, .height = max }, screen_mod.fit(1, std.math.maxInt(usize)));
    // Whatever comes in, the screen it gives can be made.
    for ([_][2]usize{ .{ max, max }, .{ 3000, 3000 }, .{ 1, std.math.maxInt(usize) }, .{ 999, 1050 } }) |wh| {
        const f = screen_mod.fit(wh[0], wh[1]);
        try std.testing.expect(f.width <= wh[0] and f.height <= wh[1]);
        try std.testing.expect(f.width * f.height <= screen_mod.max_cells);
    }
}

test "screen: a caret pair cut at the edge keeps its caret" {
    var s: Screen = try .init(gpa, 2, 1);
    defer s.deinit();
    try expectEqual(2, s.text(0, 0, "a\x01", .{}));
    try expectRow(&s, 0, "a^");
}

test "screen: the columns text takes, in every form a character is drawn in" {
    // Plain, tab (one space), wide, caret (two), invalid byte (one).
    try std.testing.expectEqual(7, screen_mod.textColumns("a\tあ\x1b\xff"));
    try std.testing.expectEqual(0, screen_mod.textColumns(""));
    try std.testing.expectEqual(2, screen_mod.charColumns("x\x7f", 1));
    var s: Screen = try .init(std.testing.allocator, 20, 1);
    defer s.deinit();
    const str = "a\tあ\x1b\xff";
    try std.testing.expectEqual(screen_mod.textColumns(str), s.text(0, 0, str, .{}));
}

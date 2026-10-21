//! Test support: documents written with their selections marked, so a test
//! reads like the screen a user sees. `«…»` is the main selection, `‹…›`
//! any other; a `|` right after the opening mark puts the cursor on the
//! first character (a backward selection), otherwise the cursor is on the
//! last one. `"a «foo» ‹|bar›\n"` holds two selections.

const std = @import("std");
const unicode = @import("../unicode.zig");
const Document = @import("document.zig").Document;
const Selection = @import("selection.zig").Selection;

const gpa = std.testing.allocator;

const main_open = "«";
const main_close = "»";
const open = "‹";
const close = "›";

/// A document holding `spec` without its marks, with its selections. The
/// caller owns it.
fn closed(text: []const u8, start: usize, backward: bool) Selection {
    const last = unicode.chars.prev(text, text.len);
    return if (backward) .span(last, start) else .span(start, last);
}

pub fn doc(marked: []const u8) !Document {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(gpa);
    var sels: std.ArrayList(Selection) = .empty;
    defer sels.deinit(gpa);
    var main: usize = 0;
    var start: ?usize = null;
    var backward = false;
    var i: usize = 0;
    while (i < marked.len) {
        const rest = marked[i..];
        const is_main = std.mem.startsWith(u8, rest, main_open);
        if (is_main or std.mem.startsWith(u8, rest, open)) {
            if (is_main) main = sels.items.len;
            i += if (is_main) main_open.len else open.len;
            start = text.items.len;
            backward = i < marked.len and marked[i] == '|';
            if (backward) i += 1;
        } else if (std.mem.startsWith(u8, rest, main_close)) {
            i += main_close.len;
            try sels.append(gpa, closed(text.items, start.?, backward));
            start = null;
        } else if (std.mem.startsWith(u8, rest, close)) {
            i += close.len;
            try sels.append(gpa, closed(text.items, start.?, backward));
            start = null;
        } else {
            try text.append(gpa, marked[i]);
            i += 1;
        }
    }
    var d: Document = try .init(gpa, text.items);
    errdefer d.deinit();
    if (sels.items.len > 0) try d.select(sels.items, main);
    return d;
}

/// `d` written back as a spec. The caller owns the result.
pub fn spec(d: *const Document) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    const text = d.text();
    var k: usize = 0;
    const list = d.sels();
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (k > 0 and list[k - 1].range(text).end == i) {
            try out.appendSlice(gpa, if (k - 1 == d.selections.main) main_close else close);
        }
        if (k < list.len and list[k].min() == i) {
            try out.appendSlice(gpa, if (k == d.selections.main) main_open else open);
            if (list[k].cursor < list[k].anchor) try out.append(gpa, '|');
            k += 1;
        }
        if (i < text.len) try out.append(gpa, text[i]);
    }
    return out.toOwnedSlice(gpa);
}

pub fn expectDoc(d: *const Document, want: []const u8) !void {
    const got = try spec(d);
    defer gpa.free(got);
    try std.testing.expectEqualStrings(want, got);
}

test "fixture: specs round-trip" {
    inline for (.{
        "«a»\n",
        "a «foo» ‹|bar›\n",
        "‹x›«|中文»\n‹\n›",
        "«|ab\ncd\n»",
    }) |s| {
        var d = try doc(s);
        defer d.deinit();
        try expectDoc(&d, s);
    }
}

test "fixture: marks set the text, anchors, cursors and the main one" {
    var d = try doc("a ‹foo› «|bar»\n");
    defer d.deinit();
    try std.testing.expectEqualStrings("a foo bar\n", d.text());
    try std.testing.expectEqual(Selection.span(2, 4), d.sels()[0]);
    try std.testing.expectEqual(Selection.span(8, 6), d.sels()[1]);
    try std.testing.expectEqual(1, d.selections.main);
}

test "fixture: without marks the selection is on the first character" {
    var d = try doc("ab\n");
    defer d.deinit();
    try expectDoc(&d, "«a»b\n");
}

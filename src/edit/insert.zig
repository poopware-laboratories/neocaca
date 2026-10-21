//! Insert mode: where each selection's cursor goes on entering it, and the
//! keys typed there, applied at every cursor. A cursor is a one-character
//! selection; typed text goes in front of its character. The caller wraps
//! the whole visit in `Document.beginSession`/`endSession` so it undoes as
//! one step.

const std = @import("std");
const unicode = @import("../unicode.zig");
const buffer = @import("../buffer.zig");
const document = @import("document.zig");
const motion = @import("motion.zig");
const Selection = @import("selection.zig").Selection;

const Change = buffer.Change;
const Document = document.Document;
const chars = unicode.chars;

pub const Error = document.Error;

pub const Where = enum {
    /// `i`: before each selection.
    before,
    /// `a`: after each selection.
    after,
    /// `I`: at the first non-blank of its first line.
    line_start,
    /// `A`: at the end of its last line.
    line_end,
    /// `o`: on a new line below its last line, with that line's indent.
    below,
    /// `O`: on a new line above its first line, with that line's indent.
    above,
};

/// One selection's replacement: `[start, end)` becomes `text`, and the
/// cursor goes `cursor` bytes into it. `dup` repeats the previous plan
/// (two cursors that open the same line).
const Plan = struct { start: usize, end: usize, text: []const u8, cursor: usize, dup: bool = false };

/// Applies one plan per selection as one revision; plans that change
/// nothing still place their cursor.
fn applyPlans(doc: *Document, plans: []const Plan) Error!void {
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    try changes.ensureTotalCapacity(doc.gpa, plans.len);
    const new = try doc.gpa.alloc(Selection, plans.len);
    defer doc.gpa.free(new);
    var delta: isize = 0;
    for (plans, new, 0..) |p, *n, i| {
        if (p.dup) {
            n.* = new[i - 1];
            continue;
        }
        const start: usize = @intCast(@as(isize, @intCast(p.start)) + delta);
        n.* = .at(start + p.cursor);
        if (p.start == p.end and p.text.len == 0) continue;
        changes.appendAssumeCapacity(.{ .start = p.start, .end = p.end, .text = p.text });
        delta += @as(isize, @intCast(p.text.len)) - @as(isize, @intCast(p.end - p.start));
    }
    try doc.edit(changes.items, new, doc.selections.main);
}

/// Moves each selection to where `where` inserts, opening lines for `o`
/// and `O`.
pub fn enter(doc: *Document, where: Where) Error!void {
    if (where == .below or where == .above) return open(doc, where == .above);
    const buf = &doc.buffer;
    const new = try doc.gpa.alloc(Selection, doc.sels().len);
    defer doc.gpa.free(new);
    for (doc.sels(), new) |s, *n| {
        const r = s.range(doc.text());
        n.* = .at(switch (where) {
            .before => r.start,
            .after => @min(r.end, buf.len() - 1),
            .line_start => motion.firstNonBlank(buf, s.min()),
            else => motion.lineEnd(buf, s.max()),
        });
    }
    try doc.select(new, doc.selections.main);
}

/// The blanks a line starts with, up to `limit` bytes.
fn indentOf(line: []const u8, limit: usize) []const u8 {
    var k: usize = 0;
    while (k < @min(line.len, limit) and (line[k] == ' ' or line[k] == '\t')) k += 1;
    return line[0..k];
}

fn open(doc: *Document, above: bool) Error!void {
    const buf = &doc.buffer;
    const list = doc.sels();
    var storage: std.ArrayList(u8) = .empty;
    defer storage.deinit(doc.gpa);
    var size: usize = 0;
    for (list) |s| size += 1 + indentOf(buf.line(buf.lineOf(if (above) s.min() else s.max())), std.math.maxInt(usize)).len;
    try storage.ensureTotalCapacity(doc.gpa, size);
    const plans = try doc.gpa.alloc(Plan, list.len);
    defer doc.gpa.free(plans);
    var last: ?usize = null;
    for (list, plans) |s, *p| {
        const n = buf.lineOf(if (above) s.min() else s.max());
        if (last == n) {
            p.* = .{ .start = 0, .end = 0, .text = "", .cursor = 0, .dup = true };
            continue;
        }
        last = n;
        const indent = indentOf(buf.line(n), std.math.maxInt(usize));
        const from = storage.items.len;
        if (above) {
            storage.appendSliceAssumeCapacity(indent);
            storage.appendAssumeCapacity('\n');
            const at = buf.lineStart(n);
            p.* = .{ .start = at, .end = at, .text = storage.items[from..], .cursor = indent.len };
        } else {
            storage.appendAssumeCapacity('\n');
            storage.appendSliceAssumeCapacity(indent);
            const at = buf.lineEnd(n);
            p.* = .{ .start = at, .end = at, .text = storage.items[from..], .cursor = 1 + indent.len };
        }
    }
    try applyPlans(doc, plans);
}

/// Types `bytes` in front of every cursor.
pub fn text(doc: *Document, bytes: []const u8) Error!void {
    const plans = try doc.gpa.alloc(Plan, doc.sels().len);
    defer doc.gpa.free(plans);
    for (doc.sels(), plans) |s, *p| p.* = .{ .start = s.cursor, .end = s.cursor, .text = bytes, .cursor = bytes.len };
    try applyPlans(doc, plans);
}

/// Enter: breaks the line at every cursor; the new line starts with the
/// blanks the old one had before the cursor.
pub fn newline(doc: *Document) Error!void {
    const buf = &doc.buffer;
    const list = doc.sels();
    var size: usize = 0;
    for (list) |s| {
        const start = motion.lineStart(buf, s.cursor);
        size += 1 + indentOf(buf.line(buf.lineOf(s.cursor)), s.cursor - start).len;
    }
    var storage: std.ArrayList(u8) = .empty;
    defer storage.deinit(doc.gpa);
    try storage.ensureTotalCapacity(doc.gpa, size);
    const plans = try doc.gpa.alloc(Plan, list.len);
    defer doc.gpa.free(plans);
    for (list, plans) |s, *p| {
        const start = motion.lineStart(buf, s.cursor);
        const indent = indentOf(buf.line(buf.lineOf(s.cursor)), s.cursor - start);
        const from = storage.items.len;
        storage.appendAssumeCapacity('\n');
        storage.appendSliceAssumeCapacity(indent);
        p.* = .{ .start = s.cursor, .end = s.cursor, .text = storage.items[from..], .cursor = 1 + indent.len };
    }
    try applyPlans(doc, plans);
}

/// Backspace: deletes the character before every cursor.
pub fn backspace(doc: *Document) Error!void {
    const plans = try doc.gpa.alloc(Plan, doc.sels().len);
    defer doc.gpa.free(plans);
    for (doc.sels(), plans) |s, *p| {
        const start = if (s.cursor > 0) chars.prev(doc.text(), s.cursor) else 0;
        p.* = .{ .start = start, .end = s.cursor, .text = "", .cursor = 0 };
    }
    try applyPlans(doc, plans);
}

/// Delete: deletes the character under every cursor, except the final
/// newline.
pub fn deleteForward(doc: *Document) Error!void {
    const t = doc.text();
    const plans = try doc.gpa.alloc(Plan, doc.sels().len);
    defer doc.gpa.free(plans);
    for (doc.sels(), plans) |s, *p| {
        const end = if (s.cursor + 1 < t.len) chars.next(t, s.cursor) else s.cursor;
        p.* = .{ .start = s.cursor, .end = end, .text = "", .cursor = 0 };
    }
    try applyPlans(doc, plans);
}

/// Pasted text with `\r\n` and lone `\r` line ends turned into `\n`, as
/// terminals send Enter in a paste as `\r`. Caller owns the result.
pub fn normalizePaste(gpa: std.mem.Allocator, bytes: []const u8) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = try .initCapacity(gpa, bytes.len);
    errdefer out.deinit(gpa);
    for (bytes, 0..) |b, i| {
        if (b == '\r' and i + 1 < bytes.len and bytes[i + 1] == '\n') continue;
        out.appendAssumeCapacity(if (b == '\r') '\n' else b);
    }
    return out.toOwnedSlice(gpa);
}

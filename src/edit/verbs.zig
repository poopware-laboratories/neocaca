//! Verbs: what acts on the selected text. Yank, delete, paste, replace,
//! case, indentation and joining apply to every selection at once as one
//! undoable change set; none of them ever removes the final newline.

const std = @import("std");
const unicode = @import("../unicode.zig");
const buffer = @import("../buffer.zig");
const document = @import("document.zig");
const Registers = @import("registers.zig").Registers;
const Selection = @import("selection.zig").Selection;

const Change = buffer.Change;
const Document = document.Document;
const chars = unicode.chars;

pub const Error = document.Error;

/// Applies `changes` and keeps every selection on the same text, mapped
/// past insertions at its ends.
fn applyMapped(doc: *Document, changes: []const Change) Error!void {
    const new = try doc.gpa.alloc(Selection, doc.sels().len);
    defer doc.gpa.free(new);
    // Sorted selections: anchors and cursors each come in order.
    var anchors: buffer.change.Mapper = .init(changes);
    var cursors: buffer.change.Mapper = .init(changes);
    for (doc.sels(), new) |s, *n| n.* = .span(anchors.map(s.anchor, .after), cursors.map(s.cursor, .after));
    try doc.edit(changes, new, doc.selections.main);
}

/// `y`: stores the text of every selection in register `reg`.
pub fn yank(doc: *const Document, regs: *Registers, reg: u8) error{OutOfMemory}!void {
    const text = doc.text();
    const strings = try doc.gpa.alloc([]const u8, doc.sels().len);
    defer doc.gpa.free(strings);
    for (doc.sels(), strings) |s, *str| {
        const r = s.range(text);
        str.* = text[r.start..r.end];
    }
    try regs.set(reg, strings);
}

/// `d` (and `Alt-d` without `regs`): yanks, then deletes the selections,
/// leaving a cursor where each one started. Whole last lines go with the
/// newline before them, as the final newline stays.
pub fn delete(doc: *Document, regs: ?*Registers, reg: u8) Error!void {
    return remove(doc, regs, reg, true);
}

/// The deleting half of `c`: as `delete`, but whole last lines leave an
/// empty line to type into.
pub fn deleteToChange(doc: *Document, regs: ?*Registers, reg: u8) Error!void {
    return remove(doc, regs, reg, false);
}

fn remove(doc: *Document, regs: ?*Registers, reg: u8, last_lines: bool) Error!void {
    if (regs) |r| try yank(doc, r, reg);
    const text = doc.text();
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    var new: std.ArrayList(Selection) = .empty;
    defer new.deinit(doc.gpa);
    try changes.ensureTotalCapacity(doc.gpa, doc.sels().len);
    try new.ensureTotalCapacity(doc.gpa, doc.sels().len);
    for (doc.sels()) |s| {
        const r = s.range(text);
        var start = r.start;
        if (last_lines and r.end == text.len) {
            // The newline before the deletions that end here, run
            // together, unless one of them already takes it.
            var k = changes.items.len;
            var first = start;
            while (k > 0 and changes.items[k - 1].end == first) {
                k -= 1;
                first = changes.items[k].start;
            }
            if (first > 0 and text[first - 1] == '\n') {
                if (k < changes.items.len) changes.items[k].start -= 1 else start -= 1;
            }
        }
        const end = @min(r.end, text.len - 1);
        new.appendAssumeCapacity(.at(r.start));
        if (end <= start) continue;
        changes.appendAssumeCapacity(.{ .start = start, .end = end, .text = "" });
    }
    var m: buffer.change.Mapper = .init(changes.items);
    for (new.items) |*n| n.* = .at(m.map(n.cursor, .before));
    try doc.edit(changes.items, new.items, doc.selections.main);
}

fn linewise(value: []const u8) bool {
    return value.len > 0 and value[value.len - 1] == '\n';
}

/// The selection over `value` inserted at `start` of the new text.
fn over(start: usize, value: []const u8) Selection {
    return .span(start, start + chars.prev(value, value.len));
}

/// `p` and `P` (`before`): pastes register `reg` after (or before) each
/// selection, the `i`th value at the `i`th selection (the last value at
/// the rest), and selects what was pasted. Values ending in a newline go
/// on the line below (or above). False when the register is empty.
pub fn paste(doc: *Document, regs: *const Registers, reg: u8, before: bool) Error!bool {
    const values = regs.get(reg);
    if (values.len == 0) return false;
    const buf = &doc.buffer;
    const text = doc.text();
    const list = doc.sels();
    const new = try doc.gpa.alloc(Selection, list.len);
    defer doc.gpa.free(new);
    var pastes: std.ArrayList(Paste) = .empty;
    defer pastes.deinit(doc.gpa);
    try pastes.ensureTotalCapacity(doc.gpa, list.len);
    for (list, 0..) |s, i| {
        const v = values[@min(i, values.len - 1)];
        if (v.len == 0) continue;
        const r = s.range(text);
        const at = if (linewise(v))
            (if (before) buf.lineStart(buf.lineOf(r.start)) else buf.lineEnd(buf.lineOf(r.end - 1)) + 1)
        else if (before) r.start else @min(r.end, text.len - 1);
        pastes.appendAssumeCapacity(.{ .change = .{ .start = at, .end = at, .text = v }, .owner = i });
    }
    // A line pasted below an earlier selection can land after a word
    // pasted for a later one. Stable: pastes at one offset keep their
    // selections' order, except that a line goes before a word.
    std.sort.block(Paste, pastes.items, {}, Paste.before);
    const changes = try doc.gpa.alloc(Change, pastes.items.len);
    defer doc.gpa.free(changes);
    var added: usize = 0;
    for (pastes.items, changes) |p, *c| {
        c.* = p.change;
        new[p.owner] = over(p.change.start + added, p.change.text);
        added += p.change.text.len;
    }
    var anchors: buffer.change.Mapper = .init(changes);
    var cursors: buffer.change.Mapper = .init(changes);
    for (list, new, 0..) |s, *n, i| {
        // Selections with an empty value stay, mapped through the pastes.
        if (values[@min(i, values.len - 1)].len > 0) continue;
        n.* = .span(anchors.map(s.anchor, .after), cursors.map(s.cursor, .after));
    }
    try doc.edit(changes, new, doc.selections.main);
    return true;
}

/// One value of a paste, and the selection it is pasted for.
const Paste = struct {
    change: Change,
    owner: usize,

    fn before(_: void, a: Paste, b: Paste) bool {
        if (a.change.start != b.change.start) return a.change.start < b.change.start;
        return linewise(a.change.text) and !linewise(b.change.text);
    }
};

/// `R`: replaces each selection with the register's value for it (as for
/// `paste`) and selects it. False when the register is empty.
pub fn replace(doc: *Document, regs: *const Registers, reg: u8) Error!bool {
    const values = regs.get(reg);
    if (values.len == 0) return false;
    try replaceWith(doc, values);
    return true;
}

/// `Alt-)` (`delta` 1) and `Alt-(` (-1): each selection takes the text of
/// the selection `delta` places before it, wrapping around.
pub fn rotateContents(doc: *Document, delta: isize) Error!void {
    const list = doc.sels();
    const n: isize = @intCast(list.len);
    if (@mod(delta, n) == 0) return;
    const text = doc.text();
    const values = try doc.gpa.alloc([]const u8, list.len);
    defer doc.gpa.free(values);
    for (values, 0..) |*v, i| {
        const from: usize = @intCast(@mod(@as(isize, @intCast(i)) - delta, n));
        const r = list[from].range(text);
        v.* = text[r.start..r.end];
    }
    try replaceWith(doc, values);
}

/// Replaces each selection with its value in `values` (the last value for
/// the rest) and selects it.
fn replaceWith(doc: *Document, values: []const []const u8) Error!void {
    const text = doc.text();
    const list = doc.sels();
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    try changes.ensureTotalCapacity(doc.gpa, list.len);
    const new = try doc.gpa.alloc(Selection, list.len);
    defer doc.gpa.free(new);
    var delta: isize = 0;
    for (list, new, 0..) |s, *n, i| {
        const v = values[@min(i, values.len - 1)];
        const r = s.range(text);
        // The final newline stays, unless a value ending in one replaces it.
        const end = if (linewise(v)) r.end else @min(r.end, text.len - 1);
        const start: usize = @intCast(@as(isize, @intCast(r.start)) + delta);
        n.* = if (v.len > 0) over(start, v) else .at(start);
        if (end == r.start and v.len == 0) continue;
        changes.appendAssumeCapacity(.{ .start = r.start, .end = end, .text = v });
        delta += @as(isize, @intCast(v.len)) - @as(isize, @intCast(end - r.start));
    }
    try doc.edit(changes.items, new, doc.selections.main);
}

/// `r<c>`: replaces every character of the selections, newlines aside,
/// with `cp`.
pub fn replaceChar(doc: *Document, cp: u21) Error!void {
    var enc_buf: [4]u8 = undefined;
    const enc = unicode.utf8.encode(cp, &enc_buf);
    const text = doc.text();
    const list = doc.sels();
    var storage: std.ArrayList(u8) = .empty;
    defer storage.deinit(doc.gpa);
    const ends = try doc.gpa.alloc(usize, list.len);
    defer doc.gpa.free(ends);
    for (list, ends) |s, *e| {
        const r = s.range(text);
        var i = r.start;
        while (i < r.end) : (i = chars.next(text, i)) {
            try storage.appendSlice(doc.gpa, if (text[i] == '\n') "\n" else enc);
        }
        e.* = storage.items.len;
    }
    const changes = try doc.gpa.alloc(Change, list.len);
    defer doc.gpa.free(changes);
    const new = try doc.gpa.alloc(Selection, list.len);
    defer doc.gpa.free(new);
    var from: usize = 0;
    var delta: isize = 0;
    for (list, ends, changes, new) |s, e, *c, *n| {
        const r = s.range(text);
        const piece = storage.items[from..e];
        from = e;
        c.* = .{ .start = r.start, .end = r.end, .text = piece };
        const start: usize = @intCast(@as(isize, @intCast(r.start)) + delta);
        const last = start + piece.len - (if (piece[piece.len - 1] == '\n') 1 else enc.len);
        n.* = if (s.cursor < s.anchor) .span(last, start) else .span(start, last);
        delta += @as(isize, @intCast(piece.len)) - @as(isize, @intCast(r.end - r.start));
    }
    try doc.edit(changes, new, doc.selections.main);
}

pub const Case = enum { upper, lower, swap };

/// `~`, `` ` `` and `` Alt-` ``: changes the case of the ASCII letters in
/// the selections.
pub fn changeCase(doc: *Document, case: Case) Error!void {
    const text = doc.text();
    var storage: std.ArrayList(u8) = .empty;
    defer storage.deinit(doc.gpa);
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    for (doc.sels()) |s| {
        const r = s.range(text);
        try storage.ensureUnusedCapacity(doc.gpa, r.end - r.start);
        for (text[r.start..r.end]) |b| storage.appendAssumeCapacity(switch (case) {
            .upper => std.ascii.toUpper(b),
            .lower => std.ascii.toLower(b),
            .swap => if (std.ascii.isUpper(b)) std.ascii.toLower(b) else std.ascii.toUpper(b),
        });
    }
    var from: usize = 0;
    for (doc.sels()) |s| {
        const r = s.range(text);
        const piece = storage.items[from..][0 .. r.end - r.start];
        from += piece.len;
        if (std.mem.eql(u8, piece, text[r.start..r.end])) continue;
        try changes.append(doc.gpa, .{ .start = r.start, .end = r.end, .text = piece });
    }
    // Lengths do not change, so neither do the selections.
    const same = try doc.gpa.dupe(Selection, doc.sels());
    defer doc.gpa.free(same);
    try doc.edit(changes.items, same, doc.selections.main);
}

/// Calls `f(doc, line, ctx)` once for every line any selection touches,
/// in order.
fn eachLine(doc: *const Document, ctx: anytype, comptime f: anytype) !void {
    const buf = &doc.buffer;
    var next: usize = 0;
    for (doc.sels()) |s| {
        for (@max(buf.lineOf(s.min()), next)..buf.lineOf(s.max()) + 1) |n| try f(doc, n, ctx);
        next = @max(next, buf.lineOf(s.max()) + 1);
    }
}

const LineEdit = struct { changes: *std.ArrayList(Change), gpa: std.mem.Allocator, width: usize, spaces: []const u8 };

fn indentLine(doc: *const Document, n: usize, e: LineEdit) !void {
    if (doc.buffer.line(n).len == 0) return;
    const start = doc.buffer.lineStart(n);
    try e.changes.append(e.gpa, .{ .start = start, .end = start, .text = e.spaces });
}

fn dedentLine(doc: *const Document, n: usize, e: LineEdit) !void {
    const line = doc.buffer.line(n);
    var k: usize = 0;
    if (line.len > 0 and line[0] == '\t') {
        k = 1;
    } else {
        while (k < @min(line.len, e.width) and line[k] == ' ') k += 1;
    }
    if (k == 0) return;
    const start = doc.buffer.lineStart(n);
    try e.changes.append(e.gpa, .{ .start = start, .end = start + k, .text = "" });
}

/// `>`: indents every selected non-empty line by `width` spaces.
pub fn indent(doc: *Document, width: usize) Error!void {
    const spaces = try doc.gpa.alloc(u8, width);
    defer doc.gpa.free(spaces);
    @memset(spaces, ' ');
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    try eachLine(doc, LineEdit{ .changes = &changes, .gpa = doc.gpa, .width = width, .spaces = spaces }, indentLine);
    try applyMapped(doc, changes.items);
}

/// `<`: removes one leading tab, or up to `width` leading spaces, from every
/// selected line.
pub fn dedent(doc: *Document, width: usize) Error!void {
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    try eachLine(doc, LineEdit{ .changes = &changes, .gpa = doc.gpa, .width = width, .spaces = "" }, dedentLine);
    try applyMapped(doc, changes.items);
}

/// `Alt-j`: joins the lines each selection spans (or its line and the
/// next), replacing every newline and the indent after it with one space,
/// or with nothing next to an empty line.
pub fn join(doc: *Document) Error!void {
    const buf = &doc.buffer;
    const text = doc.text();
    var changes: std.ArrayList(Change) = .empty;
    defer changes.deinit(doc.gpa);
    var next: usize = 0;
    for (doc.sels()) |s| {
        const first = buf.lineOf(s.min());
        const last = @min(@max(buf.lineOf(s.max()), first + 1), buf.lineCount() - 1);
        for (@max(first, next)..last) |n| {
            const nl = buf.lineEnd(n);
            var j = nl + 1;
            while (text[j] == ' ' or text[j] == '\t') j += 1;
            const space = text[j] != '\n' and buf.line(n).len > 0;
            try changes.append(doc.gpa, .{ .start = nl, .end = j, .text = if (space) " " else "" });
        }
        next = @max(next, last);
    }
    try applyMapped(doc, changes.items);
}

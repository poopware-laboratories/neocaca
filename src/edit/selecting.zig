//! Selection operations: moving every selection by a motion, shaping them
//! (reduce, flip, lines, objects) and making more of them (copies on other
//! lines, regex matches, splits). None of them changes the text, so none
//! is recorded in the undo history. Operations that can find nothing to do
//! return false and leave the selections as they were.

const std = @import("std");
const unicode = @import("../unicode.zig");
const Regex = @import("../regex.zig").Regex;
const Buffer = @import("../buffer.zig").Buffer;
const Document = @import("document.zig").Document;
const motion = @import("motion.zig");
const object = @import("object.zig");
const Selection = @import("selection.zig").Selection;
const search = @import("search.zig");

const chars = unicode.chars;
const Error = error{OutOfMemory};

pub const Motion = union(enum) {
    left,
    right,
    up,
    down,
    /// The payload says whether the motion goes over WORDs.
    word_start: bool,
    word_end: bool,
    word_back: bool,
    line_start,
    line_end,
    first_non_blank,
    buffer_start,
    /// The start of the last line.
    buffer_end,
    /// The start of a line, counted from 1 and clamped to the buffer.
    line: usize,
    find: Find,
    matching,
};

pub const Find = struct { needle: u21, till: bool, backward: bool };

/// Moves every selection by `m`, `count` times (at least once). A move
/// replaces each selection; `extend` keeps its anchor instead.
pub fn move(doc: *Document, m: Motion, count: usize, extend: bool, tab_width: usize) Error!void {
    const old = doc.sels();
    const new = try doc.gpa.alloc(Selection, old.len);
    defer doc.gpa.free(new);
    for (old, new) |s, *n| n.* = moveOne(&doc.buffer, s, m, @max(count, 1), extend, tab_width);
    try doc.select(new, doc.selections.main);
}

fn to(s: Selection, pos: usize, extend: bool) Selection {
    return if (extend) .span(s.anchor, pos) else .at(pos);
}

fn moveOne(buf: *const Buffer, s: Selection, m: Motion, count: usize, extend: bool, tab_width: usize) Selection {
    const text = buf.bytes();
    switch (m) {
        .left, .right => {
            var p = s.cursor;
            for (0..count) |_| p = if (m == .left) motion.left(buf, p) else motion.right(buf, p);
            return to(s, p, extend);
        },
        .up, .down => {
            const goal = s.goal orelse motion.column(buf, s.cursor, tab_width);
            const n: isize = @intCast(count);
            var r = to(s, motion.vertical(buf, s.cursor, if (m == .up) -n else n, goal, tab_width), extend);
            r.goal = goal;
            return r;
        },
        .word_start, .word_end, .word_back => |big| {
            var r = s;
            for (0..count) |_| {
                const w = switch (m) {
                    .word_start => motion.wordStart(text, r.cursor, big),
                    .word_end => motion.wordEnd(text, r.cursor, big),
                    else => motion.wordBack(text, r.cursor, big),
                };
                r = if (extend) .span(s.anchor, w.cursor) else w;
            }
            return r;
        },
        .line_start => return to(s, motion.lineStart(buf, s.cursor), extend),
        .line_end => {
            const end = motion.lineEnd(buf, s.cursor);
            const last = if (end > motion.lineStart(buf, s.cursor)) chars.prev(text, end) else end;
            return to(s, last, extend);
        },
        .first_non_blank => return to(s, motion.firstNonBlank(buf, s.cursor), extend),
        .buffer_start => return to(s, 0, extend),
        .buffer_end => return to(s, buf.lineStart(buf.lineCount() - 1), extend),
        .line => |n| return to(s, buf.lineStart(@min(@max(n, 1), buf.lineCount()) - 1), extend),
        .find => |f| {
            const p = motion.findChar(text, s.cursor, f.needle, count, f.till, f.backward) orelse return s;
            return .span(if (extend) s.anchor else s.cursor, p);
        },
        .matching => {
            const w = motion.matchingBracket(buf, s.cursor) orelse return s;
            return if (extend) .span(s.anchor, w.cursor) else w;
        },
    }
}

/// `;`: each selection becomes its cursor.
pub fn reduce(doc: *Document) void {
    for (doc.selections.list.items) |*s| s.* = .at(s.cursor);
}

/// `Alt-;`: swaps each selection's anchor and cursor.
pub fn flip(doc: *Document) void {
    for (doc.selections.list.items) |*s| s.* = s.flipped();
}

/// `Alt-:`: makes every selection forward.
pub fn forward(doc: *Document) void {
    for (doc.selections.list.items) |*s| s.* = .span(s.min(), s.max());
}

/// `,`: keeps only the main selection.
pub fn keepMain(doc: *Document) void {
    const list = &doc.selections.list;
    list.items[0] = doc.primary();
    list.shrinkRetainingCapacity(1);
    doc.selections.main = 0;
}

/// `Alt-,`: drops the main selection; the next one becomes main. False
/// when it is the only one.
pub fn dropMain(doc: *Document) bool {
    const list = &doc.selections.list;
    if (list.items.len == 1) return false;
    _ = list.orderedRemove(doc.selections.main);
    doc.selections.main = @min(doc.selections.main, list.items.len - 1);
    return true;
}

/// `(` and `)`: makes the selection `delta` places on the main one,
/// wrapping around.
pub fn rotateMain(doc: *Document, delta: isize) void {
    const len: isize = @intCast(doc.sels().len);
    const main: isize = @intCast(doc.selections.main);
    doc.selections.main = @intCast(@mod(main + delta, len));
}

fn coversLines(buf: *const Buffer, s: Selection) bool {
    return s.min() == motion.lineStart(buf, s.min()) and s.max() == motion.lineEnd(buf, s.max());
}

/// `x` (and `X` with `every_line`): selects the cursor's line (`X`: every
/// line the selection touches); a selection that already covers whole
/// lines grows by the next line. Repeated `count` times.
pub fn selectLines(doc: *Document, count: usize, every_line: bool) void {
    const buf = &doc.buffer;
    for (doc.selections.list.items) |*s| {
        for (0..@max(count, 1)) |_| {
            var first = buf.lineOf(s.cursor);
            var last = first;
            if (coversLines(buf, s.*)) {
                first = buf.lineOf(s.min());
                last = @min(buf.lineOf(s.max()) + 1, buf.lineCount() - 1);
            } else if (every_line) {
                first = buf.lineOf(s.min());
                last = buf.lineOf(s.max());
            }
            const start = buf.lineStart(first);
            const end = buf.lineEnd(last);
            const grown: Selection = if (every_line and s.cursor < s.anchor) .span(end, start) else .span(start, end);
            // At the end of the buffer it grows no further.
            if (grown.anchor == s.anchor and grown.cursor == s.cursor) break;
            s.* = grown;
        }
    }
    doc.selections.normalize(buf.bytes());
}

/// `Alt-x`: trims each selection to the whole lines inside it, dropping
/// those without one; the next kept selection is main if the main one
/// goes. False, changing nothing, when no selection holds a whole line.
pub fn trimLines(doc: *Document) Error!bool {
    const buf = &doc.buffer;
    var out: std.ArrayList(Selection) = .empty;
    defer out.deinit(doc.gpa);
    var main: usize = 0;
    for (doc.sels(), 0..) |s, i| {
        if (i == doc.selections.main) main = out.items.len;
        const top = buf.lineOf(s.min());
        const bottom = buf.lineOf(s.max());
        // The whole lines are those from `first` up to before `past`.
        const first = if (s.min() == buf.lineStart(top)) top else top + 1;
        const past = if (s.max() == buf.lineEnd(bottom)) bottom + 1 else bottom;
        if (first >= past) continue;
        const start = buf.lineStart(first);
        const end = buf.lineEnd(past - 1);
        try out.append(doc.gpa, if (s.cursor < s.anchor) .span(end, start) else .span(start, end));
    }
    return replaceWith(doc, out.items, main);
}

/// `%`: one selection over the whole buffer.
pub fn selectAll(doc: *Document) Error!void {
    try doc.select(&.{.span(0, doc.buffer.len() - 1)}, 0);
}

/// Where display column `col` of line `n` starts, if a character starts
/// exactly there.
fn atColumn(buf: *const Buffer, n: usize, col: usize, tab_width: usize) ?usize {
    const line = buf.line(n);
    const off = unicode.display.offsetAt(line, col, tab_width);
    if (off >= line.len or unicode.display.columnOf(line, off, tab_width) != col) return null;
    return buf.lineStart(n) + off;
}

/// `C` (`down`) and `Alt-C`: adds a copy of the main selection, at the same
/// display columns, on the nearest line past every selection where it fits,
/// and makes it main. Repeated `count` times; false when no copy fits.
pub fn copyToLine(doc: *Document, down: bool, count: usize, tab_width: usize) Error!bool {
    const buf = &doc.buffer;
    var copies: std.ArrayList(Selection) = .empty;
    defer copies.deinit(doc.gpa);
    // Each copy lies past every selection, so it is the next one's main
    // selection and edge; the selections are sorted once at the end.
    var m = doc.primary();
    const list = doc.sels();
    var edge: usize = if (down) buf.lineOf(list[list.len - 1].max()) else buf.lineOf(list[0].min());
    for (0..@max(count, 1)) |_| {
        const a_line = buf.lineOf(m.anchor);
        const c_line = buf.lineOf(m.cursor);
        const top = @min(a_line, c_line);
        const height = @max(a_line, c_line) - top;
        const a_col = motion.column(buf, m.anchor, tab_width);
        const c_col = motion.column(buf, m.cursor, tab_width);
        const found: ?Selection = while (true) {
            // `edge` walks to the next candidate top line for the copy.
            if (down) {
                if (edge + 1 + height >= buf.lineCount()) break null;
                edge += 1;
            } else {
                if (edge < height + 1) break null;
                edge -= 1;
            }
            const t = if (down) edge else edge - height;
            const anchor = atColumn(buf, t + a_line - top, a_col, tab_width) orelse continue;
            const cursor = atColumn(buf, t + c_line - top, c_col, tab_width) orelse continue;
            break .span(anchor, cursor);
        };
        m = found orelse break;
        try copies.append(doc.gpa, m);
        edge = if (down) buf.lineOf(m.max()) else buf.lineOf(m.min());
    }
    if (copies.items.len == 0) return false;
    try doc.selections.list.appendSlice(doc.gpa, copies.items);
    doc.selections.main = doc.sels().len - 1;
    doc.selections.normalize(buf.bytes());
    return true;
}

/// `Alt-i` (`inner`) and `Alt-a`: selects object `kind` around each
/// cursor, keeping the selections where it is not found; false when it is
/// found nowhere.
pub fn selectObject(doc: *Document, kind: object.Kind, inner: bool) Error!bool {
    const new = try doc.gpa.dupe(Selection, doc.sels());
    defer doc.gpa.free(new);
    var found = false;
    for (new) |*s| {
        if (object.select(&doc.buffer, s.*, kind, inner)) |o| {
            s.* = o;
            found = true;
        }
    }
    if (!found) return false;
    try doc.select(new, doc.selections.main);
    return true;
}

/// Replaces the selections with `out`, the first of them made from the
/// old main one at `main`. False, changing nothing, when `out` is empty.
fn replaceWith(doc: *Document, out: []const Selection, main: usize) Error!bool {
    if (out.len == 0) return false;
    try doc.select(out, @min(main, out.len - 1));
    return true;
}

/// `s`: selects every non-empty match of `re` inside the selections.
pub fn selectMatches(doc: *Document, re: *Regex) Error!bool {
    const text = doc.text();
    var out: std.ArrayList(Selection) = .empty;
    defer out.deinit(doc.gpa);
    var main: usize = 0;
    for (doc.sels(), 0..) |s, k| {
        if (k == doc.selections.main) main = out.items.len;
        const r = s.range(text);
        var walk: chars.Walk = .{ .text = text, .at = r.start };
        var from = r.start;
        while (search.nonEmpty(re, text, from, r.end)) |m| {
            try out.append(doc.gpa, search.over(&walk, m));
            from = m.end;
        }
    }
    return replaceWith(doc, out.items, main);
}

/// `S`: splits the selections at the non-empty matches of `re`, keeping
/// the non-empty pieces between them.
pub fn split(doc: *Document, re: *Regex) Error!bool {
    const text = doc.text();
    var out: std.ArrayList(Selection) = .empty;
    defer out.deinit(doc.gpa);
    var main: usize = 0;
    for (doc.sels(), 0..) |s, k| {
        if (k == doc.selections.main) main = out.items.len;
        const r = s.range(text);
        var walk: chars.Walk = .{ .text = text, .at = r.start };
        var start = r.start;
        var from = r.start;
        while (search.nonEmpty(re, text, from, r.end)) |m| {
            // The pieces keep out every character a match touches.
            const cut = search.over(&walk, m);
            if (cut.anchor > start) try out.append(doc.gpa, .span(start, chars.prev(text, cut.anchor)));
            start = chars.next(text, cut.cursor);
            from = m.end;
        }
        if (r.end > start) try out.append(doc.gpa, .span(start, chars.prev(text, r.end)));
    }
    return replaceWith(doc, out.items, main);
}

/// `Alt-s`: splits the selections into one per line, newline included.
pub fn splitLines(doc: *Document) Error!void {
    const buf = &doc.buffer;
    const text = doc.text();
    var out: std.ArrayList(Selection) = .empty;
    defer out.deinit(doc.gpa);
    var main: usize = 0;
    for (doc.sels(), 0..) |s, k| {
        if (k == doc.selections.main) main = out.items.len;
        const r = s.range(text);
        for (buf.lineOf(r.start)..buf.lineOf(r.end - 1) + 1) |n| {
            const start = @max(buf.lineStart(n), r.start);
            const end = @min(buf.lineEnd(n) + 1, r.end);
            try out.append(doc.gpa, .span(start, chars.prev(text, end)));
        }
    }
    try doc.select(out.items, main);
}

/// `Alt-k` (`keep`) and `Alt-K`: keeps the selections that contain a match
/// of `re`, or those that do not.
pub fn keepMatching(doc: *Document, re: *Regex, keep: bool) Error!bool {
    const text = doc.text();
    var out: std.ArrayList(Selection) = .empty;
    defer out.deinit(doc.gpa);
    var main: usize = 0;
    for (doc.sels(), 0..) |s, k| {
        if (k == doc.selections.main) main = out.items.len;
        const r = s.range(text);
        if (re.matchesIn(text, r.start, r.end) == keep) try out.append(doc.gpa, s);
    }
    return replaceWith(doc, out.items, main);
}

//! Moving every selection by a motion (`h`, `w`, `f`, `gg`, ...), `count`
//! times. Moves replace each selection, or extend it from its anchor; the
//! steps that go one character or word at a time are repeated through
//! `repeat.zig`, so a count costs about the text's length. Re-exported by
//! `selecting.zig`, where the other selection changes live.

const std = @import("std");
const unicode = @import("../unicode.zig");
const Buffer = @import("../buffer.zig").Buffer;
const Document = @import("document.zig").Document;
const motion = @import("motion.zig");
const Selection = @import("selection.zig").Selection;
const repeat = @import("repeat.zig");

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
    switch (m) {
        .left, .right, .word_start, .word_end, .word_back, .find => try moveRepeated(doc.gpa, &doc.buffer, old, new, m, @max(count, 1), extend),
        else => for (old, new) |s, *n| {
            n.* = moveOne(&doc.buffer, s, m, @max(count, 1), extend, tab_width);
        },
    }
    try doc.select(new, doc.selections.main);
}

/// One step of a motion that `move` repeats.
const Step = struct {
    buf: *const Buffer,
    m: Motion,

    pub fn step(self: *const Step, cursor: usize) ?Selection {
        const text = self.buf.bytes();
        return switch (self.m) {
            .left => .at(motion.left(self.buf, cursor)),
            .right => .at(motion.right(self.buf, cursor)),
            .word_start => |big| motion.wordStart(text, cursor, big),
            .word_end => |big| motion.wordEnd(text, cursor, big),
            .word_back => |big| motion.wordBack(text, cursor, big),
            .find => |f| .at(motion.findNext(text, cursor, f.needle, f.till, f.backward, true) orelse return null),
            else => unreachable,
        };
    }
};

/// Whether the motion's steps lower the cursor.
pub fn backwards(m: Motion) bool {
    return switch (m) {
        .left, .word_back => true,
        .find => |f| f.backward,
        else => false,
    };
}

/// The motions whose steps go one at a time, repeated through `repeat`
/// so a count costs about the text's length, not count × selections.
fn moveRepeated(gpa: std.mem.Allocator, buf: *const Buffer, old: []const Selection, new: []Selection, m: Motion, count: usize, extend: bool) Error!void {
    // For each selection still moving: where its walk starts, and which it is.
    const scratch = try gpa.alloc(usize, 2 * old.len);
    defer gpa.free(scratch);
    const starts = scratch[0..old.len];
    const which = scratch[old.len..];
    const out = try gpa.alloc(?Selection, old.len);
    defer gpa.free(out);
    var moving: usize = 0;
    for (old, 0..) |s, i| {
        new[i] = s;
        // The first `f` or `t` is found from the cursor itself: a later
        // `t` steps past the character it stopped before.
        starts[moving] = switch (m) {
            .find => |f| motion.findNext(buf.bytes(), s.cursor, f.needle, f.till, f.backward, false) orelse continue,
            else => s.cursor,
        };
        which[moving] = i;
        moving += 1;
    }
    const steps = if (m == .find) count - 1 else count;
    if (steps == 0) {
        for (starts[0..moving], out[0..moving]) |p, *o| o.* = .at(p);
    } else {
        try repeat.repeat(gpa, &Step{ .buf = buf, .m = m }, !backwards(m), starts[0..moving], steps, out[0..moving]);
    }
    for (which[0..moving], out[0..moving]) |i, o| {
        // A find with too few matches leaves its selection as it was.
        const r = o orelse continue;
        const s = old[i];
        new[i] = switch (m) {
            .left, .right => to(s, r.cursor, extend),
            .find => .span(if (extend) s.anchor else s.cursor, r.cursor),
            else => if (extend) .span(s.anchor, r.cursor) else r,
        };
    }
}

fn to(s: Selection, pos: usize, extend: bool) Selection {
    return if (extend) .span(s.anchor, pos) else .at(pos);
}

fn moveOne(buf: *const Buffer, s: Selection, m: Motion, count: usize, extend: bool, tab_width: usize) Selection {
    const text = buf.bytes();
    switch (m) {
        .up, .down => {
            const goal = s.goal orelse motion.column(buf, s.cursor, tab_width);
            const n: isize = @intCast(count);
            var r = to(s, motion.vertical(buf, s.cursor, if (m == .up) -n else n, goal, tab_width), extend);
            r.goal = goal;
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
        .matching => {
            const w = motion.matchingBracket(buf, s.cursor) orelse return s;
            return if (extend) .span(s.anchor, w.cursor) else w;
        },
        .left, .right, .word_start, .word_end, .word_back, .find => unreachable, // moveRepeated
    }
}

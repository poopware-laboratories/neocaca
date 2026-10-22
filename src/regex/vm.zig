//! The Pike VM: runs a `Program` over a text in one pass, keeping at most
//! one thread per instruction, so a search takes O(text × program) time
//! whatever the pattern. Threads are kept in priority order and the first
//! match found cuts the threads below it, which gives leftmost-first
//! (Perl-like) results: the earliest start, then the preferred branch.

const std = @import("std");
const unicode = @import("../unicode.zig");
const program = @import("program.zig");
const Program = program.Program;

pub const Match = struct { start: usize, end: usize };

const Thread = struct { pc: u32, start: usize };

/// A list of threads with at most one per instruction.
const List = struct {
    threads: []Thread,
    len: usize = 0,
    /// `seen[pc] == generation` when `pc` was visited for this step.
    seen: []u32,
};

/// Memory for one search at a time; allocated once per regex.
pub const Scratch = struct {
    a: List,
    b: List,
    stack: []u32,
    generation: u32 = 0,

    pub fn init(gpa: std.mem.Allocator, insts: usize) error{OutOfMemory}!Scratch {
        const threads = try gpa.alloc(Thread, 2 * insts);
        errdefer gpa.free(threads);
        const seen = try gpa.alloc(u32, 2 * insts);
        errdefer gpa.free(seen);
        @memset(seen, 0);
        const stack = try gpa.alloc(u32, 2 * insts + 2);
        return .{
            .a = .{ .threads = threads[0..insts], .seen = seen[0..insts] },
            .b = .{ .threads = threads[insts..], .seen = seen[insts..] },
            .stack = stack,
        };
    }

    /// Starts a new step: every `seen` mark from before becomes stale.
    fn nextGeneration(self: *Scratch) void {
        self.generation +%= 1;
        if (self.generation == 0) {
            @memset(self.a.seen, 0);
            @memset(self.b.seen, 0);
            self.generation = 1;
        }
    }

    pub fn deinit(self: *Scratch, gpa: std.mem.Allocator) void {
        const n = self.a.threads.len;
        gpa.free(self.a.threads.ptr[0 .. 2 * n]);
        gpa.free(self.a.seen.ptr[0 .. 2 * n]);
        gpa.free(self.stack);
        self.* = undefined;
    }
};

fn isWordAt(text: []const u8, i: usize) bool {
    if (i >= text.len) return false;
    const cp = unicode.utf8.decode(text[i..]).cp orelse return false;
    return unicode.class.isWord(cp);
}

fn isWordBefore(text: []const u8, i: usize) bool {
    if (i == 0) return false;
    return isWordAt(text, unicode.utf8.prevStart(text, i));
}

/// Whether a zero-width assertion holds at `at` in the full `text`.
fn holds(inst: program.Inst, text: []const u8, at: usize) bool {
    return switch (inst) {
        .line_start => at == 0 or text[at - 1] == '\n',
        .line_end => at == text.len or text[at] == '\n',
        .word_boundary => isWordBefore(text, at) != isWordAt(text, at),
        .not_word_boundary => isWordBefore(text, at) == isWordAt(text, at),
        else => unreachable,
    };
}

/// Adds the thread `pc` (and everything it reaches without consuming) at
/// position `at`, in priority order.
fn add(prog: *const Program, scratch: *Scratch, list: *List, pc0: u32, start: usize, text: []const u8, at: usize) void {
    var sp: usize = 0;
    scratch.stack[sp] = pc0;
    sp += 1;
    while (sp > 0) {
        sp -= 1;
        const pc = scratch.stack[sp];
        if (list.seen[pc] == scratch.generation) continue;
        list.seen[pc] = scratch.generation;
        switch (prog.insts[pc]) {
            .jump => |to| {
                scratch.stack[sp] = to;
                sp += 1;
            },
            .split => |s| {
                // y below x, so x and all it reaches come first.
                scratch.stack[sp] = s.y;
                scratch.stack[sp + 1] = s.x;
                sp += 2;
            },
            .line_start, .line_end, .word_boundary, .not_word_boundary => {
                if (holds(prog.insts[pc], text, at)) {
                    scratch.stack[sp] = pc + 1;
                    sp += 1;
                }
            },
            else => {
                list.threads[list.len] = .{ .pc = pc, .start = start };
                list.len += 1;
            },
        }
    }
}

fn inClass(prog: *const Program, start: u32, len: u32, cp: u21) bool {
    for (prog.ranges[start..][0..len]) |r| {
        if (cp >= r.lo and cp <= r.hi) return true;
    }
    return false;
}

/// Whether the instruction at `pc` consumes the character `d`, which
/// starts at `at`.
fn consumes(prog: *const Program, pc: u32, d: unicode.utf8.Decoded, text: []const u8, at: usize) bool {
    return switch (prog.insts[pc]) {
        .char => |c| d.cp == c,
        .byte => |b| d.cp == null and d.len > 0 and text[at] == b,
        .any => d.len > 0 and d.cp != '\n',
        .class => |k| if (d.cp) |cp| inClass(prog, k.start, k.len, cp) != k.negated else d.len > 0 and k.negated,
        else => unreachable,
    };
}

/// The leftmost-first match starting in `[from, to]` and ending by `to`;
/// with `non_empty`, the leftmost-first of those that are not empty.
/// Assertions see the whole `text`, so `^` and `\b` work inside a slice.
pub fn find(prog: *const Program, scratch: *Scratch, text: []const u8, from: usize, to: usize, non_empty: bool) ?Match {
    std.debug.assert(from <= to and to <= text.len);
    var clist = &scratch.a;
    var nlist = &scratch.b;
    clist.len = 0;
    scratch.nextGeneration();
    add(prog, scratch, clist, 0, from, text, from);
    var matched: ?Match = null;
    var pos = from;
    while (true) {
        const d = if (pos < to) unicode.utf8.decode(text[pos..to]) else unicode.utf8.Decoded{ .cp = null, .len = 0 };
        const next = pos + d.len;
        scratch.nextGeneration();
        nlist.len = 0;
        for (clist.threads[0..clist.len]) |t| {
            if (prog.insts[t.pc] == .match) {
                // An empty one, when unwanted, lets the threads below go on.
                if (non_empty and t.start == pos) continue;
                matched = .{ .start = t.start, .end = pos };
                break; // lower-priority threads lose to this match
            }
            if (consumes(prog, t.pc, d, text, pos)) add(prog, scratch, nlist, t.pc + 1, t.start, text, next);
        }
        if (pos >= to) break;
        pos = next;
        if (matched == null) add(prog, scratch, nlist, 0, pos, text, pos);
        // With a match in hand and no thread left, nothing can beat it;
        // without one, the next position may still start a match.
        if (nlist.len == 0 and matched != null) break;
        std.mem.swap(*List, &clist, &nlist);
    }
    return matched;
}

/// Where the non-empty match that starts last in `[from, to)` and ends by
/// `to` starts, `rev` being the pattern compiled reversed. One pass from
/// `to` back to `from`: a thread holds where its match would end, a new
/// one joins at every position after those already running, and the
/// first to reach `match` past its end starts last.
pub fn lastStart(rev: *const Program, scratch: *Scratch, text: []const u8, from: usize, to: usize) ?usize {
    std.debug.assert(from <= to and to <= text.len);
    var clist = &scratch.a;
    var nlist = &scratch.b;
    clist.len = 0;
    scratch.nextGeneration();
    add(rev, scratch, clist, 0, to, text, to);
    var pos = to;
    while (true) {
        for (clist.threads[0..clist.len]) |t| {
            if (rev.insts[t.pc] == .match and t.start > pos) return pos;
        }
        if (pos == from) return null;
        // The character before `pos`, as a forward walk from `from` sees it.
        const prev = from + unicode.utf8.prevStart(text[from..pos], pos - from);
        const d = unicode.utf8.decode(text[prev..pos]);
        scratch.nextGeneration();
        nlist.len = 0;
        for (clist.threads[0..clist.len]) |t| {
            if (rev.insts[t.pc] == .match) continue;
            if (consumes(rev, t.pc, d, text, prev)) add(rev, scratch, nlist, t.pc + 1, t.start, text, prev);
        }
        add(rev, scratch, nlist, 0, prev, text, prev);
        pos = prev;
        std.mem.swap(*List, &clist, &nlist);
    }
}

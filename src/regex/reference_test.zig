//! The references the regex tests check the VM against: plain
//! backtracking over a program, and random patterns to run it on.

const std = @import("std");
const program = @import("program.zig");
const unicode = @import("../unicode.zig");

/// The reference: plain backtracking over the program, which gives
/// leftmost-first results by construction. A (pc, pos) pair already being
/// tried counts as failed, which is how empty loops end in the VM too.
pub const Reference = struct {
    prog: *const program.Program,
    text: []const u8,
    to: usize,
    busy: std.AutoHashMap([2]usize, void),
    /// Matches ending before this fail, so backtracking goes on past
    /// them: `start + 1` asks for a non-empty match.
    min_end: usize = 0,

    pub fn run(self: *Reference, pc: u32, pos: usize) !?usize {
        const key = [2]usize{ pc, pos };
        if (self.busy.contains(key)) return null;
        try self.busy.put(key, {});
        defer _ = self.busy.remove(key);
        const inst = self.prog.insts[pc];
        const d = if (pos < self.to) unicode.utf8.decode(self.text[pos..self.to]) else unicode.utf8.Decoded{ .cp = null, .len = 0 };
        switch (inst) {
            .match => return if (pos >= self.min_end) pos else null,
            .jump => |t| return self.run(t, pos),
            .split => |s| return (try self.run(s.x, pos)) orelse try self.run(s.y, pos),
            .line_start => return if (pos == 0 or self.text[pos - 1] == '\n') self.run(pc + 1, pos) else null,
            .line_end => return if (pos == self.text.len or self.text[pos] == '\n') self.run(pc + 1, pos) else null,
            .word_boundary, .not_word_boundary => {
                const before = pos > 0 and unicode.class.isWord(unicode.utf8.decode(self.text[unicode.utf8.prevStart(self.text, pos)..]).cp orelse 0);
                const after = pos < self.text.len and unicode.class.isWord(unicode.utf8.decode(self.text[pos..]).cp orelse 0);
                const ok = (before != after) == (inst == .word_boundary);
                return if (ok) self.run(pc + 1, pos) else null;
            },
            .char => |c| return if (d.cp == c) self.run(pc + 1, pos + d.len) else null,
            .byte => |b| return if (d.cp == null and d.len > 0 and self.text[pos] == b) self.run(pc + 1, pos + 1) else null,
            .any => return if (d.len > 0 and d.cp != '\n') self.run(pc + 1, pos + d.len) else null,
            .class => |k| {
                const in = if (d.cp) |cp| blk: {
                    for (self.prog.ranges[k.start..][0..k.len]) |r| if (cp >= r.lo and cp <= r.hi) break :blk true;
                    break :blk false;
                } else false;
                const ok = d.len > 0 and in != k.negated;
                return if (ok) self.run(pc + 1, pos + d.len) else null;
            },
        }
    }
};

pub fn randomPattern(random: std.Random, buf: []u8, depth: usize) []const u8 {
    const atoms = [_][]const u8{ "a", "b", ".", "[ab]", "[^a]", "\\w", "^", "$", "\\b", "\n" };
    var len: usize = 0;
    const parts = 1 + random.uintLessThan(usize, 3);
    for (0..parts) |_| {
        if (len + 24 > buf.len) break;
        if (depth < 2 and random.uintLessThan(u8, 4) == 0) {
            buf[len] = '(';
            const inner = randomPattern(random, buf[len + 1 .. buf.len - 2], depth + 1);
            len += 1 + inner.len;
            if (random.boolean()) {
                buf[len] = '|';
                len += 1;
            }
            buf[len] = ')';
            len += 1;
        } else {
            const atom = atoms[random.uintLessThan(usize, atoms.len)];
            @memcpy(buf[len..][0..atom.len], atom);
            len += atom.len;
        }
        const quants = [_][]const u8{ "", "", "*", "+", "?", "*?", "{1,2}" };
        const q = quants[random.uintLessThan(usize, quants.len)];
        if (q.len > 0 and buf[len - 1] != '^' and buf[len - 1] != '$') {
            @memcpy(buf[len..][0..q.len], q);
            len += q.len;
        }
    }
    return buf[0..len];
}

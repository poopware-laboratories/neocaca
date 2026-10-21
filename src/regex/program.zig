//! Compiling an `ast.Tree` into instructions for the Pike VM (`vm.zig`).
//! Every instruction that consumes input consumes one character; splits
//! and jumps are free and are followed when threads are added.

const std = @import("std");
const ast = @import("ast.zig");

pub const Inst = union(enum) {
    char: u21,
    any,
    class: struct { start: u32, len: u32, negated: bool },
    /// Continue at both `x` and `y`, preferring `x`.
    split: struct { x: u32, y: u32 },
    jump: u32,
    line_start,
    line_end,
    word_boundary,
    not_word_boundary,
    match,
};

pub const Error = error{ OutOfMemory, TooComplex };

/// Instructions a program may hold; bounds both memory and match time.
pub const max_insts = 20_000;

pub const Program = struct {
    insts: []Inst,
    ranges: []ast.Range,

    pub fn deinit(self: *Program, gpa: std.mem.Allocator) void {
        gpa.free(self.insts);
        gpa.free(self.ranges);
        self.* = undefined;
    }
};

/// Compiles `tree`. Caller owns the result (`Program.deinit`).
pub fn compile(gpa: std.mem.Allocator, tree: ast.Tree) Error!Program {
    var c: Compiler = .{ .gpa = gpa, .tree = tree };
    defer c.insts.deinit(gpa);
    try c.emitNode(tree.root);
    _ = try c.emit(.match);
    const ranges = try gpa.dupe(ast.Range, tree.ranges);
    errdefer gpa.free(ranges);
    return .{ .insts = try c.insts.toOwnedSlice(gpa), .ranges = ranges };
}

const Compiler = struct {
    gpa: std.mem.Allocator,
    tree: ast.Tree,
    insts: std.ArrayList(Inst) = .empty,
    /// Nodes visited; nested counts over empty bodies emit nothing but
    /// would still loop, so they are bounded too.
    visits: usize = 0,

    fn emit(self: *Compiler, inst: Inst) Error!u32 {
        if (self.insts.items.len >= max_insts) return error.TooComplex;
        try self.insts.append(self.gpa, inst);
        return @intCast(self.insts.items.len - 1);
    }

    fn pc(self: *const Compiler) u32 {
        return @intCast(self.insts.items.len);
    }

    fn emitNode(self: *Compiler, index: ast.Index) Error!void {
        self.visits += 1;
        if (self.visits > 10 * max_insts) return error.TooComplex;
        switch (self.tree.nodes[index]) {
            .empty => {},
            .char => |c| _ = try self.emit(.{ .char = c }),
            .any => _ = try self.emit(.any),
            .class => |k| _ = try self.emit(.{ .class = .{ .start = k.start, .len = k.len, .negated = k.negated } }),
            .line_start => _ = try self.emit(.line_start),
            .line_end => _ = try self.emit(.line_end),
            .word_boundary => _ = try self.emit(.word_boundary),
            .not_word_boundary => _ = try self.emit(.not_word_boundary),
            .concat => |r| for (self.tree.children[r.start..][0..r.len]) |child| try self.emitNode(child),
            .alt => |r| try self.emitAlt(self.tree.children[r.start..][0..r.len]),
            .repeat => |r| try self.emitRepeat(r.child, r.min, r.max, r.greedy),
        }
    }

    fn emitAlt(self: *Compiler, branches: []const ast.Index) Error!void {
        // split L1 next; L1: a; jump end; next: split L2 next2; ...; last
        var jumps: std.ArrayList(u32) = .empty;
        defer jumps.deinit(self.gpa);
        for (branches[0 .. branches.len - 1]) |branch| {
            const split = try self.emit(.{ .split = .{ .x = 0, .y = 0 } });
            self.insts.items[split].split.x = self.pc();
            try self.emitNode(branch);
            try jumps.append(self.gpa, try self.emit(.{ .jump = 0 }));
            self.insts.items[split].split.y = self.pc();
        }
        try self.emitNode(branches[branches.len - 1]);
        for (jumps.items) |j| self.insts.items[j] = .{ .jump = self.pc() };
    }

    fn emitRepeat(self: *Compiler, child: ast.Index, min: u32, max: ?u32, greedy: bool) Error!void {
        for (0..min) |_| try self.emitNode(child);
        if (max) |m| {
            for (min..m) |_| try self.emitOptional(child, greedy);
        } else {
            // loop: split body end; body; jump loop; end:
            const loop = try self.emit(.{ .split = .{ .x = 0, .y = 0 } });
            try self.emitNode(child);
            _ = try self.emit(.{ .jump = loop });
            self.setSplit(loop, loop + 1, self.pc(), greedy);
        }
    }

    fn emitOptional(self: *Compiler, child: ast.Index, greedy: bool) Error!void {
        const split = try self.emit(.{ .split = .{ .x = 0, .y = 0 } });
        try self.emitNode(child);
        self.setSplit(split, split + 1, self.pc(), greedy);
    }

    /// Points a split at `body` and `skip`, trying `body` first when greedy.
    fn setSplit(self: *Compiler, at: u32, body: u32, skip: u32, greedy: bool) void {
        self.insts.items[at] = .{ .split = if (greedy) .{ .x = body, .y = skip } else .{ .x = skip, .y = body } };
    }
};

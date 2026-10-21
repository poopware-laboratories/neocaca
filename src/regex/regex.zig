//! `Regex`: a compiled pattern with its search memory, and `escape`.

const std = @import("std");
const parse_mod = @import("parse.zig");
const program = @import("program.zig");
const vm = @import("vm.zig");
const utf8 = @import("../unicode.zig").utf8;

pub const Match = vm.Match;
pub const Error = parse_mod.Error || program.Error;

pub const Regex = struct {
    gpa: std.mem.Allocator,
    prog: program.Program,
    scratch: vm.Scratch,

    /// Compiles `pattern`; `deinit` frees it.
    pub fn compile(gpa: std.mem.Allocator, pattern: []const u8) Error!Regex {
        var parsed = try parse_mod.parse(gpa, pattern);
        defer parsed.deinit(gpa);
        var prog = try program.compile(gpa, parsed.tree());
        errdefer prog.deinit(gpa);
        return .{ .gpa = gpa, .prog = prog, .scratch = try .init(gpa, prog.insts.len) };
    }

    pub fn deinit(self: *Regex) void {
        self.prog.deinit(self.gpa);
        self.scratch.deinit(self.gpa);
        self.* = undefined;
    }

    /// The first match starting at or after `from`, in all of `text`.
    pub fn find(self: *Regex, text: []const u8, from: usize) ?Match {
        return vm.find(&self.prog, &self.scratch, text, from, text.len);
    }

    /// The first match inside `text[from..to]`; assertions still see the
    /// text around it.
    pub fn findIn(self: *Regex, text: []const u8, from: usize, to: usize) ?Match {
        return vm.find(&self.prog, &self.scratch, text, from, to);
    }

    /// Whether `text[from..to]` contains a match.
    pub fn matchesIn(self: *Regex, text: []const u8, from: usize, to: usize) bool {
        return self.findIn(text, from, to) != null;
    }
};

/// Writes `literal` with every metacharacter escaped and every invalid
/// byte as `\xHH`, so it compiles to a pattern matching exactly `literal`
/// (where the text's characters start at its bytes). Caller owns the result.
pub fn escape(gpa: std.mem.Allocator, literal: []const u8) error{OutOfMemory}![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < literal.len) {
        const d = utf8.decode(literal[i..]);
        if (d.cp == null) {
            try out.print(gpa, "\\x{x:0>2}", .{literal[i]});
            i += 1;
            continue;
        }
        for (literal[i..][0..d.len]) |c| {
            switch (c) {
                '\\', '.', '[', ']', '(', ')', '{', '}', '*', '+', '?', '|', '^', '$' => try out.append(gpa, '\\'),
                else => {},
            }
            switch (c) {
                '\n' => try out.appendSlice(gpa, "\\n"),
                else => try out.append(gpa, c),
            }
        }
        i += d.len;
    }
    return out.toOwnedSlice(gpa);
}

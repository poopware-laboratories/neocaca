//! Tests for `program.zig`: the instructions each construct compiles to,
//! the priority order of splits, and the `max_insts` and visit limits.

const std = @import("std");
const parse = @import("parse.zig");
const program = @import("program.zig");
const ast = @import("ast.zig");
const Inst = program.Inst;

const gpa = std.testing.allocator;

fn compile(a: std.mem.Allocator, pattern: []const u8) !program.Program {
    var parsed = try parse.parse(a, pattern);
    defer parsed.deinit(a);
    return program.compile(a, parsed.tree());
}

fn expectInsts(pattern: []const u8, want: []const Inst) !void {
    var prog = try compile(gpa, pattern);
    defer prog.deinit(gpa);
    try std.testing.expectEqualSlices(Inst, want, prog.insts);
}

test "program: the empty pattern is a lone match" {
    try expectInsts("", &.{.match});
    try expectInsts("(?:)", &.{.match});
}

test "program: literals compile to one instruction per codepoint" {
    try expectInsts("ab", &.{ .{ .char = 'a' }, .{ .char = 'b' }, .match });
    try expectInsts("中é", &.{ .{ .char = 0x4e2d }, .{ .char = 0xe9 }, .match });
    try expectInsts(".", &.{ .any, .match });
}

test "program: assertions compile to their own instructions" {
    try expectInsts("^$\\b\\B", &.{ .line_start, .line_end, .word_boundary, .not_word_boundary, .match });
}

test "program: groups add no instructions" {
    try expectInsts("((a))(?:b)", &.{ .{ .char = 'a' }, .{ .char = 'b' }, .match });
}

test "program: alternation splits to each branch and jumps past the rest" {
    try expectInsts("a|b", &.{
        .{ .split = .{ .x = 1, .y = 3 } },
        .{ .char = 'a' },
        .{ .jump = 4 },
        .{ .char = 'b' },
        .match,
    });
    try expectInsts("a|b|c", &.{
        .{ .split = .{ .x = 1, .y = 3 } },
        .{ .char = 'a' },
        .{ .jump = 7 },
        .{ .split = .{ .x = 4, .y = 6 } },
        .{ .char = 'b' },
        .{ .jump = 7 },
        .{ .char = 'c' },
        .match,
    });
}

test "program: greedy loops prefer the body, lazy loops prefer the exit" {
    try expectInsts("a*", &.{ .{ .split = .{ .x = 1, .y = 3 } }, .{ .char = 'a' }, .{ .jump = 0 }, .match });
    try expectInsts("a*?", &.{ .{ .split = .{ .x = 3, .y = 1 } }, .{ .char = 'a' }, .{ .jump = 0 }, .match });
    try expectInsts("a?", &.{ .{ .split = .{ .x = 1, .y = 2 } }, .{ .char = 'a' }, .match });
    try expectInsts("a??", &.{ .{ .split = .{ .x = 2, .y = 1 } }, .{ .char = 'a' }, .match });
}

test "program: plus is one copy then a loop" {
    try expectInsts("a+", &.{ .{ .char = 'a' }, .{ .split = .{ .x = 2, .y = 4 } }, .{ .char = 'a' }, .{ .jump = 1 }, .match });
    try expectInsts("a+?", &.{ .{ .char = 'a' }, .{ .split = .{ .x = 4, .y = 2 } }, .{ .char = 'a' }, .{ .jump = 1 }, .match });
}

test "program: counts unroll into copies and optional copies" {
    try expectInsts("a{2}", &.{ .{ .char = 'a' }, .{ .char = 'a' }, .match });
    try expectInsts("a{0}", &.{.match});
    try expectInsts("a{1,3}", &.{
        .{ .char = 'a' },
        .{ .split = .{ .x = 2, .y = 3 } },
        .{ .char = 'a' },
        .{ .split = .{ .x = 4, .y = 5 } },
        .{ .char = 'a' },
        .match,
    });
    try expectInsts("a{1,}", &.{ .{ .char = 'a' }, .{ .split = .{ .x = 2, .y = 4 } }, .{ .char = 'a' }, .{ .jump = 1 }, .match });
}

test "program: classes keep their ranges, copied out of the tree" {
    var prog = try compile(gpa, "[a-c]\\d[^x]");
    defer prog.deinit(gpa);
    try std.testing.expectEqualSlices(Inst, &.{
        .{ .class = .{ .start = 0, .len = 1, .negated = false } },
        .{ .class = .{ .start = 1, .len = 1, .negated = false } },
        .{ .class = .{ .start = 2, .len = 1, .negated = true } },
        .match,
    }, prog.insts);
    try std.testing.expectEqualSlices(ast.Range, &.{
        .{ .lo = 'a', .hi = 'c' },
        .{ .lo = '0', .hi = '9' },
        .{ .lo = 'x', .hi = 'x' },
    }, prog.ranges);
}

test "program: a program of exactly max_insts instructions compiles" {
    // 19 * 1000 + 999 characters and the final match.
    var prog = try compile(gpa, "(?:a{1000}){19}a{999}");
    defer prog.deinit(gpa);
    try std.testing.expectEqual(program.max_insts, prog.insts.len);
    try std.testing.expectEqual(Inst.match, prog.insts[prog.insts.len - 1]);
}

test "program: one instruction past max_insts is too complex" {
    try std.testing.expectError(error.TooComplex, compile(gpa, "(?:a{1000}){20}"));
    try std.testing.expectError(error.TooComplex, compile(gpa, "(?:a{1000}){19}a{999}b"));
}

test "program: the node visit limit holds at the limit and one past it" {
    // Visits: the root concat, 1 + 199 * (1 + 1000) for the first part
    // and 1 + n for `(?:){n}`: 200_000 exactly with n = 798.
    var at = try compile(gpa, "(?:(?:){1000}){199}(?:){798}");
    defer at.deinit(gpa);
    try std.testing.expectEqualSlices(Inst, &.{.match}, at.insts);
    try std.testing.expectError(error.TooComplex, compile(gpa, "(?:(?:){1000}){199}(?:){799}"));
}

test "program: compile fails cleanly without memory" {
    try std.testing.checkAllAllocationFailures(gpa, struct {
        fn run(a: std.mem.Allocator) !void {
            var prog = try compile(a, "a|[b-d]|c{2,4}?|(e|f)*");
            prog.deinit(a);
        }
    }.run, .{});
}

fn expectFirst(pattern: []const u8, want: ?u8) !void {
    var prog = try compile(gpa, pattern);
    defer prog.deinit(gpa);
    errdefer std.debug.print("pattern /{s}/\n", .{pattern});
    try std.testing.expectEqual(want, prog.first);
}

test "program: the byte every match starts with" {
    try expectFirst("abc", 'a');
    try expectFirst("a+b", 'a');
    try expectFirst("(?:ab|ac)d", 'a');
    try expectFirst("(?:(?:x))", 'x');
    // The lead byte both encodings share.
    try expectFirst("é|è", 0xc3);
    try expectFirst("中", 0xe4);
}

test "program: no first byte when a match can start with another or with none" {
    try expectFirst("", null);
    try expectFirst("a|b", null);
    try expectFirst("a*b", null);
    try expectFirst("a?", null);
    try expectFirst("é|e", null);
    try expectFirst(".", null);
    try expectFirst("[a]", null);
    // Assertions look at the text around a start; a byte escape matches
    // an invalid byte, which can be part of a character the walk skips.
    try expectFirst("^a", null);
    try expectFirst("\\ba", null);
    try expectFirst("a|$", null);
    try expectFirst("\\xe4", null);
}

test "program: a reversed program has no first byte" {
    var parsed = try parse.parse(gpa, "ab");
    defer parsed.deinit(gpa);
    var rev = try program.compileReversed(gpa, parsed.tree());
    defer rev.deinit(gpa);
    try std.testing.expectEqual(null, rev.first);
}

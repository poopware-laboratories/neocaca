//! `zig build ratio -- <diff>`: the 3:1 rule of AGENTS.md over a unified
//! diff (CI passes `git diff -U0 origin/main...HEAD`), counted against the
//! files in the current directory (`neocaca.ratio`). Exits 1 when the rule
//! fails, 2 on bad usage.

const std = @import("std");
const neocaca = @import("neocaca");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 2) {
        std.debug.print("usage: zig build ratio -- <diff file>\n", .{});
        return 2;
    }
    var buf: [4096]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), io, &buf);
    const tally = try neocaca.ratio.check.checkFile(arena, io, .cwd(), args[1], &out.interface);
    try out.interface.flush();
    return if (tally.passes()) 0 else 1;
}

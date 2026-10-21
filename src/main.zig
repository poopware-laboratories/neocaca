//! Entry point: process setup only. Picks the process allocator, sets up
//! I/O and the arguments, and hands them to `neocaca.app.run`.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");

const Gpa = neocaca.alloc.process.Gpa(neocaca.alloc.process.kindFor(builtin.mode));

pub fn main(init: std.process.Init.Minimal) !u8 {
    var gpa_state: Gpa = .init();
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var threaded: std.Io.Threaded = .init(gpa, .{ .argv0 = .init(init.args), .environ = init.environ });
    defer threaded.deinit();
    const io = threaded.io();

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const raw_args = try init.args.toSlice(arena.allocator());
    const args = try arena.allocator().alloc([]const u8, raw_args.len -| 1);
    for (args, raw_args[1..]) |*arg, raw| arg.* = raw;

    var out_buf: [4096]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), io, &out_buf);
    var err: std.Io.File.Writer = .init(.stderr(), io, &err_buf);
    const code = try neocaca.app.run(args, &out.interface, &err.interface);
    try out.interface.flush();
    try err.interface.flush();
    return @backingInt(code);
}

//! Entry point: process setup only. Picks the process allocator, sets up
//! I/O, the arguments and the terminal, and hands them to `neocaca.app.run`;
//! its panic handler restores the terminal first.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");

/// Puts the terminal back before the default handler prints the panic.
pub const panic = std.debug.FullPanic(restoreThenPanic);

fn restoreThenPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    neocaca.term.tty.restoreActive();
    std.debug.defaultPanic(msg, first_trace_addr);
}

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
    const env: neocaca.app.Env = .{
        .gpa = gpa,
        .io = io,
        .dir = std.Io.Dir.cwd(),
        .in = std.posix.STDIN_FILENO,
        .out = std.posix.STDOUT_FILENO,
    };
    const code = try neocaca.app.run(env, args, &out.interface, &err.interface);
    try out.interface.flush();
    try err.interface.flush();
    return @backingInt(code);
}

//! `zig build release -- <command>`: the steps of a release
//! (`neocaca.release.run` lists them), on the repository in the
//! current directory, with the commit messages on standard input as
//! `git log --format=%B%x00` writes them. Exits 0 on success, 2 on bad
//! usage, 3 on a failure (which `zig build` reports as its own exit 1).

const std = @import("std");
const neocaca = @import("neocaca");

/// More commit text than this is not one week of pull requests.
const max_log_bytes = 16 << 20;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var in_buf: [4096]u8 = undefined;
    var in: std.Io.File.Reader = .init(.stdin(), io, &in_buf);
    const log = try in.interface.allocRemaining(arena, .limited(max_log_bytes));
    var out_buf: [4096]u8 = undefined;
    var out: std.Io.File.Writer = .init(.stdout(), io, &out_buf);
    const code = neocaca.release.run.run(arena, io, .cwd(), args[1..], log, &out.interface) catch |e| {
        try out.interface.flush();
        std.debug.print("neocaca-release: {s}\n", .{@errorName(e)});
        return 3;
    };
    try out.interface.flush();
    return code;
}

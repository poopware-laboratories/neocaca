//! Entry point: picks the process allocator, sets up I/O, and hands the
//! arguments to `run`.

const std = @import("std");
const builtin = @import("builtin");
const neocaca = @import("neocaca");
const build_options = @import("build_options");

const Writer = std.Io.Writer;
const allocator_kind = neocaca.alloc.process.kindFor(builtin.mode);

pub fn main(init: std.process.Init.Minimal) !u8 {
    var safe: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer if (allocator_kind == .safe) {
        _ = safe.deinit();
    };
    const gpa = switch (allocator_kind) {
        .safe => safe.allocator(),
        .mimalloc => neocaca.alloc.mimalloc.allocator(),
    };

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
    const code = try run(args, &out.interface, &err.interface);
    try out.interface.flush();
    try err.interface.flush();
    return code;
}

/// Everything after setup, over plain writers so it can be tested.
/// `args` excludes the program name. Returns the exit code.
fn run(args: []const []const u8, out: *Writer, err: *Writer) Writer.Error!u8 {
    const command = neocaca.cli.parse(args) catch |e| {
        try err.print("neocaca: {s}\n\n{s}", .{ switch (e) {
            error.UnknownFlag => "unknown flag",
            error.FilesBeforeSeparator => "put every file after --",
        }, neocaca.cli.usage });
        return 2;
    };
    switch (command) {
        .help => try out.writeAll(neocaca.cli.usage),
        .version => try out.print("neocaca {s}\n", .{build_options.version}),
        .edit => {
            try err.writeAll("neocaca: the editor is not written yet; see the open issues\n");
            return 1;
        },
    }
    return 0;
}

fn expectRun(args: []const []const u8, code: u8, out: []const u8, err: []const u8) !void {
    var out_buf: [1024]u8 = undefined;
    var err_buf: [1024]u8 = undefined;
    var out_w: Writer = .fixed(&out_buf);
    var err_w: Writer = .fixed(&err_buf);
    try std.testing.expectEqual(code, try run(args, &out_w, &err_w));
    try std.testing.expectEqualStrings(out, out_w.buffered());
    try std.testing.expectEqualStrings(err, err_w.buffered());
}

test "--help prints the usage and succeeds" {
    try expectRun(&.{"--help"}, 0, neocaca.cli.usage, "");
}

test "--version prints the version from build.zig.zon" {
    try expectRun(&.{"-V"}, 0, "neocaca " ++ build_options.version ++ "\n", "");
}

test "an unknown flag is a usage error on stderr" {
    try expectRun(&.{"--nope"}, 2, "", "neocaca: unknown flag\n\n" ++ neocaca.cli.usage);
}

test "files before -- explain how to fix the command" {
    try expectRun(&.{ "a", "--", "b" }, 2, "", "neocaca: put every file after --\n\n" ++ neocaca.cli.usage);
}

test "editing says plainly that it does not exist yet" {
    try expectRun(&.{"a.zig"}, 1, "", "neocaca: the editor is not written yet; see the open issues\n");
}

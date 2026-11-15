//! The repository the tests of `run.zig` work on: a temporary directory
//! with build.zig.zon and CHANGELOG.md, and the command's output.

const std = @import("std");
const run = @import("run.zig");

const io = std.testing.io;

pub const zon = ".{\n    .name = .caca,\n    .version = \"0.1.0\",\n}\n";
pub const changelog = "# Changelog\n\nEvery release of caca.\n";

pub const Repo = struct {
    tmp: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    out_buf: [4096]u8 = undefined,
    out: std.Io.Writer = undefined,

    pub fn init(self: *Repo) !void {
        self.tmp = std.testing.tmpDir(.{});
        self.arena = .init(std.testing.allocator);
        self.out = .fixed(&self.out_buf);
        try self.tmp.dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = zon });
        try self.tmp.dir.writeFile(io, .{ .sub_path = "CHANGELOG.md", .data = changelog });
    }

    pub fn deinit(self: *Repo) void {
        self.arena.deinit();
        self.tmp.cleanup();
    }

    pub fn cmd(self: *Repo, args: []const []const u8, log: []const u8) !u8 {
        self.out = .fixed(&self.out_buf);
        return run.run(self.arena.allocator(), io, self.tmp.dir, args, log, &self.out);
    }

    pub fn read(self: *Repo, path: []const u8) ![]const u8 {
        return self.tmp.dir.readFileAlloc(io, path, self.arena.allocator(), .limited(run.max_file_bytes + 1));
    }
};

/// Two commits as `git log --format=%B%x00` writes them.
pub const two_commits = "feat(edit): add a verb (#50)\n\x00\nfix(app): keep the pause (#47)\n\nBody.\n\x00\n";

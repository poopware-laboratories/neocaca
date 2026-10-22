//! Tests for `loop.zig`: a session driven by a scripted terminal.

const std = @import("std");
const term = @import("../term.zig");
const loop = @import("loop.zig");
const Session = @import("session.zig").Session;

const io = std.testing.io;
const gpa = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const Step = union(enum) {
    /// Bytes the terminal sends.
    input: []const u8,
    /// The terminal changes size (null: it stops reporting one).
    resize: ?term.Size,
    /// The wait times out.
    idle,
    /// The save in flight finishes and wakes the wait.
    saved,
};

/// Plays `steps`, then reports the terminal gone.
const Script = struct {
    steps: []const Step,
    i: usize = 0,
    /// What is left of the current input step.
    pending: []const u8 = "",
    current_size: ?term.Size = null,
    /// The timeout of every wait, in order.
    timeouts: [64]i32 = undefined,
    waits: usize = 0,
    /// How much output there was when each wait began.
    written: [64]usize = undefined,
    out: ?*std.Io.Writer = null,
    session: ?*Session = null,
    /// How often the editor stopped itself, and the size it came back to.
    suspends: usize = 0,
    resumed_size: ?term.Size = null,

    pub fn wait(self: *Script, timeout_ms: i32) !term.tty.Ready {
        self.timeouts[self.waits] = timeout_ms;
        self.written[self.waits] = if (self.out) |w| w.end else 0;
        self.waits += 1;
        if (self.pending.len > 0) return .{ .input = true };
        if (self.i == self.steps.len) return .{ .input = true };
        const step = self.steps[self.i];
        self.i += 1;
        switch (step) {
            .input => |bytes| {
                self.pending = bytes;
                return .{ .input = true };
            },
            .resize => |s| {
                self.current_size = s;
                return .{ .woken = true };
            },
            .idle => return .{},
            .saved => {
                const job = self.session.?.saving.?;
                while (!job.isFinished()) try std.Io.sleep(io, .fromMilliseconds(1), .awake);
                return .{ .woken = true };
            },
        }
    }

    pub fn read(self: *Script, buf: []u8) !usize {
        const n = @min(buf.len, self.pending.len);
        @memcpy(buf[0..n], self.pending[0..n]);
        self.pending = self.pending[n..];
        return n;
    }

    pub fn suspendProcess(self: *Script) void {
        self.suspends += 1;
        if (self.resumed_size) |s| self.current_size = s;
    }

    pub fn size(self: *const Script) ?term.Size {
        return self.current_size;
    }
};

const Fixture = struct {
    tmp: std.testing.TmpDir,
    session: Session,
    out_buf: []u8,
    out: std.Io.Writer,

    fn init(self: *Fixture, path: ?[]const u8, text: ?[]const u8) !void {
        self.tmp = std.testing.tmpDir(.{});
        errdefer self.tmp.cleanup();
        if (text) |t| try self.tmp.dir.writeFile(io, .{ .sub_path = path.?, .data = t });
        self.session = try .init(gpa, io, self.tmp.dir, path, 20, 5);
        errdefer self.session.deinit();
        self.out_buf = try gpa.alloc(u8, 1 << 16);
        self.out = .fixed(self.out_buf);
    }

    fn deinit(self: *Fixture) void {
        gpa.free(self.out_buf);
        self.session.deinit();
        self.tmp.cleanup();
    }

    fn run(self: *Fixture, script: *Script) !void {
        script.out = &self.out;
        script.session = &self.session;
        try loop.run(&self.session, script, &self.out);
    }
};

test "loop: typed keys and :wq write the file and end the loop" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{ .steps = &.{
        .{ .input = "i" }, .{ .input = "a" },  .{ .input = "\x1b" }, .idle,
        .{ .input = ":" }, .{ .input = "w" },  .{ .input = "q" },    .{ .input = "\r" },
        .saved,            .{ .input = "ix" },
    } };
    try f.run(&script);
    try expect(f.session.done());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("ab\n", try f.tmp.dir.readFile(io, "a", &buf));
    // The last input was never read.
    try expectEqual(9, script.i);
}

test "loop: typing goes on while a save is written, until it wakes the loop" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{ .steps = &.{ .{ .input = ":w\r" }, .{ .input = "ix\x1b" }, .idle, .saved } };
    try f.run(&script);
    try expectEqual(null, f.session.saving);
    try expectEqualStrings("xb\n", f.session.ed.doc.text());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("b\n", try f.tmp.dir.readFile(io, "a", &buf));
    try expectEqualStrings("\"a\" written, 1 line", f.session.ed.message.text());
    // The report is drawn before the terminal goes away.
    try expect(std.mem.indexOf(u8, f.out.buffered(), "written") != null);
}

test "loop: a terminal that goes away during a save still finishes it" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{ .steps = &.{ .{ .input = "ix\x1b" }, .idle, .{ .input = ":wq\r" } } };
    try f.run(&script);
    try expectEqual(null, f.session.saving);
    try expect(f.session.done());
    var buf: [16]u8 = undefined;
    try expectEqualStrings("xb\n", try f.tmp.dir.readFile(io, "a", &buf));
}

test "loop: Ctrl-z suspends, then the whole screen is drawn at the new size" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{
        .steps = &.{ .{ .input = "\x1a" }, .{ .input = "ix" } },
        .resumed_size = .{ .width = 30, .height = 6 },
    };
    try f.run(&script);
    try expectEqual(1, script.suspends);
    try expectEqual(30, f.session.ed.width);
    try expectEqual(6, f.session.ed.height);
    // The frame after the suspend clears the screen; the one after typing
    // does not.
    const out = f.out.buffered();
    try expect(std.mem.indexOf(u8, out[script.written[0]..script.written[1]], "\x1b[2J") != null);
    try expect(std.mem.indexOf(u8, out[script.written[1]..], "\x1b[2J") == null);
    try expectEqualStrings("xb\n", f.session.ed.doc.text());
}

test "loop: after a suspend at the same size the screen is still drawn whole" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{ .steps = &.{.{ .input = "\x1a" }} };
    try f.run(&script);
    try expectEqual(1, script.suspends);
    try expectEqual(20, f.session.ed.width);
    const out = f.out.buffered();
    try expect(std.mem.indexOf(u8, out[script.written[0]..script.written[1]], "\x1b[2J") != null);
}

test "loop: no suspend without Ctrl-z" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{ .steps = &.{.{ .input = "z\x1bz" }} };
    try f.run(&script);
    try expectEqual(0, script.suspends);
}

test "loop: each frame is written before the next wait" {
    var f: Fixture = undefined;
    try f.init("a", "b\n");
    defer f.deinit();
    var script: Script = .{ .steps = &.{ .{ .input = "i" }, .{ .input = "z" } } };
    try f.run(&script);
    try expect(script.written[0] > 0);
    try expect(script.written[1] > script.written[0]);
    try expect(script.written[2] > script.written[1]);
    try expect(std.mem.indexOf(u8, f.out.buffered(), "INSERT") != null);
}

test "loop: a terminal that has gone ends the loop without quitting" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    var script: Script = .{ .steps = &.{.{ .input = "ix" }} };
    try f.run(&script);
    try expect(!f.session.done());
    try expectEqualStrings("x\n", f.session.ed.doc.text());
}

test "loop: a lone Escape is a key once the escape timeout passes" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    var script: Script = .{ .steps = &.{ .{ .input = "i" }, .{ .input = "\x1b" }, .idle, .{ .input = "x" } } };
    try f.run(&script);
    // Waits without limit, except right after the Escape.
    try expectEqual(-1, script.timeouts[0]);
    try expectEqual(-1, script.timeouts[1]);
    try expectEqual(loop.escape_timeout_ms, script.timeouts[2]);
    try expectEqual(-1, script.timeouts[3]);
    // "x" in normal mode deletes nothing and selects the line.
    try expectEqualStrings("\n", f.session.ed.doc.text());
    try expectEqual(.normal, f.session.ed.mode);
}

test "loop: Escape and a key within the timeout are Alt with the key" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    var script: Script = .{ .steps = &.{ .{ .input = "\x1b" }, .{ .input = "k" } } };
    try f.run(&script);
    try expectEqual(.prompt, f.session.ed.mode);
}

test "loop: a resize redraws at the terminal's new size" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    var script: Script = .{ .steps = &.{.{ .resize = .{ .width = 30, .height = 7 } }} };
    try f.run(&script);
    try expectEqual(30, f.session.ed.width);
    try expectEqual(7, f.session.ed.height);
    try expectEqual(30, f.session.front.width);
    try expectEqual(7, f.session.front.height);
}

test "loop: a resize to an unknown size keeps the old one" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    var script: Script = .{ .steps = &.{.{ .resize = null }} };
    try f.run(&script);
    try expectEqual(20, f.session.ed.width);
    try expectEqual(5, f.session.ed.height);
}

test "loop: input longer than one read arrives whole" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    const n = 3 * loop.read_size + 7;
    var paste: [n + 13]u8 = undefined;
    @memcpy(paste[0..7], "i\x1b[200~");
    @memset(paste[7 .. n + 7], 'p');
    @memcpy(paste[n + 7 ..], "\x1b[201~");
    var script: Script = .{ .steps = &.{.{ .input = &paste }} };
    try f.run(&script);
    try expectEqual(n + 1, f.session.ed.doc.text().len);
}

test "loop: a failed write ends the loop with the error" {
    var f: Fixture = undefined;
    try f.init(null, null);
    defer f.deinit();
    var small: [4]u8 = undefined;
    var w: std.Io.Writer = .fixed(&small);
    var script: Script = .{ .steps = &.{} };
    try std.testing.expectError(error.WriteFailed, loop.run(&f.session, &script, &w));
}

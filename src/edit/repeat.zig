//! Repeating a motion `count` times on every selection without paying
//! count × selections. A step depends only on the cursor it starts from,
//! so two walks that reach the same cursor go on together. Each walk is
//! kept as a trail of the cursors it passed; a later selection whose walk
//! lands on the trail reads its result off it instead of walking again.

const std = @import("std");
const Selection = @import("selection.zig").Selection;

const Error = error{OutOfMemory};

/// What `count` (at least 1) steps make from each of `starts`, which are
/// sorted ascending. `ctx.step(cursor)` makes one step's selection, or
/// null when it cannot move; a step that keeps its cursor would keep it
/// forever, so a walk stops there. `forward` says the steps never lower
/// the cursor (otherwise they never raise it). `out[i]` is the last
/// step's selection from `starts[i]`, null when a step failed.
pub fn repeat(gpa: std.mem.Allocator, ctx: anytype, forward: bool, starts: []const usize, count: usize, out: []?Selection) Error!void {
    std.debug.assert(count >= 1 and out.len == starts.len);
    var trail: Trail(@TypeOf(ctx)) = .{ .ctx = ctx, .forward = forward };
    defer trail.cursors.deinit(gpa);
    defer trail.made.deinit(gpa);
    for (0..starts.len) |k| {
        // Walks go in the motion's direction, so each lands ahead of the last.
        const i = if (forward) k else starts.len - 1 - k;
        out[i] = try trail.walk(gpa, starts[i], count, k + 1 == starts.len);
    }
}

fn Trail(comptime Ctx: type) type {
    return struct {
        ctx: Ctx,
        forward: bool,
        /// The cursors one walk passed, in its direction, and the selection
        /// each step made (`made[j]` is the step to `cursors[j + 1]`).
        cursors: std.ArrayList(usize) = .empty,
        made: std.ArrayList(Selection) = .empty,
        /// How the trail ends once it can go no further.
        end: union(enum) { open, stays: Selection, fails } = .open,

        const Self = @This();

        fn walk(self: *Self, gpa: std.mem.Allocator, start: usize, count: usize, last: bool) Error!?Selection {
            var cur = start;
            var made: ?Selection = null;
            var k: usize = 0;
            while (k < count) {
                if (self.find(cur)) |j| return self.at(gpa, j + count - k);
                // Past the trail: this walk starts a new one, unless no
                // later walk could use it.
                if (!last and self.past(cur)) {
                    self.cursors.clearRetainingCapacity();
                    self.made.clearRetainingCapacity();
                    self.end = .open;
                    try self.cursors.append(gpa, cur);
                    return self.at(gpa, count - k);
                }
                const n = self.ctx.step(cur) orelse return null;
                if (n.cursor == cur) return n;
                cur = n.cursor;
                made = n;
                k += 1;
            }
            return made;
        }

        /// Where `cur` is on the trail.
        fn find(self: *const Self, cur: usize) ?usize {
            const items = self.cursors.items;
            var lo: usize = 0;
            var hi = items.len;
            while (lo < hi) {
                const mid = lo + (hi - lo) / 2;
                if (items[mid] == cur) return mid;
                if ((items[mid] < cur) == self.forward) lo = mid + 1 else hi = mid;
            }
            return null;
        }

        fn past(self: *const Self, cur: usize) bool {
            const items = self.cursors.items;
            if (items.len == 0) return true;
            const last = items[items.len - 1];
            return if (self.forward) cur > last else cur < last;
        }

        /// The selection `j` (at least 1) steps from the trail's start,
        /// extending the trail as far as it needs.
        fn at(self: *Self, gpa: std.mem.Allocator, j: usize) Error!?Selection {
            std.debug.assert(j >= 1);
            while (self.made.items.len < j and self.end == .open) {
                const from = self.cursors.items[self.cursors.items.len - 1];
                const n = self.ctx.step(from) orelse {
                    self.end = .fails;
                    break;
                };
                if (n.cursor == from) {
                    self.end = .{ .stays = n };
                    break;
                }
                try self.cursors.ensureUnusedCapacity(gpa, 1);
                try self.made.append(gpa, n);
                self.cursors.appendAssumeCapacity(n.cursor);
            }
            if (j <= self.made.items.len) return self.made.items[j - 1];
            return switch (self.end) {
                .open => unreachable,
                .stays => |n| n,
                .fails => null,
            };
        }
    };
}

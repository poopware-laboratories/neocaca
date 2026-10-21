//! `Buffer`: the text of one file as one contiguous byte array with its
//! line index. The text always ends with a newline, so every line,
//! the last included, has one and every offset below `len` is a character.
//! Edits are change sets (`change.zig`) applied all at once: the new text
//! and index are built first, so a failed edit leaves the buffer untouched.

const std = @import("std");
const change = @import("change.zig");
const lines = @import("lines.zig");

pub const Change = change.Change;

pub const ApplyError = change.Error || error{ OutOfMemory, FinalNewline };

pub const Buffer = struct {
    gpa: std.mem.Allocator,
    /// Owned. Ends with '\n'.
    text: []u8,
    /// Owned. `line_starts[n]` is where line `n` starts.
    line_starts: []usize,

    /// A buffer holding a copy of `initial`, with a newline added when it
    /// does not end with one.
    pub fn init(gpa: std.mem.Allocator, initial: []const u8) error{OutOfMemory}!Buffer {
        const add = initial.len == 0 or initial[initial.len - 1] != '\n';
        const text = try gpa.alloc(u8, initial.len + @intFromBool(add));
        errdefer gpa.free(text);
        @memcpy(text[0..initial.len], initial);
        if (add) text[initial.len] = '\n';
        return .{ .gpa = gpa, .text = text, .line_starts = try lines.starts(gpa, text) };
    }

    pub fn deinit(self: *Buffer) void {
        self.gpa.free(self.text);
        self.gpa.free(self.line_starts);
        self.* = undefined;
    }

    /// Borrowed; valid until the next edit.
    pub fn bytes(self: *const Buffer) []const u8 {
        return self.text;
    }

    pub fn len(self: *const Buffer) usize {
        return self.text.len;
    }

    pub fn lineCount(self: *const Buffer) usize {
        return self.line_starts.len;
    }

    pub fn lineStart(self: *const Buffer, n: usize) usize {
        return self.line_starts[n];
    }

    /// Offset of the newline ending line `n`.
    pub fn lineEnd(self: *const Buffer, n: usize) usize {
        return if (n + 1 < self.line_starts.len) self.line_starts[n + 1] - 1 else self.text.len - 1;
    }

    /// The line holding `offset`.
    pub fn lineOf(self: *const Buffer, offset: usize) usize {
        return lines.lineOf(self.line_starts, offset);
    }

    /// Line `n` without its newline. Borrowed; valid until the next edit.
    pub fn line(self: *const Buffer, n: usize) []const u8 {
        return self.text[self.lineStart(n)..self.lineEnd(n)];
    }

    /// Applies a change set. The result must still end with a newline; on
    /// any error the buffer is unchanged.
    pub fn apply(self: *Buffer, changes: []const Change) ApplyError!void {
        try change.validate(changes, self.text.len);
        const n = change.newLen(changes, self.text.len);
        const text = try self.gpa.alloc(u8, n);
        errdefer self.gpa.free(text);
        change.applyInto(changes, self.text, text);
        if (n == 0 or text[n - 1] != '\n') return error.FinalNewline;
        const starts = try lines.starts(self.gpa, text);
        self.gpa.free(self.text);
        self.gpa.free(self.line_starts);
        self.text = text;
        self.line_starts = starts;
    }
};

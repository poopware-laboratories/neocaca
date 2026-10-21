//! The `:` command line: what a typed command asks for. Parsing only;
//! the editor carries it out.

const std = @import("std");

pub const Command = union(enum) {
    /// An empty line.
    none,
    /// `:w [file]`, `:wq [file]`, `:x`.
    write: struct {
        /// Borrowed from the parsed line.
        path: ?[]const u8 = null,
        quit: bool = false,
        /// `:x` writes only when there are unsaved changes.
        only_if_modified: bool = false,
    },
    /// `:q`, `:q!`.
    quit: struct { force: bool = false },
    /// `:e <file>`, `:e!`, `:e! <file>`.
    edit: struct {
        /// Borrowed from the parsed line; null reloads the current file.
        path: ?[]const u8 = null,
        force: bool = false,
    },
    /// `:<n>`, counted from 1.
    goto_line: usize,
};

pub const ParseError = error{ UnknownCommand, MissingFile, TooManyArguments, BadLine };

pub fn describe(e: ParseError) []const u8 {
    return switch (e) {
        error.UnknownCommand => "unknown command",
        error.MissingFile => "a file name is needed",
        error.TooManyArguments => "too many arguments",
        error.BadLine => "no such line",
    };
}

/// Parses `line`, the text typed after `:`.
pub fn parse(line: []const u8) ParseError!Command {
    var words = std.mem.tokenizeAny(u8, line, " \t");
    const name = words.next() orelse return .none;
    const arg = words.next();
    if (words.next() != null) return error.TooManyArguments;
    if (std.ascii.isDigit(name[0])) {
        for (name) |c| if (!std.ascii.isDigit(c)) return error.UnknownCommand;
        if (arg != null) return error.TooManyArguments;
        return .{ .goto_line = std.fmt.parseInt(usize, name, 10) catch return error.BadLine };
    }
    const Name = enum { w, write, wq, x, q, quit, @"q!", e, edit, @"e!" };
    const which = std.meta.stringToEnum(Name, name) orelse return error.UnknownCommand;
    switch (which) {
        .w, .write => return .{ .write = .{ .path = arg } },
        .wq => return .{ .write = .{ .path = arg, .quit = true } },
        .x, .q, .quit, .@"q!" => if (arg != null) return error.TooManyArguments,
        .e, .edit => return .{ .edit = .{ .path = arg orelse return error.MissingFile } },
        .@"e!" => return .{ .edit = .{ .path = arg, .force = true } },
    }
    return switch (which) {
        .x => .{ .write = .{ .quit = true, .only_if_modified = true } },
        .@"q!" => .{ .quit = .{ .force = true } },
        else => .{ .quit = .{} },
    };
}

//! The `:` command line: what a typed command asks for. Parsing only;
//! the editor carries it out.

const std = @import("std");
const input = @import("../input.zig");

const Key = input.Key;
const keyname = input.keyname;

pub const Command = union(enum) {
    /// An empty line.
    none,
    /// `:w [file]`, `:w! [file]`, `:wq [file]`, `:x`.
    write: struct {
        /// Borrowed from the parsed line.
        path: ?[]const u8 = null,
        quit: bool = false,
        /// `:x` writes only when there are unsaved changes.
        only_if_modified: bool = false,
        /// `:w!` writes a read-only file too.
        force: bool = false,
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
    /// `:map <normal|insert> <key> <keys>`.
    map: struct {
        mode: input.mapping.Mode,
        key: Key,
        /// Borrowed from the parsed line; valid key notation, at most
        /// `keyname.max_keys` keys.
        keys: []const u8,
    },
    /// `:unmap <normal|insert> <key>`.
    unmap: struct { mode: input.mapping.Mode, key: Key },
};

pub const ParseError = error{
    UnknownCommand,
    MissingFile,
    MissingArgument,
    TooManyArguments,
    BadLine,
    BadMode,
    BadKey,
    NotOneKey,
    TooManyKeys,
};

pub fn describe(e: ParseError) []const u8 {
    return switch (e) {
        error.UnknownCommand => "unknown command",
        error.MissingFile => "a file name is needed",
        error.TooManyArguments => "too many arguments",
        error.BadLine => "no such line",
        error.MissingArgument => "usage: :map <mode> <key> <keys>, :unmap <mode> <key>",
        error.BadMode => "the mode is normal or insert",
        error.BadKey => "bad key name",
        error.NotOneKey => "only one key can be mapped",
        error.TooManyKeys => std.fmt.comptimePrint("a key maps to at most {d} keys", .{keyname.max_keys}),
    };
}

/// Parses `line`, the text typed after `:`.
pub fn parse(line: []const u8) ParseError!Command {
    var words = std.mem.tokenizeAny(u8, line, " \t");
    const name = words.next() orelse return .none;
    var args: [3][]const u8 = undefined;
    var n: usize = 0;
    while (words.next()) |w| : (n += 1) {
        if (n == args.len) return error.TooManyArguments;
        args[n] = w;
    }
    if (std.mem.eql(u8, name, "map")) {
        if (n < 3) return error.MissingArgument;
        var buf: [keyname.max_keys]Key = undefined;
        _ = try keys(args[2], &buf);
        return .{ .map = .{ .mode = try mode(args[0]), .key = try oneKey(args[1]), .keys = args[2] } };
    }
    if (std.mem.eql(u8, name, "unmap")) {
        if (n < 2) return error.MissingArgument;
        if (n > 2) return error.TooManyArguments;
        return .{ .unmap = .{ .mode = try mode(args[0]), .key = try oneKey(args[1]) } };
    }
    if (n > 1) return error.TooManyArguments;
    const arg: ?[]const u8 = if (n == 1) args[0] else null;
    if (std.ascii.isDigit(name[0])) {
        for (name) |c| if (!std.ascii.isDigit(c)) return error.UnknownCommand;
        if (arg != null) return error.TooManyArguments;
        return .{ .goto_line = std.fmt.parseInt(usize, name, 10) catch return error.BadLine };
    }
    const Name = enum { w, write, @"w!", wq, x, q, quit, @"q!", e, edit, @"e!" };
    const which = std.meta.stringToEnum(Name, name) orelse return error.UnknownCommand;
    switch (which) {
        .w, .write => return .{ .write = .{ .path = arg } },
        .@"w!" => return .{ .write = .{ .path = arg, .force = true } },
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

fn mode(word: []const u8) ParseError!input.mapping.Mode {
    return std.meta.stringToEnum(input.mapping.Mode, word) orelse error.BadMode;
}

/// The keys `text` names, in `out`; the result is a slice of it.
pub fn keys(text: []const u8, out: *[keyname.max_keys]Key) ParseError![]Key {
    return keyname.parse(text, out) catch |e| switch (e) {
        error.BadKey => error.BadKey,
        error.TooManyKeys => error.TooManyKeys,
    };
}

fn oneKey(text: []const u8) ParseError!Key {
    var buf: [keyname.max_keys]Key = undefined;
    const got = keys(text, &buf) catch |e| switch (e) {
        error.TooManyKeys => return error.NotOneKey,
        else => |other| return other,
    };
    if (got.len != 1) return error.NotOneKey;
    return got[0];
}

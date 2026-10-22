//! What a submitted prompt does: `:` commands, `/` and `?` searches, and
//! the regex prompts that select, split, keep or drop selections. Also the
//! search repeats (`n`, `N`, `Alt-n`) and `*`, which share the pattern.

const std = @import("std");
const edit = @import("../edit.zig");
const input = @import("../input.zig");
const regex = @import("../regex.zig");
const commands = @import("commands.zig");
const editor = @import("editor.zig");

const Editor = editor.Editor;
const Error = editor.Error;
const Regex = regex.Regex;
const selecting = edit.selecting;

/// Runs the prompt's text as its kind asks. The prompt is closed already.
pub fn submit(ed: *Editor) Error!void {
    const text = ed.prompt.text();
    switch (ed.prompt_kind) {
        .command => try command(ed, text),
        .search_forward, .search_backward => {
            const dir: edit.search.Direction = if (ed.prompt_kind == .search_forward) .forward else .backward;
            if (text.len > 0) {
                var re = compile(ed, text) orelse return;
                errdefer re.deinit();
                try ed.regs.set(edit.registers.search, &.{text});
                if (ed.search) |*old| old.deinit();
                ed.search = re;
            }
            try searchNext(ed, dir, false);
        },
        .select, .split, .keep, .drop => {
            var re = compile(ed, text) orelse return;
            defer re.deinit();
            const found = switch (ed.prompt_kind) {
                .select => try selecting.selectMatches(&ed.doc, &re),
                .split => try selecting.split(&ed.doc, &re),
                .keep => try selecting.keepMatching(&ed.doc, &re, true),
                else => try selecting.keepMatching(&ed.doc, &re, false),
            };
            // Drop fails only when every selection matches, and split
            // when the matches leave no character outside them.
            if (!found) ed.message.set(true, "{s}", .{switch (ed.prompt_kind) {
                .drop => "every selection matches",
                .split => "nothing left between the matches",
                else => "no matches",
            }});
        },
    }
}

/// The compiled pattern, or null after showing why it is bad.
fn compile(ed: *Editor, pattern: []const u8) ?Regex {
    return Regex.compile(ed.gpa, pattern) catch |e| {
        ed.message.set(true, "bad regex: {s}", .{@errorName(e)});
        return null;
    };
}

/// Selects the next match of the last pattern in `dir`.
pub fn searchNext(ed: *Editor, dir: edit.search.Direction, add: bool) Error!void {
    const re = if (ed.search) |*r| r else {
        ed.message.set(true, "no search pattern", .{});
        return;
    };
    switch (try edit.search.next(&ed.doc, re, dir, add)) {
        .found => {},
        .wrapped => ed.message.set(false, "search wrapped", .{}),
        .not_found => {
            const pattern = ed.regs.get(edit.registers.search);
            ed.message.set(true, "not found: {s}", .{if (pattern.len > 0) pattern[0] else ""});
        },
    }
}

/// `*`: the main selection, escaped, becomes the search pattern.
pub fn searchSelection(ed: *Editor) Error!void {
    const r = ed.doc.primary().range(ed.doc.text());
    const pattern = try regex.escape(ed.gpa, ed.doc.text()[r.start..r.end]);
    defer ed.gpa.free(pattern);
    var re = compile(ed, pattern) orelse return;
    errdefer re.deinit();
    try ed.regs.set(edit.registers.search, &.{pattern});
    if (ed.search) |*old| old.deinit();
    ed.search = re;
}

fn command(ed: *Editor, line: []const u8) Error!void {
    const c = commands.parse(line) catch |e| {
        ed.message.set(true, "{s}", .{commands.describe(e)});
        return;
    };
    switch (c) {
        .none => {},
        .goto_line => |n| try selecting.move(&ed.doc, .{ .line = n }, 1, false, ed.options.tab_width),
        .quit => |q| {
            if (!q.force and ed.doc.isSaving()) return stillWriting(ed);
            if (!q.force and ed.doc.isModified()) {
                ed.message.set(true, "unsaved changes; :q! discards them", .{});
                return;
            }
            ed.quit = true;
        },
        .write => |w| {
            if (w.only_if_modified and !ed.doc.isModified()) {
                ed.quit = w.quit;
                return;
            }
            const path = w.path orelse ed.path orelse return noFileName(ed);
            try ed.ask(.{ .save = .{ .path = path, .quit = w.quit } });
        },
        .edit => |e| {
            if (!e.force and ed.doc.isSaving()) return stillWriting(ed);
            if (!e.force and ed.doc.isModified()) {
                ed.message.set(true, "unsaved changes; :e! discards them", .{});
                return;
            }
            try ed.ask(.{ .load = e.path orelse ed.path orelse return noFileName(ed) });
        },
        .map => |m| {
            var buf: [input.keyname.max_keys]input.Key = undefined;
            // Parsing checked the keys already.
            const keys = commands.keys(m.keys, &buf) catch unreachable;
            ed.mappings.set(m.mode, m.key, keys) catch |e| switch (e) {
                error.TooManyMappings => ed.message.set(true, "at most {d} keys can be mapped", .{input.mapping.max_mappings}),
                error.OutOfMemory => |oom| return oom,
            };
        },
        .unmap => |u| if (!ed.mappings.remove(u.mode, u.key)) {
            var name: [input.keyname.max_name]u8 = undefined;
            ed.message.set(true, "{s} is not mapped in {t} mode", .{ input.keyname.format(u.key, &name), u.mode });
        },
    }
}

/// Whether the text is saved is not known until the save in flight ends.
fn stillWriting(ed: *Editor) void {
    ed.message.set(true, "a save is still being written", .{});
}

fn noFileName(ed: *Editor) void {
    ed.message.set(true, "no file name; :w <file>", .{});
}

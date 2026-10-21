//! `Editor`: the whole editing state (the document, registers, keymap,
//! mode, prompt, view, message) and the routing of keys and pastes to the
//! pure modules. It does no I/O: saving and loading are handed to the
//! shell as a `Request`, which reports back with `finishSave` and
//! `finishLoad`. Prompts are run by `prompting.zig`, drawing is
//! `layout.zig`.

const std = @import("std");
const edit = @import("../edit.zig");
const fs = @import("../fs.zig");
const input = @import("../input.zig");
const regex = @import("../regex.zig");
const render = @import("../render.zig");
const ui = @import("../ui.zig");
const layout = @import("layout.zig");
const prompting = @import("prompting.zig");

const Action = input.Action;
const Document = edit.Document;
const Key = input.Key;
const Regex = regex.Regex;
const selecting = edit.selecting;
const verbs = edit.verbs;

pub const Mode = enum { normal, insert, prompt };

/// Errors that are bugs, not conditions: an edit the edit functions built
/// wrongly. Running out of memory is shown as a message instead.
pub const Error = edit.verbs.Error;

pub const Options = struct {
    tab_width: usize = 8,
    indent_width: usize = 4,
    scrolloff: usize = 3,
};

/// What the shell must do for the editor. Paths are borrowed from the
/// editor until the request is finished.
pub const Request = union(enum) {
    /// Write the document's text to `path`, then `finishSave`.
    save: Save,
    /// Read `path`, then `finishLoad`.
    load: []const u8,

    pub const Save = struct { path: []const u8, quit: bool };
};

/// The line under the status line: what the last command reported.
pub const Message = struct {
    pub const max = 256;

    buf: [max]u8 = undefined,
    len: usize = 0,
    is_error: bool = false,

    pub fn text(self: *const Message) []const u8 {
        return self.buf[0..self.len];
    }

    /// Sets the message, cut at `max` bytes.
    pub fn set(self: *Message, is_error: bool, comptime fmt: []const u8, args: anytype) void {
        var w: std.Io.Writer = .fixed(&self.buf);
        // A message too long for the buffer keeps what fits.
        w.print(fmt, args) catch {};
        self.len = w.end;
        self.is_error = is_error;
    }

    pub fn clear(self: *Message) void {
        self.len = 0;
        self.is_error = false;
    }
};

pub const Editor = struct {
    gpa: std.mem.Allocator,
    doc: Document,
    regs: edit.Registers,
    keymap: input.Keymap = .{},
    mode: Mode = .normal,
    prompt: ui.prompt.Prompt,
    prompt_kind: input.action.Prompt = .command,
    view: ui.View = .{},
    theme: ui.Theme = .{},
    options: Options = .{},
    /// Owned; null for a buffer without a file.
    path: ?[]u8 = null,
    message: Message = .{},
    /// The last search pattern, compiled.
    search: ?Regex = null,
    /// Set once the editor should exit.
    quit: bool = false,
    /// The screen size, for page scrolling.
    width: usize = 80,
    height: usize = 24,
    request: ?Request = null,
    /// Owned storage for the path of `request`.
    request_path: std.ArrayList(u8) = .empty,

    /// An editor on `text`, the contents of `path` (null for a buffer
    /// without a file). Both are copied.
    pub fn init(gpa: std.mem.Allocator, path: ?[]const u8, text: []const u8) error{OutOfMemory}!Editor {
        var doc: Document = try .init(gpa, text);
        errdefer doc.deinit();
        const owned = if (path) |p| try gpa.dupe(u8, p) else null;
        return .{ .gpa = gpa, .doc = doc, .regs = .init(gpa), .prompt = .init(gpa), .path = owned };
    }

    pub fn deinit(self: *Editor) void {
        self.doc.deinit();
        self.regs.deinit();
        self.prompt.deinit();
        if (self.path) |p| self.gpa.free(p);
        if (self.search) |*re| re.deinit();
        self.request_path.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn resize(self: *Editor, width: usize, height: usize) void {
        self.width = width;
        self.height = height;
    }

    /// The rows the document gets: all but the status and message lines.
    pub fn textRows(self: *const Editor) usize {
        return self.height -| 2;
    }

    pub const draw = layout.draw;

    pub fn key(self: *Editor, k: Key) Error!void {
        if (self.mode != .prompt) self.message.clear();
        self.handleKey(k) catch |e| switch (e) {
            error.OutOfMemory => self.outOfMemory(),
            else => |other| return other,
        };
    }

    /// Bracketed paste: typed at every cursor in insert mode, inserted
    /// before the selections in normal mode, added to the prompt there.
    pub fn paste(self: *Editor, bytes: []const u8) Error!void {
        self.message.clear();
        self.handlePaste(bytes) catch |e| switch (e) {
            error.OutOfMemory => self.outOfMemory(),
            else => |other| return other,
        };
    }

    fn outOfMemory(self: *Editor) void {
        self.message.set(true, "out of memory", .{});
    }

    /// The pending request, which the shell now carries out.
    pub fn takeRequest(self: *Editor) ?Request {
        defer self.request = null;
        return self.request;
    }

    /// Asks the shell for `r`, with its path copied.
    pub fn ask(self: *Editor, r: Request) error{OutOfMemory}!void {
        const path = switch (r) {
            .save => |s| s.path,
            .load => |p| p,
        };
        self.request_path.clearRetainingCapacity();
        try self.request_path.appendSlice(self.gpa, path);
        const own = self.request_path.items;
        self.request = switch (r) {
            .save => |s| .{ .save = .{ .path = own, .quit = s.quit } },
            .load => .{ .load = own },
        };
    }

    /// Reports how the save of `s` went.
    pub fn finishSave(self: *Editor, s: Request.Save, result: fs.file.SaveError!void) void {
        self.saved(s, result) catch self.outOfMemory();
    }

    fn saved(self: *Editor, s: Request.Save, result: fs.file.SaveError!void) error{OutOfMemory}!void {
        result catch |e| {
            self.message.set(true, "cannot write \"{s}\": {s}", .{ s.path, @errorName(e) });
            return;
        };
        if (self.path == null) self.path = try self.gpa.dupe(u8, s.path);
        if (std.mem.eql(u8, self.path.?, s.path)) self.doc.markSaved();
        const lines = self.doc.buffer.lineCount();
        self.message.set(false, "\"{s}\" written, {d} line{s}", .{ s.path, lines, plural(lines) });
        if (s.quit) self.quit = true;
    }

    /// Reports how the load of `path` went: the file's contents (owned by
    /// the editor from here), null for a missing file, or the error.
    pub fn finishLoad(self: *Editor, path: []const u8, result: fs.file.LoadError!?[]u8) void {
        self.loaded(path, result) catch self.outOfMemory();
    }

    /// As `finishLoad`, but out of memory is returned, with the editor
    /// unchanged.
    pub fn loaded(self: *Editor, path: []const u8, result: fs.file.LoadError!?[]u8) error{OutOfMemory}!void {
        const contents = result catch |e| {
            self.message.set(true, "cannot open \"{s}\": {s}", .{ path, @errorName(e) });
            return;
        };
        defer if (contents) |t| self.gpa.free(t);
        var doc: Document = try .init(self.gpa, contents orelse "");
        errdefer doc.deinit();
        const owned = try self.gpa.dupe(u8, path);
        self.doc.deinit();
        self.doc = doc;
        if (self.path) |p| self.gpa.free(p);
        self.path = owned;
        self.view = .{};
        if (contents == null) {
            self.message.set(false, "\"{s}\" new file", .{path});
        } else {
            const lines = self.doc.buffer.lineCount();
            self.message.set(false, "\"{s}\" {d} line{s}", .{ path, lines, plural(lines) });
        }
    }

    fn handleKey(self: *Editor, k: Key) Error!void {
        switch (self.mode) {
            .normal => if (self.keymap.normal(k)) |a| try self.apply(a),
            .insert => if (input.keymap.insertKey(k)) |a| try self.apply(a),
            .prompt => switch (try self.prompt.key(k)) {
                .edited, .ignored => {},
                .cancel => self.mode = .normal,
                .submit => {
                    self.mode = .normal;
                    try prompting.submit(self);
                },
            },
        }
    }

    fn handlePaste(self: *Editor, bytes: []const u8) Error!void {
        if (self.mode == .prompt) return self.prompt.paste(bytes);
        const text = try edit.insert.normalizePaste(self.gpa, bytes);
        defer self.gpa.free(text);
        if (self.mode == .insert) return edit.insert.text(&self.doc, text);
        self.doc.beginSession();
        defer self.doc.endSession();
        try edit.insert.enter(&self.doc, .before);
        try edit.insert.text(&self.doc, text);
    }

    fn apply(self: *Editor, a: Action) Error!void {
        const doc = &self.doc;
        const tw = self.options.tab_width;
        switch (a) {
            .move => |m| try selecting.move(doc, m.motion, m.count, m.extend, tw),
            .select_lines => |l| selecting.selectLines(doc, l.count, l.every_line),
            .select_all => try selecting.selectAll(doc),
            .reduce => selecting.reduce(doc),
            .flip => selecting.flip(doc),
            .forward => selecting.forward(doc),
            .keep_main => selecting.keepMain(doc),
            .drop_main => if (!selecting.dropMain(doc)) {
                self.message.set(true, "the only selection cannot be dropped", .{});
            },
            .rotate_main => |d| selecting.rotateMain(doc, d),
            .copy_to_line => |c| _ = try selecting.copyToLine(doc, c.down, c.count, tw),
            .select_object => |o| _ = try selecting.selectObject(doc, o.kind, o.inner),
            .split_lines => try selecting.splitLines(doc),
            .prompt => |p| {
                self.mode = .prompt;
                self.prompt_kind = p;
                self.prompt.clear();
            },
            .search_next => |s| try prompting.searchNext(self, s.dir, s.add),
            .search_selection => try prompting.searchSelection(self),
            .delete => |d| {
                if (d.change) doc.beginSession();
                errdefer if (d.change) doc.endSession();
                const regs = if (d.yank) &self.regs else null;
                try if (d.change) verbs.deleteToChange(doc, regs, d.reg) else verbs.delete(doc, regs, d.reg);
                if (d.change) {
                    try edit.insert.enter(doc, .before);
                    self.mode = .insert;
                }
            },
            .yank => |r| try verbs.yank(doc, &self.regs, r),
            .paste => |p| if (!try verbs.paste(doc, &self.regs, p.reg, p.before)) self.emptyRegister(p.reg),
            .replace => |r| if (!try verbs.replace(doc, &self.regs, r)) self.emptyRegister(r),
            .replace_char => |c| try verbs.replaceChar(doc, c),
            .case => |c| try verbs.changeCase(doc, c),
            .indent => try verbs.indent(doc, self.options.indent_width),
            .dedent => try verbs.dedent(doc, self.options.indent_width),
            .join => try verbs.join(doc),
            .undo => if (!try doc.undo()) self.message.set(false, "nothing to undo", .{}),
            .redo => if (!try doc.redo()) self.message.set(false, "nothing to redo", .{}),
            .insert => |w| {
                doc.beginSession();
                errdefer doc.endSession();
                try edit.insert.enter(doc, w);
                self.mode = .insert;
            },
            .scroll => |s| try self.scroll(s),
            .view => |v| try self.moveView(v),
            .text => |cp| {
                var bytes: [4]u8 = undefined;
                // The keymap only makes text of valid code points.
                const n = std.unicode.utf8Encode(cp, &bytes) catch return;
                try edit.insert.text(doc, bytes[0..n]);
            },
            .newline => try edit.insert.newline(doc),
            .backspace => try edit.insert.backspace(doc),
            .delete_forward => try edit.insert.deleteForward(doc),
            .leave_insert => {
                doc.endSession();
                self.mode = .normal;
            },
        }
    }

    fn emptyRegister(self: *Editor, reg: u8) void {
        self.message.set(true, "register {c} is empty", .{reg});
    }

    /// Moves the view and every cursor by half a page or a page.
    fn scroll(self: *Editor, s: input.action.Scroll) Error!void {
        const page = @max(self.textRows(), 1);
        const n = switch (s) {
            .half_down, .half_up => @max(page / 2, 1),
            .page_down, .page_up => page,
        };
        try self.scrollBy(s == .half_down or s == .page_down, n, true);
    }

    /// `v`: places the main cursor's line in the view, or scrolls the view
    /// alone.
    fn moveView(self: *Editor, v: input.action.View) Error!void {
        const at: ui.view.Place = switch (v.to) {
            .down, .up => return self.scrollBy(v.to == .down, v.count, false),
            .top => .top,
            .center => .center,
            .bottom => .bottom,
        };
        self.view.place(.{
            .line = self.doc.buffer.lineOf(self.doc.primary().cursor),
            .lines = self.doc.buffer.lineCount(),
            .height = self.textRows(),
            .scrolloff = self.options.scrolloff,
        }, at);
    }

    /// Scrolls the view `n` lines; the cursors move as far when `carry`,
    /// and in any case into the view outside the margin.
    fn scrollBy(self: *Editor, down: bool, n: usize, carry: bool) Error!void {
        const page = @max(self.textRows(), 1);
        const lines = self.doc.buffer.lineCount();
        self.view.scroll(if (down) @intCast(@min(n, lines)) else -@as(isize, @intCast(@min(n, lines))), lines);
        const m = @min(self.options.scrolloff, (page - 1) / 2);
        const low = if (self.view.top > 0) self.view.top + m else 0;
        const high = @max(low, self.view.top + page - 1 - m);
        const line = self.doc.buffer.lineOf(self.doc.primary().cursor);
        const moved = if (!carry) line else if (down) line +| n else line -| n;
        const target = @min(std.math.clamp(moved, low, high), lines - 1);
        const tw = self.options.tab_width;
        if (target > line) try selecting.move(&self.doc, .down, target - line, false, tw);
        if (target < line) try selecting.move(&self.doc, .up, line - target, false, tw);
    }
};

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}

//! `Editor`: the whole editing state (the current document and the other
//! buffers, registers, keymap, mode, prompt, view, message) and the
//! routing of keys and pastes to the pure modules. It does no I/O: saving and loading are handed to the
//! shell as a `Request` (`requesting.zig`), which reports back with
//! `finishSave` and `finishLoad`. Prompts are run by `prompting.zig`,
//! drawing is `layout.zig`, the message line is `message.zig`.

const std = @import("std");
const edit = @import("../edit.zig");
const input = @import("../input.zig");
const regex = @import("../regex.zig");
const ui = @import("../ui.zig");
const layout = @import("layout.zig");
const prompting = @import("prompting.zig");
const viewing = @import("viewing.zig");
const requesting = @import("requesting.zig");
const buffers = @import("buffers.zig");
const Disk = @import("../fs.zig").disk.Disk;
const Form = @import("../buffer.zig").form.Form;

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
    /// Long lines go on in the rows below (`:wrap`, `:nowrap`).
    wrap: bool = true,
    /// Steps one regex command may take before it stops, changing nothing.
    regex_steps: u64 = regex.max_steps,
};

/// What the shell must do for the editor. Paths are borrowed from the
/// editor until the next `ask`: the shell copies what it keeps.
pub const Request = union(enum) {
    /// Write the document's text to `path`, then `finishSave`.
    save: Save,
    /// Read `path`, then `finishLoad`.
    load: []const u8,

    pub const Save = struct {
        path: []const u8,
        quit: bool,
        /// Write a read-only file, or one changed on disk, too.
        force: bool = false,
        /// What the file was when read or last written, set by the shell.
        expect: Disk = .unknown,
        /// The lines of the text to write, set by `ask`.
        lines: usize = 0,
        /// The form to write them in (line ends, byte order mark, final
        /// newline), set by `ask`.
        form: Form = .{},
    };
};

/// The line under the status line: see `message.zig`.
pub const Message = @import("message.zig").Message;

pub const Editor = struct {
    gpa: std.mem.Allocator,
    doc: Document,
    regs: edit.Registers,
    keymap: input.Keymap = .{},
    mappings: input.mapping.Mappings,
    mode: Mode = .normal,
    prompt: ui.prompt.Prompt,
    prompt_kind: input.action.Prompt = .command,
    view: ui.View = .{},
    theme: ui.Theme = .{},
    options: Options = .{},
    /// Owned; null for a buffer without a file.
    path: ?[]u8 = null,
    /// What the file at `path` was when it was read or last written.
    disk: Disk = .unknown,
    /// The form `path` is written in: its line ends (the text has `\n`
    /// ones), byte order mark (the text has none) and whether its last
    /// line ends (the text's always does).
    form: Form = .{},
    message: Message = .{},
    /// The last search pattern, compiled.
    search: ?Regex = null,
    /// Set once the editor should exit.
    quit: bool = false,
    /// A save that quits, or that `after_save` waits for, is being
    /// written: keys wait.
    quitting: bool = false,
    /// What a `:q` or `:e` typed during a save does once it is written.
    after_save: requesting.AfterSave = .nothing,
    /// Owned storage for the path of an `:e` in `after_save`.
    after_path: std.ArrayList(u8) = .empty,
    /// Ctrl-z was typed; see `takeSuspend`.
    suspending: bool = false,
    /// The screen size, for page scrolling.
    width: usize = 80,
    height: usize = 24,
    request: ?Request = null,
    /// Owned storage for the path of `request`.
    request_path: std.ArrayList(u8) = .empty,
    /// The keys of a mapping after one that asked for a request, waiting
    /// for the shell to serve it (`resumeKeys`).
    rest: std.ArrayList(Key) = .empty,
    /// The buffers open besides the current one, which is `doc`, `path`,
    /// `disk`, `form` and `view` (`buffers.zig`).
    buffers: buffers.Buffers = .{},

    /// An editor on `text`, the contents of `path` (null for a buffer
    /// without a file). Both are copied.
    pub fn init(gpa: std.mem.Allocator, path: ?[]const u8, text: []const u8) error{OutOfMemory}!Editor {
        var doc: Document = try .init(gpa, text);
        errdefer doc.deinit();
        const owned = if (path) |p| try gpa.dupe(u8, p) else null;
        return .{ .gpa = gpa, .doc = doc, .regs = .init(gpa), .mappings = .init(gpa), .prompt = .init(gpa), .path = owned };
    }

    pub fn deinit(self: *Editor) void {
        self.doc.deinit();
        self.regs.deinit();
        self.mappings.deinit();
        self.prompt.deinit();
        if (self.path) |p| self.gpa.free(p);
        if (self.search) |*re| re.deinit();
        self.request_path.deinit(self.gpa);
        self.after_path.deinit(self.gpa);
        self.rest.deinit(self.gpa);
        self.buffers.deinit(self.gpa);
        self.* = undefined;
    }

    /// A taller window shows the lines scrolled off above, rather than
    /// empty rows below; so does a wider one when lines wrap into fewer
    /// rows. The same size again (before every frame) changes nothing.
    pub fn resize(self: *Editor, width: usize, height: usize) void {
        const rows = self.textRows();
        const wider = width > self.width;
        self.width = width;
        self.height = height;
        const lines = self.doc.buffer.lineCount();
        if (self.textRows() <= rows and !(wider and self.options.wrap)) return;
        if (self.options.wrap) {
            var wrapped: layout.Rows = .init(self);
            self.view.fillRows(self.textRows(), lines, &wrapped);
        } else self.view.fill(self.textRows(), lines);
    }

    /// The rows the document gets: all but the status and message lines.
    pub fn textRows(self: *const Editor) usize {
        return self.height -| 2;
    }

    pub const draw = layout.draw;

    pub fn key(self: *Editor, k: Key) Error!void {
        if (self.quitting) return;
        if (self.mode != .prompt) self.message.clear();
        self.typed(k) catch |e| switch (e) {
            error.OutOfMemory => self.outOfMemory(),
            else => |other| return other,
        };
    }

    /// Whether keys of a mapping wait for `resumeKeys`.
    pub fn hasRest(self: *const Editor) bool {
        return self.rest.items.len > 0;
    }

    /// Types the keys of a mapping that waited for a request, once the
    /// shell has taken it; they may stop at another. Dropped while a save
    /// that quits is written, as typed keys are.
    pub fn resumeKeys(self: *Editor) Error!void {
        var keys = self.rest;
        self.rest = .empty;
        defer keys.deinit(self.gpa);
        if (self.quitting) return;
        self.runKeys(keys.items) catch |e| switch (e) {
            error.OutOfMemory => self.outOfMemory(),
            else => |other| return other,
        };
    }

    /// Bracketed paste: typed at every cursor in insert mode, inserted
    /// before the selections in normal mode, added to the prompt there.
    pub fn paste(self: *Editor, bytes: []const u8) Error!void {
        if (self.quitting) return;
        self.message.clear();
        self.handlePaste(bytes) catch |e| switch (e) {
            error.OutOfMemory => self.outOfMemory(),
            else => |other| return other,
        };
    }

    pub fn outOfMemory(self: *Editor) void {
        self.message.set(true, "out of memory", .{});
    }

    /// Whether the shell should stop the process (Ctrl-z), once.
    pub fn takeSuspend(self: *Editor) bool {
        defer self.suspending = false;
        return self.suspending;
    }

    pub const takeRequest = requesting.takeRequest;
    pub const ask = requesting.ask;
    pub const abandonSave = requesting.abandonSave;
    pub const finishSave = requesting.finishSave;
    pub const finishLoad = requesting.finishLoad;
    pub const noticeDisk = requesting.noticeDisk;
    pub const loaded = requesting.loaded;
    pub const open = buffers.open;
    pub const switchTo = buffers.switchTo;
    pub const bufferCount = buffers.bufferCount;
    pub const buffer = buffers.buffer;
    pub const otherModified = buffers.otherModified;

    /// Types `k`, or the keys it is mapped to, which are not mapped again.
    fn typed(self: *Editor, k: Key) Error!void {
        const mode: input.mapping.Mode = switch (self.mode) {
            // A key that completes a prefix is that key.
            .normal => if (self.keymap.awaitsKey()) return self.handleKey(k) else .normal,
            .insert => .insert,
            .prompt => return self.handleKey(k),
        };
        const mapped = self.mappings.get(mode, k) orelse return self.handleKey(k);
        // A copy: the keys may map keys again (`:map`) while they run.
        const keys = try self.gpa.dupe(Key, mapped);
        defer self.gpa.free(keys);
        try self.runKeys(keys);
    }

    /// Types `keys` until one asks for a request; the ones after it wait
    /// in `rest`. Room for them is made first: out of memory types none.
    fn runKeys(self: *Editor, keys: []const Key) Error!void {
        try self.rest.ensureTotalCapacity(self.gpa, keys.len);
        for (keys, 1..) |m, i| {
            try self.handleKey(m);
            if (self.request != null) return self.rest.appendSliceAssumeCapacity(keys[i..]);
        }
    }

    fn handleKey(self: *Editor, k: Key) Error!void {
        switch (self.mode) {
            .normal => if (self.keymap.normal(k)) |a| try self.apply(a),
            .insert => if (input.keymap.insertKey(k)) |a| try self.apply(a),
            .prompt => if (input.keymap.isSuspend(k)) try self.apply(.@"suspend") else switch (try self.prompt.key(k)) {
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

    /// Says so when a command was refused for making too many selections.
    fn limited(self: *Editor, e: selecting.LimitError) Error!void {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        prompting.tooMany(self);
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
            .copy_to_line => |c| _ = selecting.copyToLine(doc, c.down, c.count, tw) catch |e| return self.limited(e),
            .select_object => |o| if (!try selecting.selectObject(doc, o.kind, o.inner)) {
                self.message.set(true, "no object here", .{});
            },
            .split_lines => selecting.splitLines(doc) catch |e| return self.limited(e),
            .trim_lines => if (!try selecting.trimLines(doc)) {
                self.message.set(true, "no selection holds a whole line", .{});
            },
            .rotate_contents => |d| try verbs.rotateContents(doc, d),
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
            .scroll => |s| try viewing.scroll(self, s),
            .view => |v| try viewing.moveView(self, v),
            .@"suspend" => self.suspending = true,
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
};

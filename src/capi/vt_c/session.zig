const std = @import("std");
const vt = @import("ghostty-vt");
const Allocator = std.mem.Allocator;
const types = @import("types.zig");
const RowCache = @import("rowcache.zig").RowCache;

pub const Session = struct {
    alloc: Allocator,
    term: vt.Terminal,
    stream: vt.Stream(*Handler),
    handler: Handler,
    // optional writeback
    write_cb: types.WriteCb = null,
    write_ud: ?*types.c_void = null,
    // optional events (title/clipboard/bell)
    events: struct {
        on_title: ?*const fn (*types.c_void, [*]const u8, usize) callconv(.C) void = null,
        on_clipboard_set: ?*const fn (*types.c_void, [*]const u8, usize) callconv(.C) void = null,
        on_bell: ?*const fn (*types.c_void) callconv(.C) void = null,
        on_palette_changed: ?*const fn (*types.c_void) callconv(.C) void = null,
        ud: ?*types.c_void = null,
    } = .{},
    // per-screen fingerprint caches for precise dirty spans
    cache_primary: RowCache,
    cache_alt: RowCache,

    pub fn init(alloc: Allocator, cols: u16, rows: u16, max_scrollback: usize) !*Session {
        const self = try alloc.create(Session);
        errdefer alloc.destroy(self);

        var term = try vt.Terminal.init(alloc, .{ .cols = cols, .rows = rows, .max_scrollback = max_scrollback });
        errdefer term.deinit(alloc);

        const handler = Handler{ .sess = undefined };

        self.* = .{
            .alloc = alloc,
            .term = term,
            .handler = handler,
            .stream = undefined,
            .write_cb = null,
            .write_ud = null,
            .events = .{},
            .cache_primary = try RowCache.init(alloc, rows, cols),
            .cache_alt = try RowCache.init(alloc, rows, cols),
        };
        self.handler.sess = self;
        self.stream = vt.Stream(*Handler).init(&self.handler);
        return self;
    }

    pub fn deinit(self: *Session) void {
        self.cache_primary.deinit(self.alloc);
        self.cache_alt.deinit(self.alloc);
        self.term.deinit(self.alloc);
        self.alloc.destroy(self);
    }
};

// Minimal handler implementing the callbacks Stream expects and mapping to vt.Terminal
pub const Handler = struct {
    sess: *Session,

    // Execute actions
    pub fn print(self: *Handler, ch: u21) !void {
        try self.sess.term.print(ch);
    }
    pub fn printRepeat(self: *Handler, count: usize) !void {
        try self.sess.term.printRepeat(count);
    }
    pub fn bell(self: *Handler) !void {
        if (self.sess.events.on_bell) |cb| {
            if (self.sess.events.ud) |ud| cb(ud);
        }
    }
    pub fn backspace(self: *Handler) !void {
        self.sess.term.backspace();
    }
    pub fn horizontalTab(self: *Handler, count: u16) !void {
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const x = self.sess.term.screen.cursor.x;
            try self.sess.term.horizontalTab();
            if (x == self.sess.term.screen.cursor.x) break;
        }
    }
    pub fn horizontalTabBack(self: *Handler, count: u16) !void {
        var i: u16 = 0;
        while (i < count) : (i += 1) {
            const x = self.sess.term.screen.cursor.x;
            try self.sess.term.horizontalTabBack();
            if (x == self.sess.term.screen.cursor.x) break;
        }
    }
    pub fn linefeed(self: *Handler) !void {
        try self.sess.term.index();
    }
    pub fn carriageReturn(self: *Handler) !void {
        self.sess.term.carriageReturn();
    }

    // Cursor movement
    pub fn setCursorLeft(self: *Handler, amount: u16) !void {
        self.sess.term.cursorLeft(amount);
    }
    pub fn setCursorRight(self: *Handler, amount: u16) !void {
        self.sess.term.cursorRight(amount);
    }
    pub fn setCursorDown(self: *Handler, amount: u16, carriage: bool) !void {
        self.sess.term.cursorDown(amount);
        if (carriage) self.sess.term.carriageReturn();
    }
    pub fn setCursorUp(self: *Handler, amount: u16, carriage: bool) !void {
        self.sess.term.cursorUp(amount);
        if (carriage) self.sess.term.carriageReturn();
    }
    pub fn setCursorCol(self: *Handler, col: u16) !void {
        self.sess.term.setCursorPos(self.sess.term.screen.cursor.y + 1, col);
    }
    pub fn setCursorColRelative(self: *Handler, offset: u16) !void {
        self.sess.term.setCursorPos(self.sess.term.screen.cursor.y + 1, self.sess.term.screen.cursor.x + 1 +| offset);
    }
    pub fn setCursorRow(self: *Handler, row: u16) !void {
        self.sess.term.setCursorPos(row, self.sess.term.screen.cursor.x + 1);
    }
    pub fn setCursorRowRelative(self: *Handler, offset: u16) !void {
        self.sess.term.setCursorPos(self.sess.term.screen.cursor.y + 1 +| offset, self.sess.term.screen.cursor.x + 1);
    }
    pub fn setCursorPos(self: *Handler, row: u16, col: u16) !void {
        self.sess.term.setCursorPos(row, col);
    }

    // Erase / delete / insert
    pub fn eraseDisplay(self: *Handler, mode: vt.EraseDisplay, protected: bool) !void {
        self.sess.term.eraseDisplay(mode, protected);
    }
    pub fn eraseLine(self: *Handler, mode: vt.EraseLine, protected: bool) !void {
        self.sess.term.eraseLine(mode, protected);
    }
    pub fn deleteChars(self: *Handler, count: usize) !void {
        self.sess.term.deleteChars(count);
    }
    pub fn eraseChars(self: *Handler, count: usize) !void {
        self.sess.term.eraseChars(count);
    }
    pub fn insertLines(self: *Handler, count: usize) !void {
        self.sess.term.insertLines(count);
    }
    pub fn deleteLines(self: *Handler, count: usize) !void {
        self.sess.term.deleteLines(count);
    }
    pub fn insertBlanks(self: *Handler, count: usize) !void {
        self.sess.term.insertBlanks(count);
    }
    pub fn reverseIndex(self: *Handler) !void {
        self.sess.term.reverseIndex();
    }

    // SGR
    pub fn setAttribute(self: *Handler, attr: vt.Attribute) !void {
        try self.sess.term.setAttribute(attr);
    }

    // OSC callbacks we care about
    pub fn changeWindowTitle(self: *Handler, title: []const u8) !void {
        if (self.sess.events.on_title) |cb| {
            if (self.sess.events.ud) |ud| cb(ud, title.ptr, title.len);
        }
    }
    pub fn clipboardContents(self: *Handler, kind: u8, data: []const u8) !void {
        _ = kind;
        if (data.len == 0) return;
        if (self.sess.events.on_clipboard_set) |cb| {
            if (self.sess.events.ud) |ud| cb(ud, data.ptr, data.len);
        }
    }

    pub fn handleColorOperation(
        self: *Handler,
        op: vt.osc.color.Operation,
        requests: *const vt.osc.color.List,
        terminator: vt.osc.Terminator,
    ) !void {
        _ = op;
        _ = terminator;
        if (requests.count() == 0) return;
        var changed = false;
        var it = requests.constIterator(0);
        while (it.next()) |req| {
            switch (req.*) {
                .set => |set| {
                    switch (set.target) {
                        .palette => |i| {
                            self.sess.term.flags.dirty.palette = true;
                            self.sess.term.color_palette.colors[i] = set.color;
                            self.sess.term.color_palette.mask.set(i);
                            changed = true;
                        },
                        .dynamic => |_| {},
                        .special => {},
                    }
                },
                .reset => |target| switch (target) {
                    .palette => |i| {
                        self.sess.term.flags.dirty.palette = true;
                        self.sess.term.color_palette.colors[i] = self.sess.term.default_palette[i];
                        self.sess.term.color_palette.mask.unset(i);
                        changed = true;
                    },
                    .dynamic => |_| {},
                    .special => {},
                },
                .reset_palette => {
                    var mask_it = self.sess.term.color_palette.mask.iterator(.{});
                    while (mask_it.next()) |i| {
                        self.sess.term.flags.dirty.palette = true;
                        self.sess.term.color_palette.colors[i] = self.sess.term.default_palette[i];
                    }
                    self.sess.term.color_palette.mask = .initEmpty();
                    changed = true;
                },
                .reset_special => {},
                .query => |_| {},
            }
        }
        if (changed) {
            if (self.sess.events.on_palette_changed) |cb| {
                if (self.sess.events.ud) |ud| cb(ud);
            }
        }
    }

    // Margins / scroll
    pub fn setTopAndBottomMargin(self: *Handler, top: u16, bottom: u16) !void {
        self.sess.term.setTopAndBottomMargin(top, bottom);
    }
    pub fn setLeftAndRightMargin(self: *Handler, left: u16, right: u16) !void {
        self.sess.term.setLeftAndRightMargin(left, right);
    }
    pub fn setLeftAndRightMarginAmbiguous(self: *Handler) !void {
        if (self.sess.term.modes.get(.enable_left_and_right_margin)) {
            self.sess.term.setLeftAndRightMargin(0, 0);
        } else {
            try self.saveCursor();
        }
    }
    pub fn scrollUp(self: *Handler, count: u16) !void {
        self.sess.term.scrollUp(count);
    }
    pub fn scrollDown(self: *Handler, count: u16) !void {
        self.sess.term.scrollDown(count);
    }

    // Tabs & cursor save/restore
    pub fn tabSet(self: *Handler) !void { self.sess.term.tabSet(); }
    pub fn tabClear(self: *Handler, cmd: vt.TabClear) !void { self.sess.term.tabClear(cmd); }
    pub fn tabReset(self: *Handler) !void { self.sess.term.tabReset(); }
    pub fn saveCursor(self: *Handler) !void { self.sess.term.saveCursor(); }
    pub fn restoreCursor(self: *Handler) !void { try self.sess.term.restoreCursor(); }

    // Device status report (minimally handle cursor position)
    pub fn deviceStatusReport(self: *Handler, req: vt.device_status.Request) !void {
        const cb = self.sess.write_cb orelse return;
        const ud = self.sess.write_ud;
        switch (req) {
            .operating_status => {
                const resp: [4]u8 = .{ 0x1B, '[', '0', 'n' };
                cb(ud.?, &resp, resp.len);
            },
            .cursor_position => {
                var buf: [32]u8 = undefined;
                const pos = .{ .y = self.sess.term.screen.cursor.y + 1, .x = self.sess.term.screen.cursor.x + 1 };
                const s = std.fmt.bufPrint(&buf, "\x1B[{d};{d}R", .{ pos.y, pos.x }) catch return;
                cb(ud.?, s.ptr, s.len);
            },
            .color_scheme => {},
        }
    }
};

pub fn currentCache(sess: *Session) *RowCache {
    return if (sess.term.active_screen == .alternate) &sess.cache_alt else &sess.cache_primary;
}

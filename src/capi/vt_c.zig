const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const vt = @import("ghostty-vt");

// C ABI types
const c_void = anyopaque;
const c_char = u8;

// Mirror of ghostty_vt_cell_t in C
const CCell = extern struct {
    text: [*c]const u8,
    text_len: usize,
    fg_rgba: u32,
    bg_rgba: u32,
    width: u8,
    underline: bool,
    strike: bool,
    inverse: bool,
    bold: bool,
    italic: bool,
    link_tag: u32,
};

// Write callback type
const WriteCb = ?*const fn (*c_void, [*]const u8, usize) callconv(.C) void;

const Session = struct {
    alloc: Allocator,
    term: vt.Terminal,
    stream: vt.Stream(*Handler),
    handler: Handler,
    // optional writeback
    write_cb: WriteCb = null,
    write_ud: ?*c_void = null,

    pub fn init(alloc: Allocator, cols: u16, rows: u16, max_scrollback: usize) !*Session {
        const self = try alloc.create(Session);
        errdefer alloc.destroy(self);

        var term = try vt.Terminal.init(alloc, .{
            .cols = cols,
            .rows = rows,
            .max_scrollback = max_scrollback,
        });
        errdefer term.deinit(alloc);

        var handler = Handler{
            .sess = undefined, // fill after self is initialized
        };

        // Construct self now so handler can reference it
        self.* = .{
            .alloc = alloc,
            .term = term,
            .handler = handler,
            .stream = undefined, // initialized below
            .write_cb = null,
            .write_ud = null,
        };
        self.handler.sess = self;
        self.stream = vt.Stream(*Handler).init(&self.handler);
        return self;
    }

    pub fn deinit(self: *Session) void {
        self.term.deinit(self.alloc);
        self.alloc.destroy(self);
    }
};

// Minimal handler implementing the callbacks Stream expects and mapping to vt.Terminal
const Handler = struct {
    sess: *Session,

    // Execute actions
    pub fn print(self: *Handler, ch: u21) !void { try self.sess.term.print(ch); }
    pub fn printRepeat(self: *Handler, count: usize) !void { try self.sess.term.printRepeat(count); }
    pub fn bell(self: *Handler) !void { _ = self; }
    pub fn backspace(self: *Handler) !void { self.sess.term.backspace(); }
    pub fn horizontalTab(self: *Handler, count: u16) !void {
        var i: u16 = 0; while (i < count) : (i += 1) {
            const x = self.sess.term.screen.cursor.x;
            try self.sess.term.horizontalTab();
            if (x == self.sess.term.screen.cursor.x) break;
        }
    }
    pub fn horizontalTabBack(self: *Handler, count: u16) !void {
        var i: u16 = 0; while (i < count) : (i += 1) {
            const x = self.sess.term.screen.cursor.x;
            try self.sess.term.horizontalTabBack();
            if (x == self.sess.term.screen.cursor.x) break;
        }
    }
    pub fn linefeed(self: *Handler) !void { try self.sess.term.index(); }
    pub fn carriageReturn(self: *Handler) !void { self.sess.term.carriageReturn(); }

    // Cursor movement
    pub fn setCursorLeft(self: *Handler, amount: u16) !void { self.sess.term.cursorLeft(amount); }
    pub fn setCursorRight(self: *Handler, amount: u16) !void { self.sess.term.cursorRight(amount); }
    pub fn setCursorDown(self: *Handler, amount: u16, carriage: bool) !void {
        self.sess.term.cursorDown(amount);
        if (carriage) self.sess.term.carriageReturn();
    }
    pub fn setCursorUp(self: *Handler, amount: u16, carriage: bool) !void {
        self.sess.term.cursorUp(amount);
        if (carriage) self.sess.term.carriageReturn();
    }
    pub fn setCursorCol(self: *Handler, col: u16) !void { self.sess.term.setCursorPos(self.sess.term.screen.cursor.y + 1, col); }
    pub fn setCursorColRelative(self: *Handler, offset: u16) !void {
        self.sess.term.setCursorPos(self.sess.term.screen.cursor.y + 1, self.sess.term.screen.cursor.x + 1 +| offset);
    }
    pub fn setCursorRow(self: *Handler, row: u16) !void { self.sess.term.setCursorPos(row, self.sess.term.screen.cursor.x + 1); }
    pub fn setCursorRowRelative(self: *Handler, offset: u16) !void {
        self.sess.term.setCursorPos(self.sess.term.screen.cursor.y + 1 +| offset, self.sess.term.screen.cursor.x + 1);
    }
    pub fn setCursorPos(self: *Handler, row: u16, col: u16) !void { self.sess.term.setCursorPos(row, col); }

    // Erase / delete / insert
    pub fn eraseDisplay(self: *Handler, mode: vt.EraseDisplay, protected: bool) !void { self.sess.term.eraseDisplay(mode, protected); }
    pub fn eraseLine(self: *Handler, mode: vt.EraseLine, protected: bool) !void { self.sess.term.eraseLine(mode, protected); }
    pub fn deleteChars(self: *Handler, count: usize) !void { self.sess.term.deleteChars(count); }
    pub fn eraseChars(self: *Handler, count: usize) !void { self.sess.term.eraseChars(count); }
    pub fn insertLines(self: *Handler, count: usize) !void { self.sess.term.insertLines(count); }
    pub fn deleteLines(self: *Handler, count: usize) !void { self.sess.term.deleteLines(count); }
    pub fn insertBlanks(self: *Handler, count: usize) !void { self.sess.term.insertBlanks(count); }
    pub fn reverseIndex(self: *Handler) !void { self.sess.term.reverseIndex(); }

    // SGR
    pub fn setAttribute(self: *Handler, attr: vt.Attribute) !void { try self.sess.term.setAttribute(attr); }

    // Margins / scroll
    pub fn setTopAndBottomMargin(self: *Handler, top: u16, bottom: u16) !void { self.sess.term.setTopAndBottomMargin(top, bottom); }
    pub fn setLeftAndRightMargin(self: *Handler, left: u16, right: u16) !void { self.sess.term.setLeftAndRightMargin(left, right); }
    pub fn setLeftAndRightMarginAmbiguous(self: *Handler) !void {
        // Resolve ambiguity as SC (save cursor) if margin mode is disabled
        if (self.sess.term.modes.get(.enable_left_and_right_margin)) {
            self.sess.term.setLeftAndRightMargin(0, 0);
        } else {
            try self.saveCursor();
        }
    }
    pub fn scrollUp(self: *Handler, count: u16) !void { self.sess.term.scrollUp(count); }
    pub fn scrollDown(self: *Handler, count: u16) !void { self.sess.term.scrollDown(count); }

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
            .operating_status => cb(ud, "\x1B[0n".*, 4),
            .cursor_position => {
                var buf: [32]u8 = undefined;
                const pos = .{
                    .y = self.sess.term.screen.cursor.y + 1,
                    .x = self.sess.term.screen.cursor.x + 1,
                };
                const s = std.fmt.bufPrint(&buf, "\x1B[{d};{d}R", .{ pos.y, pos.x }) catch return;
                cb(ud, s.ptr, s.len);
            },
            .color_scheme => {},
        }
    }
};

// Helpers
fn pack_rgba(rgb: vt.color.RGB, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, rgb.r) << 16) | (@as(u32, rgb.g) << 8) | (@as(u32, rgb.b));
}

fn default_fg() vt.color.RGB { return vt.color.Name.white.default() catch .{ .r = 0xEA, .g = 0xEA, .b = 0xEA }; }
fn default_bg() vt.color.RGB { return vt.color.Name.black.default() catch .{ .r = 0x1D, .g = 0x1F, .b = 0x21 }; }

fn cell_text_alloc(alloc: Allocator, page: *const vt.page.Page, cell: *const vt.page.Cell) ![]u8 {
    // Empty if no text
    if (!cell.hasText()) return try alloc.dupe(u8, "");
    // Estimate up to 4 bytes per codepoint (first + grapheme)
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    // First codepoint
    try std.unicode.utf8Encode(cell.codepoint(), buf.writer());
    if (cell.hasGrapheme()) {
        if (page.lookupGrapheme(cell)) |slice| {
            const cps = slice.ptr(page.memory);
            for (cps) |cp| try std.unicode.utf8Encode(cp, buf.writer());
        }
    }
    return buf.toOwnedSlice();
}

fn cell_colors(term: *const vt.Terminal, page: *const vt.page.Page, cell: *const vt.page.Cell) struct { fg: u32, bg: u32 } {
    const palette: *const vt.color.Palette = &term.color_palette.colors;
    const style = if (cell.style_id == vt.style.default_id)
        vt.style.Style{}
    else
        page.styles.get(page.memory, cell.style_id);

    var fg_rgb = vt.style.Style.fg(style, .{ .default = default_fg(), .palette = palette, .bold = null });
    var bg_rgb = style.bg(cell, palette);
    // Respect bg-only content optimization
    if (cell.content_tag == .bg_color_palette) {
        bg_rgb = palette[cell.content.color_palette];
    } else if (cell.content_tag == .bg_color_rgb) {
        const rgb = cell.content.color_rgb; bg_rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b };
    }
    const fg = pack_rgba(fg_rgb, 0xFF);
    const bg = if (bg_rgb) |rgb| pack_rgba(rgb, 0xFF) else 0;
    return .{ .fg = fg, .bg = bg };
}

fn cell_link_tag(page: *const vt.page.Page, cell: *const vt.page.Cell) u32 {
    if (cell.hyperlink) {
        if (page.lookupHyperlink(cell)) |id| return @intCast(id);
    }
    return 0;
}

// C exports
export fn ghostty_vt_new(cols: u16, rows: u16, max_scrollback_bytes: usize) callconv(.C) ?*c_void {
    const alloc = std.heap.c_allocator;
    const s = Session.init(alloc, cols, rows, max_scrollback_bytes) catch return null;
    return s;
}

export fn ghostty_vt_free(h: ?*c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        s.deinit();
    }
}

export fn ghostty_vt_set_writer(h: ?*c_void, cb: WriteCb, ud: ?*c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        s.write_cb = cb;
        s.write_ud = ud;
    }
}

export fn ghostty_vt_resize(h: ?*c_void, cols: u16, rows: u16) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        _ = s.term.resize(s.alloc, cols, rows) catch {};
    }
}

export fn ghostty_vt_feed(h: ?*c_void, bytes: [*]const u8, len: usize) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        _ = s.stream.nextSlice(bytes[0..len]) catch {};
    }
}

export fn ghostty_vt_rows(h: ?*c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.rows);
    }
    return 0;
}

export fn ghostty_vt_cols(h: ?*c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.cols);
    }
    return 0;
}

export fn ghostty_vt_cursor_row(h: ?*c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.screen.cursor.y);
    }
    return 0;
}

export fn ghostty_vt_cursor_col(h: ?*c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.screen.cursor.x);
    }
    return 0;
}

export fn ghostty_vt_is_alt_screen(h: ?*c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.screen.active_screen == .alternate;
    }
    return false;
}

export fn ghostty_vt_row_dirty(h: ?*c_void, row: u16) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        const pin = s.term.screen.pages.pin(.{ .active = .{ .y = row, .x = 0 } }) orelse return false;
        return pin.node.data.isRowDirty(pin.y);
    }
    return false;
}

export fn ghostty_vt_row_clear_dirty(h: ?*c_void, row: u16) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        const pin = s.term.screen.pages.pin(.{ .active = .{ .y = row, .x = 0 } }) orelse return;
        var set = pin.node.data.dirtyBitSet();
        if (row < s.term.rows) set.unset(pin.y);
    }
}

export fn ghostty_vt_clear_all_dirty(h: ?*c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        var it = s.term.screen.pages.pages.first;
        while (it) |node| : (it = node.next) {
            var set = node.data.dirtyBitSet();
            set.setRangeValue(.{ .start = 0, .end = node.data.size.rows }, false);
        }
    }
}

export fn ghostty_vt_row_cells(h: ?*c_void, row: u16, out_cells: [*]CCell, out_cap: usize) callconv(.C) usize {
    if (h == null or out_cells == null or out_cap == 0) return 0;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const cols: usize = s.term.cols;
    const n = if (out_cap < cols) out_cap else cols;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const pt: vt.point.Point = .{ .active = .{ .x = @intCast(i), .y = row } };
        const got = s.term.screen.pages.getCell(pt) orelse {
            out_cells[i] = .{ .text = "", .text_len = 0, .fg_rgba = pack_rgba(default_fg(), 0xFF), .bg_rgba = 0, .width = 1, .underline = false, .strike = false, .inverse = false, .bold = false, .italic = false, .link_tag = 0 };
            continue;
        };

        const page = &got.node.data;
        const cell = got.cell;

        // width
        const width: u8 = switch (cell.wide) { .narrow => 1, .wide => 2, .spacer_tail => 0, .spacer_head => 1 };

        // text
        const text_slice = cell_text_alloc(s.alloc, page, cell) catch "";

        // style flags
        // Per-cell style flags
        const style = if (cell.style_id == vt.style.default_id)
            vt.style.Style{}
        else
            page.styles.get(page.memory, cell.style_id);
        const flags = style.flags;
        const clr = cell_colors(&s.term, page, cell);
        const link = cell_link_tag(page, cell);

        out_cells[i] = .{
            .text = if (text_slice.len == 0) "" else text_slice.ptr,
            .text_len = text_slice.len,
            .fg_rgba = clr.fg,
            .bg_rgba = clr.bg,
            .width = width,
            .underline = flags.underline != .none,
            .strike = flags.strikethrough,
            .inverse = flags.inverse,
            .bold = flags.bold,
            .italic = flags.italic,
            .link_tag = link,
        };
    }
    return n;
}

export fn ghostty_vt_row_cells_free(cells: [*]CCell, count: usize) callconv(.C) void {
    const alloc = std.heap.c_allocator;
    var i: usize = 0; while (i < count) : (i += 1) {
        if (cells[i].text_len != 0 and cells[i].text != null) {
            // Free each per-cell text buffer (allocated via c_allocator)
            alloc.free(@constCast(cells[i].text[0..cells[i].text_len]));
            cells[i].text = "";
            cells[i].text_len = 0;
        }
    }
}

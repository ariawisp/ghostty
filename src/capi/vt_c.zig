const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const vt = @import("ghostty-vt");

// C ABI types
const c_void = anyopaque;

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
    // per-screen fingerprint caches for precise dirty spans
    cache_primary: RowCache,
    cache_alt: RowCache,

    pub fn init(alloc: Allocator, cols: u16, rows: u16, max_scrollback: usize) !*Session {
        const self = try alloc.create(Session);
        errdefer alloc.destroy(self);

        var term = try vt.Terminal.init(alloc, .{
            .cols = cols,
            .rows = rows,
            .max_scrollback = max_scrollback,
        });
        errdefer term.deinit(alloc);

        const handler = Handler{
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
const Handler = struct {
    sess: *Session,

    // Execute actions
    pub fn print(self: *Handler, ch: u21) !void {
        try self.sess.term.print(ch);
    }
    pub fn printRepeat(self: *Handler, count: usize) !void {
        try self.sess.term.printRepeat(count);
    }
    pub fn bell(self: *Handler) !void {
        _ = self;
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

    // Margins / scroll
    pub fn setTopAndBottomMargin(self: *Handler, top: u16, bottom: u16) !void {
        self.sess.term.setTopAndBottomMargin(top, bottom);
    }
    pub fn setLeftAndRightMargin(self: *Handler, left: u16, right: u16) !void {
        self.sess.term.setLeftAndRightMargin(left, right);
    }
    pub fn setLeftAndRightMarginAmbiguous(self: *Handler) !void {
        // Resolve ambiguity as SC (save cursor) if margin mode is disabled
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
    pub fn tabSet(self: *Handler) !void {
        self.sess.term.tabSet();
    }
    pub fn tabClear(self: *Handler, cmd: vt.TabClear) !void {
        self.sess.term.tabClear(cmd);
    }
    pub fn tabReset(self: *Handler) !void {
        self.sess.term.tabReset();
    }
    pub fn saveCursor(self: *Handler) !void {
        self.sess.term.saveCursor();
    }
    pub fn restoreCursor(self: *Handler) !void {
        try self.sess.term.restoreCursor();
    }

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
                const pos = .{
                    .y = self.sess.term.screen.cursor.y + 1,
                    .x = self.sess.term.screen.cursor.x + 1,
                };
                const s = std.fmt.bufPrint(&buf, "\x1B[{d};{d}R", .{ pos.y, pos.x }) catch return;
                cb(ud.?, s.ptr, s.len);
            },
            .color_scheme => {},
        }
    }
};

// Helpers
fn pack_rgba(rgb: vt.color.RGB, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, rgb.r) << 16) | (@as(u32, rgb.g) << 8) | (@as(u32, rgb.b));
}

fn default_fg() vt.color.RGB {
    return vt.color.Name.white.default() catch .{ .r = 0xEA, .g = 0xEA, .b = 0xEA };
}
fn default_bg() vt.color.RGB {
    return vt.color.Name.black.default() catch .{ .r = 0x1D, .g = 0x1F, .b = 0x21 };
}

fn cell_text_alloc(alloc: Allocator, page: *const vt.page.Page, cell: *const vt.page.Cell) ![]u8 {
    // Empty if no text
    if (!cell.hasText()) return try alloc.dupe(u8, "");
    // Estimate up to 4 bytes per codepoint (first + grapheme)
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
    // First codepoint
    var tmp: [4]u8 = undefined;
    const n0: u3 = std.unicode.utf8Encode(cell.codepoint(), &tmp) catch unreachable;
    try buf.appendSlice(tmp[0..@intCast(n0)]);
    if (cell.hasGrapheme()) {
        if (page.lookupGrapheme(cell)) |slice| {
            const cps = slice;
            for (cps) |cp| {
                const n: u3 = std.unicode.utf8Encode(cp, &tmp) catch unreachable;
                try buf.appendSlice(tmp[0..@intCast(n)]);
            }
        }
    }
    return buf.toOwnedSlice();
}

fn utf8_len_for_codepoint(cp: u21) usize {
    return std.unicode.utf8CodepointSequenceLength(cp) catch 4;
}

fn cell_text_into(arena: []u8, used: *usize, page: *const vt.page.Page, cell: *const vt.page.Cell) []const u8 {
    if (!cell.hasText()) return &[_]u8{};
    // Compute total bytes needed for first + grapheme extras
    var total: usize = utf8_len_for_codepoint(cell.codepoint());
    if (cell.hasGrapheme()) {
        if (page.lookupGrapheme(cell)) |slice| {
            const cps = slice;
            for (cps) |cp| total += utf8_len_for_codepoint(cp);
        }
    }
    if (arena.len - used.* < total) {
        return &[_]u8{}; // not enough capacity; return empty and let caller handle
    }
    const start = used.*;
    // Encode into a pre-sized slice in the arena
    const out_all = arena[start .. start + total];
    var off: usize = 0;
    const n0: u3 = std.unicode.utf8Encode(cell.codepoint(), out_all[off..]) catch unreachable;
    off += @intCast(n0);
    if (cell.hasGrapheme()) {
        if (page.lookupGrapheme(cell)) |slice| {
            const cps = slice;
            for (cps) |cp| {
                const nx: u3 = std.unicode.utf8Encode(cp, out_all[off..]) catch unreachable;
                off += @intCast(nx);
            }
        }
    }
    used.* += off;
    return arena[start .. start + total];
}

fn cell_colors(term: *const vt.Terminal, page: *const vt.page.Page, cell: *const vt.page.Cell) struct { fg: u32, bg: u32 } {
    const palette: *const vt.color.Palette = &term.color_palette.colors;
    const style = if (cell.style_id == 0)
        vt.Style{}
    else
        page.styles.get(page.memory, cell.style_id).*;

    const fg_rgb = vt.Style.fg(style, .{ .default = default_fg(), .palette = palette, .bold = null });
    var bg_rgb = style.bg(cell, palette);
    // Respect bg-only content optimization
    if (cell.content_tag == .bg_color_palette) {
        bg_rgb = palette[cell.content.color_palette];
    } else if (cell.content_tag == .bg_color_rgb) {
        const rgb = cell.content.color_rgb;
        bg_rgb = .{ .r = rgb.r, .g = rgb.g, .b = rgb.b };
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
        // Recreate caches on resize
        s.cache_primary.ensure(s.alloc, rows, cols) catch {};
        s.cache_alt.ensure(s.alloc, rows, cols) catch {};
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
        return s.term.active_screen == .alternate;
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

// Coarse dirty span: for now report full row when dirty.
export fn ghostty_vt_row_dirty_span(h: ?*c_void, row: u16, out_start: ?*u16, out_end: ?*u16) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        if (out_start == null or out_end == null) return false;
        var start: u16 = 0;
        var end_: u16 = 0;
        const dirty = compute_row_span_and_update(s, row, false, &start, &end_);
        if (dirty) {
            out_start.?.* = start;
            out_end.?.* = end_;
        }
        return dirty;
    }
    return false;
}

export fn ghostty_vt_row_cells(h: ?*c_void, row: u16, out_cells: [*]CCell, out_cap: usize) callconv(.C) usize {
    if (h == null or out_cap == 0) return 0;
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
        const width: u8 = switch (cell.wide) {
            .narrow => 1,
            .wide => 2,
            .spacer_tail => 0,
            .spacer_head => 1,
        };

        // text
        const text_slice = cell_text_alloc(s.alloc, page, cell) catch "";

        // style flags
        // Per-cell style flags
        const style = if (cell.style_id == 0)
            vt.Style{}
        else
            page.styles.get(page.memory, cell.style_id).*;
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
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (cells[i].text_len != 0 and cells[i].text != null) {
            // Free each per-cell text buffer (allocated via c_allocator)
            alloc.free(@constCast(cells[i].text[0..cells[i].text_len]));
            cells[i].text = "";
            cells[i].text_len = 0;
        }
    }
}

// Arena-based row readback that avoids per-cell heap allocations for text.
export fn ghostty_vt_row_cells_into(
    h: ?*c_void,
    row: u16,
    out_cells: [*]CCell,
    out_cap: usize,
    text_arena: [*]u8,
    arena_cap: usize,
    out_arena_used: ?*usize,
) callconv(.C) usize {
    if (h == null or out_cap == 0) return 0;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const cols: usize = s.term.cols;
    const n = if (out_cap < cols) out_cap else cols;
    var used: usize = 0;
    // Prepare cache for inline update while scanning
    var cache = currentCache(s);
    cache.ensure(s.alloc, s.term.rows, s.term.cols) catch {};
    var row_hashes = cache.rowSlice(@intCast(row));
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const pt: vt.point.Point = .{ .active = .{ .x = @intCast(i), .y = row } };
        const got = s.term.screen.pages.getCell(pt) orelse {
            out_cells[i] = .{ .text = "", .text_len = 0, .fg_rgba = pack_rgba(default_fg(), 0xFF), .bg_rgba = 0, .width = 1, .underline = false, .strike = false, .inverse = false, .bold = false, .italic = false, .link_tag = 0 };
            continue;
        };

        const page = &got.node.data;
        const cell = got.cell;
        const width: u8 = switch (cell.wide) {
            .narrow => 1,
            .wide => 2,
            .spacer_tail => 0,
            .spacer_head => 1,
        };

        // Encode into arena if any text; else empty
        var text_slice: []const u8 = (&[_]u8{})[0..];
        if (width != 0) {
            text_slice = cell_text_into(@as([*]u8, text_arena)[0..arena_cap], &used, page, cell);
        }

        const style = if (cell.style_id == 0)
            vt.Style{}
        else
            page.styles.get(page.memory, cell.style_id).*;
        const flags = style.flags;
        const clr = cell_colors(&s.term, page, cell);
        const link = cell_link_tag(page, cell);

        // Update fingerprint cache inline
        row_hashes[i] = cell_fingerprint(&s.term, page, cell);

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
    if (out_arena_used) |p| p.* = used;
    return n;
}
const RowCache = struct {
    data: []u64,
    rows: u16,
    cols: u16,

    pub fn init(alloc: Allocator, rows: u16, cols: u16) !RowCache {
        const count: usize = @as(usize, rows) * @as(usize, cols);
        const buf = try alloc.alloc(u64, count);
        @memset(buf, 0);
        return .{ .data = buf, .rows = rows, .cols = cols };
    }
    pub fn deinit(self: *RowCache, alloc: Allocator) void {
        if (self.data.len != 0) alloc.free(self.data);
        self.* = .{ .data = &[_]u64{}, .rows = 0, .cols = 0 };
    }
    pub fn ensure(self: *RowCache, alloc: Allocator, rows: u16, cols: u16) !void {
        if (self.rows == rows and self.cols == cols and self.data.len != 0) return;
        self.deinit(alloc);
        self.* = try RowCache.init(alloc, rows, cols);
    }
    pub inline fn rowSlice(self: *RowCache, row: usize) []u64 {
        const cols: usize = self.cols;
        return self.data[row * cols .. (row + 1) * cols];
    }
};

fn currentCache(sess: *Session) *RowCache {
    return if (sess.term.active_screen == .alternate) &sess.cache_alt else &sess.cache_primary;
}

const FNV64_OFF: u64 = 0xcbf29ce484222325;
const FNV64_PRIME: u64 = 1099511628211;
inline fn fnv1a64_add(h: u64, b: u8) u64 {
    return (h ^ @as(u64, b)) * FNV64_PRIME;
}
inline fn hash_u32(h: u64, v: u32) u64 {
    var r = h;
    var x = v;
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        r = fnv1a64_add(r, @as(u8, @intCast(x & 0xFF)));
        x >>= 8;
    }
    return r;
}
inline fn hash_u8(h: u64, v: u8) u64 {
    return fnv1a64_add(h, v);
}

fn cell_fingerprint(term: *const vt.Terminal, page: *const vt.page.Page, cell: *const vt.page.Cell) u64 {
    var h: u64 = FNV64_OFF;
    const width: u8 = switch (cell.wide) {
        .narrow => 1,
        .wide => 2,
        .spacer_tail => 0,
        .spacer_head => 1,
    };
    h = hash_u8(h, width);
    // Text codepoints
    if (width != 0) {
        const cp: u32 = @intCast(cell.codepoint());
        h = hash_u32(h, cp);
        if (cell.hasGrapheme()) {
            if (page.lookupGrapheme(cell)) |slice| {
                const cps = slice;
                for (cps) |gcp| h = hash_u32(h, @intCast(gcp));
            }
        }
    }
    // Colors and flags
    const clr = cell_colors(term, page, cell);
    h = hash_u32(h, clr.fg);
    h = hash_u32(h, clr.bg);
    const style = if (cell.style_id == 0)
        vt.Style{}
    else
        page.styles.get(page.memory, cell.style_id).*;
    const flags = style.flags;
    var fmask: u8 = 0;
    if (flags.underline != .none) fmask |= 1;
    if (flags.strikethrough) fmask |= 2;
    if (flags.inverse) fmask |= 4;
    if (flags.bold) fmask |= 8;
    if (flags.italic) fmask |= 16;
    h = hash_u8(h, fmask);
    const link = cell_link_tag(page, cell);
    h = hash_u32(h, link);
    return h;
}

fn compute_row_span_and_update(sess: *Session, row: u16, update_cache: bool, out_start: *u16, out_end: *u16) bool {
    const cols: usize = sess.term.cols;
    // Avoid expensive pin if we only need cell access by (row, col)
    var left_found = false;
    var left: usize = 0;
    var right: usize = 0;
    var i: usize = 0;
    var cache = currentCache(sess);
    cache.ensure(sess.alloc, sess.term.rows, sess.term.cols) catch return true; // if alloc fails, default to full-row
    var row_hashes = cache.rowSlice(@intCast(row));
    while (i < cols) : (i += 1) {
        const pt: vt.point.Point = .{ .active = .{ .x = @intCast(i), .y = row } };
        const got = sess.term.screen.pages.getCell(pt);
        var fp: u64 = 0;
        if (got) |g| {
            fp = cell_fingerprint(&sess.term, &g.node.data, g.cell);
        } else {
            // default fingerprint for missing cell
            fp = 0x9E3779B97F4A7C15; // golden ratio constant as seed
        }
        if (fp != row_hashes[i]) {
            if (!left_found) {
                left_found = true;
                left = i;
            }
            right = i;
            if (update_cache) row_hashes[i] = fp;
        } else if (update_cache) {
            // keep cache as-is when equal
        }
    }
    if (left_found) {
        out_start.* = @intCast(left);
        out_end.* = @intCast(right);
        return true;
    }
    return false;
}

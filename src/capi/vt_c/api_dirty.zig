const vt = @import("ghostty-vt");
const types = @import("capi/vt_c/types.zig");
const SessionMod = @import("capi/vt_c/session.zig");
const Session = SessionMod.Session;
const RowCache = @import("capi/vt_c/rowcache.zig").RowCache;
const fingerprint = @import("capi/vt_c/fingerprint.zig");

fn compute_row_span_and_update(sess: *Session, row: u16, update_cache: bool, out_start: *u16, out_end: *u16) bool {
    const cols: usize = sess.term.cols;
    var left_found = false;
    var left: usize = 0;
    var right: usize = 0;
    var i: usize = 0;
    var cache = SessionMod.currentCache(sess);
    cache.ensure(sess.alloc, sess.term.rows, sess.term.cols) catch return true;
    var row_hashes = cache.rowSlice(@intCast(row));
    while (i < cols) : (i += 1) {
        const pt: vt.point.Point = .{ .active = .{ .x = @intCast(i), .y = row } };
        const got = sess.term.screen.pages.getCell(pt);
        var fp: u64 = 0;
        if (got) |g| {
            fp = fingerprint.cell_fingerprint(&sess.term, &g.node.data, g.cell);
        } else {
            fp = 0x9E3779B97F4A7C15; // seed for missing cell
        }
        if (fp != row_hashes[i]) {
            if (!left_found) {
                left_found = true;
                left = i;
            }
            right = i;
            if (update_cache) row_hashes[i] = fp;
        }
    }
    if (left_found) {
        out_start.* = @intCast(left);
        out_end.* = @intCast(right);
        return true;
    }
    return false;
}

export fn ghostty_vt_row_dirty(h: ?*types.c_void, row: u16) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        const pin = s.term.screen.pages.pin(.{ .active = .{ .y = row, .x = 0 } }) orelse return false;
        return pin.node.data.isRowDirty(pin.y);
    }
    return false;
}

export fn ghostty_vt_row_clear_dirty(h: ?*types.c_void, row: u16) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        const pin = s.term.screen.pages.pin(.{ .active = .{ .y = row, .x = 0 } }) orelse return;
        var set = pin.node.data.dirtyBitSet();
        if (row < s.term.rows) set.unset(pin.y);
    }
}

export fn ghostty_vt_clear_all_dirty(h: ?*types.c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        var it = s.term.screen.pages.pages.first;
        while (it) |node| : (it = node.next) {
            var set = node.data.dirtyBitSet();
            set.setRangeValue(.{ .start = 0, .end = node.data.size.rows }, false);
        }
    }
}

export fn ghostty_vt_row_dirty_span(h: ?*types.c_void, row: u16, out_start: ?*u16, out_end: ?*u16) callconv(.C) bool {
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

export fn ghostty_vt_collect_dirty_rows(h: ?*types.c_void, out_rows: [*]u16, cap: usize) callconv(.C) usize {
    if (h == null or cap == 0) return 0;
    const s: *Session = @ptrCast(@alignCast(h.?));
    var i: usize = 0;
    var y: u16 = 0;
    while (y < s.term.rows and i < cap) : (y += 1) {
        const pin = s.term.screen.pages.pin(.{ .active = .{ .y = y, .x = 0 } }) orelse continue;
        if (pin.node.data.isRowDirty(pin.y)) {
            out_rows[i] = y;
            i += 1;
        }
    }
    return i;
}

export fn ghostty_vt_collect_dirty_spans(
    h: ?*types.c_void,
    out_rows: [*]u16,
    out_start: [*]u16,
    out_end: [*]u16,
    cap: usize,
) callconv(.C) usize {
    if (h == null or cap == 0) return 0;
    const s: *Session = @ptrCast(@alignCast(h.?));
    var i: usize = 0;
    var y: u16 = 0;
    while (y < s.term.rows and i < cap) : (y += 1) {
        var start: u16 = 0;
        var end_: u16 = 0;
        const dirty = compute_row_span_and_update(s, y, false, &start, &end_);
        if (dirty) {
            out_rows[i] = y;
            out_start[i] = start;
            out_end[i] = end_;
            i += 1;
        }
    }
    return i;
}


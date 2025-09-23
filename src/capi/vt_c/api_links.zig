const types = @import("capi/vt_c/types.zig");
const Session = @import("capi/vt_c/session.zig").Session;
const vt = @import("ghostty-vt");

fn write_link_uri(
    _: *const vt.Terminal,
    page: *const vt.page.Page,
    cell: *const vt.page.Cell,
    out: [*]u8,
    out_cap: usize,
    out_len: *usize,
) bool {
    if (!cell.hyperlink) return false;
    const id = page.lookupHyperlink(cell) orelse return false;
    const link = page.hyperlink_set.get(page.memory, id);
    const uri = link.uri.offset.ptr(page.memory)[0..link.uri.len];
    out_len.* = uri.len;
    if (out_cap < uri.len) return true; // inform required length
    @memcpy(out[0..uri.len], uri);
    return true;
}

export fn ghostty_vt_link_uri_grid(
    h: ?*types.c_void,
    row: u16,
    col: u16,
    out_utf8: [*]u8,
    out_cap: usize,
    out_len: *usize,
) callconv(.C) bool {
    if (h == null) return false;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const pt: vt.point.Point = .{ .active = .{ .x = col, .y = row } };
    const got = s.term.screen.pages.getCell(pt) orelse return false;
    return write_link_uri(&s.term, &got.node.data, got.cell, out_utf8, out_cap, out_len);
}

export fn ghostty_vt_link_uri_scrollback(
    h: ?*types.c_void,
    index: usize,
    col: u16,
    out_utf8: [*]u8,
    out_cap: usize,
    out_len: *usize,
) callconv(.C) bool {
    if (h == null) return false;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const pt: vt.point.Point = .{ .history = .{ .x = col, .y = @intCast(index) } };
    const got = s.term.screen.pages.getCell(pt) orelse return false;
    return write_link_uri(&s.term, &got.node.data, got.cell, out_utf8, out_cap, out_len);
}

fn link_span_in_row(
    s: *Session,
    page: *const vt.page.Page,
    row: u16,
    col: u16,
    history: bool,
    out_c0: *u16,
    out_c1: *u16,
) bool {
    const pt0: vt.point.Point = if (history)
        .{ .history = .{ .x = col, .y = @intCast(row) } }
    else
        .{ .active = .{ .x = col, .y = row } };
    const got0 = s.term.screen.pages.getCell(pt0) orelse return false;
    const id = page.lookupHyperlink(got0.cell) orelse return false;
    const cols: u16 = @intCast(s.term.cols);
    var c0: u16 = col;
    while (c0 > 0) : (c0 -= 1) {
        const ptl: vt.point.Point = if (history)
            .{ .history = .{ .x = c0 - 1, .y = @intCast(row) } }
        else
            .{ .active = .{ .x = c0 - 1, .y = row } };
        const gl = s.term.screen.pages.getCell(ptl) orelse break;
        if (page.lookupHyperlink(gl.cell) != id) break;
    }
    var c1: u16 = col;
    while (c1 + 1 < cols) : (c1 += 1) {
        const ptr: vt.point.Point = if (history)
            .{ .history = .{ .x = c1 + 1, .y = @intCast(row) } }
        else
            .{ .active = .{ .x = c1 + 1, .y = row } };
        const gr = s.term.screen.pages.getCell(ptr) orelse break;
        if (page.lookupHyperlink(gr.cell) != id) break;
    }
    out_c0.* = c0;
    out_c1.* = c1;
    return true;
}

export fn ghostty_vt_link_span_grid_row(
    h: ?*types.c_void,
    row: u16,
    col: u16,
    out_col0: *u16,
    out_col1: *u16,
) callconv(.C) bool {
    if (h == null) return false;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const pin = s.term.screen.pages.pin(.{ .active = .{ .y = row, .x = col } }) orelse return false;
    const page = &pin.node.data;
    return link_span_in_row(s, page, row, col, false, out_col0, out_col1);
}

export fn ghostty_vt_link_span_scrollback_row(
    h: ?*types.c_void,
    index: usize,
    col: u16,
    out_col0: *u16,
    out_col1: *u16,
) callconv(.C) bool {
    if (h == null) return false;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const pt: vt.point.Point = .{ .history = .{ .x = col, .y = @intCast(index) } };
    const got = s.term.screen.pages.getCell(pt) orelse return false;
    const page = &got.node.data;
    const row: u16 = @intCast(index);
    return link_span_in_row(s, page, row, col, true, out_col0, out_col1);
}


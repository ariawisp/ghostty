const types = @import("types.zig");
const Session = @import("session.zig").Session;
const helpers = @import("helpers.zig");
const vt = @import("ghostty-vt");

export fn ghostty_vt_scrollback_size(h: ?*types.c_void) callconv(.C) usize {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        var it = s.term.screen.pages.pageIterator(.right_down, .{ .history = .{} }, null);
        var total: usize = 0;
        while (it.next()) |chunk| total += (chunk.end - chunk.start);
        return total;
    }
    return 0;
}

export fn ghostty_vt_scrollback_row_cells_into(
    h: ?*types.c_void,
    index: usize,
    out_cells: [*]types.CCell,
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
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const pt: vt.point.Point = .{ .history = .{ .x = @intCast(i), .y = @intCast(index) } };
        const got = s.term.screen.pages.getCell(pt) orelse {
            out_cells[i] = .{ .text = "", .text_len = 0, .fg_rgba = helpers.pack_rgba(helpers.default_fg(), 0xFF), .bg_rgba = 0, .width = 1, .underline = false, .strike = false, .inverse = false, .bold = false, .italic = false, .link_tag = 0 };
            continue;
        };

        const page = &got.node.data;
        const cell = got.cell;
        const width: u8 = switch (cell.wide) { .narrow => 1, .wide => 2, .spacer_tail => 0, .spacer_head => 1 };

        var text_slice: []const u8 = (&[_]u8{})[0..];
        if (width != 0) {
            text_slice = helpers.cell_text_into(@as([*]u8, text_arena)[0..arena_cap], &used, page, cell);
        }
        const style = if (cell.style_id == 0) vt.Style{} else page.styles.get(page.memory, cell.style_id).*;
        const flags = style.flags;
        const clr = helpers.cell_colors(&s.term, page, cell);
        const link = helpers.cell_link_tag(page, cell);

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

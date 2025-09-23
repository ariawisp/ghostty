const std = @import("std");
const vt = @import("ghostty-vt");
const Allocator = std.mem.Allocator;

pub fn pack_rgba(rgb: vt.color.RGB, a: u8) u32 {
    return (@as(u32, a) << 24) | (@as(u32, rgb.r) << 16) | (@as(u32, rgb.g) << 8) | (@as(u32, rgb.b));
}

pub fn default_fg() vt.color.RGB {
    return vt.color.Name.white.default() catch .{ .r = 0xEA, .g = 0xEA, .b = 0xEA };
}

pub fn default_bg() vt.color.RGB {
    return vt.color.Name.black.default() catch .{ .r = 0x1D, .g = 0x1F, .b = 0x21 };
}

pub fn cell_text_alloc(alloc: Allocator, page: *const vt.page.Page, cell: *const vt.page.Cell) ![]u8 {
    if (!cell.hasText()) return try alloc.dupe(u8, "");
    var buf = std.ArrayList(u8).init(alloc);
    errdefer buf.deinit();
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

pub fn cell_text_into(arena: []u8, used: *usize, page: *const vt.page.Page, cell: *const vt.page.Cell) []const u8 {
    if (!cell.hasText()) return &[_]u8{};
    var total: usize = utf8_len_for_codepoint(cell.codepoint());
    if (cell.hasGrapheme()) {
        if (page.lookupGrapheme(cell)) |slice| {
            const cps = slice;
            for (cps) |cp| total += utf8_len_for_codepoint(cp);
        }
    }
    if (arena.len - used.* < total) return &[_]u8{};
    const start = used.*;
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

pub fn cell_colors(term: *const vt.Terminal, page: *const vt.page.Page, cell: *const vt.page.Cell) struct { fg: u32, bg: u32 } {
    const palette: *const vt.color.Palette = &term.color_palette.colors;
    const style = if (cell.style_id == 0) vt.Style{} else page.styles.get(page.memory, cell.style_id).*;
    const fg_rgb = vt.Style.fg(style, .{ .default = default_fg(), .palette = palette, .bold = null });
    var bg_rgb = style.bg(cell, palette);
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

pub fn cell_link_tag(page: *const vt.page.Page, cell: *const vt.page.Cell) u32 {
    if (cell.hyperlink) {
        if (page.lookupHyperlink(cell)) |id| return @intCast(id);
    }
    return 0;
}


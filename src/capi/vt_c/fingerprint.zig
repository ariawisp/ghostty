const vt = @import("ghostty-vt");
const helpers = @import("helpers.zig");

const FNV64_OFF: u64 = 0xcbf29ce484222325;
const FNV64_PRIME: u64 = 1099511628211;
inline fn fnv_add_byte(h: u64, b: u8) u64 {
    return (h ^ @as(u64, b)) *% FNV64_PRIME;
}

pub fn cell_fingerprint(term: *const vt.Terminal, page: *const vt.page.Page, cell: *const vt.page.Cell) u64 {
    var h: u64 = FNV64_OFF;
    const width: u8 = switch (cell.wide) { .narrow => 1, .wide => 2, .spacer_tail => 0, .spacer_head => 1 };
    h = fnv_add_byte(h, width);
    if (width != 0) {
        const cp: u32 = @intCast(cell.codepoint());
        h = fnv_add_byte(h, @as(u8, @intCast(cp & 0xFF)));
        h = fnv_add_byte(h, @as(u8, @intCast((cp >> 8) & 0xFF)));
        h = fnv_add_byte(h, @as(u8, @intCast((cp >> 16) & 0xFF)));
        h = fnv_add_byte(h, @as(u8, @intCast((cp >> 24) & 0xFF)));
    }
    if (width != 0 and cell.hasGrapheme()) {
        if (page.lookupGrapheme(cell)) |slice| {
            const cps = slice;
            var i: usize = 0;
            while (i < cps.len) : (i += 1) {
                const v: u32 = @intCast(cps[i]);
                h = fnv_add_byte(h, @as(u8, @intCast(v & 0xFF)));
                h = fnv_add_byte(h, @as(u8, @intCast((v >> 8) & 0xFF)));
                h = fnv_add_byte(h, @as(u8, @intCast((v >> 16) & 0xFF)));
                h = fnv_add_byte(h, @as(u8, @intCast((v >> 24) & 0xFF)));
            }
        }
    }
    const clr = helpers.cell_colors(term, page, cell);
    const fg: u32 = clr.fg;
    const bg: u32 = clr.bg;
    h = fnv_add_byte(h, @as(u8, @intCast(fg & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((fg >> 8) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((fg >> 16) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((fg >> 24) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast(bg & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((bg >> 8) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((bg >> 16) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((bg >> 24) & 0xFF)));

    const style = if (cell.style_id == 0) vt.Style{} else page.styles.get(page.memory, cell.style_id).*;
    const flags = style.flags;
    var fmask: u8 = 0;
    if (flags.underline != .none) fmask |= 1;
    if (flags.strikethrough) fmask |= 2;
    if (flags.inverse) fmask |= 4;
    if (flags.bold) fmask |= 8;
    if (flags.italic) fmask |= 16;
    h = fnv_add_byte(h, fmask);

    const link = helpers.cell_link_tag(page, cell);
    const v: u32 = link;
    h = fnv_add_byte(h, @as(u8, @intCast(v & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((v >> 8) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((v >> 16) & 0xFF)));
    h = fnv_add_byte(h, @as(u8, @intCast((v >> 24) & 0xFF)));
    return h;
}

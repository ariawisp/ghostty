const types = @import("capi/vt_c/types.zig");
const Session = @import("capi/vt_c/session.zig").Session;
const vt = @import("ghostty-vt");
const helpers = @import("capi/vt_c/helpers.zig");

export fn ghostty_vt_reverse_colors(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.modes.get(.reverse_colors);
    }
    return false;
}

export fn ghostty_vt_palette_rgba(h: ?*types.c_void, out_rgba: [*]u32, cap: usize) callconv(.C) usize {
    if (h == null) return 256;
    const s: *Session = @ptrCast(@alignCast(h.?));
    const need: usize = @typeInfo(vt.color.Palette).array.len; // 256
    if (cap < need) return need;
    var i: usize = 0;
    while (i < need) : (i += 1) {
        const rgb = s.term.color_palette.colors[i];
        out_rgba[i] = (@as(u32, 0xFF) << 24) | (@as(u32, rgb.r) << 16) | (@as(u32, rgb.g) << 8) | (@as(u32, rgb.b));
    }
    return need;
}

export fn ghostty_vt_default_fg_rgba(h: ?*types.c_void) callconv(.C) u32 {
    _ = h;
    const rgb = helpers.default_fg();
    return (@as(u32, 0xFF) << 24) | (@as(u32, rgb.r) << 16) | (@as(u32, rgb.g) << 8) | (@as(u32, rgb.b));
}

export fn ghostty_vt_default_bg_rgba(h: ?*types.c_void) callconv(.C) u32 {
    _ = h;
    const rgb = helpers.default_bg();
    return (@as(u32, 0xFF) << 24) | (@as(u32, rgb.r) << 16) | (@as(u32, rgb.g) << 8) | (@as(u32, rgb.b));
}


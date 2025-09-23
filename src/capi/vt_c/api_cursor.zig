const types = @import("types.zig");
const Session = @import("session.zig").Session;

export fn ghostty_vt_cursor_row(h: ?*types.c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.screen.cursor.y);
    }
    return 0;
}

export fn ghostty_vt_cursor_col(h: ?*types.c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.screen.cursor.x);
    }
    return 0;
}

export fn ghostty_vt_is_alt_screen(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.active_screen == .alternate;
    }
    return false;
}

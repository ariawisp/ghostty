const types = @import("capi/vt_c/types.zig");
const Session = @import("capi/vt_c/session.zig").Session;

export fn ghostty_vt_mode_bracketed_paste(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.modes.get(.bracketed_paste);
    }
    return false;
}

export fn ghostty_vt_mode_mouse_enabled(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.flags.mouse_event != .none;
    }
    return false;
}

export fn ghostty_vt_mode_mouse_sgr(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.flags.mouse_format == .sgr or s.term.flags.mouse_format == .sgr_pixels;
    }
    return false;
}

export fn ghostty_vt_mode_mouse_motion(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.flags.mouse_event.motion();
    }
    return false;
}

export fn ghostty_vt_mode_mouse_any_motion(h: ?*types.c_void) callconv(.C) bool {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.flags.mouse_event == .any;
    }
    return false;
}

export fn ghostty_vt_kitty_keyboard_flags(h: ?*types.c_void) callconv(.C) u32 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return s.term.screen.kitty_keyboard.current().int();
    }
    return 0;
}


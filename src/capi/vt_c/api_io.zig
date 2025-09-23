const std = @import("std");
const vt = @import("ghostty-vt");
const types = @import("types.zig");
const Session = @import("session.zig").Session;

export fn ghostty_vt_new(cols: u16, rows: u16, max_scrollback_bytes: usize) callconv(.C) ?*types.c_void {
    const alloc = std.heap.c_allocator;
    const s = Session.init(alloc, cols, rows, max_scrollback_bytes) catch return null;
    return s;
}

export fn ghostty_vt_free(h: ?*types.c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        s.deinit();
    }
}

export fn ghostty_vt_set_writer(h: ?*types.c_void, cb: types.WriteCb, ud: ?*types.c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        s.write_cb = cb;
        s.write_ud = ud;
    }
}

export fn ghostty_vt_set_events(h: ?*types.c_void, ev: ?*const types.EventsC, ud: ?*types.c_void) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        if (ev) |p| {
            s.events.on_title = p.on_title;
            s.events.on_clipboard_set = p.on_clipboard_set;
            s.events.on_bell = p.on_bell;
            s.events.on_palette_changed = p.on_palette_changed;
            s.events.ud = ud;
        } else {
            s.events = .{};
        }
    }
}

export fn ghostty_vt_resize(h: ?*types.c_void, cols: u16, rows: u16) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        _ = s.term.resize(s.alloc, cols, rows) catch {};
        s.cache_primary.ensure(s.alloc, rows, cols) catch {};
        s.cache_alt.ensure(s.alloc, rows, cols) catch {};
    }
}

export fn ghostty_vt_feed(h: ?*types.c_void, bytes: [*]const u8, len: usize) callconv(.C) void {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        _ = s.stream.nextSlice(bytes[0..len]) catch {};
    }
}

export fn ghostty_vt_rows(h: ?*types.c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.rows);
    }
    return 0;
}

export fn ghostty_vt_cols(h: ?*types.c_void) callconv(.C) u16 {
    if (h) |ptr| {
        const s: *Session = @ptrCast(@alignCast(ptr));
        return @intCast(s.term.cols);
    }
    return 0;
}

export fn ghostty_vt_c_api_version(out_major: ?*u16, out_minor: ?*u16) callconv(.C) void {
    if (out_major) |p| p.* = 1;
    if (out_minor) |p| p.* = 0;
}

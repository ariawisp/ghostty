const std = @import("std");

// Shared C ABI types for the vt_c shim
pub const c_void = anyopaque;

// Mirror of ghostty_vt_cell_t in C
pub const CCell = extern struct {
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
pub const WriteCb = ?*const fn (*c_void, [*]const u8, usize) callconv(.C) void;

// Event registration (title/clipboard/bell)
pub const EventsC = extern struct {
    on_title: ?*const fn (*c_void, [*]const u8, usize) callconv(.C) void,
    on_clipboard_set: ?*const fn (*c_void, [*]const u8, usize) callconv(.C) void,
    on_bell: ?*const fn (*c_void) callconv(.C) void,
    on_palette_changed: ?*const fn (*c_void) callconv(.C) void,
};


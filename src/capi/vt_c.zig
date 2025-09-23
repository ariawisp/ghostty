// Thin aggregator for the vt_c C shim. All C ABI exports and helpers
// are split across focused modules for maintainability.

_ = @import("capi/vt_c/types.zig");
_ = @import("capi/vt_c/rowcache.zig");
_ = @import("capi/vt_c/helpers.zig");
_ = @import("capi/vt_c/fingerprint.zig");
_ = @import("capi/vt_c/session.zig");

// Public C API groups
_ = @import("capi/vt_c/api_io.zig");
_ = @import("capi/vt_c/api_cursor.zig");
_ = @import("capi/vt_c/api_dirty.zig");
_ = @import("capi/vt_c/api_cells.zig");
_ = @import("capi/vt_c/api_scrollback.zig");
_ = @import("capi/vt_c/api_links.zig");
_ = @import("capi/vt_c/api_modes.zig");
_ = @import("capi/vt_c/api_palette.zig");


// Thin aggregator for the vt_c C shim. All C ABI exports and helpers
// are split across focused modules for maintainability.

const types_mod = @import("vt_c/types.zig");
const rowcache_mod = @import("vt_c/rowcache.zig");
const helpers_mod = @import("vt_c/helpers.zig");
const fingerprint_mod = @import("vt_c/fingerprint.zig");
const session_mod = @import("vt_c/session.zig");

// Public C API groups
const api_io_mod = @import("vt_c/api_io.zig");
const api_cursor_mod = @import("vt_c/api_cursor.zig");
const api_dirty_mod = @import("vt_c/api_dirty.zig");
const api_cells_mod = @import("vt_c/api_cells.zig");
const api_scrollback_mod = @import("vt_c/api_scrollback.zig");
const api_links_mod = @import("vt_c/api_links.zig");
const api_modes_mod = @import("vt_c/api_modes.zig");
const api_palette_mod = @import("vt_c/api_palette.zig");

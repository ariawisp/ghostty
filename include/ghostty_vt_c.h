// Minimal C ABI shim for Ghostty's VT engine.
//
// This header exposes a small, stable surface for Kotlin/Native cinterop
// (or other C consumers) to drive the terminal emulator, feed bytes,
// and read back line/cell state for rendering. The API is intentionally
// minimal and focused on text-grid access; clipboard, IPC, and images
// can be added later.
//
// Build: zig build (installs libghostty_vt_c and this header)
#ifndef GHOSTTY_VT_C_H
#define GHOSTTY_VT_C_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

// C API version for bindings to assert compatibility at runtime.
#define GHOSTTY_VT_C_API_VERSION_MAJOR 1
#define GHOSTTY_VT_C_API_VERSION_MINOR 0
void ghostty_vt_c_api_version(uint16_t* out_major, uint16_t* out_minor);

// Opaque session handle
typedef void* ghostty_vt_t;

// Optional write callback for terminal replies (e.g., DSR, DA).
// If set, the engine may call this to write response bytes back to the host/pty.
typedef void (*ghostty_vt_write_cb)(void* userdata, const char* bytes, size_t len);

// One terminal cell snapshot for rendering. Text is UTF-8; when width==0
// (wide-trailing spacer) text is empty. The callee owns text buffers; free
// them with ghostty_vt_row_cells_free.
typedef struct ghostty_vt_cell_s {
  const char* text;     // UTF-8 (may be empty); lifetime until row_cells_free
  size_t      text_len; // bytes
  uint32_t    fg_rgba;  // 0xAARRGGBB
  uint32_t    bg_rgba;  // 0xAARRGGBB (0 for none/transparent)
  uint8_t     width;    // 0,1,2 (0 = spacer tail)
  bool        underline;
  bool        strike;
  bool        inverse;
  bool        bold;
  bool        italic;
  uint32_t    link_tag; // 0 if none; non-zero tags can be mapped to URIs via higher-level APIs in future
} ghostty_vt_cell_t;

// Session lifecycle
ghostty_vt_t ghostty_vt_new(uint16_t cols, uint16_t rows, size_t max_scrollback_bytes);
void         ghostty_vt_free(ghostty_vt_t);

// Optional writer for replies
void ghostty_vt_set_writer(ghostty_vt_t, ghostty_vt_write_cb cb, void* userdata);

// Optional event callbacks for host-side integration (title, clipboard, bell)
typedef struct ghostty_vt_events_s {
  void (*on_title)(void* userdata, const char* utf8, size_t len);
  void (*on_clipboard_set)(void* userdata, const char* utf8, size_t len);
  void (*on_bell)(void* userdata);
} ghostty_vt_events_t;

void ghostty_vt_set_events(ghostty_vt_t, const ghostty_vt_events_t* events, void* userdata);

// Resize viewport (cols, rows >= 1)
void ghostty_vt_resize(ghostty_vt_t, uint16_t cols, uint16_t rows);

// Feed raw bytes (UTF-8 and control sequences)
void ghostty_vt_feed(ghostty_vt_t, const uint8_t* bytes, size_t len);

// Basic query
uint16_t ghostty_vt_rows(ghostty_vt_t);
uint16_t ghostty_vt_cols(ghostty_vt_t);
uint16_t ghostty_vt_cursor_row(ghostty_vt_t); // 0-based
uint16_t ghostty_vt_cursor_col(ghostty_vt_t); // 0-based
bool     ghostty_vt_is_alt_screen(ghostty_vt_t);

// Mode/state queries (for input routing)
bool     ghostty_vt_mode_bracketed_paste(ghostty_vt_t);
bool     ghostty_vt_mode_mouse_enabled(ghostty_vt_t);      // any mouse mode active
bool     ghostty_vt_mode_mouse_sgr(ghostty_vt_t);          // SGR or SGR-pixel format
bool     ghostty_vt_mode_mouse_motion(ghostty_vt_t);       // button or any-motion modes
bool     ghostty_vt_mode_mouse_any_motion(ghostty_vt_t);   // any-motion mode specifically
uint32_t ghostty_vt_kitty_keyboard_flags(ghostty_vt_t);    // current kitty keyboard flags as bitmask

// Dirtiness per visible row (active area)
bool ghostty_vt_row_dirty(ghostty_vt_t, uint16_t row);
void ghostty_vt_row_clear_dirty(ghostty_vt_t, uint16_t row);
void ghostty_vt_clear_all_dirty(ghostty_vt_t);
// Optional: return a coarse dirty span. For now, returns full row when dirty.
bool ghostty_vt_row_dirty_span(ghostty_vt_t, uint16_t row, uint16_t* out_start, uint16_t* out_end);

// Read one visible row into caller-allocated array. Returns number of cells
// written (min of cols and out_cap). For each cell, the function allocates
// a small UTF-8 buffer for text; caller must free them with row_cells_free.
size_t ghostty_vt_row_cells(ghostty_vt_t, uint16_t row, ghostty_vt_cell_t* out_cells, size_t out_cap);
void   ghostty_vt_row_cells_free(ghostty_vt_cell_t* cells, size_t count);

// Write row cells into caller-provided arena for text storage.
// - Writes up to out_cap cells from the visible grid row.
// - Writes UTF-8 text contiguously into `text_arena`; sets `*out_arena_used` to total bytes written.
// - Cell.text pointers point into `text_arena` for non-empty text; empty texts have len=0 and text="".
// Returns the number of cells written (<= out_cap).
size_t ghostty_vt_row_cells_into(
    ghostty_vt_t,
    uint16_t row,
    ghostty_vt_cell_t* out_cells,
    size_t out_cap,
    char* text_arena,
    size_t arena_cap,
    size_t* out_arena_used
);

// Scrollback APIs
size_t ghostty_vt_scrollback_size(ghostty_vt_t);
size_t ghostty_vt_scrollback_row_cells_into(
    ghostty_vt_t,
    size_t index, // 0 = oldest history row
    ghostty_vt_cell_t* out_cells,
    size_t out_cap,
    char* text_arena,
    size_t arena_cap,
    size_t* out_arena_used
);

// Resolve hyperlink URIs
// Grid (visible) row: returns true if a hyperlink exists at (row,col) and writes its URI.
bool ghostty_vt_link_uri_grid(
    ghostty_vt_t,
    uint16_t row,
    uint16_t col,
    char* out_utf8,
    size_t out_cap,
    size_t* out_len
);
// Scrollback row by history index (0 = oldest)
bool ghostty_vt_link_uri_scrollback(
    ghostty_vt_t,
    size_t index,
    uint16_t col,
    char* out_utf8,
    size_t out_cap,
    size_t* out_len
);

#ifdef __cplusplus
}
#endif

#endif // GHOSTTY_VT_C_H

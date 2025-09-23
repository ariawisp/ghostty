@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package org.ghostty.vt

import kotlinx.cinterop.*
import ghostty_vt.*

class Session(
    initCols: Int = 120,
    initRows: Int = 40,
    maxScrollbackBytes: Long = 2_000_000L,
) {
    private var handle: COpaquePointer? = ghostty_vt_new(initCols.toUShort(), initRows.toUShort(), maxScrollbackBytes.toULong())
    private var selfRef: StableRef<Session>? = null

    private var writer: ((ByteArray) -> Unit)? = null
    private var onTitle: ((String) -> Unit)? = null
    private var onClipboard: ((String) -> Unit)? = null
    private var onBell: (() -> Unit)? = null
    private var onPaletteChanged: (() -> Unit)? = null

    fun close() {
        selfRef?.dispose(); selfRef = null
        handle?.let { ghostty_vt_free(it) }
        handle = null
    }

    fun assertApiVersion(requiredMajor: Int = 1) {
        memScoped {
            val maj = alloc<UShortVar>(); val min = alloc<UShortVar>()
            ghostty_vt_c_api_version(maj.ptr, min.ptr)
            require(maj.value.toInt() >= requiredMajor) { "ghostty_vt C API too old: ${maj.value}.${min.value}" }
        }
    }

    fun setWriter(cb: (ByteArray) -> Unit) {
        writer = cb
        val s = handle ?: return
        if (selfRef == null) selfRef = StableRef.create(this)
        ghostty_vt_set_writer(s, Callbacks.writeCallback, selfRef!!.asCPointer())
    }

    fun setEvents(
        onTitleChanged: ((String) -> Unit)? = null,
        onClipboardSet: ((String) -> Unit)? = null,
        onBellEvent: (() -> Unit)? = null,
        onPaletteChangedEvent: (() -> Unit)? = null,
    ) {
        onTitle = onTitleChanged
        onClipboard = onClipboardSet
        onBell = onBellEvent
        onPaletteChanged = onPaletteChangedEvent
        val s = handle ?: return
        if (selfRef == null) selfRef = StableRef.create(this)
        memScoped {
            val ev = alloc<ghostty_vt_events_s>()
            ev.on_title = Callbacks.titleCallback
            ev.on_clipboard_set = Callbacks.clipboardCallback
            ev.on_bell = Callbacks.bellCallback
            ev.on_palette_changed = Callbacks.paletteChangedCallback
            ghostty_vt_set_events(s, ev.ptr, selfRef!!.asCPointer())
        }
    }

    fun setEvents(ev: Events) = setEvents(ev.onTitleChanged, ev.onClipboardSet, ev.onBell, ev.onPaletteChanged)

    internal fun _onWrite(bytes: ByteArray) { writer?.invoke(bytes) }
    internal fun _onTitle(text: String) { onTitle?.invoke(text) }
    internal fun _onClipboard(text: String) { onClipboard?.invoke(text) }
    internal fun _onBell() { onBell?.invoke() }
    internal fun _onPaletteChanged() { onPaletteChanged?.invoke() }

    fun feed(bytes: ByteArray) {
        val s = handle ?: return
        bytes.usePinned { p -> ghostty_vt_feed(s, p.addressOf(0).reinterpret(), bytes.size.toULong()) }
    }
    fun resize(cols: Int, rows: Int) { handle?.let { ghostty_vt_resize(it, cols.toUShort(), rows.toUShort()) } }

    val cols: Int get() = (handle?.let { ghostty_vt_cols(it) } ?: 0u).toInt()
    val rows: Int get() = (handle?.let { ghostty_vt_rows(it) } ?: 0u).toInt()
    val cursorRow: Int get() = (handle?.let { ghostty_vt_cursor_row(it) } ?: 0u).toInt()
    val cursorCol: Int get() = (handle?.let { ghostty_vt_cursor_col(it) } ?: 0u).toInt()
    val isAltScreen: Boolean get() = (handle?.let { ghostty_vt_is_alt_screen(it) } ?: false)

    fun dirtySpan(row: Int): IntRange? {
        val s = handle ?: return null
        memScoped {
            val start = alloc<UShortVar>(); val end = alloc<UShortVar>()
            val ok = ghostty_vt_row_dirty_span(s, row.toUShort(), start.ptr, end.ptr)
            if (!ok) return null
            val a = start.value.toInt(); val b = end.value.toInt()
            if (a >= 0 && b >= a && b < cols) return a..b
            return 0 until cols
        }
    }
    fun clearRowDirty(row: Int) { handle?.let { ghostty_vt_row_clear_dirty(it, row.toUShort()) } }
    fun clearAllDirty() { handle?.let { ghostty_vt_clear_all_dirty(it) } }

    fun collectDirtyRows(): IntArray {
        val s = handle ?: return IntArray(0)
        val rows = rows
        memScoped {
            val out = allocArray<UShortVar>(rows)
            val n = ghostty_vt_collect_dirty_rows(s, out.reinterpret(), rows.toULong()).toInt()
            val arr = IntArray(n)
            for (i in 0 until n) arr[i] = out[i].toInt()
            return arr
        }
    }
    data class DirtySpan(val row: Int, val start: Int, val end: Int)
    fun collectDirtySpans(cap: Int = rows): List<DirtySpan> {
        val s = handle ?: return emptyList()
        val c = cap.coerceAtLeast(0)
        if (c == 0) return emptyList()
        memScoped {
            val rowsOut = allocArray<UShortVar>(c)
            val startOut = allocArray<UShortVar>(c)
            val endOut = allocArray<UShortVar>(c)
            val n = ghostty_vt_collect_dirty_spans(s, rowsOut.reinterpret(), startOut.reinterpret(), endOut.reinterpret(), c.toULong()).toInt()
            val list = ArrayList<DirtySpan>(n)
            for (i in 0 until n) list += DirtySpan(rowsOut[i].toInt(), startOut[i].toInt(), endOut[i].toInt())
            return list
        }
    }

    fun rowCells(row: Int): List<Cell> {
        val s = handle ?: return emptyList()
        val c = cols; if (c == 0 || row !in 0 until rows) return emptyList()
        ensureGridArena((c * 16).coerceAtLeast(256))
        val arena = gridArena
        arena.usePinned {
            memScoped {
                val out = allocArray<ghostty_vt_cell_s>(c)
                val used = alloc<ULongVar>(); used.value = 0u
                val n = ghostty_vt_row_cells_into(s, row.toUShort(), out, c.toULong(), it.addressOf(0).reinterpret(), arena.size.toULong(), used.ptr).toInt()
                val list = ArrayList<Cell>(n)
                for (i in 0 until n) {
                    val cc = out[i]
                    val txt = if (cc.text_len.toInt() == 0) "" else cc.text!!.readBytes(cc.text_len.toInt()).decodeToString()
                    list += Cell(txt, cc.fg_rgba.toInt(), cc.bg_rgba.toInt(), cc.width.toInt(), cc.underline, cc.strike, cc.inverse, cc.bold, cc.italic, cc.link_tag.toInt())
                }
                return list
            }
        }
    }

    fun scrollbackSize(): Int { val s = handle ?: return 0; return ghostty_vt_scrollback_size(s).toInt() }
    fun scrollbackRowCells(index: Int): List<Cell> {
        val s = handle ?: return emptyList()
        val size = scrollbackSize(); if (index !in 0 until size) return emptyList()
        val c = cols; if (c == 0) return emptyList()
        ensureScrollArena((c * 16).coerceAtLeast(256))
        val arena = scrollArena
        arena.usePinned {
            memScoped {
                val out = allocArray<ghostty_vt_cell_s>(c)
                val used = alloc<ULongVar>(); used.value = 0u
                val n = ghostty_vt_scrollback_row_cells_into(s, index.toULong(), out, c.toULong(), it.addressOf(0).reinterpret(), arena.size.toULong(), used.ptr).toInt()
                val list = ArrayList<Cell>(n)
                for (i in 0 until n) {
                    val cc = out[i]
                    val txt = if (cc.text_len.toInt() == 0) "" else cc.text!!.readBytes(cc.text_len.toInt()).decodeToString()
                    list += Cell(txt, cc.fg_rgba.toInt(), cc.bg_rgba.toInt(), cc.width.toInt(), cc.underline, cc.strike, cc.inverse, cc.bold, cc.italic, cc.link_tag.toInt())
                }
                return list
            }
        }
    }

    fun linkUriOnGrid(row: Int, col: Int): String? = Uri.query { buf, cap, len ->
        val s = handle ?: return@query false
        ghostty_vt_link_uri_grid(s, row.toUShort(), col.toUShort(), buf, cap, len)
    }
    fun linkUriInScrollback(index: Int, col: Int): String? = Uri.query { buf, cap, len ->
        val s = handle ?: return@query false
        ghostty_vt_link_uri_scrollback(s, index.toULong(), col.toUShort(), buf, cap, len)
    }

    fun linkSpanOnGrid(row: Int, col: Int): IntRange? {
        val s = handle ?: return null
        memScoped {
            val a = alloc<UShortVar>(); val b = alloc<UShortVar>()
            val ok = ghostty_vt_link_span_grid_row(s, row.toUShort(), col.toUShort(), a.ptr, b.ptr)
            if (!ok) return null
            return a.value.toInt()..b.value.toInt()
        }
    }
    fun linkSpanInScrollback(index: Int, col: Int): IntRange? {
        val s = handle ?: return null
        memScoped {
            val a = alloc<UShortVar>(); val b = alloc<UShortVar>()
            val ok = ghostty_vt_link_span_scrollback_row(s, index.toULong(), col.toUShort(), a.ptr, b.ptr)
            if (!ok) return null
            return a.value.toInt()..b.value.toInt()
        }
    }

    // Input mode queries
    fun isBracketedPasteEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_bracketed_paste(s) }
    fun isMouseReportingEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_enabled(s) }
    fun isMouseSgrEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_sgr(s) }
    fun isMouseMotionEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_motion(s) }
    fun isMouseAnyMotionEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_any_motion(s) }
    fun kittyKeyboardFlags(): Int { val s = handle ?: return 0; return ghostty_vt_kitty_keyboard_flags(s).toInt() }
    fun kittyKeyboard(): KittyKeyboardFlags = KittyKeyboardFlags.fromInt(kittyKeyboardFlags())
    fun reverseColors(): Boolean { val s = handle ?: return false; return ghostty_vt_reverse_colors(s) }
    fun defaultFgRgba(): Int { val s = handle ?: return 0xFFFFFFFF.toInt(); return ghostty_vt_default_fg_rgba(s).toInt() }
    fun defaultBgRgba(): Int { val s = handle ?: return 0x000000FF; return ghostty_vt_default_bg_rgba(s).toInt() }

    // Persistent arenas for row text
    private var gridArena: ByteArray = ByteArray(4096)
    private var scrollArena: ByteArray = ByteArray(4096)
    private fun ensureGridArena(cap: Int) { if (gridArena.size < cap) gridArena = ByteArray(cap.coerceAtLeast(gridArena.size * 2)) }
    private fun ensureScrollArena(cap: Int) { if (scrollArena.size < cap) scrollArena = ByteArray(cap.coerceAtLeast(scrollArena.size * 2)) }
}

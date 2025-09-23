package org.ghostty.vt

import kotlinx.cinterop.*
import ghostty_vt.*

data class Cell(
    val text: String,
    val fgRgba: Int,
    val bgRgba: Int,
    val width: Int,
    val underline: Boolean,
    val strike: Boolean,
    val inverse: Boolean,
    val bold: Boolean,
    val italic: Boolean,
    val linkTag: Int,
)

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
        ghostty_vt_set_writer(s, writeCallback, selfRef!!.asCPointer())
    }

    fun setEvents(
        onTitleChanged: ((String) -> Unit)? = null,
        onClipboardSet: ((String) -> Unit)? = null,
        onBellEvent: (() -> Unit)? = null,
    ) {
        onTitle = onTitleChanged
        onClipboard = onClipboardSet
        onBell = onBellEvent
        val s = handle ?: return
        if (selfRef == null) selfRef = StableRef.create(this)
        memScoped {
            val ev = alloc<ghostty_vt_events_s>()
            ev.on_title = titleCallback
            ev.on_clipboard_set = clipboardCallback
            ev.on_bell = bellCallback
            ghostty_vt_set_events(s, ev.ptr, selfRef!!.asCPointer())
        }
    }

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

    fun rowCells(row: Int): List<Cell> {
        val s = handle ?: return emptyList()
        val c = cols; if (c == 0 || row !in 0 until rows) return emptyList()
        memScoped {
            val out = allocArray<ghostty_vt_cell_s>(c)
            val arenaCap = (c * 16).coerceAtLeast(256)
            val arena = allocArray<ByteVar>(arenaCap)
            val used = alloc<ULongVar>(); used.value = 0u
            val n = ghostty_vt_row_cells_into(s, row.toUShort(), out, c.toULong(), arena, arenaCap.toULong(), used.ptr).toInt()
            val list = ArrayList<Cell>(n)
            for (i in 0 until n) {
                val cc = out[i]
                val txt = if (cc.text_len.toInt() == 0) "" else cc.text!!.readBytes(cc.text_len.toInt()).decodeToString()
                list += Cell(
                    text = txt,
                    fgRgba = cc.fg_rgba.toInt(),
                    bgRgba = cc.bg_rgba.toInt(),
                    width = cc.width.toInt(),
                    underline = cc.underline,
                    strike = cc.strike,
                    inverse = cc.inverse,
                    bold = cc.bold,
                    italic = cc.italic,
                    linkTag = cc.link_tag.toInt(),
                )
            }
            return list
        }
    }

    fun scrollbackSize(): Int { val s = handle ?: return 0; return ghostty_vt_scrollback_size(s).toInt() }
    fun scrollbackRowCells(index: Int): List<Cell> {
        val s = handle ?: return emptyList()
        val size = scrollbackSize(); if (index !in 0 until size) return emptyList()
        val c = cols; if (c == 0) return emptyList()
        memScoped {
            val out = allocArray<ghostty_vt_cell_s>(c)
            val arenaCap = (c * 16).coerceAtLeast(256)
            val arena = allocArray<ByteVar>(arenaCap)
            val used = alloc<ULongVar>(); used.value = 0u
            val n = ghostty_vt_scrollback_row_cells_into(s, index.toULong(), out, c.toULong(), arena, arenaCap.toULong(), used.ptr).toInt()
            val list = ArrayList<Cell>(n)
            for (i in 0 until n) {
                val cc = out[i]
                val txt = if (cc.text_len.toInt() == 0) "" else cc.text!!.readBytes(cc.text_len.toInt()).decodeToString()
                list += Cell(txt, cc.fg_rgba.toInt(), cc.bg_rgba.toInt(), cc.width.toInt(), cc.underline, cc.strike, cc.inverse, cc.bold, cc.italic, cc.link_tag.toInt())
            }
            return list
        }
    }

    fun linkUriOnGrid(row: Int, col: Int): String? = linkUriQuery { buf, cap, len ->
        val s = handle ?: return@linkUriQuery false
        ghostty_vt_link_uri_grid(s, row.toUShort(), col.toUShort(), buf, cap, len)
    }
    fun linkUriInScrollback(index: Int, col: Int): String? = linkUriQuery { buf, cap, len ->
        val s = handle ?: return@linkUriQuery false
        ghostty_vt_link_uri_scrollback(s, index.toULong(), col.toUShort(), buf, cap, len)
    }

    private inline fun linkUriQuery(crossinline call: (CPointer<ByteVar>?, ULong, CPointer<ULongVar>?) -> Boolean): String? = memScoped {
        val outLen = alloc<ULongVar>().also { it.value = 0u }
        val ok = call(null, 0u, outLen.ptr); if (!ok) return@memScoped null
        val need = outLen.value.toInt(); if (need <= 0) return@memScoped null
        val buf = allocArray<ByteVar>(need)
        val ok2 = call(buf, need.toULong(), outLen.ptr); if (!ok2) return@memScoped null
        buf.readBytes(outLen.value.toInt()).decodeToString()
    }

    // Input mode queries
    fun isBracketedPasteEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_bracketed_paste(s) }
    fun isMouseReportingEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_enabled(s) }
    fun isMouseSgrEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_sgr(s) }
    fun isMouseMotionEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_motion(s) }
    fun isMouseAnyMotionEnabled(): Boolean { val s = handle ?: return false; return ghostty_vt_mode_mouse_any_motion(s) }
    fun kittyKeyboardFlags(): Int { val s = handle ?: return 0; return ghostty_vt_kitty_keyboard_flags(s).toInt() }

    private companion object {
        private val writeCallback = staticCFunction { ud: COpaquePointer?, ptr: CPointer<ByteVar>?, len: ULong ->
            if (ud == null || ptr == null) return@staticCFunction
            val sess = ud.asStableRef<Session>().get()
            sess.writer?.invoke(ptr.readBytes(len.toInt()))
        }
        private val titleCallback = staticCFunction { ud: COpaquePointer?, ptr: CPointer<ByteVar>?, len: ULong ->
            if (ud == null || ptr == null) return@staticCFunction
            val sess = ud.asStableRef<Session>().get()
            val text = ptr.readBytes(len.toInt()).decodeToString()
            sess.onTitle?.invoke(text)
        }
        private val clipboardCallback = staticCFunction { ud: COpaquePointer?, ptr: CPointer<ByteVar>?, len: ULong ->
            if (ud == null || ptr == null) return@staticCFunction
            val sess = ud.asStableRef<Session>().get()
            val text = ptr.readBytes(len.toInt()).decodeToString()
            sess.onClipboard?.invoke(text)
        }
        private val bellCallback = staticCFunction { ud: COpaquePointer? ->
            val sess = ud?.asStableRef<Session>()?.get() ?: return@staticCFunction
            sess.onBell?.invoke()
        }
    }
}

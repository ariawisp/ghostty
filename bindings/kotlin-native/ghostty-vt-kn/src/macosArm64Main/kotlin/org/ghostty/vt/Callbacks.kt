@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package org.ghostty.vt

import kotlinx.cinterop.*
import ghostty_vt.*

internal object Callbacks {
    val writeCallback = staticCFunction { ud: COpaquePointer?, ptr: CPointer<ByteVar>?, len: ULong ->
        if (ud == null || ptr == null) return@staticCFunction
        val sess = ud.asStableRef<Session>().get()
        sess._onWrite(ptr.readBytes(len.toInt()))
    }
    val titleCallback = staticCFunction { ud: COpaquePointer?, ptr: CPointer<ByteVar>?, len: ULong ->
        if (ud == null || ptr == null) return@staticCFunction
        val sess = ud.asStableRef<Session>().get()
        val text = ptr.readBytes(len.toInt()).decodeToString()
        sess._onTitle(text)
    }
    val clipboardCallback = staticCFunction { ud: COpaquePointer?, ptr: CPointer<ByteVar>?, len: ULong ->
        if (ud == null || ptr == null) return@staticCFunction
        val sess = ud.asStableRef<Session>().get()
        val text = ptr.readBytes(len.toInt()).decodeToString()
        sess._onClipboard(text)
    }
    val bellCallback = staticCFunction { ud: COpaquePointer? ->
        val sess = ud?.asStableRef<Session>()?.get() ?: return@staticCFunction
        sess._onBell()
    }
    val paletteChangedCallback = staticCFunction { ud: COpaquePointer? ->
        val sess = ud?.asStableRef<Session>()?.get() ?: return@staticCFunction
        sess._onPaletteChanged()
    }
}

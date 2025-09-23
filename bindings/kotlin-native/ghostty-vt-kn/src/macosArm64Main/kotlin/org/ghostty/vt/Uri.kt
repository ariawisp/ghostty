package org.ghostty.vt

import kotlinx.cinterop.*

internal object Uri {
    inline fun query(crossinline call: (CPointer<ByteVar>?, ULong, CPointer<ULongVar>?) -> Boolean): String? = memScoped {
        val outLen = alloc<ULongVar>().also { it.value = 0u }
        val ok = call(null, 0u, outLen.ptr); if (!ok) return@memScoped null
        val need = outLen.value.toInt(); if (need <= 0) return@memScoped null
        val buf = allocArray<ByteVar>(need)
        val ok2 = call(buf, need.toULong(), outLen.ptr); if (!ok2) return@memScoped null
        buf.readBytes(outLen.value.toInt()).decodeToString()
    }
}


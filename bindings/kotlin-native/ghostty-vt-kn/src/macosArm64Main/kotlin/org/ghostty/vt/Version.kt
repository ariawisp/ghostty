package org.ghostty.vt

import kotlinx.cinterop.*
import ghostty_vt.*

object Version {
    fun cApiVersion(): Pair<Int, Int> = memScoped {
        val maj = alloc<UShortVar>(); val min = alloc<UShortVar>()
        ghostty_vt_c_api_version(maj.ptr, min.ptr)
        maj.value.toInt() to min.value.toInt()
    }
}


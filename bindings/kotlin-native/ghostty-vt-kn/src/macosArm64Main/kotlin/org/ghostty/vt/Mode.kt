package org.ghostty.vt

@JvmInline
value class KittyKeyboardFlags(private val bits: Int) {
    val disambiguate: Boolean get() = (bits and 0b00001) != 0
    val reportEvents: Boolean get() = (bits and 0b00010) != 0
    val reportAlternates: Boolean get() = (bits and 0b00100) != 0
    val reportAll: Boolean get() = (bits and 0b01000) != 0
    val reportAssociated: Boolean get() = (bits and 0b10000) != 0

    companion object {
        fun fromInt(v: Int) = KittyKeyboardFlags(v and 0x1F)
    }
}


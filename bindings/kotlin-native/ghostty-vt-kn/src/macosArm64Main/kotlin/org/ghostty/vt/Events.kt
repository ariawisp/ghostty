package org.ghostty.vt

data class Events(
    val onTitleChanged: ((String) -> Unit)? = null,
    val onClipboardSet: ((String) -> Unit)? = null,
    val onBell: (() -> Unit)? = null,
    val onPaletteChanged: (() -> Unit)? = null,
)

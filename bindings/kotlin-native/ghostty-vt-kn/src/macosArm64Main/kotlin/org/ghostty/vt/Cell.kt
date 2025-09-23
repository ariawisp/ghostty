package org.ghostty.vt

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


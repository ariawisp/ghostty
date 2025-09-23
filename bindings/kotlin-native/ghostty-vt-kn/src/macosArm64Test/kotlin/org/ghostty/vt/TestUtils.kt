package org.ghostty.vt

internal object TestSeq {
    fun esc(seq: String): ByteArray = ("\u001B" + seq).encodeToByteArray()
    fun csi(params: String): ByteArray = esc("[" + params)
    fun oscBel(ps: String, content: String): ByteArray = ("\u001B]" + ps + ";" + content + "\u0007").encodeToByteArray()
    fun oscSt(ps: String, content: String): ByteArray = ("\u001B]" + ps + ";" + content + "\u001B\\").encodeToByteArray()
}


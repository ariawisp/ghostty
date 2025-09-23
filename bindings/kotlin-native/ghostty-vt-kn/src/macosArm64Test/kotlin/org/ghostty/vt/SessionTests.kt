package org.ghostty.vt

import io.kotest.matchers.booleans.shouldBeFalse
import io.kotest.matchers.booleans.shouldBeTrue
import io.kotest.matchers.nulls.shouldNotBeNull
import io.kotest.matchers.shouldBe
import kotlin.test.Test
import kotlin.test.Ignore

class SessionTests {
    @Test
    fun lifecycleAndDefaults() {
        val s = Session(initCols = 12, initRows = 6)
        s.cols shouldBe 12
        s.rows shouldBe 6
        s.isAltScreen shouldBe false
        s.close()
        s.cols shouldBe 0
        s.rows shouldBe 0
        s.isAltScreen shouldBe false
    }

    @Test
    fun apiVersionOk() {
        val s = Session()
        s.assertApiVersion(1)
        s.close()
    }

    @Test
    fun writerRespondsToDsr() {
        val s = Session(initCols = 20, initRows = 5)
        val out = mutableListOf<ByteArray>()
        s.setWriter { bytes -> out += bytes }
        // Device Status Report (cursor position)
        s.feed(TestSeq.csi("6n"))
        out.isNotEmpty().shouldBeTrue()
        val resp = out.joinToString(separator = "") { it.decodeToString() }
        resp.startsWith("\u001B[").shouldBeTrue()
        resp.endsWith("R").shouldBeTrue()
        s.close()
    }

    @Test
    fun oscTitleEvent() {
        val s = Session()
        var title: String? = null
        s.setEvents(Events(onTitleChanged = { title = it }))
        s.feed(TestSeq.oscBel("0", "Hello"))
        title.shouldNotBeNull()
        title shouldBe "Hello"
        s.close()
    }

    // Skipped: bracketed paste (CSI ?2004) not implemented in libghostty-vt yet
    @Ignore
    @Test
    fun bracketedPasteMode() {
        val s = Session()
        s.isBracketedPasteEnabled().shouldBeFalse()
        s.feed(TestSeq.csi("?2004h"))
        s.isBracketedPasteEnabled().shouldBeTrue()
        s.feed(TestSeq.csi("?2004l"))
        s.isBracketedPasteEnabled().shouldBeFalse()
        s.close()
    }

    @Test
    fun rowCellsBasic() {
        val s = Session(initCols = 10, initRows = 5)
        s.feed("hi".encodeToByteArray())
        // In Debug builds, allow a couple of passes for the grid to reflect
        // the feed before asserting contents.
        var cells = s.rowCells(0)
        if (cells.isNotEmpty() && cells[0].text.isEmpty()) {
            // one more pass
            cells = s.rowCells(0)
        }
        cells.size shouldBe s.cols
        cells[0].text shouldBe "h"
        cells[1].text shouldBe "i"
        s.close()
    }

    // Skipped: OSC 8 hyperlinks not implemented; engine logs "unimplemented OSC hyperlink"
    @Ignore
    @Test
    fun linkUriAndSpanOnGrid() {
        val s = Session(initCols = 40, initRows = 5)
        // Start hyperlink, print text, end hyperlink (OSC 8 protocol)
        s.feed(TestSeq.oscSt("8", "" + ";" + "https://example.com"))
        s.feed("hello".encodeToByteArray())
        // Close with "ESC ] 8 ; ; ST" (two semicolons)
        s.feed(TestSeq.oscSt("8", ";"))
        val uri = s.linkUriOnGrid(0, 0)
        uri.shouldNotBeNull()
        uri shouldBe "https://example.com"
        val span = s.linkSpanOnGrid(0, 0)
        span.shouldNotBeNull()
        span!!.start shouldBe 0
        s.close()
    }

    @Test
    fun dirtyTrackingBasic() {
        val s = Session(initCols = 10, initRows = 3)
        s.feed("abc".encodeToByteArray())
        s.collectDirtyRows().isNotEmpty().shouldBeTrue()
        s.clearAllDirty()
        s.collectDirtyRows().isEmpty().shouldBeTrue()
        s.close()
    }
}

package com.healthmd.presentation.archive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ArchiveDayFilePreviewTest {
    @Test
    fun byteLimitKeepsEveryCompleteUnicodeScalarAtEveryAlignment() {
        listOf("é", "健", "🩺").forEach { scalar ->
            val width = scalar.toByteArray(Charsets.UTF_8).size
            for (prefixSize in 0 until width) {
                val prefix = "a".repeat(prefixSize)
                val source = prefix + scalar.repeat(ArchiveDayFile.MAXIMUM_BYTES / width + 5)
                val bytes = source.toByteArray(Charsets.UTF_8).copyOf(ArchiveDayFile.MAXIMUM_BYTES)
                val completeCount = (ArchiveDayFile.MAXIMUM_BYTES - prefixSize) / width
                assertEquals(prefix + scalar.repeat(completeCount), ArchiveDayFile.decodePreview(bytes, truncated = true))
            }
        }
    }

    @Test
    fun completeUnicodeAndEmptyFilesRemainExact() {
        listOf("", "---\nname: 健康 🩺 é\n---\n").forEach {
            assertEquals(it, ArchiveDayFile.decodePreview(it.toByteArray(Charsets.UTF_8), truncated = false))
        }
    }

    @Test
    fun corruptBytesCannotBecomePreviewReplacementCharacters() {
        assertNull(ArchiveDayFile.decodePreview(byteArrayOf(0xff.toByte()), truncated = false))
        assertNull(ArchiveDayFile.decodePreview(byteArrayOf(0xff.toByte(), 0x61, 0x61, 0x61, 0x61), truncated = true))
    }

    @Test
    fun lineLimitWarningDoesNotDependOnFinalNewline() {
        for (count in listOf(400, 401)) {
            for (newline in listOf("", "\n")) {
                val source = List(count) { "value" }.joinToString("\n") + newline
                val file = ArchiveDayFile("unused", "unused.md", "text/markdown", source, source.toByteArray().size.toLong())
                assertEquals(400, file.lines.size)
                assertEquals(count > 400, file.isTruncated)
            }
        }
    }
}

package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class ExportPreviewDisplayContentTest {

    @Test
    fun smallContent_isShownInFull() {
        val content = "# Health\n\n- Steps: 12,500"

        val display = ExportPreviewDisplayContent.make(content)

        assertThat(display.text).isEqualTo(content)
        assertThat(display.isTruncated).isFalse()
        assertThat(display.omittedByteCount).isEqualTo(0)
    }

    @Test
    fun largeContent_keepsHeadAndTailWithoutChangingOriginalSize() {
        val content = "HEAD" + "x".repeat(200) + "TAIL"

        val display = ExportPreviewDisplayContent.make(
            content = content,
            maximumRenderedBytes = 20,
            headBytes = 12,
            tailBytes = 8,
        )

        assertThat(display.isTruncated).isTrue()
        assertThat(display.text).startsWith("HEADxxxxxxxx")
        assertThat(display.tailText).endsWith("xxxxTAIL")
        assertThat(display.render("empty", "<localized marker>"))
            .isEqualTo(display.text + "<localized marker>" + display.tailText)
        assertThat(display.originalByteCount).isEqualTo(content.toByteArray(Charsets.UTF_8).size)
        assertThat(display.omittedByteCount).isEqualTo(188)
    }

    @Test
    fun truncation_preservesUtf8CodePointBoundaries() {
        val content = "start🙂🙂🙂🙂end"

        val display = ExportPreviewDisplayContent.make(
            content = content,
            maximumRenderedBytes = 10,
            headBytes = 7,
            tailBytes = 3,
        )

        assertThat(display.isTruncated).isTrue()
        assertThat(display.text).doesNotContain("�")
        assertThat(display.text).startsWith("start")
        assertThat(display.tailText).endsWith("end")
    }

    @Test
    fun emptyContent_usesReadablePlaceholder() {
        val display = ExportPreviewDisplayContent.make("")

        assertThat(display.text).isEmpty()
        assertThat(display.render("Localized empty file", "unused")).isEqualTo("Localized empty file")
        assertThat(display.originalByteCount).isEqualTo(0)
        assertThat(display.isTruncated).isFalse()
    }
}

package com.healthmd.presentation.export

/**
 * Bounds the text rendered by Compose without adding presentation copy. Compatibility previews
 * retain complete generated text in the model; raw snapshot previews arrive pre-bounded from
 * private storage. Localized empty/truncation text is injected only when [render] is called.
 */
internal data class ExportPreviewDisplayContent(
    val text: String,
    val tailText: String = "",
    val originalByteCount: Int,
    val omittedByteCount: Int,
) {
    val isEmpty: Boolean get() = originalByteCount == 0
    val isTruncated: Boolean get() = omittedByteCount > 0

    fun render(emptyFileLabel: String, truncationMarker: String): String = when {
        isEmpty -> emptyFileLabel
        isTruncated -> text + truncationMarker + tailText
        else -> text
    }

    companion object {
        const val DEFAULT_MAXIMUM_RENDERED_BYTES = 64 * 1024
        const val DEFAULT_HEAD_BYTES = 48 * 1024
        const val DEFAULT_TAIL_BYTES = 16 * 1024

        fun make(
            content: String,
            maximumRenderedBytes: Int = DEFAULT_MAXIMUM_RENDERED_BYTES,
            headBytes: Int = DEFAULT_HEAD_BYTES,
            tailBytes: Int = DEFAULT_TAIL_BYTES,
        ): ExportPreviewDisplayContent {
            val originalByteCount = content.utf8ByteCount()
            if (originalByteCount <= maximumRenderedBytes) {
                return ExportPreviewDisplayContent(
                    text = content,
                    originalByteCount = originalByteCount,
                    omittedByteCount = 0,
                )
            }

            val safeMaximumRenderedBytes = maximumRenderedBytes.coerceAtLeast(1)
            val safeHeadBytes = headBytes.coerceIn(0, safeMaximumRenderedBytes)
            val safeTailBytes = tailBytes.coerceIn(0, safeMaximumRenderedBytes - safeHeadBytes)
            val head = content.utf8Prefix(safeHeadBytes)
            val tail = content.utf8Suffix(safeTailBytes)
            val renderedByteCount = head.utf8ByteCount() + tail.utf8ByteCount()
            val omittedByteCount = (originalByteCount - renderedByteCount).coerceAtLeast(0)

            return ExportPreviewDisplayContent(
                text = head,
                tailText = tail,
                originalByteCount = originalByteCount,
                omittedByteCount = omittedByteCount,
            )
        }
    }
}

private fun String.utf8ByteCount(): Int = toByteArray(Charsets.UTF_8).size

private fun String.utf8Prefix(maxBytes: Int): String {
    if (maxBytes <= 0) return ""
    var index = 0
    var bytes = 0
    while (index < length) {
        val codePoint = codePointAt(index)
        val codePointBytes = codePoint.utf8ByteCount()
        if (bytes + codePointBytes > maxBytes) break
        bytes += codePointBytes
        index += Character.charCount(codePoint)
    }
    return substring(0, index)
}

private fun String.utf8Suffix(maxBytes: Int): String {
    if (maxBytes <= 0) return ""
    var index = length
    var bytes = 0
    while (index > 0) {
        val codePoint = codePointBefore(index)
        val codePointBytes = codePoint.utf8ByteCount()
        if (bytes + codePointBytes > maxBytes) break
        bytes += codePointBytes
        index -= Character.charCount(codePoint)
    }
    return substring(index)
}

private fun Int.utf8ByteCount(): Int = when {
    this <= 0x7F -> 1
    this <= 0x7FF -> 2
    this <= 0xFFFF -> 3
    else -> 4
}

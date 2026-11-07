package com.healthmd.presentation.export

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle

/** How the export preview reads a file, chosen from its extension. */
internal enum class PreviewSyntax {
    JSON, NDJSON, MARKDOWN, CSV, YAML, PLAIN;

    companion object {
        fun forPath(path: String): PreviewSyntax =
            when (path.substringAfterLast('/').substringAfterLast('.', "").lowercase()) {
                "json" -> JSON
                "ndjson", "jsonl" -> NDJSON
                "md", "markdown" -> MARKDOWN
                "csv" -> CSV
                "base", "yaml", "yml" -> YAML
                else -> PLAIN
            }
    }
}

/** Token colors, resolved from the theme by the caller so this stays testable without Compose. */
internal data class PreviewPalette(
    val key: Color,
    val string: Color,
    val literal: Color,
    val punctuation: Color,
    val heading: Color,
)

/**
 * Display-only formatting for the export preview. It never changes what is exported; the raw
 * view shows the exact bytes. Every formatter is lenient: the preview may be a truncated head
 * and tail of a file, so it must accept unbalanced or partial input without throwing.
 */
internal object ExportPreviewFormatter {
    private const val INDENT = "  "

    /** Above this many rows CSV is shown unaligned; aligning would cost more than it helps. */
    private const val CSV_ALIGN_MAX_ROWS = 2_000

    /** Columns pad to at most this width so one long cell doesn't push every row off screen. */
    private const val CSV_MAX_COLUMN_WIDTH = 32

    fun format(text: String, syntax: PreviewSyntax, palette: PreviewPalette): AnnotatedString =
        when (syntax) {
            PreviewSyntax.JSON -> json(text, palette, ndjson = false)
            PreviewSyntax.NDJSON -> json(text, palette, ndjson = true)
            PreviewSyntax.MARKDOWN -> markdown(text, palette)
            PreviewSyntax.CSV -> csv(text, palette)
            PreviewSyntax.YAML -> yaml(text, palette)
            PreviewSyntax.PLAIN -> AnnotatedString(text)
        }

    // JSON / NDJSON

    private fun json(text: String, palette: PreviewPalette, ndjson: Boolean): AnnotatedString = buildAnnotatedString {
        val punct = SpanStyle(color = palette.punctuation)
        var depth = 0
        var i = 0
        // The last two emitted characters, tracked here because reading the builder back is O(n).
        var last = ' '
        var beforeLast = ' '
        var empty = true
        fun emit(value: String, style: SpanStyle? = null) {
            if (value.isEmpty()) return
            if (style == null) append(value) else withStyle(style) { append(value) }
            beforeLast = if (value.length >= 2) value[value.length - 2] else last
            last = value[value.length - 1]
            empty = false
        }
        fun newline() = emit("\n" + INDENT.repeat(depth))
        fun nextNonSpace(from: Int): Int {
            var j = from
            while (j < text.length && text[j].isWhitespace()) j++
            return j
        }
        while (i < text.length) {
            val c = text[i]
            when {
                c == '\n' && ndjson && depth == 0 -> {
                    // NDJSON record boundary: a blank line between records.
                    if (!empty && !(last == '\n' && beforeLast == '\n')) emit(if (last == '\n') "\n" else "\n\n")
                    i++
                }
                c.isWhitespace() -> i++
                c == '"' -> {
                    val end = stringEnd(text, i)
                    val isKey = nextNonSpace(end).let { it < text.length && text[it] == ':' }
                    emit(text.substring(i, end), SpanStyle(color = if (isKey) palette.key else palette.string))
                    i = end
                }
                c == '{' || c == '[' -> {
                    val close = if (c == '{') '}' else ']'
                    val next = nextNonSpace(i + 1)
                    if (next < text.length && text[next] == close) {
                        emit("$c$close", punct)
                        i = next + 1
                    } else {
                        emit(c.toString(), punct)
                        depth++
                        newline()
                        i++
                    }
                }
                c == '}' || c == ']' -> {
                    depth = (depth - 1).coerceAtLeast(0)
                    if (!empty && last != '\n') newline()
                    emit(c.toString(), punct)
                    i++
                }
                c == ',' -> {
                    emit(",", punct)
                    newline()
                    i++
                }
                c == ':' -> {
                    emit(":", punct)
                    emit(" ")
                    i++
                }
                else -> {
                    var end = i
                    while (end < text.length && text[end] !in ",:{}[]\"" && !text[end].isWhitespace()) end++
                    emit(text.substring(i, end), SpanStyle(color = palette.literal))
                    i = end
                }
            }
        }
    }

    /** Index just past the closing quote of the string starting at [start], or the text end. */
    private fun stringEnd(text: String, start: Int): Int {
        var j = start + 1
        while (j < text.length) {
            when (text[j]) {
                '\\' -> j += 2
                '"' -> return j + 1
                else -> j++
            }
        }
        return text.length
    }

    // Markdown

    private val headingPattern = Regex("^(#{1,6})(\\s.*)?$")
    private val listPattern = Regex("^(\\s*)([-*+]|\\d+[.)])(\\s+)")
    private val wikiLinkPattern = Regex("\\[\\[[^\\]]+]]")

    private fun markdown(text: String, palette: PreviewPalette): AnnotatedString = buildAnnotatedString {
        val lines = text.split('\n')
        var inFrontmatter = lines.firstOrNull()?.trimEnd() == "---"
        lines.forEachIndexed { index, rawLine ->
            if (index > 0) append('\n')
            val line = rawLine.trimEnd('\r')
            when {
                line.trimEnd() == "---" -> {
                    withStyle(SpanStyle(color = palette.punctuation)) { append(line) }
                    if (index > 0) inFrontmatter = false
                }
                inFrontmatter -> yamlLine(line, palette)
                headingPattern.matches(line) -> withStyle(
                    SpanStyle(color = palette.heading, fontWeight = FontWeight.SemiBold),
                ) { append(line) }
                line.trimStart().startsWith("|") -> line.forEach { ch ->
                    if (ch == '|') withStyle(SpanStyle(color = palette.punctuation)) { append(ch) } else append(ch)
                }
                else -> {
                    val list = listPattern.find(line)
                    val rest = if (list != null) {
                        append(list.groupValues[1])
                        withStyle(SpanStyle(color = palette.key)) { append(list.groupValues[2]) }
                        append(list.groupValues[3])
                        line.substring(list.range.last + 1)
                    } else line
                    inline(rest, palette)
                }
            }
        }
    }

    private fun AnnotatedString.Builder.inline(text: String, palette: PreviewPalette) {
        var cursor = 0
        wikiLinkPattern.findAll(text).forEach { match ->
            append(text, cursor, match.range.first)
            withStyle(SpanStyle(color = palette.key)) { append(match.value) }
            cursor = match.range.last + 1
        }
        append(text, cursor, text.length)
    }

    // YAML (Obsidian Bases, frontmatter)

    private val yamlKeyPattern = Regex("^(\\s*)(- )?([^:#\"'\\s][^:#]*?)(:)(\\s|$)")

    private fun yaml(text: String, palette: PreviewPalette): AnnotatedString = buildAnnotatedString {
        text.split('\n').forEachIndexed { index, line ->
            if (index > 0) append('\n')
            yamlLine(line.trimEnd('\r'), palette)
        }
    }

    private fun AnnotatedString.Builder.yamlLine(line: String, palette: PreviewPalette) {
        if (line.trimStart().startsWith("#")) {
            withStyle(SpanStyle(color = palette.punctuation)) { append(line) }
            return
        }
        val match = yamlKeyPattern.find(line)
        if (match == null) {
            val dash = Regex("^(\\s*)(- )").find(line)
            if (dash != null) {
                append(dash.groupValues[1])
                withStyle(SpanStyle(color = palette.punctuation)) { append(dash.groupValues[2]) }
                yamlValue(line.substring(dash.range.last + 1), palette)
            } else {
                yamlValue(line, palette)
            }
            return
        }
        append(match.groupValues[1])
        if (match.groupValues[2].isNotEmpty()) withStyle(SpanStyle(color = palette.punctuation)) { append(match.groupValues[2]) }
        withStyle(SpanStyle(color = palette.key)) { append(match.groupValues[3]) }
        withStyle(SpanStyle(color = palette.punctuation)) { append(':') }
        yamlValue(line.substring(match.range.first + match.groupValues[1].length + match.groupValues[2].length +
            match.groupValues[3].length + 1), palette)
    }

    private fun AnnotatedString.Builder.yamlValue(value: String, palette: PreviewPalette) {
        val trimmed = value.trim()
        val color = when {
            trimmed.isEmpty() -> null
            trimmed.startsWith('"') || trimmed.startsWith('\'') -> palette.string
            trimmed == "true" || trimmed == "false" || trimmed == "null" || trimmed == "~" ||
                trimmed.toDoubleOrNull() != null -> palette.literal
            else -> null
        }
        if (color == null) append(value) else withStyle(SpanStyle(color = color)) { append(value) }
    }

    // CSV

    private fun csv(text: String, palette: PreviewPalette): AnnotatedString {
        val rows = parseCsv(text)
        if (rows.isEmpty() || rows.size > CSV_ALIGN_MAX_ROWS) return AnnotatedString(text)
        val columns = rows.maxOf { it.size }
        val widths = IntArray(columns)
        rows.forEach { row ->
            row.forEachIndexed { c, cell ->
                widths[c] = maxOf(widths[c], minOf(cell.codePointCount(0, cell.length), CSV_MAX_COLUMN_WIDTH))
            }
        }
        return buildAnnotatedString {
            rows.forEachIndexed { r, row ->
                if (r > 0) append('\n')
                val header = r == 0 && rows.size > 1
                row.forEachIndexed { c, cell ->
                    if (c > 0) withStyle(SpanStyle(color = palette.punctuation)) { append(" │ ") }
                    val padded = if (c == row.lastIndex) cell
                    else cell + " ".repeat((widths[c] - cell.codePointCount(0, cell.length)).coerceAtLeast(0))
                    if (header) {
                        withStyle(SpanStyle(color = palette.key, fontWeight = FontWeight.SemiBold)) { append(padded) }
                    } else {
                        append(padded)
                    }
                }
                if (header) {
                    append('\n')
                    withStyle(SpanStyle(color = palette.punctuation)) {
                        append(widths.joinToString("─┼─") { "─".repeat(it) })
                    }
                }
            }
        }
    }

    /** RFC 4180-style parse; unterminated quotes end at the text end. */
    internal fun parseCsv(text: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (quoted) {
                if (c == '"') {
                    if (i + 1 < text.length && text[i + 1] == '"') { cell.append('"'); i++ } else quoted = false
                } else cell.append(c)
            } else when (c) {
                '"' -> quoted = true
                ',' -> { row.add(cell.toString()); cell.clear() }
                '\r' -> Unit
                '\n' -> { row.add(cell.toString()); cell.clear(); rows.add(row); row = mutableListOf() }
                else -> cell.append(c)
            }
            i++
        }
        if (cell.isNotEmpty() || row.isNotEmpty()) { row.add(cell.toString()); rows.add(row) }
        return rows
    }
}

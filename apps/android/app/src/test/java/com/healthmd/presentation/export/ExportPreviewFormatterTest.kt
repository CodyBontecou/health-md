package com.healthmd.presentation.export

import androidx.compose.ui.graphics.Color
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class ExportPreviewFormatterTest {
    private val palette = PreviewPalette(
        key = Color(0xFF000001),
        string = Color(0xFF000002),
        literal = Color(0xFF000003),
        punctuation = Color(0xFF000004),
        heading = Color(0xFF000005),
    )

    private fun format(text: String, syntax: PreviewSyntax) = ExportPreviewFormatter.format(text, syntax, palette)

    @Test
    fun syntaxFollowsTheFileExtension() {
        assertThat(PreviewSyntax.forPath("health/raw/a.ndjson")).isEqualTo(PreviewSyntax.NDJSON)
        assertThat(PreviewSyntax.forPath("2026-11-06.JSON")).isEqualTo(PreviewSyntax.JSON)
        assertThat(PreviewSyntax.forPath("Daily/2026-11-06.md")).isEqualTo(PreviewSyntax.MARKDOWN)
        assertThat(PreviewSyntax.forPath("health.csv")).isEqualTo(PreviewSyntax.CSV)
        assertThat(PreviewSyntax.forPath("Health.base")).isEqualTo(PreviewSyntax.YAML)
        assertThat(PreviewSyntax.forPath("notes.txt")).isEqualTo(PreviewSyntax.PLAIN)
        assertThat(PreviewSyntax.forPath("no-extension")).isEqualTo(PreviewSyntax.PLAIN)
    }

    @Test
    fun jsonIsIndentedWithEmptyContainersKeptInline() {
        val out = format("""{"a":1,"b":[true,null],"c":{},"d":"x, y"}""", PreviewSyntax.JSON)
        assertThat(out.text).isEqualTo(
            """
            {
              "a": 1,
              "b": [
                true,
                null
              ],
              "c": {},
              "d": "x, y"
            }
            """.trimIndent()
        )
    }

    @Test
    fun jsonKeysStringsAndLiteralsTakeDistinctColors() {
        val out = format("""{"k":"v","n":2}""", PreviewSyntax.JSON)
        fun colorOf(token: String) = out.spanStyles.first { out.text.substring(it.start, it.end) == token }.item.color
        assertThat(colorOf("\"k\"")).isEqualTo(palette.key)
        assertThat(colorOf("\"v\"")).isEqualTo(palette.string)
        assertThat(colorOf("2")).isEqualTo(palette.literal)
    }

    @Test
    fun ndjsonRecordsAreSeparatedByABlankLine() {
        val out = format("{\"a\":1}\n{\"b\":2}\n", PreviewSyntax.NDJSON)
        assertThat(out.text).isEqualTo("{\n  \"a\": 1\n}\n\n{\n  \"b\": 2\n}\n\n")
    }

    @Test
    fun truncatedOrUnbalancedJsonNeverThrows() {
        format("""{"a":[1,2,{"b":"unterminated""", PreviewSyntax.JSON)
        format("""2]}},"tail":true}""", PreviewSyntax.NDJSON)
        format("\"\\", PreviewSyntax.JSON)
    }

    @Test
    fun escapedQuotesStayInsideStrings() {
        val out = format("""{"a":"say \"hi\", ok"}""", PreviewSyntax.JSON)
        assertThat(out.text).contains("\"say \\\"hi\\\", ok\"")
    }

    @Test
    fun markdownTextIsUnchangedAndOnlyStyled() {
        val md = "---\ndate: 2026-11-06\nsteps: 8000\n---\n# Health\n- Steps: 8000 [[Today]]\n| a | b |"
        val out = format(md, PreviewSyntax.MARKDOWN)
        assertThat(out.text).isEqualTo(md)
        val heading = out.spanStyles.first { out.text.substring(it.start, it.end) == "# Health" }
        assertThat(heading.item.color).isEqualTo(palette.heading)
        assertThat(out.spanStyles.any { out.text.substring(it.start, it.end) == "date" && it.item.color == palette.key }).isTrue()
        assertThat(out.spanStyles.any { out.text.substring(it.start, it.end) == "[[Today]]" }).isTrue()
    }

    @Test
    fun csvColumnsAlignUnderAHeaderRule() {
        val out = format("date,steps\n2026-11-06,8000\n\"a, b\",1\n", PreviewSyntax.CSV)
        val lines = out.text.lines()
        assertThat(lines[0]).isEqualTo("date       │ steps")
        assertThat(lines[1]).startsWith("──────────")
        assertThat(lines[2]).isEqualTo("2026-11-06 │ 8000")
        assertThat(lines[3]).isEqualTo("a, b       │ 1")
    }

    @Test
    fun csvParsingHonoursQuotesAndEscapedQuotes() {
        assertThat(ExportPreviewFormatter.parseCsv("a,\"b \"\"c\"\", d\"\r\n1,2"))
            .containsExactly(listOf("a", "b \"c\", d"), listOf("1", "2")).inOrder()
    }

    @Test
    fun yamlTextIsUnchangedAndKeysAreColored() {
        val yaml = "views:\n  - type: table\n    name: \"Health\"\n# comment"
        val out = format(yaml, PreviewSyntax.YAML)
        assertThat(out.text).isEqualTo(yaml)
        assertThat(out.spanStyles.any { out.text.substring(it.start, it.end) == "views" && it.item.color == palette.key }).isTrue()
        assertThat(out.spanStyles.any { out.text.substring(it.start, it.end) == "type" && it.item.color == palette.key }).isTrue()
    }
}

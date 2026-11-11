package com.healthmd.presentation.archive

import com.healthmd.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

class ArchiveDayTilesTest {
    private val note = """
        ---
        date: 2026-10-30
        type: health-data
        hrv_ms: 41.5
        active_calories: 612
        steps: 10432
        sleep_total_hours: 7.25
        resting_heart_rate: "54"
        tags:
          - health
        weight_kg: 71.2
        notes: slept well
        ---
        # Health
        steps: 99
    """.trimIndent()

    @Test
    fun `frontmatter scalars stop at the closing fence and skip nested lines`() {
        val fields = ArchiveDayTiles.frontmatterScalars(note)
        assertEquals("2026-10-30", fields.first { it.first == "date" }.second)
        assertEquals("54", fields.first { it.first == "resting_heart_rate" }.second)
        assertTrue(fields.none { it.first == "tags" || it.first.startsWith("-") })
        // Body lines after the closing fence are not frontmatter.
        assertEquals(1, fields.count { it.first == "steps" })
    }

    @Test
    fun `a file without frontmatter or a closing fence has no fields`() {
        assertTrue(ArchiveDayTiles.frontmatterScalars("# Health\nsteps: 1\n").isEmpty())
        assertTrue(ArchiveDayTiles.frontmatterScalars("---\nsteps: 1\n").isEmpty())
        assertTrue(ArchiveDayTiles.tiles("{\"steps\": 1}").isEmpty())
        assertTrue(ArchiveDayTiles.tiles("").isEmpty())
    }

    @Test
    fun `preferred metrics lead and other known numeric metrics follow in file order`() {
        val tiles = ArchiveDayTiles.tiles(note, locale = Locale.US)
        assertEquals(
            listOf("steps", "sleep_total_hours", "resting_heart_rate", "hrv_ms", "active_calories", "weight_kg"),
            tiles.map { it.key },
        )
        assertEquals("10,432", tiles[0].value)
        assertEquals(R.string.metric_name_steps, tiles[0].labelRes)
        assertEquals("", tiles[0].unit)
        assertEquals("7h 15m", tiles[1].value)
        assertEquals("54", tiles[2].value)
        assertEquals("bpm", tiles[2].unit)
        assertEquals("41.5", tiles[3].value)
        assertEquals("ms", tiles[3].unit)
        // Dates and text are never tiles.
        assertFalse(tiles.any { it.key == "date" || it.key == "notes" })
        assertEquals(2, ArchiveDayTiles.tiles(note, limit = 2).size)
    }

    @Test
    fun `camel and spaced keys map back to the snake case registry`() {
        assertEquals("resting_heart_rate", ArchiveDayTiles.canonicalKey("restingHeartRate"))
        assertEquals("resting_heart_rate", ArchiveDayTiles.canonicalKey("Resting Heart Rate"))
        assertEquals("sleep_total_hours", ArchiveDayTiles.canonicalKey("sleep_total_hours"))
        val tile = ArchiveDayTiles.tile("restingHeartRate", "52", Locale.US)
        assertEquals(R.string.metric_name_resting_hr, tile.labelRes)
        assertEquals("bpm", tile.unit)
        // Unknown keys keep their own name as the label.
        assertNull(ArchiveDayTiles.tile("custom_score", "3", Locale.US).labelRes)
    }

    @Test
    fun `day file lines drop the trailing newline and cap long files`() {
        val file = ArchiveDayFile("content://x", "a.md", "text/markdown", "a\r\nb\n", byteCount = 5)
        assertEquals(listOf("a", "b"), file.lines)
        assertFalse(file.isTruncated)
        val long = (1..500).joinToString("\n") { "line $it" }
        val big = file.copy(source = long, byteCount = long.length.toLong())
        assertEquals(ArchiveDayFile.MAXIMUM_LINES, big.lines.size)
        assertTrue(big.isTruncated)
        assertTrue(file.copy(byteCount = ArchiveDayFile.MAXIMUM_BYTES + 1L).isTruncated)
    }
}

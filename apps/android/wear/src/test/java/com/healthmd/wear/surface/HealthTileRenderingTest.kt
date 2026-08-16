package com.healthmd.wear.surface

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import com.google.common.truth.Truth.assertThat
import com.healthmd.wear.WearColors
import com.healthmd.wear.WearSpacing
import com.healthmd.wear.WearType
import com.healthmd.wear.sync.WearSnapshotRepository
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearHealthSnapshot
import java.time.Instant
import java.time.ZoneId
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class HealthTileRenderingTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @After fun cleanup() { runCatching { WearSnapshotRepository.clear(context) } }

    @Test fun `activity and recovery tiles render local current aggregates`() {
        val now = System.currentTimeMillis()
        val day = Instant.ofEpochMilli(now).atZone(ZoneId.of("UTC")).toLocalDate().toString()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = 1,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(
                localDate = day,
                steps = 8420,
                exerciseMinutes = 34.0,
                sleepMinutes = 450.0,
                hrvRmssdMillis = 46.0,
            )),
        ))

        val activity = textValues(buildTile(context, recovery = false, screenWidthDp = 192))
        val recovery = textValues(buildTile(context, recovery = true, screenWidthDp = 192))

        assertThat(activity.joinToString(" ")).contains("8,420")
        assertThat(activity.joinToString(" ")).contains("34")
        assertThat(recovery.joinToString(" ")).contains("7.5")
        assertThat(recovery.joinToString(" ")).contains("46")
    }

    @Test fun `recovery tile uses preceding overnight journal while activity stays today`() {
        val now = Instant.parse("2026-08-13T06:00:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(
                WearHealthDay("2026-08-12", sleepMinutes = 450.0, hrvRmssdMillis = 46.0),
                WearHealthDay("2026-08-13", steps = 8420, exerciseMinutes = 34.0),
            ),
        ))

        val activity = textValues(buildTile(context, recovery = false, screenWidthDp = 192, now = now)).joinToString(" ")
        val recovery = textValues(buildTile(context, recovery = true, screenWidthDp = 192, now = now)).joinToString(" ")

        assertThat(activity).contains("8,420")
        assertThat(activity).doesNotContain("7.5")
        assertThat(recovery).contains("7.5")
        assertThat(recovery).contains("46")
    }

    @Test fun `recovery tile hides two-day-old journal in a fresh snapshot`() {
        val now = Instant.parse("2026-08-13T06:00:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-11", sleepMinutes = 450.0, hrvRmssdMillis = 46.0)),
        ))

        val recovery = textValues(buildTile(context, recovery = true, screenWidthDp = 192, now = now)).joinToString(" ")
        assertThat(recovery).contains("No health data yet")
        assertThat(recovery).doesNotContain("7.5")
        assertThat(recovery).doesNotContain("46")
    }

    @Test fun `tile root exposes localized button semantics with value and freshness`() {
        val now = System.currentTimeMillis()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(localDate = localDate(now), steps = 8420, exerciseMinutes = 34.0)),
        ))

        val root = requireNotNull(requireNotNull(buildTile(context, false, 192, now).tileTimeline)
            .timelineEntries.first().layout).root as LayoutElementBuilders.Column
        val semantics = requireNotNull(requireNotNull(root.modifiers).semantics)
        assertThat(semantics.role).isEqualTo(androidx.wear.protolayout.ModifiersBuilders.SEMANTICS_ROLE_BUTTON)
        assertThat(requireNotNull(semantics.contentDescription).value).contains("Daily Activity")
        assertThat(requireNotNull(semantics.contentDescription).value).contains("8,420")
        assertThat(requireNotNull(semantics.contentDescription).value).contains("not real-time")
    }

    @Test fun `version mismatch tile hides measurements and does not claim phone sync`() {
        val now = System.currentTimeMillis()
        val day = Instant.ofEpochMilli(now).atZone(ZoneId.of("UTC")).toLocalDate().toString()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = 9,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(day, steps = 8420)),
        ))
        WearSnapshotRepository.recordVersionMismatch(context, sequence = 10L)

        val text = textValues(buildTile(context, recovery = false, screenWidthDp = 192)).joinToString(" ")
        assertThat(text).contains("Update Health.md")
        assertThat(text).doesNotContain("8,420")
        assertThat(text).doesNotContain("Last phone sync")
    }

    @Test fun `expired tile hides health measurements`() {
        val now = System.currentTimeMillis()
        val day = Instant.ofEpochMilli(now).atZone(ZoneId.of("UTC")).toLocalDate().toString()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = 2,
            capturedAtEpochMillis = now - WearHealthSnapshot.MAX_DISPLAY_MILLIS - 1,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(day, steps = 8420)),
        ))

        val text = textValues(buildTile(context, recovery = false, screenWidthDp = 192)).joinToString(" ")
        assertThat(text).contains("more than 24 hours old")
        assertThat(text).doesNotContain("8,420")
    }

    @Test fun `tile layout consumes the named renderer-neutral Wear tokens`() {
        val compact = tileRoot(screenWidthDp = 192)
        val large = tileRoot(screenWidthDp = 220)

        assertThat(requireNotNull(requireNotNull(requireNotNull(compact.modifiers).padding).start).value)
            .isEqualTo(WearSpacing.lgDp)
        assertThat(requireNotNull(requireNotNull(requireNotNull(large.modifiers).padding).start).value)
            .isEqualTo(WearSpacing.xlDp)

        val contents = compact.contents
        val title = contents[0] as LayoutElementBuilders.Text
        val firstSpacer = contents[1] as LayoutElementBuilders.Spacer
        val value = contents[2] as LayoutElementBuilders.Text
        val secondSpacer = contents[3] as LayoutElementBuilders.Spacer
        val footer = contents[4] as LayoutElementBuilders.Text

        assertThat(requireNotNull(requireNotNull(title.fontStyle).size).value).isEqualTo(WearType.titleSp)
        assertThat(requireNotNull(requireNotNull(title.fontStyle).color).argb).isEqualTo(WearColors.primaryArgb.toInt())
        assertThat(requireNotNull(requireNotNull(value.fontStyle).size).value).isEqualTo(WearType.bodySp)
        assertThat(requireNotNull(requireNotNull(value.fontStyle).color).argb).isEqualTo(WearColors.textArgb.toInt())
        assertThat(requireNotNull(requireNotNull(footer.fontStyle).size).value).isEqualTo(WearType.captionSp)
        assertThat(requireNotNull(requireNotNull(footer.fontStyle).color).argb).isEqualTo(WearColors.mutedArgb.toInt())
        assertThat((firstSpacer.height as DimensionBuilders.DpProp).value).isEqualTo(WearSpacing.smDp)
        assertThat((secondSpacer.height as DimensionBuilders.DpProp).value).isEqualTo(WearSpacing.smDp)
    }

    @Test fun `tile timeline replaces measurements at stale expiry and captured-zone midnight`() {
        val now = Instant.parse("2026-08-12T23:00:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = 3,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-12", steps = 8420)),
        ))

        val tile = buildTile(context, recovery = false, screenWidthDp = 192, now = now)
        val entries = requireNotNull(tile.tileTimeline).timelineEntries
        assertThat(entries.first().validity?.endMillis)
            .isEqualTo(Instant.parse("2026-08-13T00:00:00Z").toEpochMilli())
        assertThat(entries.any {
            it.validity?.startMillis == now + WearHealthSnapshot.CURRENT_MILLIS + 1L
        }).isTrue()
        val midnight = Instant.parse("2026-08-13T00:00:00Z").toEpochMilli()
        val midnightEntry = entries.first { it.validity?.startMillis == midnight }
        val midnightText = textValues(midnightEntry).joinToString(" ")
        assertThat(midnightText).contains("No health data yet")
        assertThat(midnightText).doesNotContain("8,420")

        val expiry = now + WearHealthSnapshot.MAX_DISPLAY_MILLIS + 1L
        val expiryEntry = entries.first { it.validity?.startMillis == expiry }
        val expiryText = textValues(expiryEntry).joinToString(" ")
        assertThat(expiryText).contains("more than 24 hours old")
        assertThat(expiryText).doesNotContain("8,420")
    }

    @Test fun `recovery tile keeps truthful hourly stale ages after midnight until expiry`() {
        val capturedAt = Instant.parse("2026-08-12T19:30:00Z").toEpochMilli()
        val now = Instant.parse("2026-08-12T23:45:00Z").toEpochMilli()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = 4,
            capturedAtEpochMillis = capturedAt,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-12", sleepMinutes = 450.0, hrvRmssdMillis = 46.0)),
        ))

        val entries = requireNotNull(buildTile(context, recovery = true, screenWidthDp = 192, now = now).tileTimeline)
            .timelineEntries
        val fiveHours = Instant.parse("2026-08-13T00:30:00.001Z").toEpochMilli()
        val sixHours = Instant.parse("2026-08-13T01:30:00.001Z").toEpochMilli()
        val fiveHourText = textValues(entries.first { it.validity?.startMillis == fiveHours }).joinToString(" ")
        val sixHourText = textValues(entries.first { it.validity?.startMillis == sixHours }).joinToString(" ")

        assertThat(fiveHourText).contains("5 hours ago")
        assertThat(fiveHourText).contains("7.5")
        assertThat(sixHourText).contains("6 hours ago")
        assertThat(sixHourText).contains("7.5")
    }

    private fun tileRoot(screenWidthDp: Int): LayoutElementBuilders.Column =
        requireNotNull(
            requireNotNull(buildTile(context, recovery = false, screenWidthDp = screenWidthDp).tileTimeline)
                .timelineEntries.first().layout,
        ).root as LayoutElementBuilders.Column

    private fun localDate(at: Long): String =
        Instant.ofEpochMilli(at).atZone(ZoneId.of("UTC")).toLocalDate().toString()

    private fun textValues(tile: androidx.wear.tiles.TileBuilders.Tile): List<String> =
        textValues(requireNotNull(tile.tileTimeline).timelineEntries.first())

    private fun textValues(entry: androidx.wear.protolayout.TimelineBuilders.TimelineEntry): List<String> {
        val root = requireNotNull(requireNotNull(entry.layout).root)
        val values = mutableListOf<String>()
        fun walk(element: LayoutElementBuilders.LayoutElement) {
            when (element) {
                is LayoutElementBuilders.Text -> values += requireNotNull(element.text).value
                is LayoutElementBuilders.Column -> element.contents.forEach(::walk)
                is LayoutElementBuilders.Row -> element.contents.forEach(::walk)
                is LayoutElementBuilders.Box -> element.contents.forEach(::walk)
            }
        }
        walk(requireNotNull(root))
        return values
    }
}

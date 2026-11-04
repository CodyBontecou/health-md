package com.healthmd.wear.surface

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import com.google.common.truth.Truth.assertThat
import com.healthmd.wear.WearColors
import com.healthmd.wear.WearSize
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
            .timelineEntries.first().layout).root as LayoutElementBuilders.Box
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
        putCurrentActivity()
        val compact = tileContent(screenWidthDp = 192)
        val large = tileContent(screenWidthDp = 220)

        assertThat(requireNotNull(requireNotNull(requireNotNull(compact.modifiers).padding).start).value)
            .isEqualTo(WearSpacing.lgDp)
        assertThat(requireNotNull(requireNotNull(requireNotNull(large.modifiers).padding).start).value)
            .isEqualTo(WearSpacing.xlDp)

        val contents = compact.contents
        val icon = contents[0] as LayoutElementBuilders.Image
        val title = contents[2] as LayoutElementBuilders.Text
        val value = contents[4] as LayoutElementBuilders.Text
        val footer = contents[6] as LayoutElementBuilders.Text
        listOf(1, 3, 5).forEach { index ->
            val spacer = contents[index] as LayoutElementBuilders.Spacer
            assertThat((spacer.height as DimensionBuilders.DpProp).value).isEqualTo(WearSpacing.smDp)
        }

        assertThat(requireNotNull(icon.resourceId).value).isEqualTo(Metric.ACTIVITY.tileIconId)
        assertThat(requireNotNull(requireNotNull(icon.colorFilter).tint).argb).isEqualTo(WearColors.metricStepsArgb.toInt())
        assertThat((icon.width as DimensionBuilders.DpProp).value).isEqualTo(WearSize.iconDp)
        assertThat(requireNotNull(requireNotNull(title.fontStyle).size).value).isEqualTo(WearType.titleSp)
        assertThat(requireNotNull(requireNotNull(title.fontStyle).color).argb).isEqualTo(WearColors.primaryArgb.toInt())
        // A displayable measurement uses the display size; status copy stays at body size.
        assertThat(requireNotNull(requireNotNull(value.fontStyle).size).value).isEqualTo(WearType.displaySp)
        assertThat(requireNotNull(requireNotNull(value.fontStyle).color).argb).isEqualTo(WearColors.textArgb.toInt())
        assertThat(requireNotNull(requireNotNull(footer.fontStyle).size).value).isEqualTo(WearType.captionSp)
        assertThat(requireNotNull(requireNotNull(footer.fontStyle).color).argb).isEqualTo(WearColors.mutedArgb.toInt())
    }

    @Test fun `daily activity draws a step progress ring only beside a real step count`() {
        val now = System.currentTimeMillis()
        putCurrentActivity(now, steps = 5_000)
        val arcs = tileRootBox(recovery = false, now = now).contents.filterIsInstance<LayoutElementBuilders.Arc>()
        assertThat(arcs).hasSize(2)
        val track = arcs[0].contents.single() as LayoutElementBuilders.ArcLine
        val progress = arcs[1].contents.single() as LayoutElementBuilders.ArcLine
        assertThat(requireNotNull(track.length).value).isEqualTo(360f)
        assertThat(requireNotNull(track.color).argb).isEqualTo(WearColors.surfaceArgb.toInt())
        assertThat(requireNotNull(progress.length).value).isEqualTo(180f)
        assertThat(requireNotNull(progress.color).argb).isEqualTo(WearColors.metricStepsArgb.toInt())
        assertThat(requireNotNull(progress.thickness).value).isEqualTo(WearSize.progressStrokeDp)

        // Recovery has no goal ring, and Daily Activity without steps does not imply zero progress.
        assertThat(tileRootBox(recovery = true, now = now).contents.filterIsInstance<LayoutElementBuilders.Arc>()).isEmpty()
        WearSnapshotRepository.clear(context)
        putCurrentActivity(now, steps = null)
        assertThat(tileRootBox(recovery = false, now = now).contents.filterIsInstance<LayoutElementBuilders.Arc>()).isEmpty()
    }

    @Test fun `progress ring clamps above-goal steps`() {
        val lines = progressRing(2.5f).map { (it as LayoutElementBuilders.Arc).contents.single() as LayoutElementBuilders.ArcLine }
        assertThat(requireNotNull(lines.last().length).value).isEqualTo(360f)
        assertThat(progressRing(0f)).hasSize(1)
    }

    @Test fun `stale tile footer states data age in the warning role`() {
        val now = System.currentTimeMillis()
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now - 3 * 3_600_000L - WearHealthSnapshot.CURRENT_MILLIS,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(localDate(now), sleepMinutes = 450.0, hrvRmssdMillis = 46.0)),
        ))
        val content = tileRootBox(recovery = true, now = now).contents.last() as LayoutElementBuilders.Column
        val footer = content.contents.last() as LayoutElementBuilders.Text
        assertThat(requireNotNull(footer.text).value).contains("ago")
        assertThat(requireNotNull(requireNotNull(footer.fontStyle).color).argb).isEqualTo(WearColors.warningArgb.toInt())
        val icon = content.contents.first() as LayoutElementBuilders.Image
        assertThat(requireNotNull(icon.resourceId).value).isEqualTo(Metric.RECOVERY.tileIconId)
    }

    @Test fun `setup tile shows the phone badge and body-size guidance without values`() {
        val content = tileRootBox(recovery = false, now = System.currentTimeMillis()).contents.single() as LayoutElementBuilders.Column
        val badge = content.contents.first() as LayoutElementBuilders.Box
        val background = requireNotNull(requireNotNull(badge.modifiers).background)
        assertThat(requireNotNull(background.color).argb).isEqualTo(WearColors.primaryContainerArgb.toInt())
        val glyph = badge.contents.single() as LayoutElementBuilders.Image
        assertThat(requireNotNull(glyph.resourceId).value).isEqualTo(TILE_ICON_PHONE)
        val message = content.contents[4] as LayoutElementBuilders.Text
        assertThat(requireNotNull(message.text).value).contains("finish setup")
        assertThat(requireNotNull(requireNotNull(message.fontStyle).size).value).isEqualTo(WearType.bodySp)
    }

    @Test fun `tile resources map every referenced image id`() {
        val resources = tileResources()
        assertThat(resources.version).isEqualTo(TILE_RESOURCES_VERSION)
        assertThat(resources.idToImageMapping.keys)
            .containsExactlyElementsIn(Metric.entries.map { it.tileIconId } + TILE_ICON_PHONE)
        val tile = buildTile(context, recovery = false, screenWidthDp = 192)
        assertThat(tile.resourcesVersion).isEqualTo(TILE_RESOURCES_VERSION)
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

    private fun putCurrentActivity(now: Long = System.currentTimeMillis(), steps: Int? = 8420) {
        WearSnapshotRepository.apply(context, WearHealthSnapshot(
            sequence = now,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(localDate(now), steps = steps, exerciseMinutes = 34.0, sleepMinutes = 450.0)),
        ))
    }

    private fun tileRootBox(recovery: Boolean, now: Long, screenWidthDp: Int = 192): LayoutElementBuilders.Box =
        requireNotNull(
            requireNotNull(buildTile(context, recovery = recovery, screenWidthDp = screenWidthDp, now = now).tileTimeline)
                .timelineEntries.first().layout,
        ).root as LayoutElementBuilders.Box

    private fun tileContent(screenWidthDp: Int): LayoutElementBuilders.Column =
        tileRootBox(recovery = false, now = System.currentTimeMillis(), screenWidthDp = screenWidthDp)
            .contents.last() as LayoutElementBuilders.Column

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

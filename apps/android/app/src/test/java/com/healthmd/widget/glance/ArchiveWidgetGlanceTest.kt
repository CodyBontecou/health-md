package com.healthmd.widget.glance

import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.assertHasStartActivityClickAction
import androidx.glance.testing.unit.hasTestTag
import androidx.glance.testing.unit.hasText
import androidx.glance.testing.unit.hasTextEqualTo
import androidx.test.core.app.ApplicationProvider
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.presentation.MainActivity
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.seconds

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ArchiveWidgetGlanceTest {
    private val zoneId = ZoneId.of("UTC")
    private val today = LocalDate.of(2026, 10, 31)
    private val now = Instant.parse("2026-10-31T06:00:00Z")
    private val nextRun = Instant.parse("2026-10-31T07:30:00Z").toEpochMilli()
    private val summary = ArchiveWidgetSummary.from(
        entries = listOf(
            ExportHistoryEntry(
                timestamp = 1,
                source = ExportSource.SCHEDULED,
                dateRangeStart = LocalDate.of(2026, 10, 1),
                dateRangeEnd = LocalDate.of(2026, 10, 30),
                successCount = 28,
                totalCount = 30,
                failedDateDetails = listOf(
                    FailedDateDetail(LocalDate.of(2026, 10, 19), ExportFailureReason.FILE_WRITE_ERROR),
                    FailedDateDetail(LocalDate.of(2026, 10, 20), ExportFailureReason.FILE_WRITE_ERROR),
                ),
            ),
        ),
        today = today,
        nextRunAtMillis = nextRun,
    )

    @Test
    fun `small archive renders the month count gaps and next run and opens the app`() =
        runGlanceAppWidgetUnitTest(timeout = 10.seconds) {
            setContext(ApplicationProvider.getApplicationContext())
            setAppWidgetSize(ArchiveWidgetSizes.Small)
            provideComposable { ArchiveWidgetContent(summary, ArchiveWidgetSizes.Small, now, zoneId) }

            onNode(hasTextEqualTo("28")).assertExists()
            onNode(hasTextEqualTo("days in October")).assertExists()
            onNode(hasTextEqualTo("2 gaps")).assertExists()
            onNode(hasText("7:30")).assertExists()
            onNode(hasText("Next")).assertDoesNotExist()
            onNode(hasTestTag("archive-export-now")).assertDoesNotExist()
            onNode(hasTestTag("archive-widget-root")).assertHasStartActivityClickAction<MainActivity>()
        }

    @Test
    fun `wide archive renders the month count next run and an Export now action`() =
        runGlanceAppWidgetUnitTest(timeout = 10.seconds) {
            setContext(ApplicationProvider.getApplicationContext())
            setAppWidgetSize(ArchiveWidgetSizes.Wide)
            provideComposable { ArchiveWidgetContent(summary, ArchiveWidgetSizes.Wide, now, zoneId) }

            // The hero count and the strip label for October 28.
            onAllNodes(hasTextEqualTo("28")).assertCountEquals(2)
            onNode(hasTextEqualTo("days in October")).assertExists()
            onNode(hasTextEqualTo("2 gaps")).assertExists()
            onNode(hasText("Next 7:30")).assertExists()
            // The strip labels the last fourteen dates, ending today.
            onNode(hasTextEqualTo("18")).assertExists()
            onNode(hasTextEqualTo("31")).assertExists()
            onNode(hasTestTag("archive-export-now"))
                .assertHasStartActivityClickAction<MainActivity>(ArchiveExportNowParameters)
        }

    @Test
    fun `no history shows the empty state and keeps Export now on the wide widget`() =
        runGlanceAppWidgetUnitTest(timeout = 10.seconds) {
            setContext(ApplicationProvider.getApplicationContext())
            setAppWidgetSize(ArchiveWidgetSizes.Wide)
            val empty = ArchiveWidgetSummary.from(emptyList(), today)
            provideComposable { ArchiveWidgetContent(empty, ArchiveWidgetSizes.Wide, now, zoneId) }

            onNode(hasText("Your archive starts here")).assertExists()
            onNode(hasTextEqualTo("days in October")).assertDoesNotExist()
            onNode(hasText("Next")).assertDoesNotExist()
            onNode(hasTestTag("archive-export-now")).assertExists()
        }

    @Test
    fun `a run on a later day carries its weekday`() =
        runGlanceAppWidgetUnitTest(timeout = 10.seconds) {
            setContext(ApplicationProvider.getApplicationContext())
            setAppWidgetSize(ArchiveWidgetSizes.Small)
            val tomorrow = summary.copy(nextRunAtMillis = Instant.parse("2026-11-01T07:30:00Z").toEpochMilli())
            provideComposable { ArchiveWidgetContent(tomorrow, ArchiveWidgetSizes.Small, now, zoneId) }

            onNode(hasText("Sun")).assertExists()
        }
}

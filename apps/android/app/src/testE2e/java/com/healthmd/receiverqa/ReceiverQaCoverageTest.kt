package com.healthmd.receiverqa

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import java.time.Instant
import java.time.LocalDate
import org.junit.Test

class ReceiverQaCoverageTest {
    @Test
    fun partialAnswerRequiresTwoActualDefaultProductionBatches() {
        val candidates = List(30) { LocalDate.of(2026, 3, 1).plusDays(it.toLong()) }
        val completed = ReceiverQaCoverage.completedDates(candidates, "holes")
        val selected = candidates.filterNot { it in completed }
        val batches = APIExportEnvelopeBuilder(JsonExporter()).buildBatches(
            requestedDates = selected,
            records = selected.map { HealthData(it, activity = ActivityData(steps = 170)) },
            failedDateDetails = emptyList(),
            settings = ExportSettings(),
            exportedAt = Instant.parse("2026-04-01T12:00:00Z"),
            calendarTimeZone = "UTC",
        )
        assertThat(selected).containsExactlyElementsIn(candidates.take(10)).inOrder()
        assertThat(batches).hasSize(2)
        val firstAck = batches.first().requestedDates
        val residual = selected.filterNot { it in firstAck }
        assertThat(firstAck).containsExactlyElementsIn(selected.take(7)).inOrder()
        assertThat(residual).containsExactlyElementsIn(selected.takeLast(3)).inOrder()
        assertThat(batches.last().requestedDates).containsExactlyElementsIn(residual).inOrder()
    }

    @Test
    fun emptyAndShortWindowsNeverInventDates() {
        val dates = List(3) { LocalDate.of(2026, 3, 1).plusDays(it.toLong()) }
        assertThat(ReceiverQaCoverage.completedDates(dates, "all")).containsExactlyElementsIn(dates).inOrder()
        assertThat(ReceiverQaCoverage.completedDates(dates, "holes")).isEmpty()
        assertThat(ReceiverQaCoverage.completedDates(emptyList(), "holes")).isEmpty()
        assertThat(ReceiverQaCoverage.completedDates(dates, "one_hole")).containsExactly(dates[0], dates[2]).inOrder()
    }
}

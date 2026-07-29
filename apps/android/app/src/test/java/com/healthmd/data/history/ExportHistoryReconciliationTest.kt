package com.healthmd.data.history

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import java.time.LocalDate
import org.junit.Test

class ExportHistoryReconciliationTest {
    @Test
    fun durableReconciliationKeySurvivesRoomMapping() {
        val entry = ExportHistoryEntry(
            timestamp = 1_000L,
            source = ExportSource.SCHEDULED,
            dateRangeStart = LocalDate.of(2026, 7, 24),
            dateRangeEnd = LocalDate.of(2026, 7, 25),
            successCount = 2,
            totalCount = 2,
            reconciliationKey = "scheduled-11111111-2222-3333-4444-555555555555",
        )

        val entity = ExportHistoryEntity.fromDomain(entry)

        assertThat(entity.reconciliationKey).isEqualTo(entry.reconciliationKey)
        assertThat(entity.toDomain().reconciliationKey).isEqualTo(entry.reconciliationKey)
    }
}

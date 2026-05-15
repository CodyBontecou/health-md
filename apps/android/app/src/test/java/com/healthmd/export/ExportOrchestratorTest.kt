package com.healthmd.export

import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class ExportOrchestratorTest {

    @Test
    fun recordsHealthConnectRateLimitAsActionableFailureReason() = runTest {
        val firstDate = LocalDate.of(2026, 4, 1)
        val rateLimitedDate = LocalDate.of(2026, 4, 2)
        val healthRepository = object : HealthRepository {
            override suspend fun fetchHealthData(date: LocalDate): HealthData {
                if (date == rateLimitedDate) {
                    throw IllegalStateException("Health Connect rate limit exceeded")
                }
                return HealthData(date = date, activity = ActivityData(steps = 100))
            }

            override suspend fun isAvailable(): Boolean = true
            override suspend fun hasPermissions(): Boolean = true
            override suspend fun hasHistoricalReadPermission(): Boolean = true
            override suspend fun hasBackgroundReadPermission(): Boolean = true
            override suspend fun getEarliestDataDate(): LocalDate? = firstDate
            override fun isBeforeFirstUnlock(): Boolean = false
        }
        val exportRepository = object : ExportRepository {
            override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean = true
            override suspend fun hasExportFolder(): Boolean = true
            override fun getExportFolderName(): String = "Health"
        }

        val result = ExportOrchestrator(healthRepository, exportRepository).exportDates(
            dates = listOf(firstDate, rateLimitedDate),
            settings = ExportSettings(),
        )

        assertEquals(0, result.successCount)
        assertEquals(2, result.totalCount)
        assertEquals(2, result.failedDateDetails.size)
        assertEquals(firstDate, result.failedDateDetails.first().date)
        assertEquals(rateLimitedDate, result.failedDateDetails.last().date)
        assertEquals(ExportFailureReason.RATE_LIMITED, result.failedDateDetails.first().reason)
        assertEquals(ExportFailureReason.RATE_LIMITED, result.failedDateDetails.last().reason)
    }

    @Test
    fun recordsHistoricalAccessSecurityExceptionAsAccessDenied() = runTest {
        val date = LocalDate.of(2026, 4, 3)
        val healthRepository = object : HealthRepository {
            override suspend fun fetchHealthData(date: LocalDate): HealthData {
                throw SecurityException("Historical data access permission is required")
            }

            override suspend fun isAvailable(): Boolean = true
            override suspend fun hasPermissions(): Boolean = true
            override suspend fun hasHistoricalReadPermission(): Boolean = true
            override suspend fun hasBackgroundReadPermission(): Boolean = true
            override suspend fun getEarliestDataDate(): LocalDate? = date
            override fun isBeforeFirstUnlock(): Boolean = false
        }
        val exportRepository = object : ExportRepository {
            override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean = true
            override suspend fun hasExportFolder(): Boolean = true
            override fun getExportFolderName(): String = "Health"
        }

        val result = ExportOrchestrator(healthRepository, exportRepository).exportDates(
            dates = listOf(date),
            settings = ExportSettings(),
        )

        assertEquals(0, result.successCount)
        assertEquals(1, result.totalCount)
        assertEquals(ExportFailureReason.ACCESS_DENIED, result.failedDateDetails.single().reason)
    }
}

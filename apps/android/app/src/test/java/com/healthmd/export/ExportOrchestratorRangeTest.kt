package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone
import kotlin.time.Duration.Companion.hours

class ExportOrchestratorRangeTest {

    @Test
    fun `ninety day export uses bounded range fetches instead of per day fetches`() = runTest {
        val dates = ninetyDays()
        val healthRepository = FakeHealthRepository(
            rangeData = dates.associateWith { dataFor(it) },
        )
        val exportRepository = RecordingExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, ExportSettings(exportFormat = ExportFormat.JSON))

        assertThat(result.successCount).isEqualTo(90)
        assertThat(result.failedDateDetails).isEmpty()
        assertThat(healthRepository.singleDayCalls).isEqualTo(0)
        assertThat(healthRepository.rangeCalls).isEqualTo(3)
        assertThat(healthRepository.rangeCallSizes).containsExactly(30, 30, 30).inOrder()
        assertThat(exportRepository.exported.map { it.date }).containsExactlyElementsIn(dates).inOrder()
    }

    @Test
    fun `rate limit during a range export marks current and remaining dates as rate limited`() = runTest {
        val dates = ninetyDays()
        val healthRepository = FakeHealthRepository(
            rangeData = dates.take(30).associateWith { dataFor(it) },
            rateLimitOnRangeCall = 2,
        )
        val exportRepository = RecordingExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, ExportSettings(exportFormat = ExportFormat.JSON))

        assertThat(result.successCount).isEqualTo(30)
        assertThat(healthRepository.rangeCalls).isEqualTo(2)
        assertThat(healthRepository.singleDayCalls).isEqualTo(0)
        assertThat(exportRepository.exported.map { it.date }).containsExactlyElementsIn(dates.take(30)).inOrder()
        assertThat(result.failedDateDetails).hasSize(60)
        assertThat(result.failedDateDetails.map { it.date }).containsExactlyElementsIn(dates.drop(30)).inOrder()
        assertThat(result.failedDateDetails.map { it.reason }.distinct())
            .containsExactly(ExportFailureReason.RATE_LIMITED)
    }

    @Test
    fun `single day export uses the same range fetch path as preview`() = runTest {
        val date = LocalDate.of(2026, 3, 15)
        val healthRepository = FakeHealthRepository(
            rangeData = mapOf(date to dataFor(date)),
        )
        val exportRepository = RecordingExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
        val settings = ExportSettings(
            exportFormat = ExportFormat.JSON,
            exportFormats = setOf(ExportFormat.JSON),
            includeGranularData = true,
        )

        val result = orchestrator.exportDates(listOf(date), settings)

        assertThat(result.successCount).isEqualTo(1)
        assertThat(healthRepository.singleDayCalls).isEqualTo(0)
        assertThat(healthRepository.rangeCalls).isEqualTo(1)
        assertThat(healthRepository.rangeCallSizes).containsExactly(1)
        assertThat(healthRepository.rangeIncludeGranularFlags).containsExactly(true)
        assertThat(exportRepository.exported.single().date).isEqualTo(date)
    }

    @Test
    fun `preview renders the five most recent days with data`() = runTest {
        val dates = (0 until 10).map { LocalDate.of(2026, 3, 1).plusDays(it.toLong()) }
        val healthRepository = FakeHealthRepository(
            rangeData = dates.associateWith { dataFor(it) },
        )
        val exportRepository = RecordingExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val preview = orchestrator.previewDates(
            dates = dates,
            settings = ExportSettings(exportFormat = ExportFormat.JSON),
        )

        assertThat(preview.requestedDateCount).isEqualTo(10)
        assertThat(preview.previewedDateCount).isEqualTo(5)
        assertThat(preview.isTruncated).isTrue()
        assertThat(exportRepository.previewed.map { it.date })
            .containsExactlyElementsIn(dates.takeLast(5).reversed())
            .inOrder()
    }

    @Test
    fun `preview skips empty recent dates while finding useful files`() = runTest {
        val dates = (0 until 8).map { LocalDate.of(2026, 3, 1).plusDays(it.toLong()) }
        val healthRepository = FakeHealthRepository(
            rangeData = dates.associateWith { dataFor(it) },
            emptyRangeDates = dates.takeLast(3).toSet(),
        )
        val exportRepository = RecordingExportRepository()

        val preview = ExportOrchestrator(healthRepository, exportRepository).previewDates(
            dates = dates,
            settings = ExportSettings(exportFormat = ExportFormat.JSON),
        )

        assertThat(preview.previewedDateCount).isEqualTo(5)
        assertThat(preview.isTruncated).isFalse()
        assertThat(healthRepository.rangeCalls).isEqualTo(8)
        assertThat(exportRepository.previewed.map { it.date })
            .containsExactlyElementsIn(dates.take(5).reversed())
            .inOrder()
    }

    @Test
    fun `range export filters data selection before writing files`() = runTest {
        val dates = listOf(LocalDate.of(2026, 3, 15), LocalDate.of(2026, 3, 16))
        val healthRepository = FakeHealthRepository(
            rangeData = dates.associateWith {
                HealthData(
                    date = it,
                    sleep = SleepData(totalDuration = 8.hours),
                    activity = ActivityData(steps = 10_000),
                )
            },
        )
        val exportRepository = RecordingExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(
            dates = dates,
            settings = ExportSettings(
                exportFormat = ExportFormat.JSON,
                dataTypes = DataTypeSelection().copy(sleep = false),
            ),
        )

        assertThat(result.successCount).isEqualTo(2)
        assertThat(exportRepository.exported).hasSize(2)
        assertThat(exportRepository.exported.all { it.sleep.hasData }).isFalse()
        assertThat(exportRepository.exported.all { it.activity.steps == 10_000 }).isTrue()
    }

    @Test
    fun `manual folder operation pins context across chunks and cannot duplicate adjacent morning owner`() = runTest {
        val previousZone = TimeZone.getDefault()
        val capturedZone = ZoneId.of("America/Los_Angeles")
        val changedZone = ZoneId.of("Europe/Berlin")
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(capturedZone))
            val wakeDate = LocalDate.of(2026, 5, 31)
            val dates = (0 until 31).map { wakeDate.minusDays(it.toLong()) }
            val sessionStartDate = dates.last()
            val sessionWakeDate = dates[dates.lastIndex - 1]
            var storedAttribution = SleepDayAttribution.MORNING_ENDS
            val observedContexts = mutableListOf<Pair<ZoneId, SleepDayAttribution>>()
            val manager = mockk<HealthConnectManager>()
            val provider = HealthConnectDataProvider(manager)
            val registry = mockk<HealthProviderRegistry>()
            val settingsRepository = mockk<SettingsRepository>()
            coEvery { settingsRepository.getSelectedHealthProviderId() } returns "health_connect"
            coEvery { settingsRepository.getSleepDayAttribution() } answers { storedAttribution }
            every { registry.providerFor("health_connect") } returns provider
            every { registry.primaryExportProvider() } returns provider
            every { manager.isBeforeFirstUnlock() } returns false
            coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
                val requested = firstArg<List<LocalDate>>()
                val zone = arg<ZoneId>(3)
                val attribution = arg<SleepDayAttribution>(5)
                observedContexts += zone to attribution
                val owner = if (attribution == SleepDayAttribution.MORNING_ENDS) sessionWakeDate else sessionStartDate
                if (observedContexts.size == 1) {
                    storedAttribution = SleepDayAttribution.NIGHT_BEGINS
                    TimeZone.setDefault(TimeZone.getTimeZone(changedZone))
                }
                requested.map { date ->
                    HealthData(
                        date = date,
                        activity = ActivityData(steps = 1),
                        sleep = if (date == owner) SleepData(totalDuration = 8.hours) else SleepData(),
                    )
                }
            }
            val exportRepository = RecordingExportRepository()

            val result = ExportOrchestrator(
                HealthRepositoryImpl(registry, settingsRepository),
                exportRepository,
            ).exportDates(dates, ExportSettings(exportFormat = ExportFormat.JSON))

            assertThat(result.successCount).isEqualTo(31)
            assertThat(observedContexts).containsExactly(
                capturedZone to SleepDayAttribution.MORNING_ENDS,
                capturedZone to SleepDayAttribution.MORNING_ENDS,
            ).inOrder()
            assertThat(exportRepository.exported.count { it.sleep.hasData }).isEqualTo(1)
            assertThat(exportRepository.exported.single { it.sleep.hasData }.date).isEqualTo(sessionWakeDate)
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test
    fun `empty authoritative range is not retried through stale single day semantics`() = runTest {
        val dates = listOf(LocalDate.of(2026, 5, 4), LocalDate.of(2026, 5, 5))
        val healthRepository = FakeHealthRepository(
            singleDayData = dates.associateWith { dataFor(it) },
            rangeReturnsEmptyData = true,
        )
        val result = ExportOrchestrator(healthRepository, RecordingExportRepository())
            .exportDates(dates, ExportSettings(exportFormat = ExportFormat.JSON))

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.map { it.reason })
            .containsExactly(ExportFailureReason.NO_HEALTH_DATA, ExportFailureReason.NO_HEALTH_DATA)
        assertThat(healthRepository.rangeCalls).isEqualTo(1)
        assertThat(healthRepository.singleDayCalls).isEqualTo(0)
    }

    private fun ninetyDays(): List<LocalDate> {
        val start = LocalDate.of(2026, 1, 1)
        return (0 until 90).map { start.plusDays(it.toLong()) }
    }

    private fun dataFor(date: LocalDate): HealthData =
        HealthData(date = date, activity = ActivityData(steps = 1_000 + date.dayOfYear))

    private class FakeHealthRepository(
        private val singleDayData: Map<LocalDate, HealthData> = emptyMap(),
        private val rangeData: Map<LocalDate, HealthData> = emptyMap(),
        private val rateLimitOnRangeCall: Int? = null,
        private val rangeReturnsEmptyData: Boolean = false,
        private val emptyRangeDates: Set<LocalDate> = emptySet(),
    ) : HealthRepository {
        var singleDayCalls = 0
            private set
        var rangeCalls = 0
            private set
        val rangeCallSizes = mutableListOf<Int>()
        val rangeIncludeGranularFlags = mutableListOf<Boolean>()

        override suspend fun resolveCaptureContext(
            zoneId: ZoneId,
            sleepDayAttributionOverride: SleepDayAttributionOverride,
        ) = AndroidCaptureContext(
            zoneId,
            (sleepDayAttributionOverride as? SleepDayAttributionOverride.Value)?.attribution
                ?: SleepDayAttribution.DEFAULT,
        )

        override suspend fun fetchHealthData(date: LocalDate): HealthData {
            singleDayCalls++
            return singleDayData[date] ?: rangeData[date] ?: HealthData(
                date = date,
                activity = ActivityData(steps = 1_000 + date.dayOfYear),
            )
        }

        override suspend fun fetchHealthDataRange(
            dates: List<LocalDate>,
            dataTypes: DataTypeSelection,
            includeGranularData: Boolean,
            zoneId: ZoneId,
            pinnedCalendarDays: Boolean,
            sleepDayAttributionOverride: SleepDayAttributionOverride,
        ): List<HealthData> {
            rangeCalls++
            rangeCallSizes += dates.size
            rangeIncludeGranularFlags += includeGranularData
            if (rateLimitOnRangeCall == rangeCalls) {
                throw RuntimeException("Health Connect rate limit exceeded")
            }
            if (rangeReturnsEmptyData) {
                return dates.map { date -> HealthData(date).filtered(dataTypes) }
            }
            return dates.map { date ->
                if (date in emptyRangeDates) {
                    HealthData(date)
                } else {
                    (rangeData[date] ?: HealthData(
                        date = date,
                        activity = ActivityData(steps = 1_000 + date.dayOfYear),
                    )).filtered(dataTypes)
                }
            }
        }

        override suspend fun isAvailable(): Boolean = true
        override suspend fun hasPermissions(): Boolean = true
        override suspend fun hasHistoricalReadPermission(): Boolean = true
        override suspend fun hasBackgroundReadPermission(): Boolean = true
        override suspend fun getEarliestDataDate(): LocalDate? = null
        override fun isBeforeFirstUnlock(): Boolean = false
    }

    private class RecordingExportRepository : ExportRepository {
        val exported = mutableListOf<HealthData>()
        val previewed = mutableListOf<HealthData>()

        override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean {
            exported += data
            return true
        }

        override suspend fun previewHealthData(data: HealthData, settings: ExportSettings): ExportPreviewDay {
            previewed += data
            val content = "preview-${data.date}"
            return ExportPreviewDay(
                date = data.date,
                files = listOf(
                    ExportPreviewFile(
                        format = ExportFormat.JSON,
                        relativePath = "${data.date}.json",
                        byteCount = content.toByteArray(Charsets.UTF_8).size,
                        content = content,
                    )
                ),
            )
        }

        override suspend fun hasExportFolder(): Boolean = true
        override fun getExportFolderName(): String = "test"
    }
}

package com.healthmd.clinicianreport

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.ClinicianReportDateProvider
import com.healthmd.data.clinicianreport.ClinicianReportSourceLabelResolver
import com.healthmd.data.clinicianreport.DefaultClinicianReportDataSource
import com.healthmd.data.clinicianreport.SystemClinicianReportDateProvider
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.domain.clinicianreport.*
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.TimeZone
import kotlin.time.Duration.Companion.minutes

@RunWith(RobolectricTestRunner::class)
class ClinicianReportDataSourceTest {
    private val day = LocalDate.of(2026, 5, 1)

    @Test fun requestsOnlyRelevantDomainsWithGranularDataAndPreservesBloodPressurePair() = runTest {
        val repository = FakeHealthRepository(listOf(HealthData(
            date = day,
            vitals = VitalsData(bloodPressureSamples = listOf(BloodPressureSample(
                time = LocalDateTime.of(2026, 5, 1, 8, 30), systolic = 123.0, diastolic = 77.0,
                source = "missing.package", metadata = mapOf("recording_method" to "manual_entry"),
                identity = ExactSourceIdentity(nativeId = "bp-1", origin = "missing.package"),
            ))),
        )))
        val source = source(repository)
        val pinnedZone = ZoneId.of("Asia/Kathmandu")
        val input = source.load(
            ReportConfiguration(ReportDateRange(day, day), setOf(ReportMetric.BLOOD_PRESSURE)),
            pinnedZone,
        )
        assertThat(repository.includeGranular).isTrue()
        assertThat(repository.requestedZoneId).isEqualTo(pinnedZone)
        assertThat(repository.pinnedCalendarDays).isTrue()
        assertThat(repository.requestedTypes!!.vitals).isTrue()
        assertThat(repository.requestedTypes!!.heart).isFalse()
        assertThat(input.bloodPressureObservations).hasSize(1)
        assertThat(input.bloodPressureObservations.single().source!!.displayLabel(reportVocabulary())).isEqualTo("missing.package (manual entry)")
        assertThat(input.bloodPressureObservations.single().stableId).contains("bp-1")
    }

    @Test fun forwardsPinnedZoneThroughRepositoryProviderAndManager() = runTest {
        val pinnedZone = ZoneId.of("Pacific/Chatham")
        val manager = mockk<HealthConnectManager>()
        val provider = HealthConnectDataProvider(manager)
        val registry = mockk<HealthProviderRegistry>()
        val settings = mockk<SettingsRepository>()
        coEvery { settings.getSelectedHealthProviderId() } returns "health_connect"
        coEvery { settings.getSleepDayAttribution() } returns SleepDayAttribution.DEFAULT
        every { registry.providerFor("health_connect") } returns provider
        coEvery {
            manager.fetchHealthDataRange(any(), any(), true, pinnedZone, true, any())
        } answers {
            firstArg<List<LocalDate>>().map { date -> HealthData(date) }
        }

        val repository = HealthRepositoryImpl(registry, settings)
        source(repository).load(
            ReportConfiguration(ReportDateRange(day, day), setOf(ReportMetric.HEART_RATE)),
            pinnedZone,
        )

        coVerify(exactly = 1) {
            manager.fetchHealthDataRange(listOf(day), any(), true, pinnedZone, true, SleepDayAttribution.DEFAULT)
        }
    }

    @Test fun explicitNightBeginsOverrideIsNotRepopulatedFromStoredMorningEnds() = runTest {
        val manager = mockk<HealthConnectManager>()
        val provider = HealthConnectDataProvider(manager)
        val registry = mockk<HealthProviderRegistry>()
        val settings = mockk<SettingsRepository>()
        coEvery { settings.getSelectedHealthProviderId() } returns "health_connect"
        coEvery { settings.getSleepDayAttribution() } returns SleepDayAttribution.MORNING_ENDS
        every { registry.providerFor("health_connect") } returns provider
        coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
            firstArg<List<LocalDate>>().map(::HealthData)
        }
        val repository = HealthRepositoryImpl(registry, settings)

        repository.fetchHealthDataRange(
            dates = listOf(day),
            sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.NIGHT_BEGINS),
        )

        coVerify(exactly = 0) { settings.getSleepDayAttribution() }
        coVerify(exactly = 1) {
            manager.fetchHealthDataRange(
                listOf(day),
                any(),
                false,
                any(),
                false,
                SleepDayAttribution.NIGHT_BEGINS,
            )
        }
    }

    @Test fun singleDateCapturePinsZoneBeforeStoredAttributionRead() = runTest {
        val previous = TimeZone.getDefault()
        val capturedZone = ZoneId.of("America/Los_Angeles")
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(capturedZone))
            val manager = mockk<HealthConnectManager>()
            val provider = HealthConnectDataProvider(manager)
            val registry = mockk<HealthProviderRegistry>()
            val settings = mockk<SettingsRepository>()
            coEvery { settings.getSelectedHealthProviderId() } returns "health_connect"
            coEvery { settings.getSleepDayAttribution() } answers {
                TimeZone.setDefault(TimeZone.getTimeZone("Europe/Berlin"))
                SleepDayAttribution.MORNING_ENDS
            }
            every { registry.providerFor("health_connect") } returns provider
            coEvery {
                manager.fetchHealthDataRange(any(), any(), false, capturedZone, false, SleepDayAttribution.MORNING_ENDS)
            } returns listOf(HealthData(day, sleep = SleepData(totalDuration = 1.minutes)))
            val repository = HealthRepositoryImpl(registry, settings)

            val captured = repository.fetchHealthData(day)

            assertThat(captured.sleep.totalDuration).isEqualTo(1.minutes)
            coVerify(exactly = 1) {
                manager.fetchHealthDataRange(any(), any(), false, capturedZone, false, SleepDayAttribution.MORNING_ENDS)
            }
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test fun systemDateProviderUsesPinnedZoneWhenAmbientDateDiffers() {
        val previous = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("Pacific/Pago_Pago"))
            val ambientToday = LocalDate.now()
            val pinnedToday = SystemClinicianReportDateProvider().today(ZoneId.of("Pacific/Kiritimati"))
            assertThat(pinnedToday).isGreaterThan(ambientToday)
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test fun rangeClampUsesPinnedZoneTodayRatherThanAmbientSystemDate() = runTest {
        val pinnedZone = ZoneId.of("Pacific/Kiritimati")
        val pinnedToday = LocalDate.of(2026, 1, 2)
        val ambientToday = LocalDate.of(2026, 1, 1)
        assertThat(ambientToday).isNotEqualTo(pinnedToday)
        val repository = FakeHealthRepository()
        val pinnedDateProvider = ClinicianReportDateProvider { zoneId ->
            assertThat(zoneId).isEqualTo(pinnedZone)
            pinnedToday
        }

        val input = source(repository, pinnedDateProvider).load(
            ReportConfiguration(
                dateRange = ReportDateRange(LocalDate.of(2026, 1, 3), LocalDate.of(2026, 1, 4)),
                selectedMetrics = setOf(ReportMetric.STEPS),
            ),
            pinnedZone,
        )

        assertThat(input.configuration.dateRange).isEqualTo(ReportDateRange(pinnedToday, pinnedToday))
        assertThat(repository.requestedDates).containsExactly(pinnedToday)
        assertThat(repository.requestedZoneId).isEqualTo(pinnedZone)
    }

    @Test fun usesDailyFallbackWithoutInventingSourceAndPrefersGranularScalar() = runTest {
        val repository = FakeHealthRepository(listOf(HealthData(
            date = day,
            heart = HeartData(restingHeartRate = 61.0, averageHeartRate = 70.0, samples = listOf(
                TimestampedSample(LocalDateTime.of(2026, 5, 1, 10, 0), 72.0, source = "sensor.app"),
            )),
            body = BodyData(weight = 80.0),
        )))
        val metrics = setOf(ReportMetric.RESTING_HEART_RATE, ReportMetric.HEART_RATE, ReportMetric.WEIGHT)
        val input = source(repository).load(ReportConfiguration(ReportDateRange(day, day), metrics), ZoneId.of("UTC"))
        assertThat(input.scalarObservations).hasSize(1)
        assertThat(input.scalarObservations.single().value).isEqualTo(72.0)
        assertThat(input.dailyValues).hasSize(2)
        assertThat(input.dailyValues.all { it.source == null }).isTrue()
    }

    @Test fun aggregateScalarFallbackRemainsDateOnlyAndManualEntryNeedsNoOrigin() = runTest {
        val repository = FakeHealthRepository(listOf(HealthData(
            date = day,
            vitals = VitalsData(
                bloodGlucoseAvg = 104.0,
                respiratoryRateSamples = listOf(TimestampedSample(
                    time = LocalDateTime.of(2026, 5, 1, 9, 0),
                    value = 15.0,
                    metadata = mapOf("recording_method" to "manual_entry"),
                )),
            ),
        )))
        val metrics = setOf(ReportMetric.BLOOD_GLUCOSE, ReportMetric.RESPIRATORY_RATE)
        val input = source(repository).load(ReportConfiguration(ReportDateRange(day, day), metrics), ZoneId.of("UTC"))
        assertThat(input.dailyValues.single().metric).isEqualTo(ReportMetric.BLOOD_GLUCOSE)
        assertThat(input.scalarObservations.none { it.metric == ReportMetric.BLOOD_GLUCOSE }).isTrue()
        assertThat(input.scalarObservations.single().source!!.displayLabel(reportVocabulary())).isEqualTo("Manual entry")
    }

    @Test fun duplicateIdentitylessWorkoutsAreNotDeduplicatedBySyntheticModelId() = runTest {
        val workout = WorkoutData(
            workoutType = WorkoutType.WALKING,
            startTime = LocalDateTime.of(2026, 5, 1, 10, 0),
            duration = 30.minutes,
            id = "synthetic-model-id",
        )
        val input = source(FakeHealthRepository(listOf(HealthData(day, workouts = listOf(workout, workout))))).load(
            ReportConfiguration(ReportDateRange(day, day), setOf(ReportMetric.WORKOUTS)),
            ZoneId.of("UTC"),
        )
        assertThat(input.workoutObservations).hasSize(2)
        assertThat(input.workoutObservations.map { it.stableId }).containsExactly(null, null)
    }

    @Test fun repositoryFailureBecomesPartialWarningInsteadOfThrowing() = runTest {
        val source = source(FakeHealthRepository(error = IllegalStateException("private value must not leak")))
        val input = source.load(ReportConfiguration(ReportDateRange(day, day), setOf(ReportMetric.BLOOD_GLUCOSE)), ZoneId.of("UTC"))
        assertThat(input.warnings).isNotEmpty()
        assertThat(input.warnings.joinToString()).doesNotContain("private value")
        assertThat(input.scalarObservations).isEmpty()
    }

    private fun source(
        repository: HealthRepository,
        dateProvider: ClinicianReportDateProvider = SystemClinicianReportDateProvider(),
    ) = DefaultClinicianReportDataSource(
        repository,
        ClinicianReportSourceLabelResolver(ApplicationProvider.getApplicationContext()),
        dateProvider,
    )

    private class FakeHealthRepository(
        private val data: List<HealthData> = emptyList(),
        private val error: Exception? = null,
    ) : HealthRepository {
        var requestedTypes: DataTypeSelection? = null
        var requestedDates: List<LocalDate>? = null
        var requestedZoneId: ZoneId? = null
        var includeGranular = false
        var pinnedCalendarDays = false
        override suspend fun fetchHealthData(date: LocalDate) = data.firstOrNull { it.date == date } ?: HealthData(date)
        override suspend fun fetchHealthDataRange(
            dates: List<LocalDate>,
            dataTypes: DataTypeSelection,
            includeGranularData: Boolean,
            zoneId: ZoneId,
            pinnedCalendarDays: Boolean,
            sleepDayAttributionOverride: SleepDayAttributionOverride,
        ): List<HealthData> {
            requestedTypes = dataTypes
            requestedDates = dates
            requestedZoneId = zoneId
            includeGranular = includeGranularData
            this.pinnedCalendarDays = pinnedCalendarDays
            error?.let { throw it }
            return data
        }
        override suspend fun isAvailable() = true
        override suspend fun hasPermissions() = true
        override suspend fun hasHistoricalReadPermission() = true
        override suspend fun hasBackgroundReadPermission() = true
        override suspend fun getEarliestDataDate(): LocalDate? = data.minOfOrNull { it.date }
        override fun isBeforeFirstUnlock() = false
    }
}

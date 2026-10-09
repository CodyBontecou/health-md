package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.export.APIExportUploadResult
import com.healthmd.data.export.APIExportUploader
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.data.health.SleepAttributionCaptureFixture
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.withInteractiveRouteConsent
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.TimeZone
import kotlin.time.Duration.Companion.hours

class APIEndpointExportRunnerTest {
    @Test
    fun postsOneEnvelopeWithReadableDatesAndReportsEmptyDates() = runTest {
        val first = LocalDate.of(2026, 7, 10)
        val second = LocalDate.of(2026, 7, 11)
        val uploader = CapturingUploader()
        val runner = runner(
            dataByDate = mapOf(
                first to HealthData(first, activity = ActivityData(steps = 100)),
                second to HealthData(second),
            ),
            uploader = uploader,
        )

        val result = runner.exportDates(
            dates = listOf(second, first),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
        )

        assertThat(result.successCount).isEqualTo(1)
        assertThat(result.totalCount).isEqualTo(2)
        assertThat(result.failedDateDetails.map { it.reason }).containsExactly(ExportFailureReason.NO_HEALTH_DATA)
        assertThat(result.httpStatusCode).isEqualTo(202)
        assertThat(uploader.calls).isEqualTo(1)
        assertThat(uploader.authorization).isEqualTo("Bearer test-token")
        assertThat(uploader.requestHeaders)
            .containsExactly(APIExportRequestHeader("X-API-Key", "test-api-key"))

        val envelope = Json.parseToJsonElement(requireNotNull(uploader.payload)).jsonObject
        assertThat(envelope.getValue("records").jsonArray).hasSize(1)
        assertThat(envelope.getValue("failed_date_details").jsonArray).hasSize(1)
    }

    @Test
    fun emptyAuthoritativeRangeDoesNotFallBackToSingleDayRead() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val uploader = CapturingUploader()
        val singleDayReads = mutableListOf<LocalDate>()
        val runner = runner(
            dataByDate = mapOf(date to HealthData(date, activity = ActivityData(steps = 100))),
            rangeDataByDate = mapOf(date to HealthData(date)),
            uploader = uploader,
            singleDayReads = singleDayReads,
        )

        val result = runner.exportDates(
            dates = listOf(date),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.NO_HEALTH_DATA)
        assertThat(singleDayReads).isEmpty()
        assertThat(uploader.calls).isEqualTo(0)
    }

    @Test
    fun apiEntryPointPinsSettingAndDefaultZoneBeforeConsentAndAcrossPerDayReads() = runTest {
        val previousZone = TimeZone.getDefault()
        val capturedZone = ZoneId.of("America/Los_Angeles")
        val changedZone = ZoneId.of("Europe/Berlin")
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(capturedZone))
            val dates = listOf(LocalDate.of(2026, 7, 10), LocalDate.of(2026, 7, 11))
            var storedAttribution = SleepDayAttribution.NIGHT_BEGINS
            val observedContexts = mutableListOf<Pair<ZoneId, SleepDayAttribution>>()
            val consentZones = mutableListOf<ZoneId>()
            val manager = mockk<HealthConnectManager>()
            val provider = HealthConnectDataProvider(manager)
            val registry = mockk<HealthProviderRegistry>()
            val settings = mockk<SettingsRepository>()
            coEvery { settings.getSelectedHealthProviderId() } returns "health_connect"
            coEvery { settings.getSleepDayAttribution() } answers { storedAttribution }
            every { registry.providerFor("health_connect") } returns provider
            every { registry.primaryExportProvider() } returns provider
            every { manager.isBeforeFirstUnlock() } returns false
            coEvery { manager.authorizeExerciseRouteConsent(any(), any(), any()) } answers {
                consentZones += arg<ZoneId>(2)
                storedAttribution = SleepDayAttribution.MORNING_ENDS
                TimeZone.setDefault(TimeZone.getTimeZone(changedZone))
            }
            coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
                val date = firstArg<List<LocalDate>>().single()
                val zone = arg<ZoneId>(3)
                val attribution = arg<SleepDayAttribution>(5)
                observedContexts += zone to attribution
                if (observedContexts.size == 1) {
                    storedAttribution = SleepDayAttribution.MORNING_ENDS
                    TimeZone.setDefault(TimeZone.getTimeZone(changedZone))
                }
                listOf(HealthData(
                    date = date,
                    activity = ActivityData(steps = 100),
                    sleep = if (date == dates.last()) SleepData(totalDuration = 8.hours) else SleepData(),
                ))
            }
            val uploader = CapturingUploader()
            val jsonExporter = JsonExporter()
            val runner = APIEndpointExportRunner(
                healthRepository = HealthRepositoryImpl(registry, settings),
                envelopeBuilder = APIExportEnvelopeBuilder(jsonExporter),
                jsonExporter = jsonExporter,
                uploader = uploader,
                credentialStore = credentials(),
            )

            val result = withInteractiveRouteConsent {
                runner.exportDates(
                    dates = dates,
                    settings = ExportSettings(
                        exportTarget = ExportTarget.API_ENDPOINT,
                        apiEndpointUrl = "https://api.example.com/healthmd",
                    ),
                )
            }

            assertThat(result.successCount).isEqualTo(2)
            assertThat(consentZones).containsExactly(capturedZone)
            assertThat(observedContexts).containsExactly(
                capturedZone to SleepDayAttribution.NIGHT_BEGINS,
                capturedZone to SleepDayAttribution.NIGHT_BEGINS,
            ).inOrder()
            assertThat(uploader.calls).isEqualTo(1)
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test
    fun shippedSleepOnlyApiUploadContainsNightDayOnceAndNoWakeDayFallback() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        fixture.storedAttribution = SleepDayAttribution.NIGHT_BEGINS
        val uploader = CapturingUploader()
        val jsonExporter = JsonExporter()
        val runner = APIEndpointExportRunner(
            healthRepository = fixture.repository,
            envelopeBuilder = APIExportEnvelopeBuilder(jsonExporter),
            jsonExporter = jsonExporter,
            uploader = uploader,
            credentialStore = credentials(),
        )
        val previousZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(fixture.zone))
            val result = runner.exportDates(
                dates = listOf(fixture.startDay, fixture.wakeDay),
                settings = ExportSettings(
                    exportTarget = ExportTarget.API_ENDPOINT,
                    apiEndpointUrl = "https://api.example.com/healthmd",
                    dataTypes = fixture.selection,
                ),
            )

            assertThat(result.successCount).isEqualTo(1)
            assertThat(result.failedDateDetails.single().date).isEqualTo(fixture.wakeDay)
            assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.NO_HEALTH_DATA)
            assertThat(uploader.calls).isEqualTo(1)
            val records = Json.parseToJsonElement(requireNotNull(uploader.payload)).jsonObject.getValue("records").jsonArray
            assertThat(records).hasSize(1)
            assertThat(records.single().jsonObject.getValue("date").jsonPrimitive.content).isEqualTo(fixture.startDay.toString())
            val sleep = records.single().jsonObject.getValue("sleep").jsonObject
            assertThat(sleep.getValue("awakeTime").jsonPrimitive.content.toDouble()).isEqualTo(30 * 60.0)
            assertThat(sleep.getValue("totalDuration").jsonPrimitive.content.toDouble()).isEqualTo(495 * 60.0)
            assertThat(fixture.singleDayReads).isEmpty()
            assertThat(fixture.observedContexts).containsExactly(
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
            ).inOrder()
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test
    fun unapprovedSleepOwnershipDoesNotReadProviderOrUploadImmutableV4Envelope() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        val uploader = CapturingUploader()
        val jsonExporter = JsonExporter()
        val runner = APIEndpointExportRunner(healthRepository = fixture.repository,
            envelopeBuilder = APIExportEnvelopeBuilder(jsonExporter), jsonExporter = jsonExporter,
            uploader = uploader, credentialStore = credentials())
        val result = runner.exportDates(listOf(fixture.startDay, fixture.wakeDay),
            ExportSettings(exportTarget = ExportTarget.API_ENDPOINT, apiEndpointUrl = "https://api.example.com/healthmd", dataTypes = fixture.selection))
        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.map { it.reason }).containsExactly(ExportFailureReason.UNKNOWN, ExportFailureReason.UNKNOWN)
        assertThat(uploader.calls).isEqualTo(0)
        assertThat(fixture.observedContexts).isEmpty()
        assertThat(fixture.storedAttribution).isEqualTo(SleepDayAttribution.MORNING_ENDS)
    }

    @Test
    fun changedDestinationFingerprintAbortsBeforeUpload() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val uploader = CapturingUploader()
        val runner = runner(
            dataByDate = mapOf(date to HealthData(date, activity = ActivityData(steps = 100))),
            uploader = uploader,
        )

        val result = runner.exportDates(
            dates = listOf(date),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
            expectedDestinationFingerprint = "stale-fingerprint",
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason)
            .isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
        assertThat(uploader.calls).isEqualTo(0)
    }

    @Test
    fun uploadFailureDoesNotCountPreparedRecordsAsSuccess() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val uploader = CapturingUploader(throwOnUpload = true)
        val runner = runner(
            dataByDate = mapOf(date to HealthData(date, activity = ActivityData(steps = 100))),
            uploader = uploader,
        )

        val result = runner.exportDates(
            dates = listOf(date),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
            ),
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails).hasSize(1)
        assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.NETWORK_ERROR)
    }

    @Test
    fun individualTrackingCollectsGranularDataWithoutRenderingItInApiPayload() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val uploader = CapturingUploader()
        val rangeFlags = mutableListOf<Boolean>()
        val runner = runner(
            dataByDate = mapOf(date to HealthData(date, activity = ActivityData(steps = 100))),
            uploader = uploader,
            rangeFlags = rangeFlags,
        )

        runner.exportDates(
            dates = listOf(date),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/healthmd",
                includeGranularData = false,
                individualTracking = IndividualTrackingSettings(
                    globalEnabled = true,
                    enabledMetrics = setOf("steps"),
                ),
            ),
        )

        assertThat(rangeFlags).containsExactly(true)
        val record = Json.parseToJsonElement(requireNotNull(uploader.payload)).jsonObject
            .getValue("records").jsonArray.single().jsonObject
        assertThat(record.getValue("activity").jsonObject.containsKey("stepSamples")).isFalse()
    }

    @Test
    fun apiPreviewUsesExplicitGranularPrivacySetting() = runTest {
        val date = LocalDate.of(2026, 7, 10)
        val rangeFlags = mutableListOf<Boolean>()
        val runner = runner(
            dataByDate = mapOf(
                date to HealthData(
                    date,
                    activity = ActivityData(
                        steps = 100,
                        stepSamples = listOf(TimestampedSample(LocalDateTime.of(2026, 7, 10, 12, 0), 100.0)),
                    ),
                )
            ),
            uploader = CapturingUploader(),
            rangeFlags = rangeFlags,
        )

        val preview = runner.previewDates(
            dates = listOf(date),
            settings = ExportSettings(
                includeGranularData = false,
                individualTracking = IndividualTrackingSettings(
                    globalEnabled = true,
                    enabledMetrics = setOf("steps"),
                ),
            ),
        )

        assertThat(rangeFlags).containsExactly(true)
        assertThat(preview.days.single().files.single().content).doesNotContain("stepSamples")
    }

    private fun runner(
        dataByDate: Map<LocalDate, HealthData>,
        uploader: APIExportUploader,
        rangeDataByDate: Map<LocalDate, HealthData> = dataByDate,
        rangeFlags: MutableList<Boolean>? = null,
        singleDayReads: MutableList<LocalDate>? = null,
    ): APIEndpointExportRunner {
        val healthRepository = object : HealthRepository {
            override suspend fun resolveCaptureContext(
                zoneId: ZoneId,
                sleepDayAttributionOverride: SleepDayAttributionOverride,
            ) = AndroidCaptureContext(
                zoneId,
                (sleepDayAttributionOverride as? SleepDayAttributionOverride.Value)?.attribution
                    ?: SleepDayAttribution.DEFAULT,
            )
            override suspend fun fetchHealthData(date: LocalDate): HealthData {
                singleDayReads?.add(date)
                return dataByDate.getValue(date)
            }
            override suspend fun fetchHealthDataRange(
                dates: List<LocalDate>,
                dataTypes: DataTypeSelection,
                includeGranularData: Boolean,
                zoneId: ZoneId,
                pinnedCalendarDays: Boolean,
                sleepDayAttributionOverride: SleepDayAttributionOverride,
            ): List<HealthData> {
                rangeFlags?.add(includeGranularData)
                return dates.map { rangeDataByDate.getValue(it).filtered(dataTypes) }
            }
            override suspend fun isAvailable(): Boolean = true
            override suspend fun hasPermissions(): Boolean = true
            override suspend fun hasHistoricalReadPermission(): Boolean = true
            override suspend fun hasBackgroundReadPermission(): Boolean = true
            override suspend fun getEarliestDataDate(): LocalDate? = dataByDate.keys.minOrNull()
            override fun isBeforeFirstUnlock(): Boolean = false
        }
        val credentials = credentials()
        val jsonExporter = JsonExporter()
        return APIEndpointExportRunner(
            healthRepository = healthRepository,
            envelopeBuilder = APIExportEnvelopeBuilder(jsonExporter),
            jsonExporter = jsonExporter,
            uploader = uploader,
            credentialStore = credentials,
        )
    }

    private fun credentials(): APIExportCredentialStore = object : APIExportCredentialStore {
        override suspend fun authorizationHeader(): String = "Bearer test-token"
        override suspend fun hasAuthorization(): Boolean = true
        override suspend fun saveAuthorization(value: String) = Unit
        override suspend fun clearAuthorization() = Unit
        override suspend fun requestHeaders(): List<APIExportRequestHeader> =
            listOf(APIExportRequestHeader("X-API-Key", "test-api-key"))
    }

    private class CapturingUploader(
        private val throwOnUpload: Boolean = false,
    ) : APIExportUploader {
        var calls = 0
        var payload: String? = null
        var authorization: String? = null
        var requestHeaders: List<APIExportRequestHeader> = emptyList()

        override suspend fun upload(
            endpointUrl: String,
            payload: String,
            authorizationHeader: String?,
            requestHeaders: List<APIExportRequestHeader>,
        ): APIExportUploadResult {
            calls++
            this.payload = payload
            authorization = authorizationHeader
            this.requestHeaders = requestHeaders
            if (throwOnUpload) throw IllegalStateException("offline")
            return APIExportUploadResult(statusCode = 202)
        }
    }
}

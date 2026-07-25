package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.RawSnapshotExportRunner
import com.healthmd.data.history.ExportHistoryEntity
import com.healthmd.data.settings.decodePersistedExportSettings
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ExportTargetReadiness
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.presentation.export.ExportUiState
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawJson
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.rawexport.SafRawExportStorage
import java.io.File
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Test

class RawSnapshotProductIntegrationTest {
    @Test
    fun oldSettingsDecodeIntoCompatibilityModeWithRawDefaults() {
        val old = """{"exportFormat":"CSV","includeMetadata":false}"""
        val decoded = decodePersistedExportSettings(old)

        assertThat(decoded.exportMode).isEqualTo(ExportMode.COMPATIBILITY)
        assertThat(decoded.rawSnapshot).isEqualTo(RawSnapshotSettings())
        assertThat(decoded.exportFormat.name).isEqualTo("CSV")
        assertThat(decoded.selectedExportFormats.map { it.name }).containsExactly("CSV")
        assertThat(decoded.includeMetadata).isFalse()
    }

    @Test
    fun legacyHistoryRowsDefaultToCompatibilityMode() {
        val entity = ExportHistoryEntity(
            timestamp = 1L,
            source = "MANUAL",
            dateRangeStart = "2026-01-01",
            dateRangeEnd = "2026-01-01",
            successCount = 1,
            totalCount = 1,
        )

        assertThat(entity.toDomain().exportMode).isEqualTo(ExportMode.COMPATIBILITY)
    }

    @Test
    fun persistedRawPageSizeIsBoundedWithoutDiscardingSettings() {
        val decoded = decodePersistedExportSettings(
            """{"exportMode":"RAW_SNAPSHOT","rawSnapshot":{"format":"NDJSON","scope":"SELECTED_RECORD_TYPES","includeExerciseRoutes":false,"pageSize":99999}}""",
        )

        assertThat(decoded.exportMode).isEqualTo(ExportMode.RAW_SNAPSHOT)
        assertThat(decoded.rawSnapshot.format).isEqualTo(RawExportFormat.NDJSON)
        assertThat(decoded.rawSnapshot.includeExerciseRoutes).isFalse()
        assertThat(decoded.rawSnapshot.pageSize).isEqualTo(5_000)
    }

    @Test
    fun rawSettingsAreSingleFormatAndNormalizePageBounds() {
        val settings = ExportSettings(
            exportMode = ExportMode.RAW_SNAPSHOT,
            rawSnapshot = RawSnapshotSettings(
                format = RawExportFormat.NDJSON,
                scope = RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA,
                includeExerciseRoutes = false,
                pageSize = 50_000,
            ),
        ).normalized()

        assertThat(settings.rawSnapshot.format).isEqualTo(RawExportFormat.NDJSON)
        assertThat(settings.rawSnapshot.scope).isEqualTo(RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA)
        assertThat(settings.rawSnapshot.includeExerciseRoutes).isFalse()
        assertThat(settings.rawSnapshot.pageSize).isEqualTo(5_000)
    }

    @Test
    fun springDstCalendarDayUsesHalfOpenTwentyThreeHourRange() {
        val request = RawSnapshotExportRunner.buildRequest(
            LocalDate.of(2026, 3, 8),
            LocalDate.of(2026, 3, 8),
            ZoneId.of("America/New_York"),
            ExportSettings(),
        )

        val seconds = request.endTime.epochSecond - request.startTime.epochSecond
        assertThat(Duration.ofSeconds(seconds)).isEqualTo(Duration.ofHours(23))
        assertThat(request.calendarZoneId).isEqualTo("America/New_York")
    }

    @Test
    fun fallDstCalendarDayUsesHalfOpenTwentyFiveHourRange() {
        val request = RawSnapshotExportRunner.buildRequest(
            LocalDate.of(2026, 11, 1),
            LocalDate.of(2026, 11, 1),
            ZoneId.of("America/New_York"),
            ExportSettings(),
        )

        val seconds = request.endTime.epochSecond - request.startTime.epochSecond
        assertThat(Duration.ofSeconds(seconds)).isEqualTo(Duration.ofHours(25))
    }

    @Test
    fun nonHourZoneAndSelectedMetricsAreCapturedDeterministically() {
        val zone = ZoneId.of("Asia/Kathmandu")
        val settings = ExportSettings().copy(
            metricSelection = ExportSettings().metricSelection.copy(
                enabledMetrics = linkedSetOf("weight", "steps", "avg_hr"),
            ),
        )
        val request = RawSnapshotExportRunner.buildRequest(
            LocalDate.of(2026, 1, 3),
            LocalDate.of(2026, 1, 4),
            zone,
            settings,
        )

        assertThat(request.startTime.epochSecond).isEqualTo(
            LocalDate.of(2026, 1, 3).atStartOfDay(zone).toInstant().epochSecond,
        )
        assertThat(request.endTime.epochSecond).isEqualTo(
            LocalDate.of(2026, 1, 5).atStartOfDay(zone).toInstant().epochSecond,
        )
        assertThat(request.selectedMetricIds.toList()).containsExactly("avg_hr", "steps", "weight").inOrder()
        val encoded = RawJson.codec.encodeToString(RawSnapshotRequest.serializer(), request)
        assertThat(encoded).contains("\"calendarZoneId\":\"Asia/Kathmandu\"")
    }

    @Test
    fun readinessRejectsUnsupportedRawProviderAndPlainHttp() {
        assertThat(
            ExportTargetReadiness.canExport(
                hasHealthPermissions = true,
                historicalPermissionNeeded = false,
                hasSelectedFormat = true,
                target = ExportTarget.DEVICE_FOLDER,
                hasExportFolder = true,
                apiEndpointConfigured = true,
                exportMode = ExportMode.RAW_SNAPSHOT,
                rawProviderSupported = false,
            ),
        ).isFalse()

        val state = ExportUiState(
            settings = ExportSettings(
                exportMode = ExportMode.RAW_SNAPSHOT,
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "http://example.com/raw",
            ),
        )
        assertThat(state.rawApiEndpointConfigured).isFalse()
        assertThat(state.destinationReady).isFalse()
        assertThat(state.previewEnabled).isFalse()
        assertThat(state.hasSelectedFormat).isTrue()
    }

    @Test
    fun allConnectedArtifactAccountingSumsDurableChildren() {
        val date = LocalDate.of(2026, 1, 1)
        val aggregate = RawSnapshotExportRunner.aggregateProviderResults(
            listOf(
                ExportResult(1, 1, target = ExportTarget.DEVICE_FOLDER, exportMode = ExportMode.RAW_SNAPSHOT, artifactCount = 1),
                ExportResult(
                    0,
                    1,
                    failedDateDetails = listOf(FailedDateDetail(date, ExportFailureReason.RAW_PARTIAL, "partial")),
                    target = ExportTarget.DEVICE_FOLDER,
                    exportMode = ExportMode.RAW_SNAPSHOT,
                    artifactCount = 1,
                ),
            ),
            ExportTarget.DEVICE_FOLDER,
        )

        assertThat(aggregate.successCount).isEqualTo(1)
        assertThat(aggregate.totalCount).isEqualTo(2)
        assertThat(aggregate.artifactCount).isEqualTo(2)
    }

    @Test
    fun sidecarFailureKeepsDurableArtifactOpenableAndReportsVerificationWarning() {
        val result = RawSnapshotExportRunner.durableArtifactVerificationFailure(LocalDate.of(2026, 1, 1))

        assertThat(result.isFailure).isTrue()
        assertThat(result.artifactCount).isEqualTo(1)
        assertThat(result.primaryFailureReason).isEqualTo(ExportFailureReason.FILE_WRITE_ERROR)
        assertThat(result.failedDateDetails.single().errorDetails.orEmpty()).contains("durable")
        assertThat(result.failedDateDetails.single().errorDetails.orEmpty()).contains("checksum")
    }

    @Test
    fun privateApiArtifactCleanupDeletesSensitiveBytes() {
        val file = File.createTempFile("healthmd-raw-cleanup", ".json")
        file.writeText("sensitive-health-data")

        assertThat(RawSnapshotExportRunner.cleanupPrivateArtifact(file)).isTrue()
        assertThat(file.exists()).isFalse()
    }

    @Test
    fun immutableFileNameIncludesRangeSchemaSnapshotAndFormat() {
        val name = SafRawExportStorage.stableFileName(
            "healthmd-raw-2026-01-01_to_2026-01-31-schema-v1",
            "0123456789abcdef",
            RawExportFormat.NDJSON,
        )

        assertThat(name).isEqualTo(
            "healthmd-raw-2026-01-01_to_2026-01-31-schema-v1-0123456789abcdef.ndjson",
        )
    }
}

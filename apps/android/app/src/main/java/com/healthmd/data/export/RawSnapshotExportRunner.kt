package com.healthmd.data.export

import android.content.Context
import android.net.Uri
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.rawexport.CompletedRawSnapshot
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.NoBackupRawExportStorage
import com.healthmd.rawexport.RawApiHeader
import com.healthmd.rawexport.RawExportResult
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawSnapshotApiClient
import com.healthmd.rawexport.RawSnapshotApiException
import com.healthmd.rawexport.RawSnapshotExportOrchestrator
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.rawexport.SafRawExportStorage
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.net.URI
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException

/** Product boundary for raw exports. It never requests compatibility HealthData. */
interface RawSnapshotService {
    suspend fun exportRange(
        startDate: LocalDate,
        endDate: LocalDate,
        settings: ExportSettings,
        target: ExportTarget = settings.exportTarget,
        expectedDestinationFingerprint: String? = null,
    ): ExportResult
}

@Singleton
class RawSnapshotExportRunner @Inject constructor(
    @ApplicationContext private val context: Context,
    private val rawRepository: RawHealthRepository,
    private val apiClient: RawSnapshotApiClient,
    private val credentialStore: APIExportCredentialStore,
    private val settingsRepository: SettingsRepository,
) : RawSnapshotService {

    override suspend fun exportRange(
        startDate: LocalDate,
        endDate: LocalDate,
        settings: ExportSettings,
        target: ExportTarget,
        expectedDestinationFingerprint: String?,
    ): ExportResult {
        if (endDate.isBefore(startDate)) {
            return failure(startDate, target, ExportFailureReason.UNKNOWN, "The raw snapshot end date is before its start date.")
        }
        if (settings.rawSnapshot.scope == RawSnapshotScope.SELECTED_RECORD_TYPES &&
            settings.metricSelection.enabledMetrics.isEmpty()
        ) {
            return failure(
                startDate,
                target,
                ExportFailureReason.NO_HEALTH_DATA,
                "Select at least one health metric or choose All Authorized Supported Data.",
            )
        }
        if (settingsRepository.getSelectedHealthProviderId() != HEALTH_CONNECT_PROVIDER_ID) {
            return failure(
                startDate,
                target,
                ExportFailureReason.RAW_UNSUPPORTED_PROVIDER,
                "Raw API snapshots are available only for Health Connect. Select Health Connect or use Compatibility Export.",
            )
        }

        val zone = ZoneId.systemDefault()
        val request = buildRequest(startDate, endDate, zone, settings)
        return try {
            when (target) {
                ExportTarget.DEVICE_FOLDER -> exportToFolder(startDate, endDate, request, settings)
                ExportTarget.API_ENDPOINT -> exportToApi(
                    startDate,
                    request,
                    settings,
                    expectedDestinationFingerprint,
                )
            }
        } catch (cancelled: CancellationException) {
            failure(startDate, target, ExportFailureReason.RAW_CANCELLED, "Raw snapshot export was cancelled.", cancelled = true)
        } catch (error: RawSnapshotApiException) {
            failure(
                startDate,
                target,
                if (error.statusCode == null) ExportFailureReason.NETWORK_ERROR else ExportFailureReason.API_REJECTED,
                error.message ?: "Raw snapshot upload failed.",
                error.statusCode,
            )
        } catch (error: SecurityException) {
            failure(startDate, target, ExportFailureReason.ACCESS_DENIED, "Raw snapshot access was denied. Re-select the folder and review Health Connect permissions.")
        } catch (error: Throwable) {
            failure(
                startDate,
                target,
                if (target == ExportTarget.DEVICE_FOLDER) ExportFailureReason.FILE_WRITE_ERROR else ExportFailureReason.HEALTH_CONNECT_ERROR,
                error.message?.takeIf(String::isNotBlank) ?: "Raw snapshot export failed before the artifact was complete.",
            )
        }
    }

    private suspend fun exportToFolder(
        startDate: LocalDate,
        endDate: LocalDate,
        request: RawSnapshotRequest,
        settings: ExportSettings,
    ): ExportResult {
        val folderUri = settingsRepository.getExportFolderUri()
            ?: return failure(startDate, ExportTarget.DEVICE_FOLDER, ExportFailureReason.NO_FOLDER_SELECTED, "Select an export folder before creating a raw snapshot.")
        val relativeDirectory = listOf(
            settings.subfolder.trim('/').takeIf(String::isNotBlank),
            RAW_DIRECTORY,
        ).filterNotNull().joinToString("/")
        val prefix = "healthmd-raw-${startDate}_to_${endDate}-schema-v1"
        val storage = SafRawExportStorage(context, Uri.parse(folderUri), relativeDirectory, prefix)
        val raw = RawSnapshotExportOrchestrator(context, rawRepository, storage).export(request)
        storage.writeIntegrityArtifact(raw.snapshotId, raw.format, raw.artifactChecksumSha256)
        return raw.toProductResult(startDate, ExportTarget.DEVICE_FOLDER)
    }

    private suspend fun exportToApi(
        startDate: LocalDate,
        request: RawSnapshotRequest,
        settings: ExportSettings,
        expectedDestinationFingerprint: String?,
    ): ExportResult {
        val configuration = credentialStore.requestConfiguration(settings.apiEndpointUrl)
            ?: return failure(startDate, ExportTarget.API_ENDPOINT, ExportFailureReason.INVALID_API_ENDPOINT, "Configure a raw snapshot HTTPS endpoint.")
        val scheme = runCatching { URI(configuration.endpointUrl).scheme }.getOrNull()
        if (!scheme.equals("https", ignoreCase = true)) {
            return failure(startDate, ExportTarget.API_ENDPOINT, ExportFailureReason.INVALID_API_ENDPOINT, "Raw snapshot API endpoints must use HTTPS.")
        }
        if (expectedDestinationFingerprint != null && expectedDestinationFingerprint != configuration.destinationFingerprint) {
            return failure(startDate, ExportTarget.API_ENDPOINT, ExportFailureReason.INVALID_API_ENDPOINT, "The raw snapshot destination changed after this export was scheduled.")
        }

        val storage = NoBackupRawExportStorage(context)
        var raw: RawExportResult? = null
        try {
            raw = RawSnapshotExportOrchestrator(context, rawRepository, storage).export(request)
            if (raw.manifest.status != RawSnapshotStatus.COMPLETE) {
                return raw.toProductResult(startDate, ExportTarget.API_ENDPOINT)
            }
            val artifactFile = File(raw.finalLocation)
            check(artifactFile.isFile) { "Completed raw snapshot artifact is missing." }
            val userHeaders = configuration.requestHeaders
                .filterNot { it.name.lowercase() in MANAGED_HEADER_NAMES }
                .map { RawApiHeader(it.name, it.value) }
            val contractHeaders = listOf(
                RawApiHeader(HEADER_SCHEMA, "healthmd.raw-snapshot; version=1"),
                RawApiHeader(HEADER_EXPORT_ID, raw.snapshotId),
                RawApiHeader(HEADER_CHECKSUM, raw.manifest.logicalChecksumSha256),
                RawApiHeader(HEADER_ARTIFACT_CHECKSUM, raw.artifactChecksumSha256),
                RawApiHeader(HEADER_CALENDAR_ZONE, request.calendarZoneId.orEmpty()),
            )
            val uploaded = apiClient.upload(
                endpointUrl = configuration.endpointUrl,
                artifact = CompletedRawSnapshot.file(artifactFile, raw.format),
                authorizationHeader = configuration.authorizationHeader,
                headers = userHeaders + contractHeaders,
            )
            return ExportResult(
                successCount = 1,
                totalCount = 1,
                target = ExportTarget.API_ENDPOINT,
                httpStatusCode = uploaded.statusCode,
                exportMode = ExportMode.RAW_SNAPSHOT,
            )
        } finally {
            // Raw API artifacts are transient no-backup files. Retain neither uploaded health data
            // nor failed-upload content; retry creates a fresh explicitly non-transactional snapshot.
            raw?.finalLocation?.let { location -> cleanupPrivateArtifact(File(location)) }
        }
    }

    private fun RawExportResult.toProductResult(date: LocalDate, target: ExportTarget): ExportResult = when (manifest.status) {
        RawSnapshotStatus.COMPLETE -> ExportResult(1, 1, target = target, exportMode = ExportMode.RAW_SNAPSHOT)
        RawSnapshotStatus.PARTIAL -> failure(
            date,
            target,
            ExportFailureReason.RAW_PARTIAL,
            if (target == ExportTarget.DEVICE_FOLDER) {
                "Raw snapshot is partial. Review its promoted artifact manifest before use."
            } else {
                "Raw snapshot was partial and was not uploaded. Review Health Connect access and retry."
            },
        )
        RawSnapshotStatus.FAILED -> failure(
            date,
            target,
            ExportFailureReason.HEALTH_CONNECT_ERROR,
            "Health Connect could not complete the raw snapshot. Review the artifact manifest and permissions.",
        )
        else -> failure(date, target, ExportFailureReason.UNKNOWN, "Raw snapshot ended without a final status.")
    }

    private fun failure(
        date: LocalDate,
        target: ExportTarget,
        reason: ExportFailureReason,
        message: String,
        statusCode: Int? = null,
        cancelled: Boolean = false,
    ) = ExportResult(
        successCount = 0,
        totalCount = 1,
        failedDateDetails = listOf(FailedDateDetail(date, reason, message)),
        wasCancelled = cancelled,
        target = target,
        httpStatusCode = statusCode,
        exportMode = ExportMode.RAW_SNAPSHOT,
    )

    companion object {
        const val HEALTH_CONNECT_PROVIDER_ID = "health_connect"
        const val RAW_DIRECTORY = "raw"
        const val HEADER_SCHEMA = "X-HealthMD-Schema"
        const val HEADER_EXPORT_ID = "X-HealthMD-Export-ID"
        const val HEADER_CHECKSUM = "X-HealthMD-Checksum-SHA256"
        const val HEADER_ARTIFACT_CHECKSUM = "X-HealthMD-Artifact-Checksum-SHA256"
        const val HEADER_CALENDAR_ZONE = "X-HealthMD-Calendar-Zone"
        private val MANAGED_HEADER_NAMES = setOf(
            HEADER_SCHEMA,
            HEADER_EXPORT_ID,
            HEADER_CHECKSUM,
            HEADER_ARTIFACT_CHECKSUM,
            HEADER_CALENDAR_ZONE,
        ).map(String::lowercase).toSet()

        internal fun cleanupPrivateArtifact(file: File): Boolean {
            if (!file.exists()) return true
            if (file.delete()) return true
            // If unlink is temporarily unavailable, first remove the sensitive bytes and retry.
            runCatching { file.outputStream().use { } }
            return !file.exists() || file.delete()
        }

        fun buildRequest(
            startDate: LocalDate,
            endDate: LocalDate,
            zoneId: ZoneId,
            settings: ExportSettings,
        ): RawSnapshotRequest {
            val raw = settings.rawSnapshot.normalized()
            val start = startDate.atStartOfDay(zoneId).toInstant()
            val endExclusive = endDate.plusDays(1).atStartOfDay(zoneId).toInstant()
            return RawSnapshotRequest(
                format = raw.format,
                scope = raw.scope,
                startTime = RawInstant(start.epochSecond, start.nano),
                endTime = RawInstant(endExclusive.epochSecond, endExclusive.nano),
                selectedMetricIds = settings.metricSelection.enabledMetrics.toSortedSet(),
                pageSize = raw.pageSize,
                includeExerciseRoutes = raw.includeExerciseRoutes,
                calendarZoneId = zoneId.id,
            )
        }
    }
}

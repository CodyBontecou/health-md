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
import com.healthmd.rawexport.RawHealthRepositoryRegistry
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
    private val rawRepositoryRegistry: RawHealthRepositoryRegistry = RawHealthRepositoryRegistry.healthConnectOnly(rawRepository),
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
        val selectedProviderId = settingsRepository.getSelectedHealthProviderId()
        val providerIds = if (selectedProviderId == ALL_CONNECTED_PROVIDER_ID) {
            settingsRepository.getConnectedHealthProviderIds()
                .filterNot { it == ALL_CONNECTED_PROVIDER_ID }
                .distinct()
                .sorted()
        } else {
            listOf(selectedProviderId)
        }
        if (providerIds.isEmpty()) {
            return failure(startDate, target, ExportFailureReason.RAW_UNSUPPORTED_PROVIDER, "No connected provider is available for a raw snapshot.")
        }

        val apiConfiguration = if (target == ExportTarget.API_ENDPOINT) {
            val captured = credentialStore.requestConfiguration(settings.apiEndpointUrl)
                ?: return failure(startDate, target, ExportFailureReason.INVALID_API_ENDPOINT, "Configure a raw snapshot HTTPS endpoint.")
            val scheme = runCatching { URI(captured.endpointUrl).scheme }.getOrNull()
            if (!scheme.equals("https", ignoreCase = true)) {
                return failure(startDate, target, ExportFailureReason.INVALID_API_ENDPOINT, "Raw snapshot API endpoints must use HTTPS.")
            }
            if (expectedDestinationFingerprint != null && expectedDestinationFingerprint != captured.destinationFingerprint) {
                return failure(startDate, target, ExportFailureReason.INVALID_API_ENDPOINT, "The raw snapshot destination changed after this export was scheduled.")
            }
            // Immutable action snapshot: every provider uses this exact URL, authorization, headers,
            // and fingerprint even if settings are edited while the action is running.
            captured.copy(requestHeaders = captured.requestHeaders.toList())
        } else null

        val zone = ZoneId.systemDefault()
        val request = buildRequest(startDate, endDate, zone, settings)
        val results = mutableListOf<ExportResult>()
        for (providerId in providerIds) {
            val repository = rawRepositoryRegistry.repositoryFor(providerId)
            val result = if (repository == null) {
                failure(
                    startDate,
                    target,
                    ExportFailureReason.RAW_UNSUPPORTED_PROVIDER,
                    "$providerId is not registered for provider-native raw snapshots; Health Connect fallback was not used.",
                )
            } else {
                exportProvider(
                    providerId, repository, startDate, endDate, request, settings, target,
                    apiConfiguration,
                )
            }
            results += result
            if (result.wasCancelled) break
        }
        if (providerIds.size == 1) return results.single()
        return aggregateProviderResults(results, target, providerIds.size)
    }

    private suspend fun exportProvider(
        providerId: String,
        repository: RawHealthRepository,
        startDate: LocalDate,
        endDate: LocalDate,
        request: RawSnapshotRequest,
        settings: ExportSettings,
        target: ExportTarget,
        apiConfiguration: APIExportRequestConfiguration?,
    ): ExportResult = try {
        when (target) {
            ExportTarget.DEVICE_FOLDER -> exportToFolder(providerId, repository, startDate, endDate, request, settings)
            ExportTarget.API_ENDPOINT -> exportToApi(providerId, repository, startDate, request, requireNotNull(apiConfiguration))
        }
    } catch (cancelled: CancellationException) {
        failure(startDate, target, ExportFailureReason.RAW_CANCELLED, "$providerId raw snapshot export was cancelled.", cancelled = true)
    } catch (error: RawSnapshotApiException) {
        failure(
            startDate, target,
            if (error.statusCode == null) ExportFailureReason.NETWORK_ERROR else ExportFailureReason.API_REJECTED,
            error.message ?: "$providerId raw snapshot upload failed.", error.statusCode,
        )
    } catch (_: SecurityException) {
        failure(startDate, target, ExportFailureReason.ACCESS_DENIED, "$providerId raw snapshot access was denied. Review provider permissions.")
    } catch (_: Exception) {
        failure(
            startDate, target,
            if (target == ExportTarget.DEVICE_FOLDER) ExportFailureReason.FILE_WRITE_ERROR else ExportFailureReason.HEALTH_CONNECT_ERROR,
            "$providerId raw snapshot failed before the artifact was complete.",
        )
    }

    private suspend fun exportToFolder(
        providerId: String,
        repository: RawHealthRepository,
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
        val prefix = "healthmd-raw-$providerId-${startDate}_to_${endDate}-schema-v1"
        val storage = SafRawExportStorage(context, Uri.parse(folderUri), relativeDirectory, prefix)
        val raw = RawSnapshotExportOrchestrator(context, repository, storage).export(request)
        try {
            storage.writeIntegrityArtifact(raw.snapshotId, raw.format, raw.artifactChecksumSha256)
        } catch (_: Exception) {
            return durableArtifactVerificationFailure(startDate)
        }
        return raw.toProductResult(startDate, ExportTarget.DEVICE_FOLDER)
    }

    private suspend fun exportToApi(
        providerId: String,
        repository: RawHealthRepository,
        startDate: LocalDate,
        request: RawSnapshotRequest,
        configuration: APIExportRequestConfiguration,
    ): ExportResult {
        val storage = NoBackupRawExportStorage(context)
        var raw: RawExportResult? = null
        try {
            raw = RawSnapshotExportOrchestrator(context, repository, storage).export(request)
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
                RawApiHeader(HEADER_PROVIDER, providerId),
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
                artifactCount = 0,
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
                "Raw snapshot was partial and was not uploaded. Review provider access and retry."
            },
            artifactCount = if (target == ExportTarget.DEVICE_FOLDER) 1 else 0,
        )
        RawSnapshotStatus.FAILED -> failure(
            date,
            target,
            ExportFailureReason.HEALTH_CONNECT_ERROR,
            "The selected provider could not complete the raw snapshot. Review the artifact manifest and permissions.",
            artifactCount = if (target == ExportTarget.DEVICE_FOLDER) 1 else 0,
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
        artifactCount: Int = 0,
    ) = ExportResult(
        successCount = 0,
        totalCount = 1,
        failedDateDetails = listOf(FailedDateDetail(date, reason, message)),
        wasCancelled = cancelled,
        target = target,
        httpStatusCode = statusCode,
        exportMode = ExportMode.RAW_SNAPSHOT,
        artifactCount = artifactCount,
    )

    companion object {
        const val HEALTH_CONNECT_PROVIDER_ID = "health_connect"
        const val ALL_CONNECTED_PROVIDER_ID = "all_connected"
        const val RAW_DIRECTORY = "raw"
        const val HEADER_SCHEMA = "X-HealthMD-Schema"
        const val HEADER_EXPORT_ID = "X-HealthMD-Export-ID"
        const val HEADER_CHECKSUM = "X-HealthMD-Checksum-SHA256"
        const val HEADER_ARTIFACT_CHECKSUM = "X-HealthMD-Artifact-Checksum-SHA256"
        const val HEADER_CALENDAR_ZONE = "X-HealthMD-Calendar-Zone"
        const val HEADER_PROVIDER = "X-HealthMD-Provider"
        private val MANAGED_HEADER_NAMES = setOf(
            HEADER_SCHEMA,
            HEADER_EXPORT_ID,
            HEADER_CHECKSUM,
            HEADER_ARTIFACT_CHECKSUM,
            HEADER_CALENDAR_ZONE,
            HEADER_PROVIDER,
        ).map(String::lowercase).toSet()

        internal fun aggregateProviderResults(
            results: List<ExportResult>,
            target: ExportTarget,
            totalProviderCount: Int = results.sumOf { it.totalCount },
        ) = ExportResult(
            successCount = results.sumOf { it.successCount },
            totalCount = totalProviderCount,
            failedDateDetails = results.flatMap { it.failedDateDetails },
            wasCancelled = results.any { it.wasCancelled },
            target = target,
            httpStatusCode = results.mapNotNull { it.httpStatusCode }.lastOrNull(),
            exportMode = ExportMode.RAW_SNAPSHOT,
            artifactCount = results.sumOf { it.artifactCount },
        )

        internal fun durableArtifactVerificationFailure(date: LocalDate) = ExportResult(
            successCount = 0,
            totalCount = 1,
            failedDateDetails = listOf(
                FailedDateDetail(
                    date,
                    ExportFailureReason.FILE_WRITE_ERROR,
                    "The raw snapshot artifact is durable, but its checksum sidecar could not be verified. The artifact remains available for inspection.",
                ),
            ),
            target = ExportTarget.DEVICE_FOLDER,
            exportMode = ExportMode.RAW_SNAPSHOT,
            artifactCount = 1,
        )

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

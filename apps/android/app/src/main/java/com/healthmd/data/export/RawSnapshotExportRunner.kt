package com.healthmd.data.export

import android.content.Context
import android.net.Uri
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportPreviewIssue
import com.healthmd.domain.model.ExportPreviewIssueKind
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
import com.healthmd.rawexport.withInteractiveRouteConsent
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.RandomAccessFile
import java.net.URI
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException

/** Product boundary for raw exports. It never requests compatibility HealthData. */
internal data class RawArtifactPreview(
    val content: String,
    val tailContent: String = "",
    val omittedByteCount: Int,
)

interface RawSnapshotService {
    suspend fun exportRange(
        startDate: LocalDate,
        endDate: LocalDate,
        settings: ExportSettings,
        target: ExportTarget = settings.exportTarget,
        expectedDestinationFingerprint: String? = null,
        allowInteractiveRouteConsent: Boolean = false,
    ): ExportResult

    /** Performs the same native source read as an export without writing or uploading a user artifact. */
    suspend fun previewRange(
        startDate: LocalDate,
        endDate: LocalDate,
        settings: ExportSettings,
        allowInteractiveRouteConsent: Boolean = false,
    ): ExportPreview
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
        allowInteractiveRouteConsent: Boolean,
    ): ExportResult {
        if (endDate.isBefore(startDate)) {
            return failure(startDate, target, ExportFailureReason.UNKNOWN)
        }
        if (settings.rawSnapshot.scope == RawSnapshotScope.SELECTED_RECORD_TYPES &&
            settings.metricSelection.enabledMetrics.isEmpty()
        ) {
            return failure(startDate, target, ExportFailureReason.NO_HEALTH_DATA)
        }
        val providerIds = selectedProviderIds()
        if (providerIds.isEmpty()) {
            return failure(startDate, target, ExportFailureReason.RAW_UNSUPPORTED_PROVIDER)
        }

        val apiConfiguration = if (target == ExportTarget.API_ENDPOINT) {
            val captured = credentialStore.requestConfiguration(settings.apiEndpointUrl)
                ?: return failure(startDate, target, ExportFailureReason.INVALID_API_ENDPOINT)
            val scheme = runCatching { URI(captured.endpointUrl).scheme }.getOrNull()
            if (!scheme.equals("https", ignoreCase = true)) {
                return failure(startDate, target, ExportFailureReason.INVALID_API_ENDPOINT)
            }
            if (expectedDestinationFingerprint != null && expectedDestinationFingerprint != captured.destinationFingerprint) {
                return failure(startDate, target, ExportFailureReason.INVALID_API_ENDPOINT)
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
                failure(startDate, target, ExportFailureReason.RAW_UNSUPPORTED_PROVIDER)
            } else {
                // Only runs explicitly marked interactive may launch Health Connect's per-session
                // exercise route consent UI; every other caller (scheduled exports, the direct
                // CLI protocol, background jobs) reports consent_required routes unchanged.
                val providerExport: suspend () -> ExportResult = {
                    exportProvider(
                        providerId, repository, startDate, endDate, request, settings, target,
                        apiConfiguration,
                    )
                }
                if (allowInteractiveRouteConsent) {
                    withInteractiveRouteConsent { providerExport() }
                } else {
                    providerExport()
                }
            }
            results += result
            if (result.wasCancelled) break
        }
        if (providerIds.size == 1) return results.single()
        return aggregateProviderResults(results, target, providerIds.size)
    }

    override suspend fun previewRange(
        startDate: LocalDate,
        endDate: LocalDate,
        settings: ExportSettings,
        allowInteractiveRouteConsent: Boolean,
    ): ExportPreview {
        val requestedDateCount = selectedDateCount(startDate, endDate)
        if (endDate.isBefore(startDate)) {
            return rawPreviewFailure(
                startDate,
                requestedDateCount,
                ExportFailureReason.UNKNOWN,
                ExportPreviewIssue(ExportPreviewIssueKind.RAW_INVALID_DATE_RANGE),
            )
        }
        if (settings.rawSnapshot.scope == RawSnapshotScope.SELECTED_RECORD_TYPES &&
            settings.metricSelection.enabledMetrics.isEmpty()
        ) {
            return rawPreviewFailure(
                startDate,
                requestedDateCount,
                ExportFailureReason.NO_HEALTH_DATA,
                ExportPreviewIssue(ExportPreviewIssueKind.RAW_SELECTION_REQUIRED),
            )
        }

        val providerIds = selectedProviderIds()
        if (providerIds.isEmpty()) {
            return rawPreviewFailure(
                startDate,
                requestedDateCount,
                ExportFailureReason.RAW_UNSUPPORTED_PROVIDER,
                ExportPreviewIssue(ExportPreviewIssueKind.RAW_PROVIDER_UNAVAILABLE),
            )
        }

        val request = buildRequest(startDate, endDate, ZoneId.systemDefault(), settings)
        val files = mutableListOf<ExportPreviewFile>()
        val issues = mutableListOf<ExportPreviewIssue>()
        var firstFailure: ExportFailureReason? = null

        for (providerId in providerIds) {
            val repository = rawRepositoryRegistry.repositoryFor(providerId)
            if (repository == null) {
                firstFailure = firstFailure ?: ExportFailureReason.RAW_UNSUPPORTED_PROVIDER
                issues += ExportPreviewIssue(ExportPreviewIssueKind.RAW_PROVIDER_UNREGISTERED, providerId)
                continue
            }

            var artifact: File? = null
            try {
                val produce: suspend () -> RawExportResult = { producePreviewArtifact(repository, request, context) }
                val raw = if (allowInteractiveRouteConsent) {
                    withInteractiveRouteConsent { produce() }
                } else {
                    produce()
                }
                artifact = File(raw.finalLocation)
                check(artifact.isFile) { "Completed raw snapshot preview artifact is missing." }
                val bounded = readRawArtifactPreview(artifact)
                val prefix = "healthmd-raw-$providerId-${startDate}_to_${endDate}-schema-v1"
                val relativeDirectory = listOf(
                    settings.subfolder.trim('/').takeIf(String::isNotBlank),
                    RAW_DIRECTORY,
                ).filterNotNull().joinToString("/")
                val displayName = SafRawExportStorage.stableFileName(prefix, raw.snapshotId, raw.format)
                files += ExportPreviewFile(
                    format = ExportFormat.JSON,
                    formatLabel = raw.format.name,
                    relativePath = listOf(relativeDirectory, displayName).filter(String::isNotBlank).joinToString("/"),
                    byteCount = raw.bytesWritten.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                    content = bounded.content,
                    previewOmittedByteCount = bounded.omittedByteCount,
                    previewTailContent = bounded.tailContent,
                )
                when (raw.manifest.status) {
                    RawSnapshotStatus.COMPLETE -> Unit
                    RawSnapshotStatus.PARTIAL -> issues += ExportPreviewIssue(ExportPreviewIssueKind.RAW_PARTIAL, providerId)
                    RawSnapshotStatus.FAILED -> issues += ExportPreviewIssue(ExportPreviewIssueKind.RAW_FAILED_MANIFEST, providerId)
                    else -> issues += ExportPreviewIssue(ExportPreviewIssueKind.RAW_NO_FINAL_STATUS, providerId)
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: SecurityException) {
                firstFailure = firstFailure ?: ExportFailureReason.ACCESS_DENIED
                issues += ExportPreviewIssue(ExportPreviewIssueKind.RAW_ACCESS_DENIED, providerId)
            } catch (_: Exception) {
                firstFailure = firstFailure ?: ExportFailureReason.HEALTH_CONNECT_ERROR
                issues += ExportPreviewIssue(ExportPreviewIssueKind.RAW_PREVIEW_FAILED, providerId)
            } finally {
                artifact?.let(::cleanupPrivateArtifact)
            }
        }

        val day = ExportPreviewDay(
            date = startDate,
            files = files,
            failureReason = firstFailure.takeIf { files.isEmpty() },
            issues = issues,
            requestedDates = if (requestedDateCount > 0) {
                generateSequence(startDate) { date -> date.plusDays(1).takeIf { !it.isAfter(endDate) } }.toList()
            } else {
                emptyList()
            },
        )
        return ExportPreview(
            requestedDateCount = requestedDateCount,
            previewedDateCount = if (files.isEmpty()) 0 else requestedDateCount,
            isTruncated = false,
            days = listOf(day),
            isRangeArtifact = true,
        )
    }

    private suspend fun producePreviewArtifact(
        repository: RawHealthRepository,
        request: RawSnapshotRequest,
        context: Context,
    ): RawExportResult = RawSnapshotExportOrchestrator(
        context,
        repository,
        NoBackupRawExportStorage(context),
    ).export(request)

    private suspend fun selectedProviderIds(): List<String> {
        val selectedProviderId = settingsRepository.getSelectedHealthProviderId()
        return if (selectedProviderId == ALL_CONNECTED_PROVIDER_ID) {
            settingsRepository.getConnectedHealthProviderIds()
                .filterNot { it == ALL_CONNECTED_PROVIDER_ID }
                .distinct()
                .sorted()
        } else {
            listOf(selectedProviderId)
        }
    }

    private fun rawPreviewFailure(
        startDate: LocalDate,
        requestedDateCount: Int,
        reason: ExportFailureReason,
        issue: ExportPreviewIssue,
    ) = ExportPreview(
        requestedDateCount = requestedDateCount,
        previewedDateCount = 0,
        isTruncated = false,
        days = listOf(ExportPreviewDay(startDate, failureReason = reason, issues = listOf(issue))),
        isRangeArtifact = true,
    )

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
    } catch (_: CancellationException) {
        failure(startDate, target, ExportFailureReason.RAW_CANCELLED, cancelled = true)
    } catch (error: RawSnapshotApiException) {
        failure(
            date = startDate,
            target = target,
            reason = if (error.statusCode == null) ExportFailureReason.NETWORK_ERROR else ExportFailureReason.API_REJECTED,
            statusCode = error.statusCode,
        )
    } catch (_: SecurityException) {
        failure(startDate, target, ExportFailureReason.ACCESS_DENIED)
    } catch (_: Exception) {
        failure(
            startDate,
            target,
            if (target == ExportTarget.DEVICE_FOLDER) ExportFailureReason.FILE_WRITE_ERROR else ExportFailureReason.HEALTH_CONNECT_ERROR,
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
            ?: return failure(startDate, ExportTarget.DEVICE_FOLDER, ExportFailureReason.NO_FOLDER_SELECTED)
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
            artifactCount = if (target == ExportTarget.DEVICE_FOLDER) 1 else 0,
        )
        RawSnapshotStatus.FAILED -> failure(
            date,
            target,
            ExportFailureReason.HEALTH_CONNECT_ERROR,
            artifactCount = if (target == ExportTarget.DEVICE_FOLDER) 1 else 0,
        )
        else -> failure(date, target, ExportFailureReason.UNKNOWN)
    }

    private fun failure(
        date: LocalDate,
        target: ExportTarget,
        reason: ExportFailureReason,
        statusCode: Int? = null,
        cancelled: Boolean = false,
        artifactCount: Int = 0,
    ) = ExportResult(
        successCount = 0,
        totalCount = 1,
        failedDateDetails = listOf(FailedDateDetail(date, reason)),
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
        private const val RAW_PREVIEW_MAX_BYTES = 60 * 1024
        private const val RAW_PREVIEW_HEAD_BYTES = 44 * 1024
        private const val RAW_PREVIEW_TAIL_BYTES = 16 * 1024

        private fun selectedDateCount(startDate: LocalDate, endDate: LocalDate): Int {
            if (endDate.isBefore(startDate)) return 0
            return (ChronoUnit.DAYS.between(startDate, endDate) + 1)
                .coerceAtMost(Int.MAX_VALUE.toLong())
                .toInt()
        }

        internal fun readRawArtifactPreview(
            file: File,
            maximumBytes: Int = RAW_PREVIEW_MAX_BYTES,
            headBytes: Int = RAW_PREVIEW_HEAD_BYTES,
            tailBytes: Int = RAW_PREVIEW_TAIL_BYTES,
        ): RawArtifactPreview {
            require(maximumBytes > 0)
            require(headBytes >= 0 && tailBytes >= 0 && headBytes + tailBytes <= maximumBytes)
            val byteCount = file.length()
            if (byteCount <= maximumBytes) {
                return RawArtifactPreview(
                    content = decodeValidUtf8(file.readBytes()),
                    omittedByteCount = 0,
                )
            }

            val headBuffer = ByteArray(headBytes)
            val tailBuffer = ByteArray(tailBytes)
            RandomAccessFile(file, "r").use { input ->
                input.readFully(headBuffer)
                input.seek(byteCount - tailBytes)
                input.readFully(tailBuffer)
            }
            val head = decodeValidUtf8(headBuffer)
            val tail = decodeValidUtf8(tailBuffer)
            val retainedByteCount = head.toByteArray(Charsets.UTF_8).size.toLong() +
                tail.toByteArray(Charsets.UTF_8).size.toLong()
            val omitted = (byteCount - retainedByteCount).coerceAtLeast(0)
            return RawArtifactPreview(
                content = head,
                tailContent = tail,
                omittedByteCount = omitted.coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
            )
        }

        private fun decodeValidUtf8(bytes: ByteArray): String = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.IGNORE)
            .onUnmappableCharacter(CodingErrorAction.IGNORE)
            .decode(ByteBuffer.wrap(bytes))
            .toString()

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
                FailedDateDetail(date, ExportFailureReason.FILE_WRITE_ERROR),
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

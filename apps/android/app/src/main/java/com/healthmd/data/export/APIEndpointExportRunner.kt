package com.healthmd.data.export

import com.healthmd.data.health.isLikelyHealthConnectRateLimit
import com.healthmd.data.isHealthConnectRateLimit
import com.healthmd.domain.exportengine.APIExportEnginePolicyResolver
import com.healthmd.domain.exportengine.APIExportIdSource
import com.healthmd.domain.exportengine.APIExportNativePlanBuilder
import com.healthmd.domain.exportengine.APIExportRustPlanner
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.DEFAULT_API_EXPORT_ID_SOURCE
import com.healthmd.domain.exportengine.ExportArtifactPlan
import com.healthmd.domain.exportengine.ExportArtifactPlanComparator
import com.healthmd.domain.exportengine.ExportCommitBarrier
import com.healthmd.domain.exportengine.ExportCommitState
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.domain.exportengine.ExportEnginePinCompatibilityException
import com.healthmd.domain.exportengine.ExportEnginePolicyTarget
import com.healthmd.domain.exportengine.FrozenAPIExportRequest
import com.healthmd.domain.exportengine.HealthMdRustAPIExportPlanner
import com.healthmd.domain.exportengine.ProductionAPIExportNativePlanBuilder
import com.healthmd.domain.exportengine.ProfileScopedAPIExportEnginePolicyResolver
import com.healthmd.domain.exportengine.ShadowComparisonDiagnostic
import com.healthmd.domain.exportengine.ShadowExportDiagnostic
import com.healthmd.domain.exportengine.ShadowExportDiagnosticSink
import com.healthmd.domain.exportengine.ShadowRustFailureCode
import com.healthmd.domain.exportengine.ShadowRustFailureDiagnostic
import com.healthmd.domain.exportengine.ExportArtifactPlanValidationException
import com.healthmd.domain.exportengine.isFatalExportEngineFailure
import com.healthmd.domain.exportengine.validateAPIPlan
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportPreviewIssue
import com.healthmd.domain.model.ExportPreviewIssueKind
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.repository.HealthRepository
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Collections
import javax.inject.Inject
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One provider capture call for one requested owner date. */
interface APIExportCaptureSource {
    fun isBeforeFirstUnlock(): Boolean

    suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData
}

private class HealthRepositoryAPIExportCaptureSource(
    private val healthRepository: HealthRepository,
) : APIExportCaptureSource {
    override fun isBeforeFirstUnlock(): Boolean = healthRepository.isBeforeFirstUnlock()

    override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData {
        val effectiveSelection = settings.effectiveDataTypeSelection()
        val captured = healthRepository.fetchHealthDataRange(
            dates = listOf(date),
            dataTypes = effectiveSelection,
            includeGranularData = settings.shouldFetchGranularData(),
        ).firstOrNull() ?: HealthData(date)
        val filtered = captured
            .filtered(effectiveSelection)
            .filtered(settings.metricSelection)
        if (filtered.hasAnyData) return filtered

        return healthRepository.fetchHealthData(date)
            .filtered(effectiveSelection)
            .filtered(settings.metricSelection)
    }
}

class APIEndpointExportRunner private constructor(
    private val captureSource: APIExportCaptureSource,
    private val envelopeBuilder: APIExportEnvelopeBuilder,
    private val uploader: APIExportUploader,
    private val credentialStore: APIExportCredentialStore,
    private val policyResolver: APIExportEnginePolicyResolver,
    private val nativePlanner: APIExportNativePlanBuilder,
    private val rustPlanner: APIExportRustPlanner,
    private val diagnosticSink: ShadowExportDiagnosticSink,
    private val comparator: ExportArtifactPlanComparator,
    private val idSource: APIExportIdSource,
    private val clock: () -> Instant,
    private val zoneIdProvider: () -> ZoneId,
    private val maxDaysPerBatch: Int,
    private val maxEncodedBytes: ULong,
    private val nonLegacyUploadAttempts: Int,
    private val operationStore: APIExportOperationStore?,
) {
    /** Source-compatible constructor for focused tests and non-Dagger callers. */
    constructor(
        healthRepository: HealthRepository,
        envelopeBuilder: APIExportEnvelopeBuilder,
        @Suppress("UNUSED_PARAMETER") jsonExporter: JsonExporter,
        uploader: APIExportUploader,
        credentialStore: APIExportCredentialStore,
    ) : this(
        captureSource = HealthRepositoryAPIExportCaptureSource(healthRepository),
        envelopeBuilder = envelopeBuilder,
        uploader = uploader,
        credentialStore = credentialStore,
        policyResolver = ProfileScopedAPIExportEnginePolicyResolver(),
        nativePlanner = ProductionAPIExportNativePlanBuilder(envelopeBuilder),
        rustPlanner = HealthMdRustAPIExportPlanner(),
        diagnosticSink = ShadowExportDiagnosticSink { },
        comparator = ExportArtifactPlanComparator(),
        idSource = DEFAULT_API_EXPORT_ID_SOURCE,
        clock = Instant::now,
        zoneIdProvider = ZoneId::systemDefault,
        maxDaysPerBatch = FrozenAPIExportRequest.DEFAULT_MAX_API_BATCH_DAYS,
        maxEncodedBytes = FrozenAPIExportRequest.DEFAULT_MAX_API_BATCH_BYTES,
        nonLegacyUploadAttempts = DEFAULT_NON_LEGACY_UPLOAD_ATTEMPTS,
        operationStore = null,
    )

    /** Production/Dagger constructor adds the app-private durable scheduled-operation store. */
    @Inject
    internal constructor(
        healthRepository: HealthRepository,
        envelopeBuilder: APIExportEnvelopeBuilder,
        @Suppress("UNUSED_PARAMETER") jsonExporter: JsonExporter,
        uploader: APIExportUploader,
        credentialStore: APIExportCredentialStore,
        operationStore: FileAPIExportOperationStore,
        diagnosticSink: ShadowExportDiagnosticSink,
    ) : this(
        captureSource = HealthRepositoryAPIExportCaptureSource(healthRepository),
        envelopeBuilder = envelopeBuilder,
        uploader = uploader,
        credentialStore = credentialStore,
        policyResolver = ProfileScopedAPIExportEnginePolicyResolver(),
        nativePlanner = ProductionAPIExportNativePlanBuilder(envelopeBuilder),
        rustPlanner = HealthMdRustAPIExportPlanner(),
        diagnosticSink = diagnosticSink,
        comparator = ExportArtifactPlanComparator(),
        idSource = DEFAULT_API_EXPORT_ID_SOURCE,
        clock = Instant::now,
        zoneIdProvider = ZoneId::systemDefault,
        maxDaysPerBatch = FrozenAPIExportRequest.DEFAULT_MAX_API_BATCH_DAYS,
        maxEncodedBytes = FrozenAPIExportRequest.DEFAULT_MAX_API_BATCH_BYTES,
        nonLegacyUploadAttempts = DEFAULT_NON_LEGACY_UPLOAD_ATTEMPTS,
        operationStore = operationStore,
    )

    /** Focused JVM-test seam; credentials remain separate from every planner input. */
    internal constructor(
        captureSource: APIExportCaptureSource,
        envelopeBuilder: APIExportEnvelopeBuilder,
        uploader: APIExportUploader,
        credentialStore: APIExportCredentialStore,
        policyResolver: APIExportEnginePolicyResolver,
        nativePlanner: APIExportNativePlanBuilder,
        rustPlanner: APIExportRustPlanner,
        diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
        comparator: ExportArtifactPlanComparator = ExportArtifactPlanComparator(),
        idSource: APIExportIdSource = DEFAULT_API_EXPORT_ID_SOURCE,
        clock: () -> Instant = Instant::now,
        zoneIdProvider: () -> ZoneId = ZoneId::systemDefault,
        maxDaysPerBatch: Int = FrozenAPIExportRequest.DEFAULT_MAX_API_BATCH_DAYS,
        maxEncodedBytes: ULong = FrozenAPIExportRequest.DEFAULT_MAX_API_BATCH_BYTES,
        nonLegacyUploadAttempts: Int = DEFAULT_NON_LEGACY_UPLOAD_ATTEMPTS,
        operationStore: APIExportOperationStore? = null,
        @Suppress("UNUSED_PARAMETER") testSeam: Unit = Unit,
    ) : this(
        captureSource = captureSource,
        envelopeBuilder = envelopeBuilder,
        uploader = uploader,
        credentialStore = credentialStore,
        policyResolver = policyResolver,
        nativePlanner = nativePlanner,
        rustPlanner = rustPlanner,
        diagnosticSink = diagnosticSink,
        comparator = comparator,
        idSource = idSource,
        clock = clock,
        zoneIdProvider = zoneIdProvider,
        maxDaysPerBatch = maxDaysPerBatch,
        maxEncodedBytes = maxEncodedBytes,
        nonLegacyUploadAttempts = nonLegacyUploadAttempts,
        operationStore = operationStore,
    )

    suspend fun exportDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
        expectedDestinationFingerprint: String? = null,
        durableOperationId: String? = null,
        durableSettingsSnapshotJson: String? = null,
    ): ExportResult {
        val normalizedDates = dates.distinct().sorted()
        if (normalizedDates.isEmpty()) {
            return ExportResult(0, 0, target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT)
        }
        val frozenSettings = settings.frozenForAPIAction()
        if (frozenSettings.selectedExportFormats.isEmpty()) {
            return configurationFailure(normalizedDates, ExportFailureReason.UNKNOWN)
        }
        val endpoint = APIExportEndpoint.normalizedOrNull(frozenSettings.apiEndpointUrl)
            ?: return configurationFailure(normalizedDates, ExportFailureReason.INVALID_API_ENDPOINT)

        // Resolve exactly once, before the first provider call. A malformed/wrong-profile answer
        // fails closed to the byte-compatible legacy implementation.
        val resolvedMode = resolveModeOnce(normalizedDates, frozenSettings)
        val requestConfiguration = credentialStore.requestConfiguration(endpoint)?.frozenCopy()
            ?: return configurationFailure(normalizedDates, ExportFailureReason.INVALID_API_ENDPOINT)
        if (expectedDestinationFingerprint != null &&
            requestConfiguration.destinationFingerprint != expectedDestinationFingerprint
        ) {
            return configurationFailure(normalizedDates, ExportFailureReason.INVALID_API_ENDPOINT)
        }

        val enginePinJson = frozenSettings.executionEnginePin?.let(ExportEnginePinCodec::encodeCanonical)
        if (durableOperationId != null) {
            val store = operationStore ?: return preparationFailure(normalizedDates)
            val existing = try {
                store.load(durableOperationId)
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return preparationFailure(normalizedDates)
            }
            if (existing != null) {
                val unresolvedDates = existing.batches.drop(existing.acknowledgedBatchCount)
                    .flatMap { it.ownerDates }
                if ((existing.requestedDates != normalizedDates && unresolvedDates != normalizedDates) ||
                    existing.destinationFingerprint != requestConfiguration.destinationFingerprint ||
                    existing.mode != resolvedMode || existing.enginePinJson != enginePinJson ||
                    existing.settingsSnapshotJson != durableSettingsSnapshotJson
                ) {
                    return preparationFailure(normalizedDates)
                }
                return commitDurable(
                    operation = existing,
                    requestConfiguration = requestConfiguration,
                    invocationDates = normalizedDates,
                )
            }
        }

        val snapshot = OperationSnapshot(
            mode = resolvedMode,
            settings = frozenSettings,
            calendarTimeZone = frozenSettings.executionEnginePin?.ianaTimeZone ?: zoneIdProvider().id,
            exportedAt = clock(),
            ids = idSource.next(),
        )
        val capture = captureDates(normalizedDates, snapshot.settings, onProgress)
        if (capture.wasCancelled) {
            return cancelledResult(normalizedDates, capture.failedDateDetails)
        }
        if (snapshot.mode == ExportEngineMode.legacy && capture.records.isEmpty()) {
            return noRecordResult(normalizedDates, capture.failedDateDetails)
        }

        val request = try {
            FrozenAPIExportRequest.capture(
                requestedDates = normalizedDates,
                records = capture.records,
                failedDateDetails = capture.failedDateDetails,
                settings = snapshot.settings,
                mode = snapshot.mode,
                ids = snapshot.ids,
                calendarTimeZone = snapshot.calendarTimeZone,
                exportedAt = snapshot.exportedAt,
                maxDaysPerBatch = maxDaysPerBatch,
                maxEncodedBytes = maxEncodedBytes,
            )
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return preparationFailure(normalizedDates)
        }
        val prepared = prepare(request) ?: return preparationFailure(normalizedDates)
        val validated = try {
            validatePreparedPlan(prepared, request)
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return preparationFailure(normalizedDates)
        }

        if (durableOperationId != null) {
            val store = operationStore ?: return preparationFailure(normalizedDates)
            val durable = try {
                DurableAPIExportOperation(
                    operationId = durableOperationId,
                    destinationFingerprint = requestConfiguration.destinationFingerprint,
                    mode = validated.mode,
                    enginePinJson = enginePinJson,
                    settingsSnapshotJson = durableSettingsSnapshotJson,
                    requestedDates = normalizedDates,
                    recordDates = capture.records.mapTo(linkedSetOf(), HealthData::date),
                    captureFailures = capture.failedDateDetails,
                    batches = validated.scopedBodies.mapIndexed { index, (body, ownerDates) ->
                        DurableAPIExportBatch(
                            index = index,
                            relativePath = body.relativePath,
                            ownerDates = ownerDates,
                            bytes = body.bytes,
                        )
                    },
                ).also { store.create(it) }
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return preparationFailure(normalizedDates)
            }
            return commitDurable(durable, requestConfiguration, normalizedDates)
        }

        return commit(
            prepared = validated,
            requestConfiguration = requestConfiguration,
            requestedDates = normalizedDates,
            records = capture.records,
            failedDateDetails = capture.failedDateDetails,
        )
    }

    /** Deletes a fully acknowledged journal only after pending-state reconciliation succeeds. */
    suspend fun discardCompletedDurableOperation(operationId: String) {
        val store = operationStore ?: return
        try {
            val operation = store.load(operationId) ?: return
            if (operation.acknowledgedBatchCount == operation.batches.size) {
                store.delete(operationId)
            }
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            // Cleanup is post-reconciliation. Retaining a completed journal is safer than turning a
            // successful delivery into a new pending operation; a later cleanup may retry deletion.
        }
    }

    suspend fun previewDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        maxPreviewDays: Int = ExportOrchestrator.MAX_PREVIEW_DAYS,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
    ): ExportPreview {
        val normalizedDates = dates.distinct().sortedDescending()
        val previewCandidates = normalizedDates.take(ExportOrchestrator.MAX_PREVIEW_FETCH_ATTEMPTS)
        if (previewCandidates.isEmpty()) {
            return ExportPreview(0, 0, false, emptyList())
        }
        val frozenSettings = settings.frozenForAPIAction()
        // Preview resolves the same authority before capture but intentionally never snapshots
        // credentials and never calls the uploader.
        val mode = resolveModeOnce(previewCandidates.sorted(), frozenSettings)
        val snapshot = OperationSnapshot(
            mode = mode,
            settings = frozenSettings,
            calendarTimeZone = frozenSettings.executionEnginePin?.ianaTimeZone ?: zoneIdProvider().id,
            exportedAt = clock(),
            ids = idSource.next(),
        )
        val capture = captureDates(
            dates = previewCandidates,
            settings = snapshot.settings,
            onProgress = onProgress,
            stopAfterRecordCount = maxPreviewDays.coerceAtLeast(1),
        )
        coroutineContext.ensureActive()
        val attemptedDates = capture.attemptedDates.sorted()
        if (attemptedDates.isEmpty()) {
            return ExportPreview(
                requestedDateCount = normalizedDates.size,
                previewedDateCount = 0,
                isTruncated = normalizedDates.isNotEmpty(),
                days = emptyList(),
            )
        }
        if (snapshot.mode == ExportEngineMode.legacy && capture.records.isEmpty()) {
            return ExportPreview(
                requestedDateCount = normalizedDates.size,
                previewedDateCount = 0,
                isTruncated = normalizedDates.size > capture.attemptedDates.size,
                days = capture.failedDateDetails
                    .filter { it.reason != ExportFailureReason.NO_HEALTH_DATA }
                    .map { ExportPreviewDay(it.date, failureReason = it.reason) },
            )
        }
        val request = try {
            FrozenAPIExportRequest.capture(
                requestedDates = attemptedDates,
                records = capture.records.sortedBy(HealthData::date),
                failedDateDetails = capture.failedDateDetails.sortedBy(FailedDateDetail::date),
                settings = snapshot.settings,
                mode = snapshot.mode,
                ids = snapshot.ids,
                calendarTimeZone = snapshot.calendarTimeZone,
                exportedAt = snapshot.exportedAt,
                maxDaysPerBatch = maxDaysPerBatch,
                maxEncodedBytes = maxEncodedBytes,
            )
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return preparationFailurePreview(normalizedDates, attemptedDates.first())
        }
        val prepared = prepare(request)
            ?: return preparationFailurePreview(normalizedDates, attemptedDates.first())
        val validated = try {
            validatePreparedPlan(prepared, request)
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return preparationFailurePreview(normalizedDates, attemptedDates.first())
        }
        val days = validated.scopedBodies.map { (body, bodyDates) ->
            ExportPreviewDay(
                date = bodyDates.first(),
                files = listOf(
                    ExportPreviewFile(
                        format = ExportFormat.JSON,
                        relativePath = body.relativePath,
                        byteCount = body.bytes.size,
                        content = body.bytes.decodeToString(),
                    ),
                ),
                requestedDates = bodyDates,
            )
        }
        return ExportPreview(
            requestedDateCount = normalizedDates.size,
            previewedDateCount = capture.records.size,
            isTruncated = normalizedDates.size > capture.attemptedDates.size,
            days = days,
        )
    }

    private fun resolveModeOnce(
        dates: List<LocalDate>,
        settings: ExportSettings,
    ): ExportEngineMode {
        settings.executionEnginePin?.let { pin ->
            // Persisted authority never inherits a current rollout default. Structural/profile
            // incompatibility fails during precommit validation rather than downgrading authority.
            return pin.engine
        }
        if (settings.executionEngineAuthorityIsFrozen) {
            return ExportEngineMode.legacy
        }
        val policy = try {
            policyResolver.resolve()
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return ExportEngineMode.legacy
        }
        if (
            policy.profile != AndroidExportProfile.android_frozen_v4 ||
            policy.target != ExportEnginePolicyTarget.API_V1_FROZEN_V4
        ) {
            return ExportEngineMode.legacy
        }
        if (policy.mode != ExportEngineMode.legacy && !dates.areContiguous()) {
            // Render-input v1 describes one closed date range. Sparse history retries stay wholly
            // legacy rather than inventing outcomes for dates the user did not request.
            return ExportEngineMode.legacy
        }
        return policy.mode
    }

    private suspend fun captureDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)?,
        stopAfterRecordCount: Int? = null,
    ): CaptureResult {
        val records = mutableListOf<HealthData>()
        val failures = mutableListOf<FailedDateDetail>()
        val attempted = mutableListOf<LocalDate>()
        for ((index, date) in dates.withIndex()) {
            if (stopAfterRecordCount != null && records.size >= stopAfterRecordCount) break
            try {
                coroutineContext.ensureActive()
            } catch (_: CancellationException) {
                return CaptureResult(records, failures, attempted, wasCancelled = true)
            }
            attempted += date
            onProgress?.invoke(index + 1, dates.size, date.toString())
            if (captureSource.isBeforeFirstUnlock()) {
                failures += FailedDateDetail(date, ExportFailureReason.DEVICE_LOCKED)
                continue
            }
            try {
                val record = captureSource.capture(date, settings)
                if (record.date != date) {
                    failures += FailedDateDetail(date, ExportFailureReason.UNKNOWN)
                } else if (record.hasAnyData) {
                    records += record
                } else {
                    failures += FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA)
                }
            } catch (_: CancellationException) {
                return CaptureResult(records, failures, attempted, wasCancelled = true)
            } catch (error: SecurityException) {
                failures += FailedDateDetail(date, classifySecurityException(error), error.message)
            } catch (error: Exception) {
                failures += FailedDateDetail(date, classifyException(error), error.message)
            }
        }
        return CaptureResult(
            records = records.sortedBy(HealthData::date),
            failedDateDetails = failures.sortedBy(FailedDateDetail::date),
            attemptedDates = attempted,
            wasCancelled = false,
        )
    }

    private suspend fun prepare(request: FrozenAPIExportRequest): PreparedAPIPlan? {
        if (request.mode == ExportEngineMode.legacy) {
            val payload = try {
                envelopeBuilder.build(
                    records = request.records,
                    failedDateDetails = request.failedDateDetails,
                    settings = request.settings,
                    dateRangeStart = request.dateRangeStart,
                    dateRangeEnd = request.dateRangeEnd,
                    exportedAt = request.exportedAt,
                    calendarTimeZone = request.calendarTimeZone,
                )
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return null
            }
            return PreparedAPIPlan(
                mode = ExportEngineMode.legacy,
                bodies = listOf(PreparedAPIBody("POST/api-v1.json", payload.encodeToByteArray())),
            )
        }

        val nativePlan = if (request.mode == ExportEngineMode.shadow) {
            try {
                nativePlanner.plan(request).also { validateAPIPlan(it, request) }
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return null
            }
        } else {
            null
        }
        val rust = try {
            rustPlanner.plan(request).also { result ->
                if (result.pin.engine != request.mode ||
                    result.pin.profile != AndroidExportProfile.android_frozen_v4
                ) {
                    throw ExportArtifactPlanValidationException(
                        com.healthmd.domain.exportengine.ExportArtifactPlanValidationIssue.PROFILE,
                    )
                }
                validateAPIPlan(result.plan, request)
            }
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            if (request.mode == ExportEngineMode.shadow) {
                emitSafely(
                    ShadowRustFailureDiagnostic(
                        profile = AndroidExportProfile.android_frozen_v4,
                        semanticProfileRevision = ExportEnginePin.EXPECTED_SEMANTIC_PROFILE_REVISION,
                        renderProfileRevision = HealthMdCoreServiceRevision.renderProfileRevision,
                        code = error.toShadowFailureCode(),
                    ),
                )
                return PreparedAPIPlan.fromArtifactPlan(
                    ExportEngineMode.shadow,
                    checkNotNull(nativePlan) { "shadow native API plan was not captured" },
                )
            }
            // Rust authority fails closed before any HTTP side effect. There is no legacy fallback.
            return null
        }

        return when (request.mode) {
            ExportEngineMode.legacy -> null
            ExportEngineMode.rust -> PreparedAPIPlan.fromArtifactPlan(request.mode, rust.plan)
            ExportEngineMode.shadow -> {
                val shadowNativePlan = checkNotNull(nativePlan) {
                    "shadow native API plan was not captured"
                }
                emitSafely(
                    ShadowComparisonDiagnostic(
                        profile = AndroidExportProfile.android_frozen_v4,
                        semanticProfileRevision = rust.pin.semanticProfileRevision,
                        renderProfileRevision = rust.pin.renderProfileRevision,
                        comparison = comparator.compare(shadowNativePlan, rust.plan),
                    ),
                )
                PreparedAPIPlan.fromArtifactPlan(request.mode, shadowNativePlan)
            }
        }
    }

    private suspend fun commitDurable(
        operation: DurableAPIExportOperation,
        requestConfiguration: APIExportRequestConfiguration,
        invocationDates: List<LocalDate>,
    ): ExportResult {
        val store = operationStore ?: return preparationFailure(operation.requestedDates)
        var frontier = operation.acknowledgedBatchCount
        var lastStatusCode: Int? = null
        try {
            while (frontier < operation.batches.size) {
                coroutineContext.ensureActive()
                val batch = operation.batches[frontier]
                val attempts = if (operation.mode == ExportEngineMode.legacy) {
                    1
                } else {
                    nonLegacyUploadAttempts.coerceAtLeast(1)
                }
                val upload = uploadPreparedBody(
                    body = PreparedAPIBody(batch.relativePath, batch.bytes),
                    requestConfiguration = requestConfiguration,
                    maxAttempts = attempts,
                )
                lastStatusCode = upload.statusCode
                // Acknowledgement is persisted before the next body. If the process dies after the
                // server response but before this commit, the exact same body is retransmitted;
                // arbitrary HTTP endpoints cannot provide stronger than at-least-once delivery.
                store.acknowledge(operation.operationId, frontier)
                frontier += 1
            }
            return durableResult(
                operation,
                frontier,
                invocationDates,
                lastStatusCode = lastStatusCode,
            )
        } catch (_: CancellationException) {
            return durableResult(
                operation = operation,
                frontier = frontier,
                invocationDates = invocationDates,
                unresolvedReason = ExportFailureReason.NETWORK_ERROR,
                unresolvedDetails = null,
                lastStatusCode = lastStatusCode,
                wasCancelled = true,
            )
        } catch (error: APIExportClientException) {
            val safeDetails = error.statusCode?.let { "HTTP $it" }
            return durableResult(
                operation = operation,
                frontier = frontier,
                invocationDates = invocationDates,
                unresolvedReason = error.failureReason,
                unresolvedDetails = safeDetails,
                lastStatusCode = error.statusCode,
            )
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            return durableResult(
                operation = operation,
                frontier = frontier,
                invocationDates = invocationDates,
                unresolvedReason = ExportFailureReason.NETWORK_ERROR,
                unresolvedDetails = null,
                lastStatusCode = lastStatusCode,
            )
        }
    }

    private fun durableResult(
        operation: DurableAPIExportOperation,
        frontier: Int,
        invocationDates: List<LocalDate>,
        unresolvedReason: ExportFailureReason = ExportFailureReason.NETWORK_ERROR,
        unresolvedDetails: String? = null,
        lastStatusCode: Int? = null,
        wasCancelled: Boolean = false,
    ): ExportResult {
        val invocationSet = invocationDates.toSet()
        val acknowledgedDates = operation.batches.take(frontier)
            .flatMapTo(linkedSetOf()) { it.ownerDates }
            .filterTo(linkedSetOf()) { it in invocationSet }
        val unresolvedDates = operation.batches.drop(frontier)
            .flatMapTo(linkedSetOf()) { it.ownerDates }
            .filterTo(linkedSetOf()) { it in invocationSet }
        val acknowledgedCaptureFailures = operation.captureFailures.filter {
            it.date in acknowledgedDates
        }.map { it.copy(errorDetails = null) }
        val unresolvedFailures = unresolvedDates.map {
            FailedDateDetail(it, unresolvedReason, unresolvedDetails)
        }
        return ExportResult(
            successCount = operation.recordDates.count { it in acknowledgedDates },
            totalCount = invocationDates.size,
            failedDateDetails = acknowledgedCaptureFailures + unresolvedFailures,
            wasCancelled = wasCancelled,
            target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT,
            httpStatusCode = lastStatusCode,
            retryOperationIds = unresolvedDates.associateWith { operation.operationId },
            freshCaptureRetryDates = acknowledgedCaptureFailures.mapTo(linkedSetOf()) { it.date },
        )
    }

    private suspend fun commit(
        prepared: ValidatedPreparedAPIPlan,
        requestConfiguration: APIExportRequestConfiguration,
        requestedDates: List<LocalDate>,
        records: List<HealthData>,
        failedDateDetails: List<FailedDateDetail>,
    ): ExportResult {
        val barrier = ExportCommitBarrier()
        barrier.markMaterialized()
        var lastStatusCode: Int? = null
        try {
            coroutineContext.ensureActive()
            // Every body was rendered, validated, and defensively copied before this transition.
            barrier.markCommitting()
            for (body in prepared.bodies) {
                coroutineContext.ensureActive()
                val attempts = if (prepared.mode == ExportEngineMode.legacy) {
                    1
                } else {
                    nonLegacyUploadAttempts.coerceAtLeast(1)
                }
                val result = uploadPreparedBody(
                    body = body,
                    requestConfiguration = requestConfiguration,
                    maxAttempts = attempts,
                )
                lastStatusCode = result.statusCode
            }
            barrier.markCompleted()
            return ExportResult(
                successCount = records.size,
                totalCount = requestedDates.size,
                failedDateDetails = failedDateDetails.map { it.copy(errorDetails = null) },
                target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT,
                httpStatusCode = lastStatusCode,
            )
        } catch (_: CancellationException) {
            barrier.failIfOpen()
            return cancelledResult(requestedDates, failedDateDetails)
        } catch (error: APIExportClientException) {
            barrier.failIfOpen()
            val safeDetails = error.statusCode?.let { "HTTP $it" }
            return uploadFailure(
                requestedDates,
                error.failureReason,
                safeDetails,
                error.statusCode,
            )
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            barrier.failIfOpen()
            return uploadFailure(
                requestedDates,
                ExportFailureReason.NETWORK_ERROR,
                null,
            )
        }
    }

    private suspend fun uploadPreparedBody(
        body: PreparedAPIBody,
        requestConfiguration: APIExportRequestConfiguration,
        maxAttempts: Int,
    ): APIExportUploadResult {
        var attempt = 1
        while (true) {
            try {
                return uploader.upload(
                    endpointUrl = requestConfiguration.endpointUrl,
                    payload = body.bytes.decodeToString(),
                    authorizationHeader = requestConfiguration.authorizationHeader,
                    requestHeaders = requestConfiguration.requestHeaders,
                )
            } catch (error: APIExportClientException) {
                if (!error.retryable || attempt >= maxAttempts) throw error
                attempt += 1
                // Retry the same already-prepared immutable body; never invoke either planner.
            }
        }
    }

    /**
     * Validates the selected public envelopes once before preview, durable journal creation, or a
     * foreground POST can consume them. This is deliberately stricter than artifact-plan shape:
     * ranges must partition the exact captured scope and records/failures must represent every
     * captured outcome exactly once. It never logs payload-derived validation details.
     */
    private fun validatePreparedPlan(
        prepared: PreparedAPIPlan,
        request: FrozenAPIExportRequest,
    ): ValidatedPreparedAPIPlan {
        val expectedRecordDates = request.records.map(HealthData::date)
        val expectedFailures = request.failedDateDetails.associateBy(FailedDateDetail::date)
        val calendarZone = ZoneId.of(request.calendarTimeZone)
        var cursor = 0
        val scoped = prepared.bodies.map { body ->
            val bytes = body.bytes
            val content = bytes.decodeToString()
            require(content.encodeToByteArray().contentEquals(bytes)) {
                "API body is not canonical UTF-8"
            }
            val root = Json.parseToJsonElement(content).jsonObject
            require(root.getValue("schema").jsonPrimitive.content == APIExportEnvelopeBuilder.API_EXPORT_SCHEMA)
            require(
                root.getValue("schema_version").jsonPrimitive.int ==
                    APIExportEnvelopeBuilder.API_EXPORT_SCHEMA_VERSION,
            )
            require(root.getValue("daily_record_schema").jsonPrimitive.content == HealthMdExportSchema.IDENTIFIER)
            require(
                root.getValue("daily_record_schema_version").jsonPrimitive.int ==
                    HealthMdExportSchema.VERSION,
            )
            require(root.getValue("exported_at").jsonPrimitive.content == request.exportedAt.toString())
            require(root.getValue("source").jsonPrimitive.content == "android")

            val dateRange = root.getValue("date_range").jsonObject
            val start = LocalDate.parse(dateRange.getValue("start").jsonPrimitive.content)
            val end = LocalDate.parse(dateRange.getValue("end").jsonPrimitive.content)
            require(cursor < request.requestedDates.size && request.requestedDates[cursor] == start) {
                "API body range is not contiguous with the captured scope"
            }
            val endIndex = (cursor until request.requestedDates.size).firstOrNull {
                request.requestedDates[it] == end
            } ?: -1
            require(endIndex >= cursor) { "API body range is outside the captured scope" }
            val ownerDates = request.requestedDates.subList(cursor, endIndex + 1).toList()
            if (prepared.mode != ExportEngineMode.legacy) {
                require(ownerDates.size <= request.maxDaysPerBatch)
                require(bytes.size.toULong() <= request.maxEncodedBytes || ownerDates.size == 1) {
                    "API body exceeds the configured batch bound"
                }
            }

            val records = root.getValue("records").jsonArray
            require(root.getValue("record_count").jsonPrimitive.int == records.size)
            val recordDates = records.map { element ->
                val record = element.jsonObject
                require(record.getValue("schema").jsonPrimitive.content == HealthMdExportSchema.IDENTIFIER)
                require(
                    record.getValue("schema_version").jsonPrimitive.int ==
                        HealthMdExportSchema.VERSION,
                )
                val timeContext = record.getValue("time_context").jsonObject
                require(
                    timeContext.getValue("calendar_timezone").jsonPrimitive.content ==
                        request.calendarTimeZone,
                )
                LocalDate.parse(record.getValue("date").jsonPrimitive.content)
            }
            val failures = root.getValue("failed_date_details").jsonArray
            val failureDates = failures.map { element ->
                val failure = element.jsonObject
                val timestamp = Instant.parse(failure.getValue("date").jsonPrimitive.content)
                val ownerDate = timestamp.atZone(calendarZone).toLocalDate()
                val expected = requireNotNull(expectedFailures[ownerDate]) {
                    "API body contains an unexpected failed owner date"
                }
                require(
                    failure.getValue("date").jsonPrimitive.content ==
                        APIExportEnvelopeBuilder.failureTimestamp(
                            ownerDate,
                            request.calendarTimeZone,
                        ),
                )
                require(
                    failure.getValue("reason").jsonPrimitive.content ==
                        APIExportEnvelopeBuilder.failureReasonWireValue(expected.reason),
                )
                val expectedDetails = expected.errorDetails?.takeIf(String::isNotBlank)
                require(failure["errorDetails"]?.jsonPrimitive?.contentOrNull == expectedDetails)
                ownerDate
            }
            require(recordDates.distinct().size == recordDates.size)
            require(failureDates.distinct().size == failureDates.size)
            require(recordDates.toSet().intersect(failureDates.toSet()).isEmpty())
            require(
                recordDates == ownerDates.filter { it in expectedRecordDates },
            )
            require(
                failureDates == ownerDates.filter { it in expectedFailures },
            )
            require((recordDates + failureDates).sorted() == ownerDates)

            cursor = endIndex + 1
            body to ownerDates
        }
        require(cursor == request.requestedDates.size) {
            "API bodies do not cover the captured scope"
        }
        return ValidatedPreparedAPIPlan(prepared.mode, scoped)
    }

    private fun emitSafely(diagnostic: ShadowExportDiagnostic) {
        try {
            diagnosticSink.emit(diagnostic)
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            // Typed health-free diagnostics are strictly non-authoritative.
        }
    }

    private fun configurationFailure(
        dates: List<LocalDate>,
        reason: ExportFailureReason,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.map { FailedDateDetail(it, reason) },
        target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT,
    )

    private fun preparationFailure(dates: List<LocalDate>): ExportResult = configurationFailure(
        dates = dates,
        reason = ExportFailureReason.UNKNOWN,
    )

    private fun preparationFailurePreview(
        requestedDates: List<LocalDate>,
        failureDate: LocalDate,
    ): ExportPreview = ExportPreview(
        requestedDateCount = requestedDates.size,
        previewedDateCount = 0,
        isTruncated = requestedDates.size > 1,
        days = listOf(
            ExportPreviewDay(
                date = failureDate,
                failureReason = ExportFailureReason.UNKNOWN,
                issues = listOf(ExportPreviewIssue(ExportPreviewIssueKind.API_PREPARATION_FAILED)),
            ),
        ),
    )

    private fun noRecordResult(
        normalizedDates: List<LocalDate>,
        failures: List<FailedDateDetail>,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = normalizedDates.size,
        failedDateDetails = failures.map { it.copy(errorDetails = null) }.ifEmpty {
            listOf(FailedDateDetail(normalizedDates.first(), ExportFailureReason.NO_HEALTH_DATA))
        },
        target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT,
    )

    private fun cancelledResult(
        dates: List<LocalDate>,
        failures: List<FailedDateDetail>,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = failures.map { it.copy(errorDetails = null) },
        wasCancelled = true,
        target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT,
    )

    private fun uploadFailure(
        dates: List<LocalDate>,
        reason: ExportFailureReason,
        details: String?,
        statusCode: Int? = null,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.map { FailedDateDetail(it, reason, details) },
        target = com.healthmd.domain.model.ExportTarget.API_ENDPOINT,
        httpStatusCode = statusCode,
    )

    private fun classifySecurityException(error: SecurityException): ExportFailureReason {
        val message = error.message.orEmpty()
        return when {
            message.contains("rate limit", ignoreCase = true) ||
                message.contains("too many requests", ignoreCase = true) ||
                message.contains("quota", ignoreCase = true) -> ExportFailureReason.RATE_LIMITED
            message.contains("background", ignoreCase = true) ->
                ExportFailureReason.BACKGROUND_PERMISSION_DENIED
            message.contains("permission", ignoreCase = true) ||
                message.contains("denied", ignoreCase = true) ||
                message.contains("access", ignoreCase = true) -> ExportFailureReason.ACCESS_DENIED
            else -> ExportFailureReason.DEVICE_LOCKED
        }
    }

    private fun classifyException(error: Exception): ExportFailureReason = when {
        error.isHealthConnectRateLimit() || error.isLikelyHealthConnectRateLimit() ->
            ExportFailureReason.RATE_LIMITED
        error.message.orEmpty().contains("Health Connect", ignoreCase = true) ->
            ExportFailureReason.HEALTH_CONNECT_ERROR
        else -> ExportFailureReason.UNKNOWN
    }

    private data class OperationSnapshot(
        val mode: ExportEngineMode,
        val settings: ExportSettings,
        val calendarTimeZone: String,
        val exportedAt: Instant,
        val ids: com.healthmd.domain.exportengine.APIExportIds,
    )

    private data class CaptureResult(
        val records: List<HealthData>,
        val failedDateDetails: List<FailedDateDetail>,
        val attemptedDates: List<LocalDate>,
        val wasCancelled: Boolean,
    )

    private class PreparedAPIBody(
        val relativePath: String,
        bytes: ByteArray,
    ) {
        private val storedBytes = bytes.copyOf()
        val bytes: ByteArray get() = storedBytes.copyOf()
    }

    private class PreparedAPIPlan(
        val mode: ExportEngineMode,
        bodies: List<PreparedAPIBody>,
    ) {
        val bodies: List<PreparedAPIBody> = Collections.unmodifiableList(bodies.toList())

        init {
            require(this.bodies.isNotEmpty()) { "API export plan is empty" }
        }

        companion object {
            fun fromArtifactPlan(
                mode: ExportEngineMode,
                plan: ExportArtifactPlan,
            ): PreparedAPIPlan = PreparedAPIPlan(
                mode = mode,
                bodies = plan.items.map { item ->
                    PreparedAPIBody(item.relativePath, item.content)
                },
            )
        }
    }

    private class ValidatedPreparedAPIPlan(
        val mode: ExportEngineMode,
        scopedBodies: List<Pair<PreparedAPIBody, List<LocalDate>>>,
    ) {
        val scopedBodies: List<Pair<PreparedAPIBody, List<LocalDate>>> =
            Collections.unmodifiableList(
                scopedBodies.map { (body, ownerDates) ->
                    body to Collections.unmodifiableList(ownerDates.toList())
                },
            )
        val bodies: List<PreparedAPIBody> =
            Collections.unmodifiableList(this.scopedBodies.map { it.first })

        init {
            require(this.scopedBodies.isNotEmpty()) { "Validated API export plan is empty" }
        }
    }

    private object HealthMdCoreServiceRevision {
        const val renderProfileRevision: UInt = 2u
    }

    companion object {
        private const val DEFAULT_NON_LEGACY_UPLOAD_ATTEMPTS = 2
    }
}

private fun ExportSettings.frozenForAPIAction(): ExportSettings = copy(
    exportFormats = Collections.unmodifiableSet(exportFormats.toSet()),
    metricSelection = MetricSelectionState(
        Collections.unmodifiableSet(metricSelection.enabledMetrics.toSet()),
    ),
    individualTracking = individualTracking.copy(
        enabledMetrics = Collections.unmodifiableSet(individualTracking.enabledMetrics.toSet()),
        metricConfigs = Collections.unmodifiableMap(individualTracking.metricConfigs.toMap()),
    ),
    formatCustomization = formatCustomization.copy(
        frontmatterConfig = formatCustomization.frontmatterConfig.copy(
            fields = Collections.unmodifiableList(
                formatCustomization.frontmatterConfig.fields.map { it.copy() },
            ),
            customFields = Collections.unmodifiableMap(
                formatCustomization.frontmatterConfig.customFields.toMap(),
            ),
            placeholderFields = Collections.unmodifiableList(
                formatCustomization.frontmatterConfig.placeholderFields.toList(),
            ),
        ),
        markdownTemplate = formatCustomization.markdownTemplate.copy(),
    ),
)

private fun APIExportRequestConfiguration.frozenCopy(): APIExportRequestConfiguration = copy(
    requestHeaders = Collections.unmodifiableList(requestHeaders.map(APIExportRequestHeader::copy)),
)

private fun List<LocalDate>.areContiguous(): Boolean =
    zipWithNext().all { (left, right) -> left.plusDays(1) == right }

private fun ExportCommitBarrier.failIfOpen() {
    if (state == ExportCommitState.planned ||
        state == ExportCommitState.materialized ||
        state == ExportCommitState.committing
    ) {
        markFailed()
    }
}

private fun Throwable.toShadowFailureCode(): ShadowRustFailureCode = when (this) {
    is ExportEnginePinCompatibilityException -> ShadowRustFailureCode.PIN_INCOMPATIBLE
    is ExportArtifactPlanValidationException -> ShadowRustFailureCode.INVALID_PLAN
    is LinkageError -> ShadowRustFailureCode.CORE_UNAVAILABLE
    else -> ShadowRustFailureCode.RENDER_FAILED
}

private fun rethrowCancellationOrFatal(error: Throwable) {
    if (error is CancellationException || error.isFatalExportEngineFailure()) throw error
}

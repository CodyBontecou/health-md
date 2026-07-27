package com.healthmd.domain.exportengine

import com.healthmd.core.HealthMdCoreService
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.render.HealthMdRenderInputAdapter
import com.healthmd.domain.semantic.HealthMdSemanticInputAdapter
import com.healthmd.domain.semantic.HealthMdSemanticSessionRunner
import java.time.Instant
import java.time.LocalDate
import java.util.Collections
import java.util.UUID
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Stable request/session identity shared by the native and Rust API-v1 plans. */
data class APIExportIds(
    val requestId: String,
    val sessionId: String,
)

fun interface APIExportIdSource {
    fun next(): APIExportIds
}

/** Small injectable seam over the profile-scoped API-v1 policy resolver. */
fun interface APIExportEnginePolicyResolver {
    fun resolve(): ResolvedExportEnginePolicy
}

class ProfileScopedAPIExportEnginePolicyResolver(
    private val resolver: ExportEnginePolicyResolver = ExportEnginePolicyResolver(),
) : APIExportEnginePolicyResolver {
    override fun resolve(): ResolvedExportEnginePolicy = resolver.resolveApiV1()
}

/**
 * Immutable post-capture input for both API planners. Destination URLs, headers, credentials, and
 * their fingerprint deliberately do not cross this boundary.
 */
class FrozenAPIExportRequest private constructor(
    requestedDates: List<LocalDate>,
    records: List<HealthData>,
    failedDateDetails: List<FailedDateDetail>,
    val settings: ExportSettings,
    val mode: ExportEngineMode,
    val ids: APIExportIds,
    val calendarTimeZone: String,
    val exportedAt: Instant,
    val maxDaysPerBatch: Int,
    val maxEncodedBytes: ULong,
    val suppliedPin: ExportEnginePin?,
) {
    val profile: AndroidExportProfile = AndroidExportProfile.android_frozen_v4
    val requestedDates: List<LocalDate> =
        Collections.unmodifiableList(requestedDates.toList())
    val records: List<HealthData> = Collections.unmodifiableList(records.toList())
    val failedDateDetails: List<FailedDateDetail> =
        Collections.unmodifiableList(failedDateDetails.map { it.copy() })
    val dateRangeStart: LocalDate = this.requestedDates.first()
    val dateRangeEnd: LocalDate = this.requestedDates.last()

    init {
        require(this.requestedDates.isNotEmpty()) { "API export date scope is empty" }
        require(this.requestedDates == this.requestedDates.distinct().sorted()) {
            "API export date scope is invalid"
        }
        require(maxDaysPerBatch in 1..MAX_API_BATCH_DAYS) { "API export day bound is invalid" }
        require(maxEncodedBytes > 0uL) { "API export byte bound is invalid" }
        val recordDates = this.records.map(HealthData::date)
        val failureDates = this.failedDateDetails.map(FailedDateDetail::date)
        require(recordDates.distinct().size == recordDates.size) { "API export records are invalid" }
        require(failureDates.distinct().size == failureDates.size) { "API export failures are invalid" }
        require(recordDates.toSet().intersect(failureDates.toSet()).isEmpty()) {
            "API export outcomes are invalid"
        }
        require((recordDates + failureDates).sorted() == this.requestedDates) {
            "API export outcomes do not cover the date scope"
        }
        require(this.records == this.records.sortedBy(HealthData::date)) {
            "API export records are out of order"
        }
        require(this.failedDateDetails == this.failedDateDetails.sortedBy(FailedDateDetail::date)) {
            "API export failures are out of order"
        }
    }

    companion object {
        const val MAX_API_BATCH_DAYS = 7
        const val DEFAULT_MAX_API_BATCH_DAYS = 7
        const val DEFAULT_MAX_API_BATCH_BYTES: ULong = 8_388_608uL

        fun capture(
            requestedDates: List<LocalDate>,
            records: List<HealthData>,
            failedDateDetails: List<FailedDateDetail>,
            settings: ExportSettings,
            mode: ExportEngineMode,
            ids: APIExportIds,
            calendarTimeZone: String,
            exportedAt: Instant,
            maxDaysPerBatch: Int = DEFAULT_MAX_API_BATCH_DAYS,
            maxEncodedBytes: ULong = DEFAULT_MAX_API_BATCH_BYTES,
        ): FrozenAPIExportRequest = FrozenAPIExportRequest(
            requestedDates = requestedDates,
            records = records,
            failedDateDetails = failedDateDetails,
            settings = settings,
            mode = mode,
            ids = ids.copy(),
            calendarTimeZone = calendarTimeZone,
            exportedAt = exportedAt,
            maxDaysPerBatch = maxDaysPerBatch,
            maxEncodedBytes = maxEncodedBytes,
            suppliedPin = settings.executionEnginePin,
        )
    }
}

fun interface APIExportNativePlanBuilder {
    fun plan(request: FrozenAPIExportRequest): ExportArtifactPlan
}

/** Destination-neutral plan made from the existing Kotlin envelope builder's exact UTF-8 bytes. */
class ProductionAPIExportNativePlanBuilder(
    private val envelopeBuilder: APIExportEnvelopeBuilder,
) : APIExportNativePlanBuilder {
    override fun plan(request: FrozenAPIExportRequest): ExportArtifactPlan {
        val batches = envelopeBuilder.buildBatches(
            requestedDates = request.requestedDates,
            records = request.records,
            failedDateDetails = request.failedDateDetails,
            settings = request.settings,
            exportedAt = request.exportedAt,
            calendarTimeZone = request.calendarTimeZone,
            maxDaysPerBatch = request.maxDaysPerBatch,
            maxEncodedBytes = request.maxEncodedBytes,
        )
        val items = batches.mapIndexed { index, batch ->
            val content = batch.payload.encodeToByteArray()
            val relativePath = apiArtifactPath(request.ids.requestId, index)
            val contentSha256 = sha256Hex(content)
            ExportArtifactPlanItem(
                artifactId = artifactIdHex(
                    requestId = request.ids.requestId,
                    sessionId = request.ids.sessionId,
                    profile = request.profile,
                    relativePath = relativePath,
                    mediaType = API_MEDIA_TYPE,
                    writeMode = ExportArtifactWriteMode.api_post,
                    contentSha256 = contentSha256,
                ),
                relativePath = relativePath,
                mediaType = API_MEDIA_TYPE,
                writeMode = ExportArtifactWriteMode.api_post,
                content = content,
                sha256 = contentSha256,
            )
        }
        return ExportArtifactPlan(
            schema = ExportArtifactPlan.SCHEMA,
            artifactPlanVersion = ExportArtifactPlan.VERSION,
            requestId = request.ids.requestId,
            sessionId = request.ids.sessionId,
            profile = request.profile,
            items = items,
        )
    }
}

data class APIExportRustPlan(
    val pin: ExportEnginePin,
    val plan: ExportArtifactPlan,
)

fun interface APIExportRustPlanner {
    suspend fun plan(request: FrozenAPIExportRequest): APIExportRustPlan
}

/** M4 semantic + M5 render adapter for Android API-v1. All shared-core work stays on Default. */
class HealthMdRustAPIExportPlanner(
    private val coreService: HealthMdCoreService = HealthMdCoreService(),
    private val rustEngine: RustExportEngine = RustExportEngine(coreService),
    private val defaultDispatcher: CoroutineDispatcher = Dispatchers.Default,
) : APIExportRustPlanner {
    override suspend fun plan(request: FrozenAPIExportRequest): APIExportRustPlan =
        withContext(defaultDispatcher) {
            require(request.profile == AndroidExportProfile.android_frozen_v4) {
                "API v1 requires the frozen-v4 profile"
            }
            require(request.mode != ExportEngineMode.legacy) {
                "legacy API work cannot invoke the Rust planner"
            }
            val readiness = coreService.checkReadiness()
            val registry = coreService.getMetricRegistry(request.profile.coreProfile)
            val pin = request.suppliedPin?.also { persisted ->
                val compatibility = ExportEnginePinValidator().validate(persisted, readiness, registry)
                if (!compatibility.isCompatible ||
                    persisted.engine != request.mode ||
                    persisted.profile != request.profile ||
                    persisted.ianaTimeZone != request.calendarTimeZone
                ) {
                    throw ExportEnginePinCompatibilityException(compatibility)
                }
            } ?: ExportEnginePin.create(
                engine = request.mode,
                profile = request.profile,
                ianaTimeZone = request.calendarTimeZone,
                readiness = readiness,
                registry = registry,
            )
            val frozenCustomization = request.settings.formatCustomization.forFrozenApiV4()
            val semanticConfiguration = HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionId = request.ids.sessionId,
                profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
                selection = request.settings.metricSelection,
                registry = registry,
                calendarTimeZone = request.calendarTimeZone,
                retainPlatformExtensions = false,
            )
            val semanticBatches = HealthMdSemanticInputAdapter.boundedBatches(
                sessionId = request.ids.sessionId,
                profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
                healthData = request.records,
                registry = registry,
                converter = frozenCustomization.unitConverter,
                calendarTimeZone = request.calendarTimeZone,
                timeFormat = frozenCustomization.timeFormat,
                includeLegacyAndroidAliases = false,
            ).map { it.bytes }
            val semanticResult = HealthMdSemanticSessionRunner.process(
                configurationBytes = semanticConfiguration,
                batches = semanticBatches,
                service = coreService,
            )
            val render = HealthMdRenderInputAdapter.encode(
                semanticResult = semanticResult,
                registry = registry,
                calendarTimeZone = request.calendarTimeZone,
                options = HealthMdRenderInputAdapter.Options(
                    requestId = request.ids.requestId,
                    formats = listOf("json"),
                    unitSystem = when (frozenCustomization.unitPreference) {
                        UnitPreference.METRIC -> "metric"
                        UnitPreference.IMPERIAL -> "imperial"
                    },
                    includeMetadata = request.settings.includeMetadata,
                    groupByCategory = request.settings.groupByCategory,
                    includePlatformExtensions = false,
                    includeGranularData = request.settings.includeGranularData,
                    rawCaptureStatus = "not_requested",
                    writeMode = "overwrite",
                    api = HealthMdRenderInputAdapter.ApiOptions(
                        envelopeVersion = APIExportEnvelopeBuilder.API_EXPORT_SCHEMA_VERSION,
                        exportedAt = request.exportedAt.toString(),
                        source = "android",
                        dateRangeStart = request.dateRangeStart.toString(),
                        dateRangeEnd = request.dateRangeEnd.toString(),
                        failedDateDetails = request.failedDateDetails.map { failure ->
                            HealthMdRenderInputAdapter.ApiFailureOptions(
                                ownerDate = failure.date.toString(),
                                timestamp = APIExportEnvelopeBuilder.failureTimestamp(
                                    failure.date,
                                    request.calendarTimeZone,
                                ),
                                reason = APIExportEnvelopeBuilder.failureReasonWireValue(failure.reason),
                                errorDetails = failure.errorDetails,
                            )
                        },
                        maxDaysPerBatch = request.maxDaysPerBatch,
                        maxEncodedBytes = request.maxEncodedBytes,
                    ),
                ),
                presentationByOwnerDate = request.records.associateBy { it.date.toString() },
                presentationCustomization = frozenCustomization,
            )
            val fullPlan = rustEngine.render(
                input = ExportRenderInput(
                    pin = pin,
                    requestId = request.ids.requestId,
                    sessionId = request.ids.sessionId,
                    configurationBytes = render.configuration,
                    semanticResultBytes = semanticResult,
                    renderBatches = render.batches,
                ),
                readiness = readiness,
                registry = registry,
            )
            val apiItems = fullPlan.items.filter { it.writeMode == ExportArtifactWriteMode.api_post }
            if (apiItems.isEmpty() || fullPlan.items.any {
                    it.writeMode == ExportArtifactWriteMode.api_post &&
                        (it.mediaType != API_MEDIA_TYPE || !it.relativePath.startsWith("api/"))
                }
            ) {
                throw ExportArtifactPlanValidationException(
                    ExportArtifactPlanValidationIssue.WRITE_MODE,
                )
            }
            APIExportRustPlan(
                pin = pin,
                plan = fullPlan.copy(items = apiItems),
            )
        }
}

internal const val API_MEDIA_TYPE = "application/json"

internal fun apiArtifactPath(requestId: String, batchIndex: Int): String =
    "api/$requestId-${batchIndex.toString().padStart(4, '0')}.json"

internal fun validateAPIPlan(
    plan: ExportArtifactPlan,
    request: FrozenAPIExportRequest,
) {
    if (plan.requestId != request.ids.requestId) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.REQUEST_ID)
    }
    if (plan.sessionId != request.ids.sessionId) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.SESSION_ID)
    }
    if (plan.profile != AndroidExportProfile.android_frozen_v4) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.PROFILE)
    }
    if (plan.items.isEmpty()) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.ARTIFACT_COUNT)
    }
    plan.items.forEachIndexed { index, item ->
        if (item.relativePath != apiArtifactPath(request.ids.requestId, index)) {
            throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.RELATIVE_PATH)
        }
        if (item.mediaType != API_MEDIA_TYPE) {
            throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.MEDIA_TYPE)
        }
        if (item.writeMode != ExportArtifactWriteMode.api_post) {
            throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.WRITE_MODE)
        }
    }
}

internal val DEFAULT_API_EXPORT_ID_SOURCE = APIExportIdSource {
    APIExportIds(
        requestId = UUID.randomUUID().toString(),
        sessionId = UUID.randomUUID().toString(),
    )
}

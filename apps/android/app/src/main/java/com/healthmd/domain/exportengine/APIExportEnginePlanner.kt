package com.healthmd.domain.exportengine

import com.healthmd.core.HealthMdCoreService
import com.healthmd.data.export.frozenForAPIAction
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.AndroidCaptureContext
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
import kotlinx.coroutines.ensureActive
import kotlin.coroutines.coroutineContext
import kotlinx.serialization.json.*

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
    settings: ExportSettings,
    val mode: ExportEngineMode,
    val ids: APIExportIds,
    val calendarTimeZone: String,
    val exportedAt: Instant,
    val maxDaysPerBatch: Int,
    val maxEncodedBytes: ULong,
    val suppliedPin: ExportEnginePin?,
) {
    val settings: ExportSettings = settings.frozenForAPIAction()
    val captureContext: AndroidCaptureContext? = this.settings.executionSleepCaptureContext?.copy()
    val profile: AndroidExportProfile = if (captureContext?.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS ||
        suppliedPin?.profile == AndroidExportProfile.android_sleep_v6) AndroidExportProfile.android_sleep_v6
        else AndroidExportProfile.android_frozen_v4
    val envelopeVersion: Int = if (profile == AndroidExportProfile.android_sleep_v6)
        APIExportEnvelopeBuilder.WAKE_DATE_API_EXPORT_SCHEMA_VERSION else APIExportEnvelopeBuilder.API_EXPORT_SCHEMA_VERSION
    val requestedDates: List<LocalDate> =
        Collections.unmodifiableList(requestedDates.toList())
    val records: List<HealthData> = Collections.unmodifiableList(if (profile == AndroidExportProfile.android_sleep_v6)
            records.map { it.filtered(this.settings.metricSelection, captureContext).immutableWakeDateSource() } else records.toList())
    val failedDateDetails: List<FailedDateDetail> =
        Collections.unmodifiableList(failedDateDetails.map { it.copy() })
    val dateRangeStart: LocalDate = this.requestedDates.first()
    val dateRangeEnd: LocalDate = this.requestedDates.last()

    init {
        require(!this.settings.executionSleepCaptureAuthorityIsFrozen || captureContext != null) {
            "API immutable capture authority is missing"
        }
        require(captureContext == null || captureContext.zoneId.id == calendarTimeZone) {
            "API capture clock is incompatible"
        }
        if (profile == AndroidExportProfile.android_sleep_v6) {
            require(mode == ExportEngineMode.rust && captureContext?.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS &&
                captureContext.exportProfileID == profile.publicProfileId && captureContext.zoneId.id == calendarTimeZone) {
                "API successor capture authority is incompatible"
            }
            require(!this.settings.executionEngineAuthorityIsFrozen || suppliedPin != null) {
                "API successor renderer authority is missing"
            }
        } else {
            require(captureContext == null || captureContext.sleepDayAttribution == SleepDayAttribution.NIGHT_BEGINS) {
                "historical API capture authority is incompatible"
            }
        }
        require(suppliedPin == null || (suppliedPin.profile == profile && suppliedPin.engine == mode &&
            suppliedPin.ianaTimeZone == calendarTimeZone && ExportEnginePinCodec.isStructurallyValid(suppliedPin))) {
            "API renderer authority is incompatible"
        }
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
        require(request.profile == AndroidExportProfile.android_frozen_v4) {
            "Successor API requires the Rust renderer"
        }
        val batches = envelopeBuilder.buildBatches(
            requestedDates = request.requestedDates,
            records = request.records,
            failedDateDetails = request.failedDateDetails,
            settings = request.settings,
            exportedAt = request.exportedAt,
            calendarTimeZone = request.calendarTimeZone,
            maxDaysPerBatch = request.maxDaysPerBatch,
            maxEncodedBytes = request.maxEncodedBytes,
            captureContext = request.captureContext?.takeIf { request.profile == AndroidExportProfile.android_sleep_v6 },
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
            artifactPlanVersion = request.profile.contractVersions.artifactPlan,
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
            if (request.profile == AndroidExportProfile.android_sleep_v6 &&
                request.requestedDates.zipWithNext().any { (first, second) -> first.plusDays(1) != second }) {
                return@withContext planSparseSuccessor(request)
            }
            require(request.profile != AndroidExportProfile.android_analytical_v5) {
                "API requires an explicit supported native profile"
            }
            require(request.mode != ExportEngineMode.legacy) {
                "legacy API work cannot invoke the Rust planner"
            }
            val readiness = coreService.checkReadiness()
            val registry = request.suppliedPin?.let {
                coreService.getMetricRegistryAtAuthority(request.profile.coreProfile, it.registryVersion, it.registrySha256)
            } ?: coreService.getMetricRegistry(request.profile.coreProfile, request.profile.contractVersions.registry)
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
            val wakeDate = request.profile == AndroidExportProfile.android_sleep_v6
            val frozenCustomization = if (wakeDate) request.settings.formatCustomization.copy(
                unitPreference = UnitPreference.METRIC, includeLegacyAndroidAliases = false,
                includeAndroidNativeFields = true)
                else request.settings.formatCustomization.forFrozenApiV4()
            val semanticProfile = if (wakeDate) HealthMdSemanticInputAdapter.Profile.SLEEP_V6
                else HealthMdSemanticInputAdapter.Profile.FROZEN_V4
            val semanticConfiguration = HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionId = request.ids.sessionId,
                profile = semanticProfile,
                selection = request.settings.metricSelection,
                registry = registry,
                calendarTimeZone = request.calendarTimeZone,
                retainPlatformExtensions = false,
                captureContext = request.captureContext,
            )
            val semanticBatches = HealthMdSemanticInputAdapter.boundedBatches(
                sessionId = request.ids.sessionId,
                profile = semanticProfile,
                healthData = request.records,
                registry = registry,
                converter = frozenCustomization.unitConverter,
                calendarTimeZone = request.calendarTimeZone,
                timeFormat = frozenCustomization.timeFormat,
                includeLegacyAndroidAliases = false,
                captureContext = request.captureContext,
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
                    renderProfileRevision = pin.renderProfileRevision,
                    requestId = request.ids.requestId,
                    composeSleepRecordsNatively = wakeDate,
                    composeWorkoutRecordsNatively = wakeDate,
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
                        envelopeVersion = request.envelopeVersion,
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
                presentationByOwnerDate = request.records.associate { it.date.toString() to
                    if (wakeDate) AndroidWakeDateSourceProjection.aggregate(it) else it },
                presentationCustomization = frozenCustomization,
                captureContext = request.captureContext,
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
                plan = if (wakeDate) composeSuccessorAPI(request, fullPlan.copy(items = apiItems), semanticResult)
                    else fullPlan.copy(items = apiItems),
            )
        }

    /** Bind complete native records before applying API batch limits and final artifact identities. */
    private suspend fun composeSuccessorAPI(request: FrozenAPIExportRequest, plan: ExportArtifactPlan,
        semanticResult: ByteArray): ExportArtifactPlan {
        val encoder = Json { prettyPrint = true }
        val envelopes = plan.items.map { Json.parseToJsonElement(it.content.decodeToString()).jsonObject }
        val aggregateRecords = envelopes.flatMap { it.getValue("records").jsonArray }.map { it.jsonObject }
        val aggregates = aggregateRecords.associateBy { it.getValue("date").jsonPrimitive.content }
        require(aggregates.size == aggregateRecords.size && aggregates.keys == request.records.map { it.date.toString() }.toSet())
        val records = request.records.associate { source ->
            source.date to AndroidWakeDateSourceProjection.composeAPIRecord(source, request.settings,
                requireNotNull(request.captureContext), semanticResult, aggregates.getValue(source.date.toString()))
        }
        val failureRecords = envelopes.flatMap { it.getValue("failed_date_details").jsonArray }.map { it.jsonObject }
        val failures = failureRecords.associateBy { it.getValue("date").jsonPrimitive.content }
        require(failures.size == failureRecords.size && failures.keys == request.failedDateDetails.map {
            APIExportEnvelopeBuilder.failureTimestamp(it.date, request.calendarTimeZone) }.toSet())
        fun body(dates: List<LocalDate>): ByteArray {
            val envelope = envelopes.first().toMutableMap()
            envelope["date_range"] = buildJsonObject { put("start", dates.first().toString()); put("end", dates.last().toString()) }
            val daily = dates.mapNotNull(records::get)
            envelope["records"] = JsonArray(daily)
            envelope["record_count"] = JsonPrimitive(daily.size)
            envelope["failed_date_details"] = JsonArray(dates.mapNotNull { date ->
                failures[APIExportEnvelopeBuilder.failureTimestamp(date, request.calendarTimeZone)] })
            return encoder.encodeToString(JsonObject.serializer(), JsonObject(envelope)).encodeToByteArray()
        }
        val items = mutableListOf<ExportArtifactPlanItem>()
        var start = 0
        while (start < request.requestedDates.size) {
            coroutineContext.ensureActive()
            var end = start + 1
            var content = body(request.requestedDates.subList(start, end))
            while (end < minOf(request.requestedDates.size, start + request.maxDaysPerBatch) &&
                content.size.toULong() <= request.maxEncodedBytes) {
                val candidate = body(request.requestedDates.subList(start, end + 1))
                if (candidate.size.toULong() > request.maxEncodedBytes) break
                content = candidate
                end += 1
            }
            val path = apiArtifactPath(request.ids.requestId, items.size)
            val hash = sha256Hex(content)
            items += ExportArtifactPlanItem(artifactIdHex(request.ids.requestId, request.ids.sessionId,
                request.profile, path, API_MEDIA_TYPE, ExportArtifactWriteMode.api_post, hash),
                path, API_MEDIA_TYPE, ExportArtifactWriteMode.api_post, content, sha256 = hash)
            start = end
        }
        return plan.copy(items = items)
    }

    /** Render each requested run without inventing outcomes for omitted retry dates. */
    private suspend fun planSparseSuccessor(request: FrozenAPIExportRequest): APIExportRustPlan {
        val groups = mutableListOf<MutableList<LocalDate>>()
        for (date in request.requestedDates) {
            if (groups.lastOrNull()?.lastOrNull()?.plusDays(1) != date) groups.add(mutableListOf())
            groups.last().add(date)
        }
        val plans = groups.map { dates ->
            val scope = dates.toSet()
            plan(FrozenAPIExportRequest.capture(dates, request.records.filter { it.date in scope },
                request.failedDateDetails.filter { it.date in scope }, request.settings, request.mode,
                request.ids, request.calendarTimeZone, request.exportedAt, request.maxDaysPerBatch,
                request.maxEncodedBytes))
        }
        val pin = plans.first().pin
        require(plans.all { it.pin == pin }) { "API partitions disagree on renderer authority" }
        val items = plans.flatMap { it.plan.items }.mapIndexed { index, item ->
            val path = apiArtifactPath(request.ids.requestId, index)
            ExportArtifactPlanItem(artifactId = artifactIdHex(request.ids.requestId, request.ids.sessionId,
                request.profile, path, item.mediaType, item.writeMode, item.sha256),
                relativePath = path, mediaType = item.mediaType, writeMode = item.writeMode,
                content = item.content, sha256 = item.sha256)
        }
        return APIExportRustPlan(pin, ExportArtifactPlan(ExportArtifactPlan.SCHEMA,
            request.profile.contractVersions.artifactPlan, request.ids.requestId, request.ids.sessionId,
            request.profile, items))
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
    if (plan.profile != request.profile || plan.artifactPlanVersion != request.profile.contractVersions.artifactPlan) {
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

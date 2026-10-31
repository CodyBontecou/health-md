package com.healthmd.domain.exportengine

import com.healthmd.core.HealthMdCoreService
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.render.HealthMdRenderInputAdapter
import com.healthmd.domain.semantic.HealthMdSemanticInputAdapter
import com.healthmd.domain.semantic.HealthMdSemanticSessionRunner
import com.healthmd.rawexport.ExportMode
import java.time.ZoneId
import java.util.Collections
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Request/session IDs are injectable so orchestration and artifact identity are deterministic in tests. */
data class DailyAggregateExportIds(
    val requestId: String,
    val sessionId: String,
)

fun interface DailyAggregateExportIdSource {
    fun next(): DailyAggregateExportIds
}

/** Small testable boundary over the existing profile-scoped policy resolver. */
fun interface LocalExportEnginePolicyResolver {
    fun resolve(profile: AndroidExportProfile): ResolvedExportEnginePolicy
}

class ProfileScopedLocalExportEnginePolicyResolver(
    private val resolver: ExportEnginePolicyResolver = ExportEnginePolicyResolver(),
) : LocalExportEnginePolicyResolver {
    override fun resolve(profile: AndroidExportProfile): ResolvedExportEnginePolicy =
        resolver.resolveLocal(profile)
}

/**
 * Immutable application snapshot of the settings used by one simple daily aggregate attempt.
 * It contains no destination handle and [data] is the one already-captured provider result.
 */
class FrozenDailyAggregateExportRequest private constructor(
    val data: HealthData,
    val profile: AndroidExportProfile,
    val mode: ExportEngineMode,
    val ids: DailyAggregateExportIds,
    formats: List<ExportFormat>,
    relativePaths: Map<ExportFormat, String>,
    val aggregateSubfolder: String?,
    val baseName: String,
    val includeMetadata: Boolean,
    val groupByCategory: Boolean,
    val customization: FormatCustomization,
    val metricSelection: MetricSelectionState,
    val includeGranularData: Boolean,
    val suppliedPin: ExportEnginePin?,
    val captureContext: AndroidCaptureContext?,
) {
    val formats: List<ExportFormat> = Collections.unmodifiableList(formats.toList())
    private val storedRelativePaths: Map<ExportFormat, String> =
        Collections.unmodifiableMap(relativePaths.toMap())

    fun relativePath(format: ExportFormat): String =
        storedRelativePaths.getValue(format)

    companion object {
        fun capture(
            data: HealthData,
            settings: ExportSettings,
            profile: AndroidExportProfile,
            mode: ExportEngineMode,
            ids: DailyAggregateExportIds,
        ): FrozenDailyAggregateExportRequest {
            val context = settings.executionSleepCaptureContext?.copy()
            val formats = settings.selectedExportFormats.sortedBy(ExportFormat::ordinal)
            require(!settings.executionSleepCaptureAuthorityIsFrozen || context != null) {
                "immutable capture authority is missing"
            }
            if (profile == AndroidExportProfile.android_sleep_v6) {
                require(mode == ExportEngineMode.rust) { "wake-date export requires the Rust engine" }
                require(context?.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS &&
                    context.exportProfileID == profile.publicProfileId) { "wake-date capture authority is incompatible" }
                // The render adapter admits qualified selected native records and
                // rejects remaining arrays before a destination can accept the plan.
                require(!settings.formatCustomization.includeLegacyAndroidAliases &&
                    data.compatibilityProvenance == null) {
                    "wake-date native presentation is not qualified"
                }
            } else if (context != null) {
                require(context.sleepDayAttribution == SleepDayAttribution.NIGHT_BEGINS &&
                    (context.exportProfileID == null || context.exportProfileID == profile.publicProfileId)) {
                    "historical capture authority is incompatible"
                }
            }
            require(context == null || settings.executionEnginePin == null ||
                context.zoneId.id == settings.executionEnginePin.ianaTimeZone) {
                "capture and engine clock authority disagree"
            }
            val customization = settings.formatCustomization.frozenCopy()
            return FrozenDailyAggregateExportRequest(
                data = if (profile == AndroidExportProfile.android_sleep_v6) data.immutableWakeDateSource() else data,
                profile = profile,
                mode = mode,
                ids = ids.copy(),
                formats = formats,
                relativePaths = formats.associateWith { settings.aggregateRelativePath(data.date, it) },
                aggregateSubfolder = settings.aggregateSubfolderPath(data.date),
                baseName = settings.formatFilename(data.date),
                includeMetadata = settings.includeMetadata,
                groupByCategory = settings.groupByCategory,
                customization = customization,
                metricSelection = settings.metricSelection.copy(
                    enabledMetrics = Collections.unmodifiableSet(
                        settings.metricSelection.enabledMetrics.toSet(),
                    ),
                ),
                includeGranularData = settings.includeGranularData,
                suppliedPin = settings.executionEnginePin,
                captureContext = context,
            )
        }
    }
}

fun interface DailyAggregateNativePlanBuilder {
    fun plan(request: FrozenDailyAggregateExportRequest): ExportArtifactPlan
}

/** Handwritten destination-neutral adapter around the existing production Kotlin exporters. */
class ProductionDailyAggregateNativePlanBuilder(
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
) : DailyAggregateNativePlanBuilder {
    override fun plan(request: FrozenDailyAggregateExportRequest): ExportArtifactPlan {
        require(request.profile != AndroidExportProfile.android_sleep_v6) {
            "wake-date profile cannot invoke historical native exporters"
        }
        val items = request.formats.map { format ->
            val content = when (format) {
                ExportFormat.MARKDOWN -> markdownExporter.export(
                    data = request.data,
                    includeMetadata = request.includeMetadata,
                    groupByCategory = request.groupByCategory,
                    customization = request.customization,
                    includeGranularData = request.includeGranularData,
                )
                ExportFormat.OBSIDIAN_BASES -> obsidianBasesExporter.export(
                    data = request.data,
                    customization = request.customization,
                )
                ExportFormat.JSON -> jsonExporter.export(
                    data = request.data,
                    customization = request.customization,
                    includeGranularData = request.includeGranularData,
                )
                ExportFormat.CSV -> csvExporter.export(
                    data = request.data,
                    customization = request.customization,
                    includeGranularData = request.includeGranularData,
                )
            }.encodeToByteArray()
            val relativePath = request.relativePath(format)
            val mediaType = format.artifactMediaType()
            val contentSha256 = sha256Hex(content)
            ExportArtifactPlanItem(
                artifactId = artifactIdHex(
                    requestId = request.ids.requestId,
                    sessionId = request.ids.sessionId,
                    profile = request.profile,
                    relativePath = relativePath,
                    mediaType = mediaType,
                    writeMode = ExportArtifactWriteMode.overwrite,
                    contentSha256 = contentSha256,
                ),
                relativePath = relativePath,
                mediaType = mediaType,
                writeMode = ExportArtifactWriteMode.overwrite,
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

data class DailyAggregateRustPlan(
    val pin: ExportEnginePin,
    val plan: ExportArtifactPlan,
)

/** Concrete Rust work is behind this boundary so JVM orchestration tests need no native library. */
fun interface DailyAggregateRustPlanner {
    suspend fun plan(request: FrozenDailyAggregateExportRequest): DailyAggregateRustPlan
}

/**
 * Concrete M4/M5-to-UniFFI adapter. Every core snapshot, semantic call, and render call runs on
 * [Dispatchers.Default], and the already-captured [HealthData] is its only health input.
 */
class HealthMdRustDailyAggregatePlanner(
    private val coreService: HealthMdCoreService = HealthMdCoreService(),
    private val rustEngine: RustExportEngine = RustExportEngine(coreService),
    private val defaultDispatcher: CoroutineDispatcher = Dispatchers.Default,
    private val zoneIdProvider: () -> ZoneId = ZoneId::systemDefault,
) : DailyAggregateRustPlanner {
    override suspend fun plan(
        request: FrozenDailyAggregateExportRequest,
    ): DailyAggregateRustPlan = withContext(defaultDispatcher) {
        val timeZone = request.captureContext?.zoneId?.id ?: request.suppliedPin?.ianaTimeZone ?: zoneIdProvider().id
        val readiness = coreService.checkReadiness()
        val registry = request.suppliedPin?.let {
            coreService.getMetricRegistryAtAuthority(request.profile.coreProfile, it.registryVersion, it.registrySha256)
        } ?: coreService.getMetricRegistry(request.profile.coreProfile, request.profile.contractVersions.registry)
        val pin = request.suppliedPin?.also { persisted ->
            val compatibility = ExportEnginePinValidator().validate(persisted, readiness, registry)
            if (!compatibility.isCompatible || persisted.engine != request.mode || persisted.profile != request.profile) {
                throw ExportEnginePinCompatibilityException(compatibility)
            }
        } ?: ExportEnginePin.create(
            engine = request.mode,
            profile = request.profile,
            ianaTimeZone = timeZone,
            readiness = readiness,
            registry = registry,
        )
        val semanticProfile = when (request.profile) {
            AndroidExportProfile.android_frozen_v4 -> HealthMdSemanticInputAdapter.Profile.FROZEN_V4
            AndroidExportProfile.android_analytical_v5 -> HealthMdSemanticInputAdapter.Profile.ANALYTICAL_V5
            AndroidExportProfile.android_sleep_v6 -> HealthMdSemanticInputAdapter.Profile.SLEEP_V6
        }
        val semanticConfiguration = HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionId = request.ids.sessionId,
            profile = semanticProfile,
            selection = request.metricSelection,
            registry = registry,
            calendarTimeZone = timeZone,
            retainPlatformExtensions = false,
            captureContext = request.captureContext,
        )
        val semanticBatches = HealthMdSemanticInputAdapter.boundedBatches(
            sessionId = request.ids.sessionId,
            profile = semanticProfile,
            healthData = listOf(request.data),
            registry = registry,
            converter = request.customization.unitConverter,
            calendarTimeZone = timeZone,
            timeFormat = request.customization.timeFormat,
            includeLegacyAndroidAliases = request.customization.includeLegacyAndroidAliases,
            captureContext = request.captureContext,
        ).map { it.bytes }
        val semanticResult = HealthMdSemanticSessionRunner.process(
            configurationBytes = semanticConfiguration,
            batches = semanticBatches,
            service = coreService,
        )
        val composeNativeSources = request.profile == AndroidExportProfile.android_sleep_v6
        val presentationData = if (composeNativeSources) AndroidWakeDateSourceProjection.aggregate(request.data) else request.data
        val markdown = request.customization.markdownTemplate
        val renderInput = HealthMdRenderInputAdapter.encode(
            semanticResult = semanticResult,
            registry = registry,
            calendarTimeZone = timeZone,
            options = HealthMdRenderInputAdapter.Options(
                requestId = request.ids.requestId,
                composeSleepRecordsNatively = composeNativeSources,
                composeWorkoutRecordsNatively = composeNativeSources,
                formats = request.formats.map(ExportFormat::renderWireValue),
                renderProfileRevision = pin.renderProfileRevision,
                unitSystem = when (request.customization.unitPreference) {
                    UnitPreference.METRIC -> "metric"
                    UnitPreference.IMPERIAL -> "imperial"
                },
                includeMetadata = request.includeMetadata,
                groupByCategory = request.groupByCategory,
                includePlatformExtensions = false,
                includeGranularData = request.includeGranularData,
                rawCaptureStatus = "not_requested",
                writeMode = "overwrite",
                useEmoji = markdown.useEmoji,
                sectionHeaderLevel = markdown.sectionHeaderLevel,
                bullet = markdown.bulletStyle.symbol,
                includeSummary = markdown.includeSummary,
                customTemplate = markdown.customTemplate.takeIf {
                    markdown.style == MarkdownTemplateStyle.CUSTOM
                },
                includeDate = request.customization.frontmatterConfig.includeDate,
                dateKey = request.customization.frontmatterConfig.customDateKey,
                includeType = request.customization.frontmatterConfig.includeType,
                typeKey = request.customization.frontmatterConfig.customTypeKey,
                typeValue = request.customization.frontmatterConfig.customTypeValue,
                customFrontmatter = request.customization.frontmatterConfig.customFields,
                placeholderFrontmatter = request.customization.frontmatterConfig.placeholderFields,
                disabledFrontmatterKeys = if (request.profile == AndroidExportProfile.android_sleep_v6) {
                    registry.outputs.mapNotNull { output ->
                        output.key.takeIf { request.customization.frontmatterConfig.outputKey(it) == null }
                    }
                } else emptyList(),
                baseDirectory = request.aggregateSubfolder.orEmpty(),
                filenameTemplate = request.baseName,
                folderTemplate = "",
                markdownFolder = "",
                basesFolder = "",
                jsonFolder = "",
                csvFolder = "",
                rollupDirectory = "rollups",
                basesSuffix = "-bases",
                api = null,
            ),
            presentationByOwnerDate = mapOf(request.data.date.toString() to presentationData),
            presentationCustomization = request.customization,
            captureContext = request.captureContext,
        )
        val input = ExportRenderInput(
            pin = pin,
            requestId = request.ids.requestId,
            sessionId = request.ids.sessionId,
            configurationBytes = renderInput.configuration,
            semanticResultBytes = semanticResult,
            renderBatches = renderInput.batches,
        )
        val aggregatePlan = rustEngine.render(input, readiness, registry)
        DailyAggregateRustPlan(
            pin = pin,
            plan = if (composeNativeSources) AndroidWakeDateSourceProjection.compose(request, aggregatePlan, semanticResult) else aggregatePlan,
        )
    }
}

sealed interface LocalDailyAggregatePlanningResult {
    data object Legacy : LocalDailyAggregatePlanningResult

    data class Planned(
        val mode: ExportEngineMode,
        val plan: ExportArtifactPlan,
        val formats: List<ExportFormat>,
    ) : LocalDailyAggregatePlanningResult {
        init {
            require(mode != ExportEngineMode.legacy) { "planned local export requires a nonlegacy engine" }
        }
    }

    data class Failed(val mode: ExportEngineMode) : LocalDailyAggregatePlanningResult {
        init {
            require(mode != ExportEngineMode.legacy) { "legacy planning cannot fail closed here" }
        }
    }
}

fun interface LocalDailyAggregateExportPlanner {
    suspend fun plan(
        data: HealthData,
        settings: ExportSettings,
    ): LocalDailyAggregatePlanningResult
}

/**
 * The first production M6 seam: one simple local daily aggregate operation chooses one engine and
 * one authoritative plan before any destination owner is invoked.
 */
class AndroidDailyAggregateExportPlanner(
    private val nativePlanner: DailyAggregateNativePlanBuilder,
    private val policyResolver: LocalExportEnginePolicyResolver =
        ProfileScopedLocalExportEnginePolicyResolver(),
    private val rustPlanner: DailyAggregateRustPlanner = HealthMdRustDailyAggregatePlanner(),
    private val diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
    private val comparator: ExportArtifactPlanComparator = ExportArtifactPlanComparator(),
    private val idSource: DailyAggregateExportIdSource = DailyAggregateExportIdSource {
        DailyAggregateExportIds(
            requestId = UUID.randomUUID().toString(),
            sessionId = UUID.randomUUID().toString(),
        )
    },
) : LocalDailyAggregateExportPlanner {
    override suspend fun plan(
        data: HealthData,
        settings: ExportSettings,
    ): LocalDailyAggregatePlanningResult {
        val suppliedPin = settings.executionEnginePin
        val context = settings.executionSleepCaptureContext
        val isWakeDate = context?.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS ||
            suppliedPin?.profile == AndroidExportProfile.android_sleep_v6
        val selectedProfile = if (isWakeDate) {
            if (context?.sleepDayAttribution != SleepDayAttribution.MORNING_ENDS ||
                context.exportProfileID != AndroidExportProfile.android_sleep_v6.publicProfileId) {
                return LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust)
            }
            AndroidExportProfile.android_sleep_v6
        } else settings.formatCustomization.compatibilitySchemaProfile.toExportProfile()
        if (suppliedPin != null && suppliedPin.profile != selectedProfile) {
            return LocalDailyAggregatePlanningResult.Failed(suppliedPin.engine)
        }
        val expectedTarget = when (selectedProfile) {
            AndroidExportProfile.android_frozen_v4 -> ExportEnginePolicyTarget.ANDROID_FROZEN_V4
            AndroidExportProfile.android_analytical_v5 -> ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5
            AndroidExportProfile.android_sleep_v6 -> ExportEnginePolicyTarget.ANDROID_SLEEP_V6
        }
        val policy = if (suppliedPin != null) {
            ResolvedExportEnginePolicy(suppliedPin.engine, suppliedPin.profile, expectedTarget)
        } else if (settings.executionEngineAuthorityIsFrozen) {
            if (isWakeDate) return LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust)
            ResolvedExportEnginePolicy(ExportEngineMode.legacy, selectedProfile, expectedTarget)
        } else {
            try {
                policyResolver.resolve(selectedProfile)
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return if (isWakeDate) LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust)
                else LocalDailyAggregatePlanningResult.Legacy
            }
        }
        if (isWakeDate && policy.mode != ExportEngineMode.rust) {
            return LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust)
        }
        if (policy.profile != selectedProfile || policy.target != expectedTarget) {
            return if (suppliedPin == null && !isWakeDate) LocalDailyAggregatePlanningResult.Legacy
            else LocalDailyAggregatePlanningResult.Failed(policy.mode)
        }
        if (policy.mode == ExportEngineMode.legacy) return LocalDailyAggregatePlanningResult.Legacy
        if (!(if (isWakeDate) supportsWakeDateFiles(settings) else supportsNonLegacy(settings))) {
            return if (suppliedPin == null && !isWakeDate) LocalDailyAggregatePlanningResult.Legacy
            else LocalDailyAggregatePlanningResult.Failed(policy.mode)
        }

        val request = try {
            FrozenDailyAggregateExportRequest.capture(
                data = data,
                settings = settings,
                profile = selectedProfile,
                mode = policy.mode,
                ids = idSource.next(),
            )
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return LocalDailyAggregatePlanningResult.Failed(policy.mode)
        }
        val nativePlan = if (policy.mode == ExportEngineMode.shadow) {
            try {
                nativePlanner.plan(request).also { validatePlanShape(it, request) }
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return LocalDailyAggregatePlanningResult.Failed(policy.mode)
            }
        } else {
            null
        }

        val rust = try {
            rustPlanner.plan(request).also { result ->
                if (result.pin.engine != policy.mode || result.pin.profile != selectedProfile ||
                    (request.captureContext != null && result.pin.ianaTimeZone != request.captureContext.zoneId.id)) {
                    throw ExportArtifactPlanValidationException(
                        ExportArtifactPlanValidationIssue.PROFILE,
                    )
                }
                validatePlanShape(result.plan, request)
            }
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            if (policy.mode == ExportEngineMode.shadow) {
                emitSafely(
                    ShadowRustFailureDiagnostic(
                        profile = selectedProfile,
                        semanticProfileRevision = ExportEnginePin.EXPECTED_SEMANTIC_PROFILE_REVISION,
                        renderProfileRevision = HealthMdCoreService.EXPECTED_RENDER_PROFILE_REVISION,
                        code = error.toShadowFailureCode(),
                    ),
                )
                return planned(
                    policy.mode,
                    checkNotNull(nativePlan) { "shadow native plan was not captured" },
                    request.formats,
                )
            }
            return LocalDailyAggregatePlanningResult.Failed(policy.mode)
        }

        return when (policy.mode) {
            ExportEngineMode.legacy -> LocalDailyAggregatePlanningResult.Legacy
            ExportEngineMode.rust -> planned(policy.mode, rust.plan, request.formats)
            ExportEngineMode.shadow -> {
                val shadowNativePlan = checkNotNull(nativePlan) {
                    "shadow native plan was not captured"
                }
                emitSafely(
                    ShadowComparisonDiagnostic(
                        profile = selectedProfile,
                        semanticProfileRevision = rust.pin.semanticProfileRevision,
                        renderProfileRevision = rust.pin.renderProfileRevision,
                        comparison = comparator.compare(shadowNativePlan, rust.plan),
                    ),
                )
                planned(policy.mode, shadowNativePlan, request.formats)
            }
        }
    }

    private fun emitSafely(diagnostic: ShadowExportDiagnostic) {
        try {
            diagnosticSink.emit(diagnostic)
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            // Diagnostics are health-free and strictly non-authoritative.
        }
    }

    companion object {
        fun supportsNonLegacy(settings: ExportSettings): Boolean =
            settings.writeMode == WriteMode.OVERWRITE &&
                !settings.dailyNoteInjection.enabled &&
                !settings.individualTracking.globalEnabled &&
                settings.exportMode == ExportMode.COMPATIBILITY &&
                settings.exportTarget == ExportTarget.DEVICE_FOLDER &&
                settings.selectedExportFormats.isNotEmpty() &&
                settings.selectedExportFormats.all { it in M5_FORMATS }

        /** Side effects and destination write modes are applied by the existing native writer. */
        fun supportsWakeDateFiles(settings: ExportSettings): Boolean =
            settings.executionSleepCaptureContext?.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS &&
                supportsNonLegacy(settings.copy(writeMode = WriteMode.OVERWRITE,
                    dailyNoteInjection = settings.dailyNoteInjection.copy(enabled = false),
                    individualTracking = settings.individualTracking.copy(globalEnabled = false)))

        private val M5_FORMATS: Set<ExportFormat> = setOf(
            ExportFormat.MARKDOWN,
            ExportFormat.OBSIDIAN_BASES,
            ExportFormat.JSON,
            ExportFormat.CSV,
        )
    }
}

private fun planned(
    mode: ExportEngineMode,
    plan: ExportArtifactPlan,
    formats: List<ExportFormat>,
): LocalDailyAggregatePlanningResult.Planned = LocalDailyAggregatePlanningResult.Planned(
    mode = mode,
    plan = plan,
    formats = Collections.unmodifiableList(formats.toList()),
)

private fun validatePlanShape(
    plan: ExportArtifactPlan,
    request: FrozenDailyAggregateExportRequest,
) {
    if (plan.requestId != request.ids.requestId) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.REQUEST_ID)
    }
    if (plan.sessionId != request.ids.sessionId) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.SESSION_ID)
    }
    if (plan.profile != request.profile) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.PROFILE)
    }
    if (plan.items.size != request.formats.size) {
        throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.ARTIFACT_COUNT)
    }
    plan.items.zip(request.formats).forEach { (item, format) ->
        if (item.relativePath != request.relativePath(format)) {
            throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.RELATIVE_PATH)
        }
        if (item.mediaType != format.artifactMediaType()) {
            throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.MEDIA_TYPE)
        }
        if (item.writeMode != ExportArtifactWriteMode.overwrite) {
            throw ExportArtifactPlanValidationException(ExportArtifactPlanValidationIssue.WRITE_MODE)
        }
    }
}

private fun CompatibilitySchemaProfile.toExportProfile(): AndroidExportProfile = when (this) {
    CompatibilitySchemaProfile.IOS_V4_FROZEN -> AndroidExportProfile.android_frozen_v4
    CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> AndroidExportProfile.android_analytical_v5
}

private fun ExportFormat.renderWireValue(): String = when (this) {
    ExportFormat.MARKDOWN -> "markdown"
    ExportFormat.OBSIDIAN_BASES -> "obsidian_bases"
    ExportFormat.JSON -> "json"
    ExportFormat.CSV -> "csv"
}

private fun ExportFormat.artifactMediaType(): String = when (this) {
    ExportFormat.MARKDOWN,
    ExportFormat.OBSIDIAN_BASES -> "text/markdown; charset=utf-8"
    ExportFormat.JSON -> "application/json"
    ExportFormat.CSV -> "text/csv; charset=utf-8"
}

internal fun FormatCustomization.frozenCopy(): FormatCustomization = copy(
    frontmatterConfig = frontmatterConfig.frozenCopy(),
    markdownTemplate = markdownTemplate.copy(),
)

private fun FrontmatterConfiguration.frozenCopy(): FrontmatterConfiguration = copy(
    fields = Collections.unmodifiableList(fields.map { it.copy() }),
    customFields = Collections.unmodifiableMap(customFields.toMap()),
    placeholderFields = Collections.unmodifiableList(placeholderFields.toList()),
)

private fun Throwable.toShadowFailureCode(): ShadowRustFailureCode = when (this) {
    is ExportEnginePinCompatibilityException -> ShadowRustFailureCode.PIN_INCOMPATIBLE
    is ExportArtifactPlanValidationException -> ShadowRustFailureCode.INVALID_PLAN
    is LinkageError -> ShadowRustFailureCode.CORE_UNAVAILABLE
    else -> ShadowRustFailureCode.RENDER_FAILED
}

private fun rethrowCancellationOrFatal(error: Throwable) {
    if (error is CancellationException || error.isFatalExportEngineFailure()) throw error
}

private fun freezeQuantitySamples(samples: List<com.healthmd.domain.model.TimestampedSample>) =
    Collections.unmodifiableList(samples.map { sample ->
        sample.copy(metadata = Collections.unmodifiableMap(sample.metadata.toMap()),
            context = Collections.unmodifiableMap(sample.context.toMap()))
    })

private fun freezeWorkouts(workouts: List<com.healthmd.domain.model.WorkoutData>) =
    Collections.unmodifiableList(workouts.map { workout ->
        workout.copy(
            metadata = Collections.unmodifiableMap(workout.metadata.toMap()),
            laps = Collections.unmodifiableList(workout.laps.toList()),
            segments = Collections.unmodifiableList(workout.segments.toList()),
            splits = Collections.unmodifiableList(workout.splits.toList()),
            route = Collections.unmodifiableList(workout.route.toList()),
            heartRateSamples = freezeQuantitySamples(workout.heartRateSamples),
            speedSamples = freezeQuantitySamples(workout.speedSamples),
            cyclingCadenceSamples = freezeQuantitySamples(workout.cyclingCadenceSamples),
            stepsCadenceSamples = freezeQuantitySamples(workout.stepsCadenceSamples),
            powerSamples = freezeQuantitySamples(workout.powerSamples),
            elevationSamples = freezeQuantitySamples(workout.elevationSamples),
            correlatedSourceIds = Collections.unmodifiableMap(workout.correlatedSourceIds.mapValues { (_, ids) ->
                Collections.unmodifiableList(ids.toList())
            }),
        )
    })

/** Freeze admitted native facts before any asynchronous local/API planning. */
internal fun HealthData.immutableWakeDateSource(): HealthData = copy(
    activity = this.activity.copy(
        stepSamples = freezeQuantitySamples(this.activity.stepSamples),
        activityIntensityEntries = Collections.unmodifiableList(this.activity.activityIntensityEntries.map { entry ->
            entry.copy(metadata = Collections.unmodifiableMap(entry.metadata.toMap()))
        }),
    ),
    heart = this.heart.copy(
        samples = freezeQuantitySamples(this.heart.samples),
        hrvSamples = freezeQuantitySamples(this.heart.hrvSamples),
    ),
    vitals = this.vitals.copy(
        bloodOxygenSamples = freezeQuantitySamples(this.vitals.bloodOxygenSamples),
        bloodGlucoseSamples = freezeQuantitySamples(this.vitals.bloodGlucoseSamples),
        respiratoryRateSamples = freezeQuantitySamples(this.vitals.respiratoryRateSamples),
        bodyTemperatureSamples = freezeQuantitySamples(this.vitals.bodyTemperatureSamples),
        basalBodyTemperatureSamples = freezeQuantitySamples(this.vitals.basalBodyTemperatureSamples),
        skinTemperatureDeltas = freezeQuantitySamples(this.vitals.skinTemperatureDeltas),
        bloodPressureSamples = Collections.unmodifiableList(this.vitals.bloodPressureSamples.map { sample ->
            sample.copy(metadata = Collections.unmodifiableMap(sample.metadata.toMap()))
        }),
    ),
    sleep = this.sleep.copy(
        stages = Collections.unmodifiableList(this.sleep.stages.toList()),
        sessions = Collections.unmodifiableList(this.sleep.sessions.map { session ->
            session.copy(metadata = Collections.unmodifiableMap(session.metadata.toMap()))
        }),
    ),
    mindfulness = this.mindfulness.copy(
        sessions = Collections.unmodifiableList(this.mindfulness.sessions.map { session ->
            session.copy(metadata = Collections.unmodifiableMap(session.metadata.toMap()))
        }),
    ),
    nutrition = this.nutrition.copy(
        meals = Collections.unmodifiableList(this.nutrition.meals.map { meal ->
            meal.copy(metadata = Collections.unmodifiableMap(meal.metadata.toMap()))
        }),
    ),
    reproductiveHealth = this.reproductiveHealth.copy(
        menstruationPeriods = Collections.unmodifiableList(this.reproductiveHealth.menstruationPeriods.map { period ->
            period.copy(metadata = Collections.unmodifiableMap(period.metadata.toMap()))
        }),
    ),
    workouts = freezeWorkouts(this.workouts),
    // These sources are rejected when populated at acceptance. Freeze the empty
    // collections too, so later caller mutation cannot change that decision.
    plannedWorkouts = Collections.unmodifiableList(this.plannedWorkouts.toList()),
    medicalResources = this.medicalResources.copy(
        resources = Collections.unmodifiableList(this.medicalResources.resources.toList()),
        countsByType = Collections.unmodifiableMap(this.medicalResources.countsByType.toMap()),
    ),
)

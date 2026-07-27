package com.healthmd.domain.exportengine

import com.healthmd.core.HealthMdCoreService
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.CompatibilitySchemaProfile
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
            val formats = settings.selectedExportFormats.sortedBy(ExportFormat::ordinal)
            val customization = settings.formatCustomization.frozenCopy()
            return FrozenDailyAggregateExportRequest(
                data = data,
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
        val timeZone = request.suppliedPin?.ianaTimeZone ?: zoneIdProvider().id
        val readiness = coreService.checkReadiness()
        val registry = coreService.getMetricRegistry(request.profile.coreProfile)
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
        }
        val semanticConfiguration = HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionId = request.ids.sessionId,
            profile = semanticProfile,
            selection = request.metricSelection,
            registry = registry,
            calendarTimeZone = timeZone,
            retainPlatformExtensions = false,
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
        ).map { it.bytes }
        val semanticResult = HealthMdSemanticSessionRunner.process(
            configurationBytes = semanticConfiguration,
            batches = semanticBatches,
            service = coreService,
        )
        val markdown = request.customization.markdownTemplate
        val renderInput = HealthMdRenderInputAdapter.encode(
            semanticResult = semanticResult,
            registry = registry,
            calendarTimeZone = timeZone,
            options = HealthMdRenderInputAdapter.Options(
                requestId = request.ids.requestId,
                formats = request.formats.map(ExportFormat::renderWireValue),
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
            presentationByOwnerDate = mapOf(request.data.date.toString() to request.data),
            presentationCustomization = request.customization,
        )
        val input = ExportRenderInput(
            pin = pin,
            requestId = request.ids.requestId,
            sessionId = request.ids.sessionId,
            configurationBytes = renderInput.configuration,
            semanticResultBytes = semanticResult,
            renderBatches = renderInput.batches,
        )
        DailyAggregateRustPlan(
            pin = pin,
            plan = rustEngine.render(input, readiness, registry),
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
        val selectedProfile = settings.formatCustomization.compatibilitySchemaProfile.toExportProfile()
        val suppliedPin = settings.executionEnginePin
        if (suppliedPin != null && suppliedPin.profile != selectedProfile) {
            return LocalDailyAggregatePlanningResult.Failed(suppliedPin.engine)
        }
        val expectedTarget = when (selectedProfile) {
            AndroidExportProfile.android_frozen_v4 ->
                ExportEnginePolicyTarget.ANDROID_FROZEN_V4
            AndroidExportProfile.android_analytical_v5 ->
                ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5
        }
        val policy = if (suppliedPin != null) {
            ResolvedExportEnginePolicy(suppliedPin.engine, suppliedPin.profile, expectedTarget)
        } else if (settings.executionEngineAuthorityIsFrozen) {
            ResolvedExportEnginePolicy(ExportEngineMode.legacy, selectedProfile, expectedTarget)
        } else {
            try {
                policyResolver.resolve(selectedProfile)
            } catch (error: Throwable) {
                rethrowCancellationOrFatal(error)
                return LocalDailyAggregatePlanningResult.Legacy
            }
        }
        if (policy.profile != selectedProfile || policy.target != expectedTarget) {
            return if (suppliedPin == null) LocalDailyAggregatePlanningResult.Legacy
            else LocalDailyAggregatePlanningResult.Failed(policy.mode)
        }
        if (policy.mode == ExportEngineMode.legacy) return LocalDailyAggregatePlanningResult.Legacy
        if (!supportsNonLegacy(settings)) {
            return if (suppliedPin == null) LocalDailyAggregatePlanningResult.Legacy
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
                if (result.pin.engine != policy.mode || result.pin.profile != selectedProfile) {
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

private fun FormatCustomization.frozenCopy(): FormatCustomization = copy(
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

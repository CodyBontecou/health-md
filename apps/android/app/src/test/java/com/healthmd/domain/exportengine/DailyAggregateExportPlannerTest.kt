package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.WriteMode
import com.healthmd.rawexport.ExportMode
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class DailyAggregateExportPlannerTest {
    @Test
    fun profilePolicyIsResolvedOnceAndRustSkipsNativeAndReturnsOnlyRustPlan() = runTest {
        var policyCalls = 0
        var nativeCalls = 0
        var rustCalls = 0
        var capturedRequest: FrozenDailyAggregateExportRequest? = null
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { request ->
                nativeCalls += 1
                plan(request, "native")
            },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                policyCalls += 1
                resolved(ExportEngineMode.rust, profile)
            },
            rustPlanner = DailyAggregateRustPlanner { request ->
                rustCalls += 1
                capturedRequest = request
                DailyAggregateRustPlan(
                    pin = testPin(ExportEngineMode.rust, request.profile),
                    plan = plan(request, "rust"),
                )
            },
            idSource = fixedIds(),
        )
        val settings = simpleSettings().copy(
            formatCustomization = simpleSettings().formatCustomization.copy(
                compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
            ),
        )

        val result = planner.plan(day, settings) as LocalDailyAggregatePlanningResult.Planned

        assertThat(policyCalls).isEqualTo(1)
        assertThat(nativeCalls).isEqualTo(0)
        assertThat(rustCalls).isEqualTo(1)
        assertThat(capturedRequest!!.data).isSameInstanceAs(day)
        assertThat(capturedRequest!!.profile).isEqualTo(AndroidExportProfile.android_analytical_v5)
        assertThat(result.mode).isEqualTo(ExportEngineMode.rust)
        assertThat(result.plan.items.single().content.decodeToString()).isEqualTo("rust")
    }

    @Test
    fun shadowComparesButAlwaysReturnsNativeIncludingRustFailure() = runTest {
        val diagnostics = mutableListOf<ShadowExportDiagnostic>()
        var failRust = false
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { request -> plan(request, "native") },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                resolved(ExportEngineMode.shadow, profile)
            },
            rustPlanner = DailyAggregateRustPlanner { request ->
                if (failRust) error("must not escape or be logged")
                DailyAggregateRustPlan(
                    pin = testPin(ExportEngineMode.shadow, request.profile),
                    plan = plan(request, "rust"),
                )
            },
            diagnosticSink = ShadowExportDiagnosticSink(diagnostics::add),
            idSource = fixedIds(),
        )

        val compared = planner.plan(day, simpleSettings()) as LocalDailyAggregatePlanningResult.Planned
        failRust = true
        val failed = planner.plan(day, simpleSettings()) as LocalDailyAggregatePlanningResult.Planned

        assertThat(compared.plan.items.single().content.decodeToString()).isEqualTo("native")
        assertThat(failed.plan.items.single().content.decodeToString()).isEqualTo("native")
        assertThat(diagnostics).hasSize(2)
        assertThat(diagnostics[0]).isInstanceOf(ShadowComparisonDiagnostic::class.java)
        assertThat(diagnostics[1]).isInstanceOf(ShadowRustFailureDiagnostic::class.java)
        assertThat(diagnostics[1].toString()).doesNotContain("must not escape")
    }

    @Test
    fun shadowNativePlanningFailureFailsBeforeRustAndCannotCommit() = runTest {
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { error("native authority failed") },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                resolved(ExportEngineMode.shadow, profile)
            },
            rustPlanner = DailyAggregateRustPlanner {
                rustCalls += 1
                error("Rust must not run without the authoritative native plan")
            },
            idSource = fixedIds(),
        )

        val result = planner.plan(day, simpleSettings())

        assertThat(result).isEqualTo(LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.shadow))
        assertThat(rustCalls).isEqualTo(0)
    }

    @Test
    fun unsupportedOperationsResolveWhollyToLegacyBeforeEitherPlannerRuns() = runTest {
        var policyCalls = 0
        var nativeCalls = 0
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder {
                nativeCalls += 1
                error("unsupported operation reached native planning")
            },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                policyCalls += 1
                resolved(ExportEngineMode.rust, profile)
            },
            rustPlanner = DailyAggregateRustPlanner {
                rustCalls += 1
                error("unsupported operation reached Rust planning")
            },
            idSource = fixedIds(),
        )
        val unsupported = listOf(
            simpleSettings().copy(writeMode = WriteMode.APPEND),
            simpleSettings().copy(dailyNoteInjection = DailyNoteInjectionSettings(enabled = true)),
            simpleSettings().copy(individualTracking = IndividualTrackingSettings(globalEnabled = true)),
            simpleSettings().copy(exportMode = ExportMode.RAW_SNAPSHOT),
            simpleSettings().copy(exportTarget = ExportTarget.API_ENDPOINT),
        )

        val results = unsupported.map { planner.plan(day, it) }

        assertThat(results).containsExactlyElementsIn(
            List(unsupported.size) { LocalDailyAggregatePlanningResult.Legacy },
        )
        assertThat(policyCalls).isEqualTo(unsupported.size)
        assertThat(nativeCalls).isEqualTo(0)
        assertThat(rustCalls).isEqualTo(0)
    }

    @Test
    fun frozenNilAuthorityRemainsLegacyWithoutReadingCurrentPolicy() = runTest {
        var policyCalls = 0
        var nativeCalls = 0
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder {
                nativeCalls += 1
                error("frozen legacy must not plan")
            },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                policyCalls += 1
                resolved(ExportEngineMode.rust, profile)
            },
            rustPlanner = DailyAggregateRustPlanner {
                rustCalls += 1
                error("frozen legacy must not plan")
            },
            idSource = fixedIds(),
        )

        val result = planner.plan(
            day,
            simpleSettings().copy(executionEngineAuthorityIsFrozen = true),
        )

        assertThat(result).isEqualTo(LocalDailyAggregatePlanningResult.Legacy)
        assertThat(policyCalls).isEqualTo(0)
        assertThat(nativeCalls).isEqualTo(0)
        assertThat(rustCalls).isEqualTo(0)
    }

    @Test
    fun persistedPinBypassesCurrentPolicyAndCannotDowngradeUnsupportedResume() = runTest {
        val persisted = testPin(ExportEngineMode.rust, AndroidExportProfile.android_frozen_v4)
        var rustSawPersistedPin = false
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { request -> plan(request, "native") },
            policyResolver = LocalExportEnginePolicyResolver {
                error("persisted work must not resolve the current rollout policy")
            },
            rustPlanner = DailyAggregateRustPlanner { request ->
                rustSawPersistedPin = request.suppliedPin == persisted
                DailyAggregateRustPlan(persisted, plan(request, "rust"))
            },
            idSource = fixedIds(),
        )

        val planned = planner.plan(
            day,
            simpleSettings().copy(executionEnginePin = persisted),
        ) as LocalDailyAggregatePlanningResult.Planned
        val unsupported = planner.plan(
            day,
            simpleSettings().copy(
                executionEnginePin = persisted,
                writeMode = WriteMode.APPEND,
            ),
        )

        assertThat(rustSawPersistedPin).isTrue()
        assertThat(planned.mode).isEqualTo(ExportEngineMode.rust)
        assertThat(planned.plan.items.single().content.decodeToString()).isEqualTo("rust")
        assertThat(unsupported).isEqualTo(
            LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust),
        )
    }

    @Test
    fun rustPlanningFailureFailsClosedWithoutLegacyResult() = runTest {
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { request -> plan(request, "native") },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                resolved(ExportEngineMode.rust, profile)
            },
            rustPlanner = DailyAggregateRustPlanner { error("closed failure") },
            idSource = fixedIds(),
        )

        val result = planner.plan(day, simpleSettings())

        assertThat(result).isEqualTo(LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust))
    }

    @Test
    fun productionNativeBuilderUsesExactExistingBytesPathsAndArtifactIdentity() {
        val settings = simpleSettings().copy(
            exportFormats = setOf(
                ExportFormat.MARKDOWN,
                ExportFormat.OBSIDIAN_BASES,
                ExportFormat.JSON,
                ExportFormat.CSV,
            ),
            subfolder = "vault/health",
            folderStructure = "{year}/{month}",
            filenameFormat = "Health-{date}",
        )
        val request = FrozenDailyAggregateExportRequest.capture(
            data = day,
            settings = settings,
            profile = AndroidExportProfile.android_frozen_v4,
            mode = ExportEngineMode.shadow,
            ids = DailyAggregateExportIds(TEST_REQUEST_ID, TEST_SESSION_ID),
        )
        val builder = ProductionDailyAggregateNativePlanBuilder(
            MarkdownExporter(),
            JsonExporter(),
            CsvExporter(),
            ObsidianBasesExporter(),
        )

        val plan = builder.plan(request)

        assertThat(plan.items.map { it.relativePath }).containsExactly(
            "vault/health/2026/03/Health-2026-03-15.md",
            "vault/health/2026/03/Health-2026-03-15-bases.md",
            "vault/health/2026/03/Health-2026-03-15.json",
            "vault/health/2026/03/Health-2026-03-15.csv",
        ).inOrder()
        assertThat(plan.items.map { it.content.decodeToString() }).containsExactly(
            MarkdownExporter().export(
                day,
                settings.includeMetadata,
                settings.groupByCategory,
                settings.formatCustomization,
                settings.includeGranularData,
            ),
            ObsidianBasesExporter().export(day, settings.formatCustomization),
            JsonExporter().export(day, settings.formatCustomization, settings.includeGranularData),
            CsvExporter().export(day, settings.formatCustomization, settings.includeGranularData),
        ).inOrder()
        assertThat(plan.items.map { it.artifactId }.distinct()).hasSize(4)
    }

    @Test
    fun concreteRustAdapterIsAvailableWithoutLoadingUniFfi() {
        val adapter: DailyAggregateRustPlanner = HealthMdRustDailyAggregatePlanner()

        assertThat(adapter).isInstanceOf(HealthMdRustDailyAggregatePlanner::class.java)
    }

    private fun plan(
        request: FrozenDailyAggregateExportRequest,
        contentPrefix: String,
    ): ExportArtifactPlan {
        val items = request.formats.map { format ->
            val content = if (request.formats.size == 1) {
                contentPrefix.encodeToByteArray()
            } else {
                "$contentPrefix-${format.name.lowercase()}".encodeToByteArray()
            }
            val mediaType = mediaType(format)
            val sha256 = sha256Hex(content)
            ExportArtifactPlanItem(
                artifactId = artifactIdHex(
                    requestId = request.ids.requestId,
                    sessionId = request.ids.sessionId,
                    profile = request.profile,
                    relativePath = request.relativePath(format),
                    mediaType = mediaType,
                    writeMode = ExportArtifactWriteMode.overwrite,
                    contentSha256 = sha256,
                ),
                relativePath = request.relativePath(format),
                mediaType = mediaType,
                writeMode = ExportArtifactWriteMode.overwrite,
                content = content,
                sha256 = sha256,
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

    private fun resolved(
        mode: ExportEngineMode,
        profile: AndroidExportProfile,
    ): ResolvedExportEnginePolicy = ResolvedExportEnginePolicy(
        mode = mode,
        profile = profile,
        target = when (profile) {
            AndroidExportProfile.android_frozen_v4 -> ExportEnginePolicyTarget.ANDROID_FROZEN_V4
            AndroidExportProfile.android_analytical_v5 -> ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5
        },
    )

    private fun fixedIds() = DailyAggregateExportIdSource {
        DailyAggregateExportIds(TEST_REQUEST_ID, TEST_SESSION_ID)
    }

    private fun simpleSettings(): ExportSettings = ExportSettings(
        exportFormat = ExportFormat.JSON,
        exportFormats = setOf(ExportFormat.JSON),
        writeMode = WriteMode.OVERWRITE,
    )

    private fun mediaType(format: ExportFormat): String = when (format) {
        ExportFormat.MARKDOWN,
        ExportFormat.OBSIDIAN_BASES -> "text/markdown; charset=utf-8"
        ExportFormat.JSON -> "application/json"
        ExportFormat.CSV -> "text/csv; charset=utf-8"
    }

    private val day = com.healthmd.domain.model.HealthData(
        date = LocalDate.of(2026, 3, 15),
        activity = com.healthmd.domain.model.ActivityData(steps = 1234),
    )
}

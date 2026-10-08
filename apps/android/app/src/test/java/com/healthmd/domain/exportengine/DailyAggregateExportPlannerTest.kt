package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.SleepDayAttribution
import org.junit.Assert.assertThrows
import java.time.ZoneId
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
    fun explicitlyPinnedWakeDateRoutesOnlyToRustWithItsCapturedProfileAndClock() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
        val pin = ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_sleep_v6,
            ianaTimeZone = context.zoneId.id,
            readiness = testReadiness(),
            registry = testRegistry(AndroidExportProfile.android_sleep_v6).copy(
                registryVersion = 2u, registrySha256 = HEALTHMD_SLEEP_REGISTRY_SHA256,
            ),
        )
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { error("successor cannot use native historical writers") },
            policyResolver = LocalExportEnginePolicyResolver { error("frozen authority cannot consult current policy") },
            rustPlanner = DailyAggregateRustPlanner { request ->
                rustCalls += 1
                assertThat(request.profile).isEqualTo(AndroidExportProfile.android_sleep_v6)
                assertThat(request.captureContext).isEqualTo(context)
                assertThat(request.suppliedPin).isEqualTo(pin)
                DailyAggregateRustPlan(pin, plan(request, "wake-date"))
            },
            idSource = fixedIds(),
        )
        val result = planner.plan(day, simpleSettings().copy(
            executionEnginePin = pin,
            executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
        ))
        assertThat(result).isInstanceOf(LocalDailyAggregatePlanningResult.Planned::class.java)
        val planned = result as LocalDailyAggregatePlanningResult.Planned
        assertThat(planned.plan.profile).isEqualTo(AndroidExportProfile.android_sleep_v6)
        assertThat(planned.plan.artifactPlanVersion).isEqualTo(2u)
        assertThat(planned.mode).isEqualTo(ExportEngineMode.rust)
        assertThat(rustCalls).isEqualTo(1)
    }

    @Test
    fun wakeDateRoutingNeverReturnsHistoricalLegacyForUnqualifiedOperationsOrPolicies() = runTest {
        var nativeCalls = 0
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { nativeCalls += 1; error("historical writer must not run") },
            policyResolver = LocalExportEnginePolicyResolver { profile ->
                ResolvedExportEnginePolicy(ExportEngineMode.legacy, profile, ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5)
            },
            rustPlanner = DailyAggregateRustPlanner { rustCalls += 1; error("invalid request must not run") },
            idSource = fixedIds(),
        )
        val settings = simpleSettings().copy(
            executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS),
            executionSleepCaptureAuthorityIsFrozen = true,
        )
        val candidates = listOf(
            settings,
            settings.copy(writeMode = WriteMode.APPEND),
            settings.copy(dailyNoteInjection = DailyNoteInjectionSettings(enabled = true)),
            settings.copy(individualTracking = IndividualTrackingSettings(globalEnabled = true)),
            settings.copy(executionEngineAuthorityIsFrozen = true),
            settings.copy(executionSleepCaptureContext = settings.executionSleepCaptureContext!!.copy(exportProfileID = null)),
        )
        assertThat(candidates.map { planner.plan(day, it) }).containsExactlyElementsIn(
            List(candidates.size) { LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust) },
        )
        assertThat(nativeCalls).isEqualTo(0)
        assertThat(rustCalls).isEqualTo(0)
    }

    @Test
    fun frozenRequestRejectsMissingDraftConflictingAndUnqualifiedAuthorityBeforePlanning() {
        val context = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
        val settings = simpleSettings().copy(executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true)
        val incompatible = listOf(
            settings.copy(executionSleepCaptureContext = null),
            settings.copy(executionSleepCaptureContext = context.copy(exportProfileID = null)),
            settings.copy(executionSleepCaptureContext = AndroidCaptureContext(context.zoneId, SleepDayAttribution.NIGHT_BEGINS)),
            settings.copy(includeGranularData = true),
            settings.copy(formatCustomization = settings.formatCustomization.copy(includeLegacyAndroidAliases = true)),
        )
        for (candidate in incompatible) {
            assertThrows(IllegalArgumentException::class.java) {
                FrozenDailyAggregateExportRequest.capture(day, candidate, AndroidExportProfile.android_sleep_v6,
                    ExportEngineMode.rust, DailyAggregateExportIds(TEST_REQUEST_ID, TEST_SESSION_ID))
            }
        }
        for (mode in listOf(ExportEngineMode.legacy, ExportEngineMode.shadow)) {
            assertThrows(IllegalArgumentException::class.java) {
                FrozenDailyAggregateExportRequest.capture(day, settings, AndroidExportProfile.android_sleep_v6,
                    mode, DailyAggregateExportIds(TEST_REQUEST_ID, TEST_SESSION_ID))
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            FrozenDailyAggregateExportRequest.capture(day, settings, AndroidExportProfile.android_frozen_v4,
                ExportEngineMode.rust, DailyAggregateExportIds(TEST_REQUEST_ID, TEST_SESSION_ID))
        }
        val night = settings.copy(executionSleepCaptureContext = AndroidCaptureContext(context.zoneId, SleepDayAttribution.NIGHT_BEGINS),
            executionEnginePin = testPin(ExportEngineMode.rust))
        val error = assertThrows(IllegalArgumentException::class.java) {
            FrozenDailyAggregateExportRequest.capture(day, night, AndroidExportProfile.android_frozen_v4,
                ExportEngineMode.rust, DailyAggregateExportIds(TEST_REQUEST_ID, TEST_SESSION_ID))
        }
        assertThat(error.message).isEqualTo("capture and engine clock authority disagree")
    }

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
            artifactPlanVersion = request.profile.contractVersions.artifactPlan,
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
            AndroidExportProfile.android_sleep_v6 -> error("No qualified successor production policy")
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

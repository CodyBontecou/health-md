package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.storage.ExportRepositoryImpl
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ExportRepositoryEngineSeamTest {
    @Test
    fun legacySelectionKeepsExistingExporterAndCommitPathUnchanged() = runTest {
        val manager = manager()
        var writtenContent: String? = null
        every {
            manager.writeFile(any(), any(), any(), any(), any(), any())
        } answers {
            writtenContent = arg(4)
            true
        }
        val repository = repository(
            manager = manager,
            planner = LocalDailyAggregateExportPlanner { _, _ ->
                LocalDailyAggregatePlanningResult.Legacy
            },
        )
        val settings = simpleSettings()

        val success = repository.exportHealthData(day, settings)

        assertThat(success).isTrue()
        assertThat(writtenContent).isEqualTo(
            JsonExporter().export(day, settings.formatCustomization, settings.includeGranularData),
        )
        verify(exactly = 1) {
            manager.writeFile(
                folderUri,
                "health",
                "2026-03-15",
                "json",
                any(),
                FileExportManager.WriteMode.OVERWRITE,
            )
        }
        verify(exactly = 0) {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        }
    }

    @Test
    fun shadowPlansBeforeWritingAndCommitsNativeBytesOnly() = runTest {
        val events = mutableListOf<String>()
        val manager = manager()
        val committed = mutableListOf<String>()
        every {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        } answers {
            events += "write"
            committed += arg<String>(2)
            true
        }
        val planner = applicationPlanner(
            mode = ExportEngineMode.shadow,
            nativeContent = "native-authority",
            rustContent = "rust-shadow",
            events = events,
            rustFailure = true,
        )
        val repository = repository(manager, planner)

        val success = repository.exportHealthData(day, simpleSettings())

        assertThat(success).isTrue()
        assertThat(committed).containsExactly("native-authority")
        assertThat(events).containsExactly("native-plan", "rust-plan", "write").inOrder()
        verify(exactly = 0) { manager.writeFile(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun rustCommitsRustBytesOnly() = runTest {
        val manager = manager()
        val committed = mutableListOf<String>()
        every {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        } answers {
            committed += arg<String>(2)
            true
        }
        val repository = repository(
            manager,
            AndroidDailyAggregateExportPlanner(
                nativePlanner = DailyAggregateNativePlanBuilder {
                    error("Rust authority must not invoke the native renderer")
                },
                policyResolver = policy(ExportEngineMode.rust),
                rustPlanner = DailyAggregateRustPlanner { request ->
                    DailyAggregateRustPlan(
                        testPin(ExportEngineMode.rust, request.profile),
                        plan(request, "rust-authority"),
                    )
                },
                idSource = fixedIds(),
            ),
        )

        val success = repository.exportHealthData(day, simpleSettings())

        assertThat(success).isTrue()
        assertThat(committed).containsExactly("rust-authority")
        verify(exactly = 0) { manager.writeFile(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun rustPlanningFailureReturnsFalseWithoutLegacyFallbackOrDestinationWrite() = runTest {
        val manager = manager()
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { request -> plan(request, "native") },
            policyResolver = policy(ExportEngineMode.rust),
            rustPlanner = DailyAggregateRustPlanner { error("precommit Rust failure") },
            idSource = fixedIds(),
        )
        val repository = repository(manager, planner)

        val success = repository.exportHealthData(day, simpleSettings())

        assertThat(success).isFalse()
        verify(exactly = 0) { manager.writeFile(any(), any(), any(), any(), any(), any()) }
        verify(exactly = 0) {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        }
    }

    @Test
    fun failedFirstWriteStopsCommitAndNeverFallsBackOrRerenders() = runTest {
        val manager = manager()
        var writeCalls = 0
        every {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        } answers {
            writeCalls += 1
            false
        }
        var nativeCalls = 0
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { request ->
                nativeCalls += 1
                plan(request, "native")
            },
            policyResolver = policy(ExportEngineMode.rust),
            rustPlanner = DailyAggregateRustPlanner { request ->
                rustCalls += 1
                DailyAggregateRustPlan(
                    testPin(ExportEngineMode.rust, request.profile),
                    plan(request, "rust"),
                )
            },
            idSource = fixedIds(),
        )
        val settings = simpleSettings().copy(
            exportFormats = setOf(ExportFormat.MARKDOWN, ExportFormat.JSON),
        )
        val repository = repository(manager, planner)

        val success = repository.exportHealthData(day, settings)

        assertThat(success).isFalse()
        assertThat(writeCalls).isEqualTo(1)
        assertThat(nativeCalls).isEqualTo(0)
        assertThat(rustCalls).isEqualTo(1)
        verify(exactly = 0) { manager.writeFile(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun unsupportedAppendOperationUsesOnlyWholeLegacyPath() = runTest {
        val manager = manager()
        every { manager.writeFile(any(), any(), any(), any(), any(), any()) } returns true
        var nativeCalls = 0
        var rustCalls = 0
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder {
                nativeCalls += 1
                error("must stay legacy")
            },
            policyResolver = policy(ExportEngineMode.rust),
            rustPlanner = DailyAggregateRustPlanner {
                rustCalls += 1
                error("must stay legacy")
            },
            idSource = fixedIds(),
        )
        val repository = repository(manager, planner)
        val settings = simpleSettings().copy(writeMode = WriteMode.APPEND)

        val success = repository.exportHealthData(day, settings)

        assertThat(success).isTrue()
        assertThat(nativeCalls).isEqualTo(0)
        assertThat(rustCalls).isEqualTo(0)
        verify(exactly = 1) {
            manager.writeFile(any(), any(), any(), any(), any(), FileExportManager.WriteMode.APPEND)
        }
        verify(exactly = 0) {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        }
    }

    @Test
    fun previewUsesTheSameSelectedPlanWithoutDestinationSideEffects() = runTest {
        val manager = manager()
        val committed = mutableListOf<String>()
        every {
            manager.writeFileAtRelativePath(any(), any(), any(), any())
        } answers {
            committed += arg<String>(2)
            true
        }
        val repository = repository(
            manager,
            applicationPlanner(
                mode = ExportEngineMode.rust,
                nativeContent = "native",
                rustContent = "same-rust-preview",
            ),
        )
        val settings = simpleSettings()

        val preview = repository.previewHealthData(day, settings)

        assertThat(preview.files.single().content).isEqualTo("same-rust-preview")
        assertThat(preview.files.single().relativePath).isEqualTo("health/2026-03-15.json")
        assertThat(preview.files.single().byteCount).isEqualTo("same-rust-preview".encodeToByteArray().size)
        verify(exactly = 0) { manager.writeFileAtRelativePath(any(), any(), any(), any()) }
        verify(exactly = 0) { manager.writeFile(any(), any(), any(), any(), any(), any()) }

        assertThat(repository.exportHealthData(day, settings)).isTrue()
        assertThat(committed).containsExactly(preview.files.single().content)
    }

    private fun applicationPlanner(
        mode: ExportEngineMode,
        nativeContent: String,
        rustContent: String,
        events: MutableList<String>? = null,
        rustFailure: Boolean = false,
    ): LocalDailyAggregateExportPlanner = AndroidDailyAggregateExportPlanner(
        nativePlanner = DailyAggregateNativePlanBuilder { request ->
            events?.add("native-plan")
            plan(request, nativeContent)
        },
        policyResolver = policy(mode),
        rustPlanner = DailyAggregateRustPlanner { request ->
            events?.add("rust-plan")
            if (rustFailure) error("health-free Rust failure")
            DailyAggregateRustPlan(
                pin = testPin(mode, request.profile),
                plan = plan(request, rustContent),
            )
        },
        idSource = fixedIds(),
    )

    private fun policy(mode: ExportEngineMode): LocalExportEnginePolicyResolver =
        LocalExportEnginePolicyResolver { profile ->
            ResolvedExportEnginePolicy(
                mode = mode,
                profile = profile,
                target = when (profile) {
                    AndroidExportProfile.android_frozen_v4 ->
                        ExportEnginePolicyTarget.ANDROID_FROZEN_V4
                    AndroidExportProfile.android_analytical_v5 ->
                        ExportEnginePolicyTarget.ANDROID_ANALYTICAL_V5
                },
            )
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

    private fun repository(
        manager: FileExportManager,
        planner: LocalDailyAggregateExportPlanner,
    ): ExportRepositoryImpl {
        val settingsRepository = mockk<SettingsRepository>()
        coEvery { settingsRepository.getExportFolderUri() } returns folderUri
        return ExportRepositoryImpl(
            fileExportManager = manager,
            markdownExporter = MarkdownExporter(),
            jsonExporter = JsonExporter(),
            csvExporter = CsvExporter(),
            obsidianBasesExporter = ObsidianBasesExporter(),
            settingsRepository = settingsRepository,
            dailyAggregatePlanner = planner,
        )
    }

    private fun manager(): FileExportManager = mockk(relaxed = true)

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

    private val day = HealthData(
        date = LocalDate.of(2026, 3, 15),
        activity = ActivityData(steps = 1234),
    )

    private val folderUri = "content://exports"
}

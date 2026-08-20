package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSettingsSnapshotView
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.Runs
import io.mockk.slot
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import java.time.ZoneId

@OptIn(ExperimentalCoroutinesApi::class)
class ExportProfilesViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val snapshotJson = kotlinx.serialization.json.Json.encodeToString(
        ExportSettingsSnapshotView.serializer(),
        ExportSettingsSnapshotView(
            exportFormats = setOf("JSON", "MARKDOWN"),
            filenameFormat = "{date}",
            includeGranularData = true,
            metricSelection = ExportSettingsSnapshotView.MetricSelectionView(
                enabledMetrics = setOf("heart_rate", "steps", "sleep_duration"),
            ),
        ),
    )

    private fun profile(
        id: String = "p1",
        name: String = "Daily",
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        snapshotJson: String = this.snapshotJson,
    ) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = snapshotJson,
        target = target,
        apiEndpointUrl = null,
        isMigrationDefault = false,
        createdAtEpochMillis = 0L,
        updatedAtEpochMillis = 0L,
    )

    private fun entry(
        profileId: String,
        isEnabled: Boolean = false,
    ) = ScheduledProfileEntry(
        profileId = profileId,
        isEnabled = isEnabled,
        anchorEpochDay = 20_000L,
    )

    /** Canonical frozen snapshot the editor path produces (pin-free, target-scoped). */
    private fun canonicalSnapshot(
        settings: ExportSettings,
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
    ): String = AndroidExportSettingsSnapshotCodec.encodeCanonical(
        AndroidExportSettingsSnapshot.capture(
            settings = settings.copy(exportTarget = target, scheduledExportTarget = target),
            pin = null,
            zone = ZoneId.of("UTC"),
        ),
    )

    private class Harness(
        val profiles: MutableStateFlow<List<ExportProfile>>,
        val activeProfileId: MutableStateFlow<String?>,
        val entries: MutableStateFlow<List<ScheduledProfileEntry>>,
        val repository: ExportProfileRepository,
        val entryStore: ScheduledProfileEntryStore,
        val scheduler: ScheduledProfileScheduler,
        val snapshotFactory: ScheduledProfileSnapshotFactory,
        val settingsRepository: SettingsRepository,
        val profileCoordinator: ExportProfileCoordinator,
    ) {
        fun viewModel() = ExportProfilesViewModel(
            repository,
            entryStore,
            scheduler,
            snapshotFactory,
            settingsRepository,
            profileCoordinator,
        )
    }

    private fun harness(
        initialProfiles: List<ExportProfile> = listOf(profile("p1"), profile("p2", name = "Weekly")),
        initialActiveId: String? = "p1",
        initialEntries: List<ScheduledProfileEntry> = emptyList(),
        currentFolderUri: String? = null,
        currentSettings: ExportSettings = ExportSettings(),
    ): Harness {
        val profiles = MutableStateFlow(initialProfiles)
        val activeProfileId = MutableStateFlow(initialActiveId)
        val entries = MutableStateFlow(initialEntries)

        val repository = mockk<ExportProfileRepository> {
            every { this@mockk.profiles } returns profiles
            every { this@mockk.activeProfileId } returns activeProfileId
            coEvery { getProfiles() } answers { profiles.value }
            coEvery { getActiveProfile() } answers {
                profiles.value.firstOrNull { it.id == activeProfileId.value }
                    ?: profiles.value.firstOrNull()
            }
            coEvery { bindFolder(any(), any(), any()) } returns true
        }
        val entryStore = mockk<ScheduledProfileEntryStore> {
            every { this@mockk.entries } returns entries
            coEvery { upsert(any()) } just Runs
            coEvery { delete(any()) } just Runs
        }
        val scheduler = mockk<ScheduledProfileScheduler> {
            coEvery { reconcile(any()) } just Runs
        }
        val snapshotFactory = mockk<ScheduledProfileSnapshotFactory> {
            every { captureFromCurrent(any(), any(), any()) } returns snapshotJson
        }
        val settingsRepository = mockk<SettingsRepository> {
            coEvery { getExportSettings() } returns currentSettings
            every { exportFolderUri } returns kotlinx.coroutines.flow.flowOf(currentFolderUri)
            every { exportSettings } returns kotlinx.coroutines.flow.flowOf(
                currentSettings,
            )
        }
        val profileCoordinator = mockk<ExportProfileCoordinator> {
            coEvery { activate(any()) } returns true
        }
        return Harness(
            profiles,
            activeProfileId,
            entries,
            repository,
            entryStore,
            scheduler,
            snapshotFactory,
            settingsRepository,
            profileCoordinator,
        )
    }

    @Test
    fun `rows pair profiles with active flag entry and decoded snapshot`() = runTest {
        val entries = listOf(entry("p2", isEnabled = true))
        val harness = harness(initialEntries = entries)
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        val rows = viewModel.uiState.value.rows
        assertThat(rows).hasSize(2)
        assertThat(rows.first { it.profile.id == "p1" }.isActive).isTrue()
        assertThat(rows.first { it.profile.id == "p2" }.isActive).isFalse()
        assertThat(rows.first { it.profile.id == "p2" }.entry?.isEnabled).isTrue()
        assertThat(rows.first { it.profile.id == "p1" }.entry).isNull()

        val snapshot = rows.first().snapshot
        assertThat(snapshot).isNotNull()
        assertThat(snapshot!!.exportFormats).containsExactly("JSON", "MARKDOWN")
        assertThat(snapshot.includeGranularData).isTrue()
        assertThat(snapshot.enabledMetricCount).isEqualTo(3)
        assertThat(viewModel.uiState.value.activeProfileName).isEqualTo("Daily")
    }

    @Test
    fun `dangling active id falls back to first profile as active`() = runTest {
        val harness = harness(initialActiveId = "missing")
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        val rows = viewModel.uiState.value.rows
        assertThat(rows.first { it.profile.id == "p1" }.isActive).isTrue()
        assertThat(rows.first { it.profile.id == "p2" }.isActive).isFalse()
    }

    @Test
    fun `undecodable snapshot surfaces as null without breaking rows`() = runTest {
        val harness = harness(
            initialProfiles = listOf(profile("p1", snapshotJson = "not-json")),
        )
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        val row = viewModel.uiState.value.rows.single()
        assertThat(row.snapshot).isNull()
    }

    @Test
    fun `start creation opens the form seeded from current settings with a unique name`() = runTest {
        val harness = harness()
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.startCreation()

        assertThat(viewModel.uiState.value.creatingProfile).isTrue()
        val draft = ExportProfilesViewModel.initialCreationDraft(
            rows = viewModel.uiState.value.rows,
            currentSettings = viewModel.uiState.value.currentSettings,
        )
        assertThat(draft.name).isEqualTo("Profile")
        assertThat(draft.target).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(draft.settings.filenameFormat)
            .isEqualTo(ExportSettings.DEFAULT_FILENAME_FORMAT)
    }

    @Test
    fun `suggested profile name skips taken names case-insensitively`() {
        assertThat(
            ExportProfilesViewModel.suggestedProfileName(
                listOf(profile("p1", name = "Daily"), profile("p2", name = "Weekly")),
            ),
        ).isEqualTo("Profile")
        assertThat(
            ExportProfilesViewModel.suggestedProfileName(
                listOf(
                    profile("p1", name = "profile"),
                    profile("p2", name = "Profile 2"),
                ),
            ),
        ).isEqualTo("Profile 3")
    }

    @Test
    fun `create profile freezes the draft seeds entry activates and opens detail`() = runTest {
        val harness = harness()
        coEvery {
            harness.repository.add(any(), any(), any(), any(), any(), any())
        } answers {
            profile(id = "p-new", name = "Morning")
        }
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.startCreation()
        val draft = ExportProfilesViewModel.initialCreationDraft(
            rows = viewModel.uiState.value.rows,
            currentSettings = viewModel.uiState.value.currentSettings,
        ).copy(
            name = "Morning",
            folderUri = "content://tree/morning",
            folderDisplayName = "Morning",
            settings = viewModel.uiState.value.currentSettings.copy(filenameFormat = "morning-{date}"),
        )
        viewModel.createProfile(draft)
        advanceUntilIdle()

        val jsonSlot = slot<String>()
        coVerify {
            harness.repository.add(
                name = "Morning",
                any(),
                ExportTarget.DEVICE_FOLDER,
                any(),
                "content://tree/morning",
                "Morning",
            )
        }
        coVerify { harness.repository.add(any(), capture(jsonSlot), any(), any(), any(), any()) }
        val decoded = AndroidExportSettingsSnapshotCodec.decodeOrNull(jsonSlot.captured)
        assertThat(decoded).isNotNull()
        assertThat(decoded!!.enginePin).isNull()
        assertThat(decoded.filenameFormat).isEqualTo("morning-{date}")
        assertThat(decoded.scheduledExportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)

        val entrySlot = slot<ScheduledProfileEntry>()
        coVerify { harness.entryStore.upsert(capture(entrySlot)) }
        assertThat(entrySlot.captured.profileId).isEqualTo("p-new")
        assertThat(entrySlot.captured.isEnabled).isFalse()

        // Creation activates the copy (iOS parity).
        coVerify(exactly = 1) { harness.profileCoordinator.activate("p-new") }

        assertThat(viewModel.uiState.value.detailProfileId).isEqualTo("p-new")
        assertThat(viewModel.uiState.value.creatingProfile).isFalse()
    }

    @Test
    fun `initial edit draft restores the frozen snapshot onto current settings`() {
        val frozen = ExportSettings(
            filenameFormat = "frozen-{date}",
            includeGranularData = true,
        )
        val stored = profile(
            "p1",
            snapshotJson = canonicalSnapshot(frozen),
        ).copy(
            folderUri = "content://tree/vault",
            folderDisplayName = "Vault",
        )

        val draft = ExportProfilesViewModel.initialEditDraft(
            profile = stored,
            currentSettings = ExportSettings(filenameFormat = "live-{date}"),
        )

        assertThat(draft.name).isEqualTo("Daily")
        assertThat(draft.target).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(draft.folderUri).isEqualTo("content://tree/vault")
        assertThat(draft.settings.filenameFormat).isEqualTo("frozen-{date}")
        assertThat(draft.settings.includeGranularData).isTrue()
    }

    @Test
    fun `initial edit draft falls back to live settings for a corrupt snapshot`() {
        val draft = ExportProfilesViewModel.initialEditDraft(
            profile = profile("p1", snapshotJson = "not-json"),
            currentSettings = ExportSettings(filenameFormat = "live-{date}"),
        )

        assertThat(draft.settings.filenameFormat).isEqualTo("live-{date}")
    }

    @Test
    fun `update profile persists the draft atomically and syncs the active profile`() = runTest {
        val harness = harness()
        coEvery {
            harness.repository.applyEditorUpdate(any(), any(), any(), any(), any(), any(), any())
        } returns "Morning"
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.openEditor("p1")
        assertThat(viewModel.uiState.value.editingProfileId).isEqualTo("p1")

        val draft = ExportProfilesViewModel.initialEditDraft(
            profile = profile("p1"),
            currentSettings = viewModel.uiState.value.currentSettings,
        ).copy(name = "Morning")
        viewModel.updateProfile("p1", draft)
        advanceUntilIdle()

        val jsonSlot = slot<String>()
        coVerify {
            harness.repository.applyEditorUpdate(
                "p1",
                "Morning",
                capture(jsonSlot),
                ExportTarget.DEVICE_FOLDER,
                any(),
                any(),
                any(),
            )
        }
        val decoded = AndroidExportSettingsSnapshotCodec.decodeOrNull(jsonSlot.captured)
        assertThat(decoded).isNotNull()
        assertThat(decoded!!.enginePin).isNull()

        // Editing the ACTIVE profile re-applies the new snapshot onto live settings.
        coVerify(exactly = 1) { harness.profileCoordinator.activate("p1") }
        assertThat(viewModel.uiState.value.editingProfileId).isNull()
    }

    @Test
    fun `update profile never touches live state for a non-active profile`() = runTest {
        val harness = harness()
        coEvery {
            harness.repository.applyEditorUpdate(any(), any(), any(), any(), any(), any(), any())
        } returns "Renamed"
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        val draft = ExportProfilesViewModel.initialEditDraft(
            profile = profile("p2", name = "Weekly"),
            currentSettings = viewModel.uiState.value.currentSettings,
        )
        viewModel.updateProfile("p2", draft)
        advanceUntilIdle()

        coVerify(exactly = 1) {
            harness.repository.applyEditorUpdate("p2", any(), any(), any(), any(), any(), any())
        }
        coVerify(exactly = 0) { harness.profileCoordinator.activate(any()) }
        assertThat(viewModel.uiState.value.editingProfileId).isNull()
    }

    @Test
    fun `draft overlap preview names profiles writing the same files as the draft`() = runTest {
        val overlapping = ExportSettings()
        val harness = harness(
            initialProfiles = listOf(
                profile(
                    "p1",
                    name = "Daily",
                    snapshotJson = canonicalSnapshot(overlapping),
                ),
                profile(
                    "p2",
                    name = "Weekly",
                    snapshotJson = canonicalSnapshot(overlapping),
                ).copy(folderUri = "content://tree/weekly"),
            ),
            currentFolderUri = "content://tree/live",
        )
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        // Unbound candidate falls back to the live folder: overlaps the unbound Daily profile.
        assertThat(
            viewModel.draftOverlapPreview(
                editingProfileId = null,
                target = ExportTarget.DEVICE_FOLDER,
                folderUri = null,
                settings = ExportSettings(),
            ),
        ).containsExactly("Daily")

        // A distinct filename template breaks the collision.
        assertThat(
            viewModel.draftOverlapPreview(
                editingProfileId = null,
                target = ExportTarget.DEVICE_FOLDER,
                folderUri = null,
                settings = ExportSettings(filenameFormat = "unique-{date}"),
            ),
        ).isEmpty()

        // Binding the weekly folder collides with Weekly instead.
        assertThat(
            viewModel.draftOverlapPreview(
                editingProfileId = null,
                target = ExportTarget.DEVICE_FOLDER,
                folderUri = "content://tree/weekly",
                settings = ExportSettings(),
            ),
        ).containsExactly("Weekly")

        // Editing Daily excludes its own stored identity from the preview.
        assertThat(
            viewModel.draftOverlapPreview(
                editingProfileId = "p1",
                target = ExportTarget.DEVICE_FOLDER,
                folderUri = null,
                settings = ExportSettings(),
            ),
        ).isEmpty()

        // API endpoint targets never participate in file overlap.
        assertThat(
            viewModel.draftOverlapPreview(
                editingProfileId = null,
                target = ExportTarget.API_ENDPOINT,
                folderUri = null,
                settings = ExportSettings(),
            ),
        ).isEmpty()
    }

    @Test
    fun `activate applies the profile through the coordinator`() = runTest {
        val harness = harness()
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.activate("p2")
        advanceUntilIdle()

        coVerify(exactly = 1) { harness.profileCoordinator.activate("p2") }
    }

    @Test
    fun `rename delegates to repository and clears dialog state`() = runTest {
        val harness = harness()
        coEvery { harness.repository.rename("p1", "Morning") } returns "Morning"
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.startRename("p1")
        viewModel.rename("p1", "Morning")
        advanceUntilIdle()

        coVerify(exactly = 1) { harness.repository.rename("p1", "Morning") }
        assertThat(viewModel.uiState.value.renamingProfileId).isNull()
    }

    @Test
    fun `duplicate adds copy with frozen snapshot and opens detail`() = runTest {
        val harness = harness()
        coEvery { harness.repository.profileById("p2") } returns profile("p2", name = "Weekly")
        coEvery {
            harness.repository.add(any(), any(), any(), any())
        } answers {
            profile(id = "p-copy", name = "Weekly 2")
        }
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.duplicate("p2")
        advanceUntilIdle()

        coVerify {
            harness.repository.add(
                name = "Weekly",
                settingsSnapshotJson = snapshotJson,
                target = ExportTarget.DEVICE_FOLDER,
                apiEndpointUrl = null,
            )
        }
        assertThat(viewModel.uiState.value.detailProfileId).isEqualTo("p-copy")
    }

    @Test
    fun `delete removes entry and reconciles when repository deletes`() = runTest {
        val harness = harness()
        coEvery { harness.repository.delete("p2") } returns true
        coEvery { harness.repository.profileById("p2") } returns null
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.askDelete("p2")
        viewModel.delete("p2")
        advanceUntilIdle()

        coVerify(exactly = 1) { harness.entryStore.delete("p2") }
        coVerify(atLeast = 1) { harness.scheduler.reconcile() }
        assertThat(viewModel.uiState.value.pendingDeleteProfileId).isNull()
        assertThat(viewModel.uiState.value.detailProfileId).isNull()
    }

    @Test
    fun `delete keeps entry when last-profile guard refuses`() = runTest {
        val harness = harness(initialProfiles = listOf(profile("p1")))
        coEvery { harness.repository.delete("p1") } returns false
        coEvery { harness.repository.profileById("p1") } returns profile("p1")
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.delete("p1")
        advanceUntilIdle()

        coVerify(exactly = 0) { harness.entryStore.delete(any()) }
    }

    @Test
    fun `save entry upserts reconciles and closes editor`() = runTest {
        val harness = harness()
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        val draft = entry("p1", isEnabled = true)
        viewModel.openScheduleEditor("p1")
        viewModel.saveEntry(draft)
        advanceUntilIdle()

        coVerify(exactly = 1) { harness.entryStore.upsert(draft) }
        coVerify(atLeast = 1) { harness.scheduler.reconcile() }
        assertThat(viewModel.uiState.value.editingScheduleProfileId).isNull()
    }
}

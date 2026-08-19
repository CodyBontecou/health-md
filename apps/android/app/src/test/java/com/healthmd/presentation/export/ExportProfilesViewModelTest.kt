package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportProfile
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
            coEvery { getExportSettings() } returns com.healthmd.domain.model.ExportSettings()
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
    fun `add from current settings captures snapshot seeds entry and opens detail`() = runTest {
        val harness = harness()
        coEvery {
            harness.repository.add(any(), any(), any(), any())
        } answers {
            profile(id = "p-new", name = "Profile 3")
        }
        val viewModel = harness.viewModel()
        advanceUntilIdle()

        viewModel.addFromCurrentSettings()
        advanceUntilIdle()

        val jsonSlot = slot<String>()
        coVerify {
            harness.repository.add(any(), capture(jsonSlot), any(), any())
        }
        assertThat(jsonSlot.captured).isEqualTo(snapshotJson)

        val entrySlot = slot<ScheduledProfileEntry>()
        coVerify { harness.entryStore.upsert(capture(entrySlot)) }
        assertThat(entrySlot.captured.profileId).isEqualTo("p-new")
        assertThat(entrySlot.captured.isEnabled).isFalse()

        // Duplicates activate the copy (iOS picker parity).
        coVerify(exactly = 1) { harness.profileCoordinator.activate("p-new") }

        assertThat(viewModel.uiState.value.detailProfileId).isEqualTo("p-new")
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

package com.healthmd.data.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import com.healthmd.testing.syntheticExportEnginePin
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

/**
 * Editing-authority parity (export-profile decision 1): the live settings are the active
 * profile's editable projection — bootstrap applies the active snapshot, activation stages
 * the restore before switching the pointer, and live edits flush back after a debounce.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ExportProfileCoordinatorTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val settingsState = MutableStateFlow(ExportSettings())
    private val profilesState = MutableStateFlow<List<ExportProfile>>(emptyList())
    private val activeIdState = MutableStateFlow<String?>(null)

    private val factory = ScheduledProfileSnapshotFactory(
        mockk<ExportEnginePinPlanner> {
            // Deterministic pin matching the snapshot's structural rules: profile follows the
            // target/schema mapping and the zone mirrors the capture zone.
            every { forScheduledExport(any(), any(), any()) } answers {
                val target = secondArg<ExportTarget>()
                syntheticExportEnginePin(
                    profile = if (target == ExportTarget.API_ENDPOINT) {
                        AndroidExportProfile.android_frozen_v4
                    } else {
                        when (firstArg<ExportSettings>().formatCustomization.compatibilitySchemaProfile) {
                            CompatibilitySchemaProfile.IOS_V4_FROZEN -> AndroidExportProfile.android_frozen_v4
                            CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> AndroidExportProfile.android_analytical_v5
                        }
                    },
                    zoneId = thirdArg<java.time.ZoneId>().id,
                )
            }
        },
    )

    private val settingsRepository = mockk<SettingsRepository> {
        every { exportSettings } returns settingsState
        coEvery { getExportSettings() } answers { settingsState.value }
        coEvery { updateExportSettings(any()) } answers { settingsState.value = firstArg() }
        coEvery { getExportFolderUri() } answers { liveFolderUri }
        coEvery { saveExportFolderUri(any()) } answers { liveFolderUri = firstArg() }
    }

    private var liveFolderUri: String? = null

    private val profileRepository = mockk<ExportProfileRepository> {
        every { profiles } returns profilesState
        every { activeProfileId } returns activeIdState
        coEvery { getProfiles() } answers { profilesState.value }
        coEvery { getActiveProfileId() } answers { activeIdState.value }
        coEvery { getActiveProfile() } answers {
            profilesState.value.firstOrNull { it.id == activeIdState.value }
                ?: profilesState.value.firstOrNull()
        }
        coEvery { profileById(any()) } answers { profilesState.value.firstOrNull { it.id == firstArg<String>() } }
        coEvery { activate(any()) } answers {
            val id = firstArg<String>()
            if (profilesState.value.any { it.id == id }) {
                activeIdState.value = id
                true
            } else false
        }
        coEvery { updateProfile(any(), any(), any(), any()) } answers {
            val id = firstArg<String>()
            val index = profilesState.value.indexOfFirst { it.id == id }
            if (index >= 0) {
                profilesState.value = profilesState.value.toMutableList().apply {
                    set(index, this[index].copy(
                        settingsSnapshotJson = secondArg<String>(),
                        target = thirdArg<ExportTarget>(),
                        apiEndpointUrl = arg(3),
                        updatedAtEpochMillis = System.currentTimeMillis(),
                    ))
                }
                true
            } else false
        }
        coEvery { bindFolder(any(), any(), any()) } answers {
            val id = firstArg<String>()
            val index = profilesState.value.indexOfFirst { it.id == id }
            if (index >= 0) {
                profilesState.value = profilesState.value.toMutableList().apply {
                    set(
                        index,
                        this[index].copy(
                            folderUri = secondArg(),
                            folderDisplayName = thirdArg(),
                        ),
                    )
                }
                true
            } else false
        }
        coEvery { migrateDefaultIfNeeded(any(), any(), any()) } answers {
            if (profilesState.value.isNotEmpty()) return@answers null
            val profile = ExportProfile(
                id = "default",
                name = "Default",
                settingsSnapshotJson = firstArg<String>(),
                target = secondArg<ExportTarget>(),
                apiEndpointUrl = thirdArg<String?>(),
                isMigrationDefault = true,
                createdAtEpochMillis = 0L,
                updatedAtEpochMillis = 0L,
            )
            profilesState.value = listOf(profile)
            activeIdState.value = profile.id
            profile
        }
    }

    private fun profile(
        id: String,
        name: String = id,
        settings: ExportSettings = ExportSettings(),
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        endpointUrl: String? = null,
        folderUri: String? = null,
        folderDisplayName: String? = null,
    ): ExportProfile {
        val scoped = settings.copy(
            exportTarget = target,
            scheduledExportTarget = target,
            apiEndpointUrl = endpointUrl ?: settings.apiEndpointUrl,
        )
        return ExportProfile(
            id = id,
            name = name,
            settingsSnapshotJson = factory.captureFromCurrent(scoped, target, endpointUrl),
            target = target,
            apiEndpointUrl = endpointUrl,
            folderUri = folderUri,
            folderDisplayName = folderDisplayName,
            createdAtEpochMillis = 0L,
            updatedAtEpochMillis = 0L,
        )
    }

    private fun coordinator(scope: CoroutineScope) = ExportProfileCoordinator(
        profileRepository,
        settingsRepository,
        factory,
        mockk(relaxed = true),
    ).apply { this.scope = scope }

    // MARK: - Bootstrap

    @Test
    fun `bootstrap migrates Default from current settings and binds the endpoint`() = runTest {
        settingsState.value = ExportSettings(
            filenameFormat = "health-{date}",
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/hook",
        )
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val coordinator = coordinator(scope)

        try {
            coordinator.ensureStarted()
            advanceUntilIdle()

            assertThat(profilesState.value).hasSize(1)
            val migrated = profilesState.value.single()
            assertThat(migrated.name).isEqualTo("Default")
            assertThat(migrated.target).isEqualTo(ExportTarget.API_ENDPOINT)
            assertThat(migrated.apiEndpointUrl).isEqualTo("https://example.test/hook")
            assertThat(activeIdState.value).isEqualTo("default")
        } finally {
            scope.cancel()
        }
    }

    @Test
    fun `bootstrap applies the active profile onto live settings`() = runTest {
        val frozen = ExportSettings(
            filenameFormat = "frozen-{date}",
            exportFormats = setOf(com.healthmd.domain.model.ExportFormat.JSON),
            includeGranularData = true,
        )
        profilesState.value = listOf(profile("p1", settings = frozen))
        activeIdState.value = "p1"
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val coordinator = coordinator(scope)

        try {
            coordinator.ensureStarted()
            advanceUntilIdle()

            assertThat(settingsState.value.filenameFormat).isEqualTo("frozen-{date}")
            assertThat(settingsState.value.exportFormats)
                .containsExactly(com.healthmd.domain.model.ExportFormat.JSON)
            assertThat(settingsState.value.includeGranularData).isTrue()
            assertThat(settingsState.value.executionEngineAuthorityIsFrozen).isTrue()
        } finally {
            scope.cancel()
        }
    }

    // MARK: - Activation

    @Test
    fun `activate stages the incoming snapshot, flushes outgoing edits, and applies`() = runTest {
        val outgoing = ExportSettings(filenameFormat = "outgoing-{date}")
        val incoming = ExportSettings(
            filenameFormat = "incoming-{date}",
            writeMode = com.healthmd.domain.model.WriteMode.UPDATE,
        )
        profilesState.value = listOf(
            profile("p1", name = "One", settings = outgoing),
            profile("p2", name = "Two", settings = incoming),
        )
        activeIdState.value = "p1"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))
        val updateOrder = mutableListOf<String>()

        coEvery { profileRepository.updateProfile(any(), any(), any(), any()) } answers {
            updateOrder += "update:${firstArg<String>()}"
            val id = firstArg<String>()
            val index = profilesState.value.indexOfFirst { it.id == id }
            if (index >= 0) {
                profilesState.value = profilesState.value.toMutableList().apply {
                    set(
                        index,
                        this[index].copy(
                            settingsSnapshotJson = secondArg<String>(),
                            target = thirdArg<ExportTarget>(),
                            apiEndpointUrl = arg(3),
                        ),
                    )
                }
                true
            } else false
        }
        coEvery { profileRepository.activate(any()) } answers {
            updateOrder += "activate:${firstArg<String>()}"
            activeIdState.value = firstArg()
            true
        }

        // The user edited live settings while p1 was active (unflushed).
        settingsState.value = settingsState.value.copy(filenameFormat = "edited-{date}")

        assertThat(coordinator.activate("p2")).isTrue()
        advanceUntilIdle()

        // Outgoing edits froze into p1 before the pointer moved to p2.
        assertThat(updateOrder).containsAtLeast("update:p1", "activate:p2").inOrder()
        assertThat(activeIdState.value).isEqualTo("p2")
        // Live settings now carry the incoming profile's frozen output.
        assertThat(settingsState.value.filenameFormat).isEqualTo("incoming-{date}")
        assertThat(settingsState.value.writeMode).isEqualTo(com.healthmd.domain.model.WriteMode.UPDATE)
    }

    @Test
    fun `activate reapplying the active profile is a plain apply`() = runTest {
        profilesState.value = listOf(
            profile("p1", settings = ExportSettings(filenameFormat = "frozen-{date}")),
        )
        activeIdState.value = "p1"
        settingsState.value = settingsState.value.copy(filenameFormat = "drifted-{date}")
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        assertThat(coordinator.activate("p1")).isTrue()
        assertThat(settingsState.value.filenameFormat).isEqualTo("frozen-{date}")
        assertThat(activeIdState.value).isEqualTo("p1")
    }

    @Test
    fun `activate fails closed on an undecodable snapshot without moving the pointer`() = runTest {
        val corrupted = ExportProfile(
            id = "p2",
            name = "Corrupt",
            settingsSnapshotJson = "not-json",
            target = ExportTarget.DEVICE_FOLDER,
            createdAtEpochMillis = 0L,
            updatedAtEpochMillis = 0L,
        )
        profilesState.value = listOf(
            profile("p1", settings = ExportSettings(filenameFormat = "live-{date}")),
            corrupted,
        )
        activeIdState.value = "p1"
        val before = settingsState.value
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        assertThat(coordinator.activate("p2")).isFalse()
        assertThat(activeIdState.value).isEqualTo("p1")
        assertThat(settingsState.value.filenameFormat).isEqualTo(before.filenameFormat)
    }

    @Test
    fun `activate rejects unknown ids`() = runTest {
        profilesState.value = listOf(profile("p1"))
        activeIdState.value = "p1"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        assertThat(coordinator.activate("missing")).isFalse()
        assertThat(activeIdState.value).isEqualTo("p1")
    }

    // MARK: - Folder binding adoption

    @Test
    fun `activate adopts the profile's bound folder as the live device folder`() = runTest {
        profilesState.value = listOf(
            profile("p1", settings = ExportSettings(filenameFormat = "a-{date}")),
            profile(
                "p2",
                settings = ExportSettings(filenameFormat = "b-{date}"),
                folderUri = "content://vault-b",
                folderDisplayName = "Vault B",
            ),
        )
        activeIdState.value = "p1"
        liveFolderUri = "content://vault-a"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        assertThat(coordinator.activate("p2")).isTrue()

        assertThat(activeIdState.value).isEqualTo("p2")
        assertThat(liveFolderUri).isEqualTo("content://vault-b")
    }

    @Test
    fun `re-applying the active profile adopts its newly bound folder`() = runTest {
        profilesState.value = listOf(
            profile(
                "p1",
                settings = ExportSettings(filenameFormat = "frozen-{date}"),
                folderUri = "content://vault-b",
                folderDisplayName = "Vault B",
            ),
        )
        activeIdState.value = "p1"
        liveFolderUri = "content://vault-a"
        settingsState.value = settingsState.value.copy(filenameFormat = "drifted-{date}")
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        // Editor save / folder rebind on the already-active profile: the snapshot refreshes
        // live settings AND the new binding is adopted as the live device folder.
        assertThat(coordinator.activate("p1")).isTrue()

        assertThat(settingsState.value.filenameFormat).isEqualTo("frozen-{date}")
        assertThat(liveFolderUri).isEqualTo("content://vault-b")
    }

    @Test
    fun `re-applying the active profile keeps the live folder when unbound`() = runTest {
        profilesState.value = listOf(
            profile("p1", settings = ExportSettings(filenameFormat = "frozen-{date}")),
        )
        activeIdState.value = "p1"
        liveFolderUri = "content://vault-a"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        assertThat(coordinator.activate("p1")).isTrue()

        assertThat(liveFolderUri).isEqualTo("content://vault-a")
    }

    @Test
    fun `activate keeps the current folder for unbound profiles`() = runTest {
        profilesState.value = listOf(
            profile("p1", settings = ExportSettings(filenameFormat = "a-{date}")),
            profile("p2", settings = ExportSettings(filenameFormat = "b-{date}")),
        )
        activeIdState.value = "p1"
        liveFolderUri = "content://vault-a"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        assertThat(coordinator.activate("p2")).isTrue()

        assertThat(liveFolderUri).isEqualTo("content://vault-a")
    }

    @Test
    fun `folderWasSelected rebinds the active profile to the picked folder`() = runTest {
        profilesState.value = listOf(profile("p1"))
        activeIdState.value = "p1"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        coordinator.folderWasSelected("content://vault-x", "Vault X")

        val bound = profilesState.value.single()
        assertThat(bound.folderUri).isEqualTo("content://vault-x")
        assertThat(bound.folderDisplayName).isEqualTo("Vault X")
    }

    // MARK: - Edit flush

    @Test
    fun `flushEdits freezes live settings into the active profile`() = runTest {
        val original = ExportSettings(filenameFormat = "original-{date}")
        profilesState.value = listOf(profile("p1", settings = original))
        activeIdState.value = "p1"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        settingsState.value = settingsState.value.copy(
            filenameFormat = "edited-{date}",
            includeGranularData = true,
        )
        coordinator.flushEdits()

        val jsonSlot = slot<String>()
        coVerify(exactly = 1) { profileRepository.updateProfile("p1", capture(jsonSlot), any(), any()) }
        val decoded = AndroidExportSettingsSnapshotCodec.decodeOrNull(jsonSlot.captured)
        assertThat(decoded).isNotNull()
        assertThat(decoded!!.filenameFormat).isEqualTo("edited-{date}")
        assertThat(decoded.includeGranularData).isTrue()
    }

    @Test
    fun `flushEdits syncs the profile target and endpoint binding`() = runTest {
        profilesState.value = listOf(
            profile("p1", settings = ExportSettings(filenameFormat = "original-{date}")),
        )
        activeIdState.value = "p1"
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        settingsState.value = settingsState.value.copy(
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/hook",
        )
        coordinator.flushEdits()

        coVerify(exactly = 1) {
            profileRepository.updateProfile(
                "p1",
                any(),
                ExportTarget.API_ENDPOINT,
                "https://example.test/hook",
            )
        }
    }

    @Test
    fun `flushEdits skips the write when nothing output-affecting changed`() = runTest {
        val current = ExportSettings(filenameFormat = "stable-{date}")
        profilesState.value = listOf(profile("p1", settings = current))
        activeIdState.value = "p1"
        settingsState.value = current
        val coordinator = coordinator(CoroutineScope(SupervisorJob()))

        // Schedule-only bookkeeping: excluded from snapshots, must not churn the profile.
        settingsState.value = current.copy(scheduleEnabled = true, scheduleHour = 9)
        coordinator.flushEdits()

        coVerify(exactly = 0) { profileRepository.updateProfile(any(), any(), any(), any()) }
    }

    @Test
    fun `live edits flush into the active profile after the debounce window`() = runTest {
        profilesState.value = listOf(profile("p1", settings = ExportSettings(filenameFormat = "start-{date}")))
        activeIdState.value = "p1"
        val scope = CoroutineScope(SupervisorJob() + StandardTestDispatcher(testScheduler))
        val coordinator = coordinator(scope)

        try {
            coordinator.ensureStarted()
            advanceUntilIdle()
            coEvery { profileRepository.updateProfile(any(), any(), any(), any()) } answers { true }

            settingsState.value = settingsState.value.copy(filenameFormat = "debounced-{date}")
            advanceTimeBy(ExportProfileCoordinator.EDIT_FLUSH_INTERVAL_MILLIS + 1)
            advanceUntilIdle()

            val jsonSlot = slot<String>()
            coVerify(atLeast = 1) {
                profileRepository.updateProfile("p1", capture(jsonSlot), any(), any())
            }
            val decoded = AndroidExportSettingsSnapshotCodec.decodeOrNull(jsonSlot.captured)
            assertThat(decoded!!.filenameFormat).isEqualTo("debounced-{date}")
        } finally {
            scope.cancel()
        }
    }

}

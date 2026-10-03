package com.healthmd.sharedsetup

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MetricSelectionState
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.io.File
import java.time.ZoneId

class SharedSetupServiceTest {
    @Test
    fun `versioned preview is a zero-write v2 import plan`() = runTest {
        val service = SharedSetupService(FixtureRegistry)
        val bytes = v2FixtureFile().readBytes()

        val versioned = service.previewVersioned(bytes).getOrThrow()

        assertThat(versioned.profiles).hasSize(2)
        assertThat(versioned.source.schemaVersion).isEqualTo(SHARED_SETUP_V2_VERSION)
    }

    @Test
    fun `preview fails closed on a v1-shaped document with a bounded message`() = runTest {
        val service = SharedSetupService(FixtureRegistry)
        // Minimal v1-shaped bytes, synthesized inline: the pre-canonical v1 contract is gone
        // and dispatch must reject it before any typed decoding.
        val v1Bytes = """{"schema":"healthmd.shared_setup","schema_version":1}"""
            .encodeToByteArray()

        val result = service.previewVersioned(v1Bytes)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message)
            .isEqualTo("This shared setup version is not supported.")
    }

    @Test
    fun `explicit v2 writer maps export context then emits canonical LF bytes`() = runTest {
        val service = SharedSetupService(FixtureRegistry)
        val defaults = ExportSettings.newInstallDefaults().copy(
            metricSelection = MetricSelectionState(emptySet()),
            individualTracking = IndividualTrackingSettings(),
        )
        val snapshot = AndroidExportSettingsSnapshot.capture(defaults, pin = null, zone = ZoneId.of("UTC"))
        val profile = ExportProfile(
            id = "123e4567-e89b-42d3-a456-426614174099",
            name = "Portable",
            settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot),
            target = ExportTarget.DEVICE_FOLDER,
            folderUri = "content://local-only/not-exported",
            folderDisplayName = "Local only",
            createdAtEpochMillis = 1,
            updatedAtEpochMillis = 2,
        )
        val profileRepository = mockk<ExportProfileRepository>()
        val scheduleStore = mockk<ScheduledProfileEntryStore>()
        coEvery { profileRepository.getProfiles() } returns listOf(profile)
        coEvery { profileRepository.getActiveProfileId() } returns profile.id
        coEvery { scheduleStore.getEntries() } returns emptyList()
        var extensionLoads = 0
        val source = RepositorySharedSetupV2ExportSource(
            profileRepository = profileRepository,
            scheduledProfileEntryStore = scheduleStore,
            appVersion = "1.2.3-test",
            preservedAppleExtensions = {
                extensionLoads += 1
                emptyMap()
            },
        )

        val bytes = service.exportV2Bytes(source)

        assertThat(extensionLoads).isEqualTo(1)
        coVerify(exactly = 1) { profileRepository.getProfiles() }
        coVerify(exactly = 1) { profileRepository.getActiveProfileId() }
        coVerify(exactly = 1) { scheduleStore.getEntries() }
        assertThat(bytes.last()).isEqualTo('\n'.code.toByte())
        assertThat(bytes[bytes.lastIndex - 1]).isNotEqualTo('\n'.code.toByte())
        val decoded = SharedSetupV2Codec(FixtureRegistry).decode(bytes)
        assertThat(decoded).isInstanceOf(SharedSetupVersionedDecodeResult.Valid::class.java)
        assertThat(bytes.decodeToString()).doesNotContain(profile.id)
        assertThat(bytes.decodeToString()).doesNotContain("content://")
    }

    @Test
    fun `v2 apply validates plan normalizes selection and delegates explicit Undo`() = runTest {
        val service = SharedSetupService(FixtureRegistry)
        val preview = service.previewVersioned(v2FixtureFile().readBytes()).getOrThrow()
        var appliedRequest: SharedSetupV2ApplyRequest? = null
        val callback = SharedSetupV2ApplyCallback { request ->
            appliedRequest = request
            Result.success(Unit)
        }

        val applied = service.applyV2(
            plan = preview,
            selectedBundleIds = listOf("profile-002", "profile-001"),
            mode = SharedSetupV2ApplyMode.ADD,
            callback = callback,
        ).getOrThrow()

        assertThat(applied.selectedBundleIds).containsExactly("profile-001", "profile-002").inOrder()
        assertThat(appliedRequest?.selectedBundleIds)
            .containsExactly("profile-001", "profile-002").inOrder()
        assertThat(applied.canUndo).isTrue()

        var invalidCallbackCalls = 0
        val invalidCallback = SharedSetupV2ApplyCallback {
            invalidCallbackCalls += 1
            Result.success(Unit)
        }
        val invalid = service.applyV2(
            plan = preview.copy(activeProfile = "profile-999"),
            selectedBundleIds = listOf("profile-001"),
            mode = SharedSetupV2ApplyMode.REPLACE,
            callback = invalidCallback,
        )
        assertThat(invalid.isFailure).isTrue()
        listOf(
            emptyList(),
            listOf("profile-001", "profile-001"),
            listOf("profile-999"),
        ).forEach { invalidSelection ->
            assertThat(
                service.applyV2(
                    plan = preview,
                    selectedBundleIds = invalidSelection,
                    mode = SharedSetupV2ApplyMode.REPLACE,
                    callback = invalidCallback,
                ).isFailure,
            ).isTrue()
        }
        assertThat(invalidCallbackCalls).isEqualTo(0)

        var undoCalls = 0
        val undone = service.undoV2(
            SharedSetupV2UndoCallback {
                undoCalls += 1
                Result.success(Unit)
            },
        ).getOrThrow()
        assertThat(undone.didUndo).isTrue()
        assertThat(undoCalls).isEqualTo(1)
    }

    private object FixtureRegistry : SharedSetupMetricRegistry {
        override val version = 1
        override val sha256 = "da1ef4f1dd2c9117e5922ae64207510c743c8b14624a792bab93f98494ccb070"
        private val bindings = listOf(
            SharedSetupRegistryBinding("active_energy", "active_energy", "active_calories", "mapped_alias"),
            SharedSetupRegistryBinding("blood_pressure_systolic", "blood_pressure_systolic", "bp_systolic", "mapped_alias"),
            SharedSetupRegistryBinding("heart_rate_avg", "heart_rate_avg", "avg_hr", "mapped_alias"),
            SharedSetupRegistryBinding("hrv", "hrv", null, "platform_exact_or_unavailable"),
            SharedSetupRegistryBinding("sleep_core", "sleep_core", "sleep_light", "mapped_alias"),
            SharedSetupRegistryBinding("steps", "steps", "steps", "platform_exact_or_unavailable"),
        )
        override val bySemanticId = bindings.associateBy { it.semanticId }
        override val byAndroidSelectionId = bindings.mapNotNull { binding ->
            binding.androidSelectionId?.let { it to binding }
        }.toMap()
    }

    private fun v2FixtureFile(): File = contractFile(
        "packages/contracts/shared-setup/v2/fixtures/android-shared-setup-v2.json",
    )

    private fun contractFile(path: String): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, path)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: error("Could not locate $path")
        }
    }
}

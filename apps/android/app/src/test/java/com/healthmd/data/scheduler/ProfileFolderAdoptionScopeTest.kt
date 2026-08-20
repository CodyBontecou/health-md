package com.healthmd.data.scheduler

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import java.util.concurrent.ConcurrentLinkedQueue
import org.junit.Rule
import org.junit.Test

/**
 * Per-profile folder adoption (iOS folder-gate parity): the live folder URI swaps to the run
 * profile's binding for the duration of a folder-target run and restores afterwards, mutually
 * exclusively across concurrent runs.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class ProfileFolderAdoptionScopeTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private fun profile(
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        folderUri: String? = "content://vault-b",
    ) = ExportProfile(
        id = "p1",
        name = "Daily",
        settingsSnapshotJson = "{}",
        target = target,
        folderUri = folderUri,
        createdAtEpochMillis = 0L,
        updatedAtEpochMillis = 0L,
    )

    @Test
    fun `adopts the profile folder for the run and restores the previous value`() = runTest {
        var live = "content://vault-a"
        val repository = mockk<SettingsRepository> {
            coEvery { getExportFolderUri() } answers { live }
            coEvery { saveExportFolderUri(any()) } answers { live = firstArg() }
        }
        val scope = ProfileFolderAdoptionScope(repository)
        val observed = mutableListOf<String>()

        scope.withProfileFolder(profile()) { observed += live }

        assertThat(observed).containsExactly("content://vault-b")
        assertThat(live).isEqualTo("content://vault-a")
    }

    @Test
    fun `restores the previous value when the run fails`() = runTest {
        var live = "content://vault-a"
        val repository = mockk<SettingsRepository> {
            coEvery { getExportFolderUri() } answers { live }
            coEvery { saveExportFolderUri(any()) } answers { live = firstArg() }
        }
        val scope = ProfileFolderAdoptionScope(repository)

        val error = runCatching {
            scope.withProfileFolder(profile()) { error("run failed") }
        }.exceptionOrNull()

        assertThat(error).hasMessageThat().isEqualTo("run failed")
        assertThat(live).isEqualTo("content://vault-a")
    }

    @Test
    fun `runs unchanged for API targets and unbound folder profiles`() = runTest {
        var writes = 0
        val repository = mockk<SettingsRepository> {
            coEvery { getExportFolderUri() } returns "content://vault-a"
            coEvery { saveExportFolderUri(any()) } answers { writes++ }
        }
        val scope = ProfileFolderAdoptionScope(repository)

        scope.withProfileFolder(profile(target = ExportTarget.API_ENDPOINT)) { Unit }
        scope.withProfileFolder(profile(folderUri = null)) { Unit }
        scope.withProfileFolder(profile(folderUri = "  ")) { Unit }

        assertThat(writes).isEqualTo(0)
    }

    @Test
    fun `skips adoption when no live folder exists`() = runTest {
        var writes = 0
        val repository = mockk<SettingsRepository> {
            coEvery { getExportFolderUri() } returns null
            coEvery { saveExportFolderUri(any()) } answers { writes++ }
        }
        val scope = ProfileFolderAdoptionScope(repository)

        scope.withProfileFolder(profile()) { Unit }

        assertThat(writes).isEqualTo(0)
    }

    @Test
    fun `does not rewrite the folder when it already matches`() = runTest {
        var writes = 0
        val repository = mockk<SettingsRepository> {
            coEvery { getExportFolderUri() } returns "content://vault-b"
            coEvery { saveExportFolderUri(any()) } answers { writes++ }
        }
        val scope = ProfileFolderAdoptionScope(repository)

        scope.withProfileFolder(profile()) { Unit }

        // Adoption is a no-op when the profile already matches the live folder: one write only
        // would still be wrong (restore), so the guard must produce zero writes total.
        assertThat(writes).isEqualTo(0)
    }

    @Test
    fun `concurrent folder runs never observe each other's adopted folder`() = runTest {
        var live = "content://vault-a"
        val repository = mockk<SettingsRepository> {
            coEvery { getExportFolderUri() } answers { live }
            coEvery { saveExportFolderUri(any()) } answers { live = firstArg() }
        }
        val scope = ProfileFolderAdoptionScope(repository)

        data class FolderRun(val binding: String, val seen: ConcurrentLinkedQueue<String>, val deferred: kotlinx.coroutines.Deferred<Unit>)

        val runs = (0 until 6).map { index ->
            val binding = if (index % 2 == 0) "content://vault-b" else "content://vault-c"
            val seen = ConcurrentLinkedQueue<String>()
            val deferred = async {
                scope.withProfileFolder(profile(folderUri = binding)) {
                    seen += live
                    kotlinx.coroutines.delay(10)
                    seen += live
                }
            }
            FolderRun(binding, seen, deferred)
        }
        runs.map { it.deferred }.awaitAll()

        // Runs serialize under the adoption mutex: each run sees its own binding at both
        // sample points — never a foreign folder swapped mid-run.
        runs.forEach { run ->
            assertThat(run.seen).containsExactly(run.binding, run.binding).inOrder()
        }
    }
}

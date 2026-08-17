package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.PendingScheduledExportRequest
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.time.LocalDate

class SharedSetupSettingsTransactionTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var repository: SettingsRepositoryImpl

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { temporaryFolder.newFile("shared-setup.preferences_pb") },
        )
        repository = SettingsRepositoryImpl(dataStore, mockk<Context>(relaxed = true))
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    @Test
    fun `atomic apply stores one rollback snapshot and undo restores exact previous local state`() = runTest {
        val previous = ExportSettings.newInstallDefaults().copy(
            filenameFormat = "before-{date}",
            scheduleEnabled = true,
            pendingScheduledRetryDates = listOf("2026-01-01"),
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(date = LocalDate.of(2026, 1, 2))
            ),
        ).normalized()
        repository.updateExportSettings(previous)
        val candidate = previous.copy(
            filenameFormat = "after-{date}",
            scheduleEnabled = false,
            pendingScheduledRetryDates = emptyList(),
            pendingScheduledExportRequests = emptyList(),
        ).normalized()
        val appleExtension = "{\"extension_version\":1,\"synthetic\":true}"

        assertThat(
            repository.applySharedSetupTransaction(
                expectedCurrent = previous,
                candidate = candidate,
                pendingEndpoint = "https://setup.invalid/health",
                preservedAppleExtension = appleExtension,
            )
        ).isTrue()
        assertThat(repository.getExportSettings()).isEqualTo(candidate)
        assertThat(repository.getSharedSetupUndo()).isEqualTo(previous)
        assertThat(repository.getPendingSharedSetupEndpoint()).isEqualTo("https://setup.invalid/health")
        assertThat(repository.getPreservedSharedSetupAppleExtension()).isEqualTo(appleExtension)

        val restored = repository.undoSharedSetupTransaction(candidate)

        assertThat(restored).isEqualTo(previous)
        assertThat(repository.getExportSettings()).isEqualTo(previous)
        assertThat(repository.getSharedSetupUndo()).isNull()
        assertThat(repository.getPendingSharedSetupEndpoint()).isNull()
        assertThat(repository.getPreservedSharedSetupAppleExtension()).isNull()
    }

    @Test
    fun `rollback after verification failure restores previous settings and transaction metadata`() = runTest {
        val previous = ExportSettings.newInstallDefaults().copy(filenameFormat = "before-{date}", scheduleEnabled = true).normalized()
        repository.updateExportSettings(previous)
        val candidate = previous.copy(filenameFormat = "candidate-{date}", scheduleEnabled = false).normalized()

        assertThat(
            repository.applySharedSetupTransaction(
                expectedCurrent = previous,
                candidate = candidate,
                pendingEndpoint = "https://candidate.invalid/path",
                preservedAppleExtension = "{\"extension_version\":1}",
            )
        ).isTrue()

        val restored = repository.rollbackSharedSetupTransaction(candidate)

        assertThat(restored).isEqualTo(previous)
        assertThat(repository.getExportSettings()).isEqualTo(previous)
        assertThat(repository.getPendingSharedSetupEndpoint()).isNull()
        assertThat(repository.getPreservedSharedSetupAppleExtension()).isNull()
        assertThat(repository.getSharedSetupUndo()).isNull()
    }

    @Test
    fun `endpoint confirmation and verification rollback are compare and set writes`() = runTest {
        val previous = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        repository.updateExportSettings(previous)
        val imported = previous.copy(filenameFormat = "imported-{date}", scheduleEnabled = false).normalized()
        val hint = "https://setup.invalid/health"
        assertThat(repository.applySharedSetupTransaction(previous, imported, hint, "{}")).isTrue()
        val confirmed = imported.copy(apiEndpointUrl = hint).normalized()

        assertThat(repository.confirmSharedSetupEndpoint(imported, hint, confirmed)).isTrue()
        assertThat(repository.getExportSettings()).isEqualTo(confirmed)
        assertThat(repository.getPendingSharedSetupEndpoint()).isNull()

        assertThat(repository.rollbackSharedSetupEndpointConfirmation(confirmed, imported, hint)).isTrue()
        assertThat(repository.getExportSettings()).isEqualTo(imported)
        assertThat(repository.getPendingSharedSetupEndpoint()).isEqualTo(hint)
    }

    @Test
    fun `compare and set mismatch performs zero writes`() = runTest {
        val actual = ExportSettings.newInstallDefaults().copy(filenameFormat = "actual-{date}").normalized()
        repository.updateExportSettings(actual)
        val stale = actual.copy(filenameFormat = "stale-{date}")
        val candidate = actual.copy(filenameFormat = "candidate-{date}")

        assertThat(
            repository.applySharedSetupTransaction(
                expectedCurrent = stale,
                candidate = candidate,
                pendingEndpoint = "https://should-not-write.invalid/path",
                preservedAppleExtension = "{}",
            )
        ).isFalse()

        assertThat(repository.getExportSettings()).isEqualTo(actual)
        assertThat(repository.getSharedSetupUndo()).isNull()
        assertThat(repository.getPendingSharedSetupEndpoint()).isNull()
        assertThat(repository.getPreservedSharedSetupAppleExtension()).isNull()
    }
}

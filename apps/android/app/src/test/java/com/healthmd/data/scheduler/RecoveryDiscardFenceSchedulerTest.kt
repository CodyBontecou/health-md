package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.APIRecoveryAuthorities
import com.healthmd.data.export.DurableAPIExportBatch
import com.healthmd.data.export.DurableAPIExportOperation
import com.healthmd.data.export.FileAPIExportOperationStore
import com.healthmd.data.export.RecoveryDiscardFence
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.export.FakeBillingRepository
import com.healthmd.export.FakeExportHistoryRepository
import com.healthmd.export.FakeExportRepository
import com.healthmd.export.FakeHealthRepository
import com.healthmd.export.FakeSettingsRepository
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class RecoveryDiscardFenceSchedulerTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test
    fun defaultDiscardRevokesExactAdmittedWorkerWithoutChangingTheNextOccurrenceOrFolderRecovery() = runTest {
        val h = harness(ownedAdmission = true)
        val store = FileAPIExportOperationStore(h.context)
        val operation = compatibility(h.pending.apiOperationId!!)
        store.create(operation)
        store.create(operation.copy(operationId = "past"))
        store.acknowledge("past", 0)

        assertThat(h.manager.discardPendingAPIRecovery()).isTrue()

        assertThat(h.state.load()).isEqualTo(h.next)
        assertThat(h.state.loadAdmission()).isNull()
        assertThat(h.state.markAdmissionExecutionCompleted(h.admission.occurrence, h.admission.operationId, h.admission.workRequestId)).isFalse()
        assertThat(h.settings.getExportSettings().pendingScheduledExportRequests).containsExactly(h.folder)
        assertThat(h.settings.getExportSettings().scheduleEnabled).isTrue()
        assertThat(h.settings.getExportSettings().apiEndpointUrl).isEqualTo("https://synthetic.example.test")
        assertThat(h.history.entries).isEmpty()
        assertThat(h.health.fetchedDates).isEmpty()
        assertThat(runCatching { store.create(operation) }.isFailure).isTrue()
        assertThat(store.load("past")!!.acknowledgedBatchCount).isEqualTo(1)
    }

    @Test
    fun matchingConfigurationAloneDoesNotAuthorizeDiscardOfAnUnrelatedActiveAdmission() = runTest {
        val h = harness(ownedAdmission = false)

        assertThat(h.manager.discardPendingAPIRecovery()).isTrue()

        assertThat(h.state.loadAdmission()).isEqualTo(h.admission)
        assertThat(h.state.load()).isEqualTo(h.next)
        assertThat(RecoveryDiscardFence(h.context.noBackupFilesDir).isDiscarded(h.admission.operationId)).isFalse()
        assertThat(h.settings.getExportSettings().pendingScheduledExportRequests).containsExactly(h.folder)
    }

    @Test
    fun defaultWorkerResumingAnOlderNativeVerifiedPendingOperationIsAlsoRevoked() = runTest {
        val h = harness(ownedAdmission = false, validPendingAuthority = true)
        assertThat(h.pending.apiOperationId).isNotEqualTo(h.admission.operationId)

        assertThat(h.manager.discardPendingAPIRecovery()).isTrue()

        assertThat(h.state.loadAdmission()).isNull()
        assertThat(h.state.load()).isEqualTo(h.next)
        assertThat(RecoveryDiscardFence(h.context.noBackupFilesDir).isDiscarded(h.admission.operationId)).isTrue()
        assertThat(RecoveryDiscardFence(h.context.noBackupFilesDir).isDiscarded(h.pending.apiOperationId!!)).isTrue()
        assertThat(h.health.fetchedDates).isEmpty()
    }

    @Test
    fun startupReplaysFenceBeforeDefaultAdmissionAndPendingClearWithNoReadOrHistoryMutation() = runTest {
        val h = harness(ownedAdmission = true)
        RecoveryDiscardFence(h.context.noBackupFilesDir).discard(listOf(h.admission.operationId))

        h.manager.inspectPendingRecovery()

        assertThat(h.state.loadAdmission()).isNull()
        assertThat(h.state.load()).isEqualTo(h.next)
        assertThat(h.state.markAdmissionExecutionCompleted(h.admission.occurrence, h.admission.operationId, h.admission.workRequestId)).isFalse()
        assertThat(h.settings.getExportSettings().pendingScheduledExportRequests).containsExactly(h.folder)
        assertThat(h.history.entries).isEmpty()
        assertThat(h.health.fetchedDates).isEmpty()
    }

    private fun harness(ownedAdmission: Boolean, validPendingAuthority: Boolean = false): Harness {
        val root = temporaryFolder.newFolder()
        val app = ApplicationProvider.getApplicationContext<Context>()
        val preferences = app.getSharedPreferences("synthetic-discard-${root.name}", Context.MODE_PRIVATE)
        val context = mockk<Context> {
            every { noBackupFilesDir } returns root
            every { getSharedPreferences(any(), any()) } returns preferences
        }
        val settings = ExportSettings(scheduleEnabled = true, scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://synthetic.example.test")
        val occurrence = ScheduledExportOccurrence(ScheduledExportConfiguration.from(settings, "a".repeat(64), ZoneId.of("UTC")),
            1_000_000L, day.plusDays(1), "synthetic-generation")
        val next = occurrence.copy(triggerAtMillis = 2_000_000L)
        val admission = ScheduledExportAdmission.create(occurrence, occurrence.triggerAtMillis, false)
        val state = ScheduledExportStateStore(context)
        state.save(occurrence)
        check(state.prepareAdmission(admission, next))
        val credentials = object : APIExportCredentialStore {
            override suspend fun authorizationHeader(): String? = null
            override suspend fun hasAuthorization() = false
            override suspend fun saveAuthorization(value: String) = Unit
            override suspend fun clearAuthorization() = Unit
            override suspend fun destinationFingerprint(endpointUrl: String) = "a".repeat(64)
        }
        val proof = APIRecoveryAuthorities.create(APIExportRequestConfiguration(settings.apiEndpointUrl, null, emptyList(), "a".repeat(64)), null)
        val pending = PendingScheduledExportRequest(day, exportTarget = ExportTarget.API_ENDPOINT,
            destinationFingerprint = "a".repeat(64), apiOperationId = if (ownedAdmission) admission.operationId else "unrelated-recovery",
            apiAuthorityJson = proof.takeIf { validPendingAuthority })
        val folder = PendingScheduledExportRequest(day.minusDays(1), firstFailedAtMillis = 123L)
        val repository = FakeSettingsRepository(initialSettings = settings.copy(pendingScheduledExportRequests = listOf(pending, folder)),
            initialFolderUri = "content://synthetic", initialPurchased = true)
        val history = FakeExportHistoryRepository()
        val health = FakeHealthRepository()
        val manager = ScheduledExportRecoveryManager(context, health, FakeExportRepository(), repository, history,
            entitlementRepository = FakeBillingRepository(), distributionPolicy = DistributionPolicy.play(), stateStore = state,
            apiCredentialStore = credentials.takeIf { validPendingAuthority })
        return Harness(context, state, admission, next, pending, folder, repository, history, health, manager)
    }

    private data class Harness(val context: Context, val state: ScheduledExportStateStore, val admission: ScheduledExportAdmission,
        val next: ScheduledExportOccurrence, val pending: PendingScheduledExportRequest, val folder: PendingScheduledExportRequest,
        val settings: FakeSettingsRepository, val history: FakeExportHistoryRepository, val health: FakeHealthRepository,
        val manager: ScheduledExportRecoveryManager)
    private val day = LocalDate.ofEpochDay(10_000)
    private fun compatibility(id: String) = DurableAPIExportOperation(id, "a".repeat(64), ExportEngineMode.legacy,
        null, null, listOf(day), setOf(day), emptyList(),
        listOf(DurableAPIExportBatch(0, "POST/api-v1.json", listOf(day), "synthetic".encodeToByteArray())))
}

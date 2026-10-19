package com.healthmd.data.scheduler

import android.content.Context
import android.app.job.JobScheduler
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.await
import androidx.work.impl.WorkManagerImpl
import androidx.work.workDataOf
import com.healthmd.data.export.EncryptedAPIExportCredentialStore
import com.healthmd.domain.model.ExportTarget
import com.healthmd.sharedsetup.SharedSetupInstrumentationEntryPoint
import dagger.hilt.android.EntryPointAccessors
import java.io.File
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Real DataStore/WorkManager repair coverage in the disposable E2E package. Export requests have
 * a one-day delay and are cancelled during cleanup; the only executed worker repairs scheduling.
 * A repeated repair for the same generation must preserve the already armed fallback identity.
 *
 * Optional process-death host path: run seedInterruptedDiscardState with
 * `-e pr194InterruptionQa true`, kill the E2E process without force-stopping the package or opening
 * MainActivity, force only the checkpoint's repair JobScheduler ID, then run verifyRecoveredState
 * with the same argument. On API 34+, include the checkpoint's WorkManager namespace:
 * `cmd jobscheduler run -f -n androidx.work.systemjobscheduler com.healthmd.android.e2e JOB_ID`.
 * WorkManager startup may reconcile and reschedule that job; if so, force its replacement ID
 * after startup finishes and wait for worker success before opening verification instrumentation.
 * The repair has a five-minute delay to prevent racing the host driver.
 */
@RunWith(AndroidJUnit4::class)
class ScheduledProfileDiscardInterruptionRuntimeTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val services: SharedSetupInstrumentationEntryPoint get() =
        EntryPointAccessors.fromApplication(context, SharedSetupInstrumentationEntryPoint::class.java)
    private val workManager: WorkManager get() = WorkManager.getInstance(context)
    private val checkpointFile: File get() = File(context.filesDir, "scheduled-discard-interruption-qa.json")
    private val json = Json

    @Test
    fun persistedRepairRunsThroughHiltAndRearmsWithoutExporting() {
        assumeTrue("Requires the isolated E2E variant", context.packageName == E2E_PACKAGE)
        requireIsolatedPackage()
        runBlocking {
            check(!checkpointFile.exists()) { "Complete or clean up the staged interruption QA first" }
            val checkpoint = seedInterruptedState(repairDelaySeconds = 5)
            try {
                verifyRecovery(checkpoint)
                val fallbackBefore = unfinishedFallback(checkpoint.profileId)
                services.scheduledProfileScheduler().finishRecoveryDiscard(
                    checkpoint.profileId, 1L, listOf(UUID.fromString(checkpoint.oldExportId)),
                )
                val fallbackAfter = unfinishedFallback(checkpoint.profileId)
                assertEquals("A delayed same-generation repair must preserve the armed fallback", fallbackBefore.id, fallbackAfter.id)
                assertEquals(WorkInfo.State.ENQUEUED, fallbackAfter.state)
            } finally {
                cleanup(checkpoint)
            }
        }
    }

    @Test
    fun seedInterruptedDiscardState() {
        requireHostOptIn()
        runBlocking {
            check(!checkpointFile.exists()) { "A staged interruption scenario already exists" }
            val checkpoint = seedInterruptedState(repairDelaySeconds = 300)
            assertEquals(1L, services.scheduledProfileEntryStore().entry(checkpoint.profileId)?.recoveryGeneration)
            assertEquals(WorkInfo.State.ENQUEUED, workInfo(checkpoint.oldExportId).state)
            assertEquals(WorkInfo.State.ENQUEUED, workInfo(checkpoint.repairId).state)
            Log.i(TAG, "SEEDED repair=${checkpoint.repairId} job=${checkpoint.repairJobId}; kill the E2E process and force only this repair job")
        }
    }

    @Test
    fun verifyRecoveredState() {
        requireHostOptIn()
        runBlocking {
            val checkpoint = readCheckpoint()
            try {
                verifyRecovery(checkpoint)
            } finally {
                cleanup(checkpoint)
            }
        }
    }

    @Test
    fun cleanupInterruptedDiscardState() {
        requireHostOptIn()
        runBlocking {
            if (checkpointFile.exists()) cleanup(readCheckpoint())
        }
    }

    private fun requireHostOptIn() {
        assumeTrue(
            "Staged process-death QA requires an explicit host driver",
            InstrumentationRegistry.getArguments().getString("pr194InterruptionQa") == "true",
        )
        requireIsolatedPackage()
    }

    private fun requireIsolatedPackage() {
        check(context.packageName == E2E_PACKAGE) { "Interruption QA may only modify the disposable E2E app" }
    }

    private suspend fun seedInterruptedState(repairDelaySeconds: Long): Checkpoint {
        val profiles = services.exportProfileRepository()
        val store = services.scheduledProfileEntryStore()
        val dataStore = actualDataStore()
        val before = dataStore.data.first()
        val originalProfiles = before[PROFILES_KEY]
        val originalActive = before[ACTIVE_KEY]
        val credentialDigest = credentialDigest()
        val currentSettings = services.settingsRepository().getExportSettings()
        val snapshot = services.profileSnapshotFactory().captureFromCurrent(
            current = currentSettings, target = ExportTarget.DEVICE_FOLDER,
        )
        val profile = profiles.add(
            name = "Interruption QA ${UUID.randomUUID()}", settingsSnapshotJson = snapshot,
            target = ExportTarget.DEVICE_FOLDER,
        )
        val now = ZonedDateTime.now(ZoneId.of("UTC"))
        val future = now.plusHours(2)
        val pending = ScheduledProfilePendingExport(
            id = UUID.randomUUID().toString(),
            ownerEpochDays = listOf(LocalDate.of(2026, 9, 10).toEpochDay()),
            fireAtMillis = 10_000L, settingsSnapshotJson = snapshot,
            target = ExportTarget.DEVICE_FOLDER, profileName = profile.name,
        )
        val entry = ScheduledProfileEntry(
            profileId = profile.id, isEnabled = true,
            anchorEpochDay = now.toLocalDate().toEpochDay(),
            hour = future.hour, minute = future.minute, zoneId = "UTC", lookbackDays = 1,
            lastSuccessEpochMillis = COMPLETED_FRONTIER,
            lastRefreshSuccessEpochMillis = REFRESH_FRONTIER,
            pendingExports = listOf(pending),
        )
        val oldExport = OneTimeWorkRequestBuilder<ScheduledProfileExportWorker>()
            .setInitialDelay(1, TimeUnit.DAYS)
            .setInputData(workDataOf(
                ScheduledProfileExportWorker.INPUT_PROFILE_ID to profile.id,
                ScheduledProfileExportWorker.INPUT_RECOVERY_GENERATION to 0L,
            ))
            .build()
        val oldFallback = OneTimeWorkRequestBuilder<ScheduledProfileTriggerWorker>()
            .setInitialDelay(1, TimeUnit.DAYS)
            .setInputData(workDataOf(
                ScheduledProfileTriggerWorker.INPUT_PROFILE_ID to profile.id,
                ScheduledProfileTriggerWorker.INPUT_RECOVERY_GENERATION to 0L,
            ))
            .build()
        val repair = OneTimeWorkRequestBuilder<ScheduledProfileReconcileWorker>()
            .setInitialDelay(repairDelaySeconds, TimeUnit.SECONDS)
            .setInputData(workDataOf(
                ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to profile.id,
                ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION to 1L,
                ScheduledProfileReconcileWorker.INPUT_OLD_EXPORT_WORK_IDS to arrayOf(oldExport.id.toString()),
            ))
            .build()
        val checkpoint = Checkpoint(
            profile.id, oldExport.id.toString(), oldFallback.id.toString(), repair.id.toString(),
            originalProfiles, originalActive, credentialDigest,
            repairJobNamespace = if (Build.VERSION.SDK_INT >= 34) WORK_MANAGER_NAMESPACE else null,
        )
        // Save the exact cleanup scope before durable work can outlive this test process.
        try {
            checkpointFile.writeText(json.encodeToString(Checkpoint.serializer(), checkpoint))
            assertTrue(store.upsert(entry))
            workManager.enqueueUniqueWork(
                ScheduledProfileScheduler.exportWorkName(profile.id), ExistingWorkPolicy.REPLACE, oldExport,
            ).await()
            workManager.enqueueUniqueWork(
                ScheduledProfileScheduler.fallbackName(profile.id), ExistingWorkPolicy.REPLACE, oldFallback,
            ).await()
            workManager.enqueueUniqueWork(
                ScheduledProfileScheduler.reconcileWorkName(profile.id), ExistingWorkPolicy.REPLACE, repair,
            ).await()
            val registeredCheckpoint = checkpoint.copy(repairJobId = awaitRepairJobId(repair.id))
            checkpointFile.writeText(json.encodeToString(Checkpoint.serializer(), registeredCheckpoint))
            // Model the killed transition after its store commit but before runtime cancellation.
            assertTrue(store.discardPendingRecovery(profile.id))
            assertTrue(requireNotNull(store.entry(profile.id)).pendingExports.isEmpty())
            return registeredCheckpoint
        } catch (error: Throwable) {
            cleanup(checkpoint)
            throw error
        }
    }

    private suspend fun verifyRecovery(checkpoint: Checkpoint) {
        val repair = withTimeout(30_000L) {
            workManager.getWorkInfoByIdFlow(UUID.fromString(checkpoint.repairId))
                .first { it?.state?.isFinished == true }
        }
        assertEquals("The actual Hilt repair worker must finish", WorkInfo.State.SUCCEEDED, repair?.state)
        assertEquals(WorkInfo.State.CANCELLED, workInfo(checkpoint.oldExportId).state)
        val oldFallback = workManager.getWorkInfoById(UUID.fromString(checkpoint.oldFallbackId))
            .get(2, TimeUnit.SECONDS)
        assertTrue(
            "The replaced old fallback must be cancelled or removed, never unfinished",
            oldFallback == null || oldFallback.state == WorkInfo.State.CANCELLED,
        )
        val entry = requireNotNull(services.scheduledProfileEntryStore().entry(checkpoint.profileId))
        assertTrue(entry.isEnabled)
        assertEquals(1L, entry.recoveryGeneration)
        assertTrue(entry.pendingExports.isEmpty())
        assertEquals(COMPLETED_FRONTIER, entry.lastSuccessEpochMillis)
        assertEquals(REFRESH_FRONTIER, entry.lastRefreshSuccessEpochMillis)
        assertEquals(checkpoint.credentialDigest, credentialDigest())
        val exports = workManager.getWorkInfosForUniqueWork(
            ScheduledProfileScheduler.exportWorkName(checkpoint.profileId),
        ).get(2, TimeUnit.SECONDS)
        assertTrue("Repair must never enqueue a fresh export", exports.all { it.id.toString() == checkpoint.oldExportId })
        val fallback = workManager.getWorkInfosForUniqueWork(
            ScheduledProfileScheduler.fallbackName(checkpoint.profileId),
        ).get(2, TimeUnit.SECONDS).single { !it.state.isFinished }
        assertEquals(WorkInfo.State.ENQUEUED, fallback.state)
        val spec = requireNotNull(WorkManagerImpl.getInstance(context).workDatabase.workSpecDao().getWorkSpec(fallback.id.toString()))
        assertEquals(1L, spec.input.getLong(ScheduledProfileTriggerWorker.INPUT_RECOVERY_GENERATION, -1L))
        assertTrue("Only a future ordinary boundary may be armed", spec.calculateNextRunTime() > System.currentTimeMillis())
        Log.i(TAG, "RECOVERED generation=1 old export cancelled; future fallback armed; no upload admitted")
    }

    private fun workInfo(id: String): WorkInfo = requireNotNull(
        workManager.getWorkInfoById(UUID.fromString(id)).get(2, TimeUnit.SECONDS),
    )

    private fun unfinishedFallback(profileId: String): WorkInfo = workManager.getWorkInfosForUniqueWork(
        ScheduledProfileScheduler.fallbackName(profileId),
    ).get(2, TimeUnit.SECONDS).single { !it.state.isFinished }

    private suspend fun awaitRepairJobId(id: UUID): Int {
        val defaultJobs = context.getSystemService(JobScheduler::class.java)
        val jobs = if (Build.VERSION.SDK_INT >= 34) defaultJobs.forNamespace(WORK_MANAGER_NAMESPACE) else defaultJobs
        val deadline = SystemClock.elapsedRealtime() + 5_000L
        while (SystemClock.elapsedRealtime() < deadline) {
            jobs.allPendingJobs.firstOrNull {
                it.extras.getString("EXTRA_WORK_SPEC_ID") == id.toString()
            }?.let { return it.id }
            delay(50)
        }
        error("The durable repair must have a registered JobScheduler job")
    }

    private suspend fun cleanup(checkpoint: Checkpoint) = withContext(NonCancellable) {
        workManager.cancelUniqueWork(ScheduledProfileScheduler.reconcileWorkName(checkpoint.profileId)).await()
        workManager.cancelWorkById(UUID.fromString(checkpoint.oldExportId)).await()
        services.scheduledProfileScheduler().removeEntry(checkpoint.profileId)
        actualDataStore().edit { preferences ->
            if (checkpoint.originalProfiles == null) preferences.remove(PROFILES_KEY)
            else preferences[PROFILES_KEY] = checkpoint.originalProfiles
            if (checkpoint.originalActive == null) preferences.remove(ACTIVE_KEY)
            else preferences[ACTIVE_KEY] = checkpoint.originalActive
        }
        check(checkpointFile.delete() || !checkpointFile.exists()) { "Could not remove interruption QA checkpoint" }
    }

    private suspend fun credentialDigest(): String {
        val credentials = EncryptedAPIExportCredentialStore(context)
        val values = listOf(credentials.authorizationHeader().orEmpty()) +
            credentials.requestHeaders().flatMap { listOf(it.name, it.value) }
        val bytes = values.joinToString("") { "${it.length}:$it" }.toByteArray(Charsets.UTF_8)
        return MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    }

    // Existing production entrypoint supplies the same real DataStore used by profiles/schedules.
    // Preserve exact absence/bytes so even a fresh E2E install needs no retained synthetic profile.
    @Suppress("UNCHECKED_CAST")
    private fun actualDataStore(): DataStore<Preferences> =
        services.scheduledProfileEntryStore().javaClass.getDeclaredField("dataStore").let { field ->
            field.isAccessible = true
            field.get(services.scheduledProfileEntryStore()) as DataStore<Preferences>
        }

    private fun readCheckpoint(): Checkpoint = json.decodeFromString(Checkpoint.serializer(), checkpointFile.readText())

    @Serializable
    private data class Checkpoint(
        val profileId: String,
        val oldExportId: String,
        val oldFallbackId: String,
        val repairId: String,
        val originalProfiles: String?,
        val originalActive: String?,
        val credentialDigest: String,
        val repairJobId: Int? = null,
        val repairJobNamespace: String? = null,
    )

    private companion object {
        const val E2E_PACKAGE = "com.healthmd.android.e2e"
        const val TAG = "DiscardInterruptionQA"
        const val WORK_MANAGER_NAMESPACE = "androidx.work.systemjobscheduler"
        const val COMPLETED_FRONTIER = 1_000L
        const val REFRESH_FRONTIER = 2_000L
        val PROFILES_KEY = stringPreferencesKey("export_profiles")
        val ACTIVE_KEY = stringPreferencesKey("export_profiles_active_id")
    }
}

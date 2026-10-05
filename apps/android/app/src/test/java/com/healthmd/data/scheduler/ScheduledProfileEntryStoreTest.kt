package com.healthmd.data.scheduler

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportTarget
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.APIRecoveryAuthorities
import com.healthmd.data.export.DurableAPIExportBatch
import com.healthmd.data.export.DurableAPIExportOperation
import com.healthmd.data.export.FileAPIExportOperationStore
import com.healthmd.data.export.RecoveryDiscardFence
import com.healthmd.domain.exportengine.ExportEngineMode
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Fresh-store and corruption boundaries for the profile schedule DataStore payload. */
class ScheduledProfileEntryStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: ScheduledProfileEntryStore
    private lateinit var context: Context

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStoreFile = temporaryFolder.newFolder().resolve("scheduled_profiles.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { dataStoreFile },
        )
        val privateRoot = temporaryFolder.newFolder("private")
        context = mockk<Context> { every { noBackupFilesDir } returns privateRoot }
        store = ScheduledProfileEntryStore(dataStore = dataStore, context = context)
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    private fun entry(profileId: String, hour: Int = 8) = ScheduledProfileEntry(
        profileId = profileId,
        anchorEpochDay = 20_000,
        hour = hour,
        zoneId = "UTC",
    )

    @Test
    fun `discard refuses a pending pointer rebound to another operation authority`() = runTest {
        val day = LocalDate.ofEpochDay(10_000)
        val pending = ScheduledProfilePendingExport("pending", listOf(day.toEpochDay()), 1000L, "snapshot",
            ExportTarget.API_ENDPOINT, "Synthetic", durableOperationId = "operation", apiAuthorityJson = "original-proof")
        val original = entry("alpha").copy(isEnabled = true, pendingExports = listOf(pending))
        store.upsert(original)
        val journals = FileAPIExportOperationStore(context)
        journals.create(DurableAPIExportOperation("operation", "a".repeat(64), ExportEngineMode.legacy,
            null, "snapshot", listOf(day), setOf(day), emptyList(),
            listOf(DurableAPIExportBatch(0, "POST/api-v1.json", listOf(day), "synthetic".encodeToByteArray())),
            apiAuthorityJson = "different-proof"))

        assertThat(store.discardPendingRecovery("alpha")).isFalse()

        assertThat(store.entry("alpha")).isEqualTo(original)
        assertThat(journals.load("operation")!!.apiAuthorityJson).isEqualTo("different-proof")
    }

    @Test
    fun `startup replays fence before pending clear and rejects late callbacks before generation commit`() = runTest {
        val pending = ScheduledProfilePendingExport("pending", listOf(10_000L), 1000L, "snapshot",
            ExportTarget.API_ENDPOINT, "Synthetic", durableOperationId = "owned-operation")
        val original = entry("alpha").copy(isEnabled = true, pendingExports = listOf(pending),
            lastSuccessEpochMillis = 123L, lastRefreshSuccessEpochMillis = 456L)
        store.upsert(original)
        RecoveryDiscardFence(context.noBackupFilesDir).discard(listOf("owned-operation"), "alpha", 0L)
        // The disk fence is durable but the original DataStore generation is deliberately still zero.
        assertThat(store.recordRetry("alpha", 999L, pending.id, listOf(pending), 0L)).isFalse()
        assertThat(store.markAPIJournalRequired("alpha", 0L, pending.id, "unverified", "owned-operation")).isFalse()
        val restarted = ScheduledProfileEntryStore(dataStore, context)
        assertThat(restarted.entry("alpha")).isEqualTo(original.copy(pendingExports = emptyList(), recoveryGeneration = 1L))
        assertThat(restarted.entry("alpha")!!.recoveryGeneration).isEqualTo(1L)
    }

    @Test
    fun `discard purges only owned private bodies and late create cannot resurrect them`() = runTest {
        val day = LocalDate.ofEpochDay(10_000)
        val authority = APIRecoveryAuthorities.create(APIExportRequestConfiguration(
            "https://synthetic.example.test", null, emptyList(), "a".repeat(64)), "alpha")
        val pending = ScheduledProfilePendingExport("pending", listOf(day.toEpochDay()), 1000L, "snapshot",
            ExportTarget.API_ENDPOINT, "Synthetic", durableOperationId = "owned-operation", apiAuthorityJson = authority)
        store.upsert(entry("alpha").copy(isEnabled = true, pendingExports = listOf(pending),
            lastSuccessEpochMillis = 123L, lastRefreshSuccessEpochMillis = 456L))
        val journals = FileAPIExportOperationStore(context)
        val owned = DurableAPIExportOperation("owned-operation", "a".repeat(64), ExportEngineMode.legacy,
            null, "snapshot", listOf(day), setOf(day), emptyList(),
            listOf(DurableAPIExportBatch(0, "POST/api-v1.json", listOf(day), "synthetic".encodeToByteArray())),
            apiAuthorityJson = authority)
        val past = owned.copy(operationId = "past-operation")
        journals.create(owned)
        journals.create(past)
        journals.acknowledge(past.operationId, 0)

        assertThat(store.discardPendingRecovery("alpha")).isTrue()

        assertThat(context.noBackupFilesDir.walkTopDown().filter { it.name.startsWith("body-") }.count()).isEqualTo(1)
        val restarted = FileAPIExportOperationStore(context)
        assertThat(runCatching { restarted.create(owned) }.isFailure).isTrue()
        assertThat(restarted.load(past.operationId)!!.acknowledgedBatchCount).isEqualTo(1)
        val cleared = store.entry("alpha")!!
        assertThat(cleared.pendingExports).isEmpty()
        assertThat(cleared.lastSuccessEpochMillis).isEqualTo(123L)
        assertThat(cleared.lastRefreshSuccessEpochMillis).isEqualTo(456L)
    }

    @Test
    fun `prepared delivery fence persists and stale discard callback cannot recreate it`() = runTest {
        store.upsert(entry("alpha").copy(isEnabled = true, lastSuccessEpochMillis = 1234L))
        val authority = APIRecoveryAuthorities.create(APIExportRequestConfiguration(
            "https://synthetic.example.test", null, emptyList(), "a".repeat(64)), "alpha")
        val pending = ScheduledProfilePendingExport("pending", listOf(1L), 1000L, "snapshot",
            ExportTarget.API_ENDPOINT, "Synthetic", durableOperationId = "operation", apiAuthorityJson = authority)
        assertThat(store.admitAPIExport("alpha", 0L, pending)).isTrue()
        assertThat(store.markAPIJournalRequired("alpha", 0L, pending.id, authority, "wrong-operation")).isFalse()
        assertThat(store.markAPIJournalRequired("alpha", 0L, pending.id, authority, "operation")).isTrue()
        val reloaded = ScheduledProfileEntryStore(dataStore, context)
        assertThat(reloaded.entry("alpha")!!.pendingExports.single().apiJournalRequired).isTrue()
        assertThat(store.discardPendingRecovery("alpha")).isTrue()
        assertThat(store.markAPIJournalRequired("alpha", 0L, pending.id, authority, "operation")).isFalse()
        assertThat(reloaded.entry("alpha")!!.pendingExports).isEmpty()
        assertThat(reloaded.entry("alpha")!!.lastSuccessEpochMillis).isEqualTo(1234L)
    }

    @Test
    fun `upsert creates the first entry when the key is absent`() = runTest {
        assertThat(dataStore.data.first().asMap().keys.map { it.name })
            .doesNotContain(ENTRIES_KEY.name)

        assertThat(store.upsert(entry("first"))).isTrue()

        assertThat(store.getEntries().map { it.profileId }).containsExactly("first")
        assertThat(dataStore.data.first()[ENTRIES_KEY]).isNotNull()
    }

    @Test
    fun `upsert preserves other profiles and replaces only the matching id`() = runTest {
        store.upsert(entry("alpha", hour = 8))
        store.upsert(entry("beta", hour = 9))
        store.upsert(entry("alpha", hour = 10))

        val entries = store.getEntries()
        assertThat(entries.map { it.profileId }).containsExactly("alpha", "beta").inOrder()
        assertThat(entries.single { it.profileId == "alpha" }.hour).isEqualTo(10)
        assertThat(entries.single { it.profileId == "beta" }.hour).isEqualTo(9)
    }

    @Test
    fun `configuration upsert preserves a newer worker success frontier`() = runTest {
        assertThat(
            store.upsert(entry("alpha").copy(lastSuccessEpochMillis = 1234L)),
        ).isTrue()

        assertThat(store.upsert(entry("alpha", hour = 10))).isTrue()

        val stored = store.entry("alpha")!!
        assertThat(stored.hour).isEqualTo(10)
        assertThat(stored.lastSuccessEpochMillis).isEqualTo(1234L)
    }

    @Test
    fun `concurrent progress and configuration updates preserve both changes`() = runTest {
        store.upsert(entry("alpha", hour = 8))

        listOf(
            async(Dispatchers.Default) {
                store.update("alpha") { it.copy(hour = 10) }
            },
            async(Dispatchers.Default) {
                store.recordSuccess("alpha", fireAtMillis = 5678L)
            },
        ).awaitAll()

        val stored = store.entry("alpha")!!
        assertThat(stored.hour).isEqualTo(10)
        assertThat(stored.lastSuccessEpochMillis).isEqualTo(5678L)
    }

    @Test
    fun `backoff retry checkpoint survives configuration upsert and clears individually`() = runTest {
        store.upsert(entry("alpha").copy(isEnabled = true))
        val first = ScheduledProfilePendingExport(
            id = "pending-first",
            ownerEpochDays = listOf(20_001L),
            fireAtMillis = 1_000L,
            settingsSnapshotJson = "snapshot-a",
            target = ExportTarget.DEVICE_FOLDER,
            profileName = "Alpha",
        )
        val second = first.copy(id = "pending-second", ownerEpochDays = listOf(20_002L))

        store.recordRetry(
            profileId = "alpha",
            fireAtMillis = 1_000L,
            attemptedPendingID = null,
            replacements = listOf(first, second),
        )
        // A stale settings draft must not erase worker-owned retry state.
        store.upsert(entry("alpha", hour = 10))

        val checkpoint = store.entry("alpha")!!
        assertThat(checkpoint.lastSuccessEpochMillis).isEqualTo(1_000L)
        assertThat(checkpoint.pendingExports).containsExactly(first, second).inOrder()

        store.recordSuccess(
            profileId = "alpha",
            fireAtMillis = 1_000L,
            completedPendingID = first.id,
        )
        assertThat(store.entry("alpha")!!.pendingExports).containsExactly(second)
    }

    @Test
    fun `cancellation checkpoint fails closed when the profile row is missing`() = runTest {
        val residual = ScheduledProfilePendingExport(
            id = "missing-residual",
            ownerEpochDays = listOf(20_001L),
            fireAtMillis = 1_000L,
            settingsSnapshotJson = "snapshot",
            target = ExportTarget.DEVICE_FOLDER,
            profileName = "Missing",
        )

        assertThat(
            store.recordCancellation(
                profileId = "missing",
                fireAtMillis = 1_000L,
                attemptedPendingID = null,
                replacements = listOf(residual),
            ),
        ).isFalse()
    }

    @Test
    fun `refresh-only success advances the refresh frontier without touching catch-up`() = runTest {
        store.upsert(entry("alpha").copy(isEnabled = true, lastSuccessEpochMillis = 900L))

        store.recordSuccess(profileId = "alpha", fireAtMillis = null)
        store.recordRefreshSuccess(profileId = "alpha", slotMillis = 2_000L)

        val stored = store.entry("alpha")!!
        assertThat(stored.lastSuccessEpochMillis).isEqualTo(900L)
        assertThat(stored.lastRefreshSuccessEpochMillis).isEqualTo(2_000L)

        // A later, earlier refresh checkpoint never moves the frontier backwards.
        store.recordRefreshSuccess(profileId = "alpha", slotMillis = 1_500L)
        assertThat(store.entry("alpha")!!.lastRefreshSuccessEpochMillis).isEqualTo(2_000L)
    }

    @Test
    fun `refresh-only retry keeps residuals empty and the frontier frozen`() = runTest {
        store.upsert(entry("alpha").copy(isEnabled = true, lastSuccessEpochMillis = 900L))

        assertThat(
            store.recordRetry(
                profileId = "alpha",
                fireAtMillis = null,
                attemptedPendingID = null,
                replacements = emptyList(),
            ),
        ).isTrue()

        val stored = store.entry("alpha")!!
        assertThat(stored.lastSuccessEpochMillis).isEqualTo(900L)
        assertThat(stored.pendingExports).isEmpty()
    }

    @Test
    fun `blocked imported profile cannot be enabled by upsert update or legacy migration`() = runTest {
        assertThat(store.upsert(entry("blocked"))).isTrue()
        dataStore.edit {
            it[com.healthmd.sharedsetup.SharedSetupV2ProfilePersistence.blockedProfileIdsKey] =
                setOf("blocked")
        }

        assertThat(store.upsert(entry("blocked").copy(isEnabled = true))).isFalse()
        assertThat(store.update("blocked") { it.copy(isEnabled = true) }).isFalse()
        assertThat(store.entry("blocked")!!.isEnabled).isFalse()

        store.delete("blocked")
        assertThat(store.beginLegacyMigration(entry("blocked").copy(isEnabled = true))).isFalse()
        assertThat(store.getEntries()).isEmpty()
    }

    @Test
    fun `legacy migration entry and pending marker commit together`() = runTest {
        val migrated = entry("default").copy(isEnabled = true)

        assertThat(store.beginLegacyMigration(migrated)).isTrue()
        assertThat(store.entry("default")).isEqualTo(migrated)
        assertThat(store.pendingLegacyMigrationProfileId()).isEqualTo("default")

        assertThat(store.finishLegacyMigration("default")).isTrue()
        assertThat(store.pendingLegacyMigrationProfileId()).isNull()
    }

    @Test
    fun `malformed present payload blocks writes without replacing its bytes`() = runTest {
        val corrupt = "{not-json"
        dataStore.edit { it[ENTRIES_KEY] = corrupt }

        assertThat(store.upsert(entry("must-not-overwrite"))).isFalse()

        assertThat(dataStore.data.first()[ENTRIES_KEY]).isEqualTo(corrupt)
        assertThat(store.getEntries()).isEmpty()
    }

    @Test
    fun `concurrent first writes retain both profiles`() = runTest {
        listOf("alpha", "beta").map { profileId ->
            async(Dispatchers.Default) { store.upsert(entry(profileId)) }
        }.awaitAll()

        assertThat(store.getEntries().map { it.profileId })
            .containsExactly("alpha", "beta")
    }

    @Test
    fun `discard clears only this profile recovery and admits the current window`() = runTest {
        val zone = ZoneId.of("UTC")
        val today = LocalDate.of(2026, 9, 20)
        val oldFire = today.minusDays(7).atTime(8, 0).atZone(zone).toInstant().toEpochMilli()
        val pending = ScheduledProfilePendingExport(
            id = "historical-recovery",
            ownerEpochDays = (10..12).map { LocalDate.of(2026, 9, it).toEpochDay() },
            fireAtMillis = oldFire, settingsSnapshotJson = "old-snapshot",
            target = ExportTarget.API_ENDPOINT, profileName = "Synthetic API",
            apiEndpointUrl = "https://example.test/export", durableOperationId = "old-operation",
        )
        val original = entry("alpha").copy(
            isEnabled = true, anchorEpochDay = today.minusDays(20).toEpochDay(), lookbackDays = 1,
            todayRefreshEnabled = true, todayRefreshIntervalHours = 3,
            lastSuccessEpochMillis = oldFire, pendingExports = listOf(pending),
        )
        store.upsert(original)
        store.upsert(entry("beta"))
        val now = today.atTime(13, 0).atZone(zone).toInstant().toEpochMilli()
        assertThat(ScheduledProfileOccurrenceMath.dueOccurrence(store.entry("alpha")!!, now)!!.pendingExport)
            .isEqualTo(pending)

        assertThat(store.discardPendingRecovery("alpha")).isTrue()

        val cleared = store.entry("alpha")!!
        assertThat(cleared).isEqualTo(original.copy(pendingExports = emptyList(), recoveryGeneration = 1L))
        assertThat(store.entry("beta")).isEqualTo(entry("beta"))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(cleared, now)!!
        assertThat(due.pendingExport).isNull()
        assertThat(due.exportDates).containsExactly(today.minusDays(1), today).inOrder()
    }

    @Test
    fun `discard fences late retry cancellation success and refresh checkpoints`() = runTest {
        val original = entry("alpha").copy(lastSuccessEpochMillis = 1_000L, lastRefreshSuccessEpochMillis = 2_000L)
        store.upsert(original)
        assertThat(store.discardPendingRecovery("alpha")).isTrue()
        val pending = ScheduledProfilePendingExport(
            id = "late-residual", ownerEpochDays = listOf(20_001L), fireAtMillis = 3_000L,
            settingsSnapshotJson = "old-snapshot", target = ExportTarget.DEVICE_FOLDER, profileName = "Alpha",
        )

        assertThat(store.recordRetry("alpha", 3_000L, null, listOf(pending), 0L)).isFalse()
        assertThat(store.recordCancellation("alpha", 3_000L, null, listOf(pending), 0L)).isFalse()
        store.recordSuccess("alpha", 3_000L, expectedRecoveryGeneration = 0L)
        store.recordRefreshSuccess("alpha", 4_000L, expectedRecoveryGeneration = 0L)
        assertThat(store.updateForGeneration("alpha", 0L) { it.copy(hour = 15) }).isFalse()

        assertThat(store.entry("alpha")).isEqualTo(original.copy(recoveryGeneration = 1L))
        assertThat(store.recordRetry("alpha", 3_000L, null, listOf(pending), 1L)).isTrue()
        assertThat(store.entry("alpha")!!.pendingExports).containsExactly(pending)
    }

    @Test
    fun `stale editor save and schedule toggles cannot undo a discard`() = runTest {
        val pending = ScheduledProfilePendingExport(
            id = "stale-draft-residual", ownerEpochDays = listOf(20_001L), fireAtMillis = 1_000L,
            settingsSnapshotJson = "snapshot", target = ExportTarget.DEVICE_FOLDER, profileName = "Alpha",
        )
        val draft = entry("alpha").copy(pendingExports = listOf(pending))
        store.upsert(draft)
        store.update("alpha") { it.copy(isEnabled = false) }
        store.update("alpha") { it.copy(isEnabled = true) }
        assertThat(store.entry("alpha")!!.pendingExports).containsExactly(pending)
        store.discardPendingRecovery("alpha")

        store.upsert(draft.copy(hour = 10))

        val stored = store.entry("alpha")!!
        assertThat(stored.hour).isEqualTo(10)
        assertThat(stored.pendingExports).isEmpty()
        // Both toggles and discard fence prior callbacks; an unchanged draft cannot revive them.
        assertThat(stored.recoveryGeneration).isEqualTo(3L)
        assertThat(store.recordRetry("alpha", 2_000L, null, listOf(pending), 1L)).isFalse()
    }

    @Test
    fun `concurrent discard and old retry cannot restore recovery`() = runTest {
        store.upsert(entry("alpha"))
        val pending = ScheduledProfilePendingExport(
            id = "racing-residual", ownerEpochDays = listOf(20_001L), fireAtMillis = 1_000L,
            settingsSnapshotJson = "snapshot", target = ExportTarget.DEVICE_FOLDER, profileName = "Alpha",
        )

        listOf(
            async(Dispatchers.Default) { store.discardPendingRecovery("alpha") },
            async(Dispatchers.Default) { store.recordRetry("alpha", 1_000L, null, listOf(pending), 0L) },
        ).awaitAll()

        assertThat(store.entry("alpha")!!.pendingExports).isEmpty()
        assertThat(store.entry("alpha")!!.recoveryGeneration).isEqualTo(1L)
    }

    @Test
    fun `discard fails closed for absent or malformed entries`() = runTest {
        assertThat(store.discardPendingRecovery("missing")).isFalse()
        dataStore.edit { it[ENTRIES_KEY] = "{not-json" }

        assertThat(store.discardPendingRecovery("alpha")).isFalse()

        assertThat(dataStore.data.first()[ENTRIES_KEY]).isEqualTo("{not-json")
    }

    @Test
    fun `entries written before recovery generation existed default to zero`() = runTest {
        dataStore.edit {
            it[ENTRIES_KEY] = """[{"profileId":"legacy","anchorEpochDay":20000,"zoneId":"UTC"}]"""
        }

        assertThat(store.entry("legacy")!!.recoveryGeneration).isEqualTo(0L)
        assertThat(store.discardPendingRecovery("legacy")).isTrue()
        assertThat(store.entry("legacy")!!.recoveryGeneration).isEqualTo(1L)
    }

    private companion object {
        val ENTRIES_KEY = stringPreferencesKey("scheduled_profile_entries")
    }
}

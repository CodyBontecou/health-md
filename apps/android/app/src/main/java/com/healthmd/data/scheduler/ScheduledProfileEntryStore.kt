package com.healthmd.data.scheduler

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.data.export.RecoveryDiscardFence
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.sharedsetup.SharedSetupV2ProfilePersistence
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import timber.log.Timber

/**
 * DataStore persistence for [ScheduledProfileEntry] (Android phase-6 runtime).
 *
 * One entry per profile; the [ExportProfileRules.MAX_PROFILES] bound keeps the alarm count
 * bounded too. Orphan cleanup (profile deleted) happens in [ScheduledProfileScheduler], not here:
 * this store is inert data persistence only.
 */
@Singleton
class ScheduledProfileEntryStore @Inject constructor(
    private val dataStore: DataStore<Preferences>,
    @ApplicationContext private val context: Context,
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val listSerializer = ListSerializer(ScheduledProfileEntry.serializer())
    private val discardFence by lazy { RecoveryDiscardFence(context.noBackupFilesDir) }

    private object Keys {
        val ENTRIES = stringPreferencesKey("scheduled_profile_entries")
        val LEGACY_MIGRATION_PENDING_PROFILE_ID =
            stringPreferencesKey("scheduled_profile_legacy_migration_pending_profile_id")
    }

    val entries: Flow<List<ScheduledProfileEntry>> = dataStore.data.map { prefs ->
        decode(prefs[Keys.ENTRIES]).orEmpty()
    }

    suspend fun getEntries(): List<ScheduledProfileEntry> {
        reconcilePendingDiscards()
        return entries.first()
    }

    /** Finishes a crash after revocation/unlink but before the pending-state/generation commit. */
    private suspend fun reconcilePendingDiscards() = withContext(Dispatchers.IO) {
        discardFence.reconcile()
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            val updated = existing.map { entry ->
                if (discardFence.isProfileGenerationDiscarded(entry.profileId, entry.recoveryGeneration)) {
                    entry.copy(pendingExports = emptyList(), recoveryGeneration = Math.addExact(entry.recoveryGeneration, 1L))
                } else entry
            }
            if (updated != existing) prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, updated)
        }
    }

    suspend fun entry(profileId: String): ScheduledProfileEntry? =
        getEntries().firstOrNull { it.profileId == profileId }

    /**
     * Inserts or replaces the single entry bound to the profile. Returns false when a malformed
     * present payload blocks the write; callers performing migration must not advance source state
     * until this returns true and the entry reads back.
     */
    suspend fun upsert(entry: ScheduledProfileEntry): Boolean {
        var persisted = false
        dataStore.edit { prefs ->
            // A corrupt persisted list must never be rewritten from a failed read;
            // that would silently wipe every other entry. Skip the mutation instead.
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            if (
                entry.isEnabled &&
                entry.profileId in prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            ) {
                return@edit
            }
            val previous = existing.firstOrNull { it.profileId == entry.profileId }
            // UI drafts may have been opened before a worker recorded success. Configuration
            // saves must never move the durable catch-up frontier backwards.
            val reconfigured = previous?.let { scheduleChanged(it, entry) } == true
            val merged = entry.copy(
                lastSuccessEpochMillis = latest(
                    previous?.lastSuccessEpochMillis,
                    entry.lastSuccessEpochMillis,
                ),
                lastRefreshSuccessEpochMillis = latest(
                    previous?.lastRefreshSuccessEpochMillis,
                    entry.lastRefreshSuccessEpochMillis,
                ),
                // A configuration draft may predate a worker's cancellation checkpoint. Preserve
                // exact residual groups until the worker clears them individually.
                pendingExports = previous?.pendingExports ?: entry.pendingExports,
                recoveryGeneration = if (reconfigured) Math.addExact(requireNotNull(previous).recoveryGeneration, 1L)
                    else previous?.recoveryGeneration ?: entry.recoveryGeneration,
            )
            val updated = existing.filterNot { it.profileId == entry.profileId } + merged
            prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, updated.sortedBy { it.profileId })
            persisted = true
        }
        return persisted
    }

    suspend fun update(
        profileId: String,
        change: (ScheduledProfileEntry) -> ScheduledProfileEntry,
    ): Boolean = updateIfCurrent(profileId, null, change)

    /** Worker-owned configuration changes must also be inert after recovery is discarded. */
    suspend fun updateForGeneration(
        profileId: String,
        expectedRecoveryGeneration: Long,
        change: (ScheduledProfileEntry) -> ScheduledProfileEntry,
    ): Boolean = updateIfCurrent(profileId, expectedRecoveryGeneration, change)

    private suspend fun updateIfCurrent(
        profileId: String,
        expectedRecoveryGeneration: Long?,
        change: (ScheduledProfileEntry) -> ScheduledProfileEntry,
    ): Boolean {
        var persisted = false
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            val index = existing.indexOfFirst { it.profileId == profileId }
            if (index < 0) return@edit
            if (expectedRecoveryGeneration != null &&
                (existing[index].recoveryGeneration != expectedRecoveryGeneration ||
                    discardFence.isProfileGenerationDiscarded(profileId, expectedRecoveryGeneration))
            ) return@edit
            val requested = change(existing[index])
            val changed = requested.copy(recoveryGeneration = maxOf(
                requested.recoveryGeneration,
                if (expectedRecoveryGeneration == null && scheduleChanged(existing[index], requested)) {
                    Math.addExact(existing[index].recoveryGeneration, 1L)
                } else existing[index].recoveryGeneration,
            ))
            require(changed.profileId == profileId) { "Scheduled profile update cannot change identity." }
            if (
                changed.isEnabled &&
                profileId in prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            ) {
                return@edit
            }
            val updated = existing.toMutableList().apply { set(index, changed) }
            prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, updated.sortedBy { it.profileId })
            persisted = true
        }
        return persisted
    }

    /** Pins a new API occurrence before capture; an existing group is never reauthorized. */
    suspend fun admitAPIExport(
        profileId: String,
        expectedRecoveryGeneration: Long,
        pending: ScheduledProfilePendingExport,
    ): Boolean = updateForGeneration(profileId, expectedRecoveryGeneration) { current ->
        require(current.isEnabled && pending.target == com.healthmd.domain.model.ExportTarget.API_ENDPOINT)
        require(com.healthmd.data.export.APIRecoveryAuthorities.isValid(pending.apiAuthorityJson))
        val existing = current.pendingExports.firstOrNull { it.id == pending.id }
        require(existing == null || existing == pending)
        current.copy(pendingExports = if (existing == null) current.pendingExports + pending else current.pendingExports)
    }

    /** Persists missing-journal refusal before any external delivery, with the discard fence. */
    suspend fun markAPIJournalRequired(
        profileId: String,
        expectedRecoveryGeneration: Long,
        pendingId: String,
        authority: String,
        operationId: String,
    ): Boolean {
        var matched = false
        val persisted = updateForGeneration(profileId, expectedRecoveryGeneration) { current ->
            if (!current.isEnabled || current.pendingExports.none {
                    it.id == pendingId && it.apiAuthorityJson == authority && it.durableOperationId == operationId
                }) return@updateForGeneration current
            matched = true
            current.copy(pendingExports = current.pendingExports.map {
                if (it.id == pendingId) it.copy(apiJournalRequired = true) else it
            })
        }
        return persisted && matched
    }

    /**
     * Persist exact private revocation before unlink and before clearing the DataStore admission.
     * A crash in between is replayed by getEntries; no worker can recreate the private operation.
     * Configuration, credentials, history and completed/refresh frontiers remain untouched.
     */
    suspend fun discardPendingRecovery(profileId: String): Boolean = try {
        withContext(Dispatchers.IO) {
            var discarded = false
            dataStore.edit { prefs ->
                val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
                val current = existing.firstOrNull { it.profileId == profileId } ?: return@edit
                val nextGeneration = Math.addExact(current.recoveryGeneration, 1L)
                val bindings = current.pendingExports.filter {
                    it.target == com.healthmd.domain.model.ExportTarget.API_ENDPOINT && it.durableOperationId != null
                }.groupBy { requireNotNull(it.durableOperationId) }.mapValues { (_, pending) ->
                    pending.map { RecoveryDiscardFence.Binding(it.apiAuthorityJson, it.settingsSnapshotJson) }.distinct().single()
                }
                discardFence.discard(bindings.keys, profileId, current.recoveryGeneration, expectedBindings = bindings)
                prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, existing.map {
                    if (it.profileId == profileId) it.copy(pendingExports = emptyList(), recoveryGeneration = nextGeneration) else it
                })
                discarded = true
            }
            discarded
        }
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (_: Exception) {
        false
    }

    suspend fun delete(profileId: String) {
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            prefs[Keys.ENTRIES] = json.encodeToString(
                listSerializer,
                existing.filterNot { it.profileId == profileId },
            )
        }
    }

    /** Records a successful occurrence and clears only the residual group it completed.
     *
     * A null [fireAtMillis] records a Today Refresh-only success: the completed-day catch-up
     * frontier must not move, because that run exported only today's partial file.
     */
    suspend fun recordSuccess(
        profileId: String,
        fireAtMillis: Long?,
        completedPendingID: String? = null,
        expectedRecoveryGeneration: Long? = null,
    ) {
        updateIfCurrent(profileId, expectedRecoveryGeneration) { current ->
            current.copy(
                lastSuccessEpochMillis = fireAtMillis?.let { latest(current.lastSuccessEpochMillis, it) }
                    ?: current.lastSuccessEpochMillis,
                pendingExports = completedPendingID?.let { completedID ->
                    current.pendingExports.filterNot { it.id == completedID }
                } ?: current.pendingExports,
            )
        }
    }

    /**
     * Records a successful same-day refresh slot so its occurrence is not re-run. Refresh
     * success is independent of the completed-day frontier: a merged run may satisfy its slot
     * while other dates still fail and stay retryable.
     */
    suspend fun recordRefreshSuccess(
        profileId: String,
        slotMillis: Long,
        expectedRecoveryGeneration: Long? = null,
    ) {
        updateIfCurrent(profileId, expectedRecoveryGeneration) { current ->
            current.copy(
                lastRefreshSuccessEpochMillis = latest(
                    current.lastRefreshSuccessEpochMillis,
                    slotMillis,
                ),
            )
        }
    }

    /**
     * Advances the occurrence frontier while replacing only the attempted residual group with the
     * exact unresolved owner-date groups. Cancellation and backoff retries share this checkpoint
     * so completed dates are not repeated and later profile edits cannot rewrite in-flight work.
     */
    suspend fun recordCancellation(
        profileId: String,
        fireAtMillis: Long?,
        attemptedPendingID: String?,
        replacements: List<ScheduledProfilePendingExport>,
        expectedRecoveryGeneration: Long? = null,
    ): Boolean = recordResiduals(
        profileId = profileId,
        fireAtMillis = fireAtMillis,
        attemptedPendingID = attemptedPendingID,
        replacements = replacements,
        expectedRecoveryGeneration = expectedRecoveryGeneration,
    )

    /** Freezes unresolved work before a WorkManager backoff retry can observe profile edits. */
    suspend fun recordRetry(
        profileId: String,
        fireAtMillis: Long?,
        attemptedPendingID: String?,
        replacements: List<ScheduledProfilePendingExport>,
        expectedRecoveryGeneration: Long? = null,
    ): Boolean = recordResiduals(
        profileId = profileId,
        fireAtMillis = fireAtMillis,
        attemptedPendingID = attemptedPendingID,
        replacements = replacements,
        expectedRecoveryGeneration = expectedRecoveryGeneration,
    )

    private suspend fun recordResiduals(
        profileId: String,
        fireAtMillis: Long?,
        attemptedPendingID: String?,
        replacements: List<ScheduledProfilePendingExport>,
        expectedRecoveryGeneration: Long?,
    ): Boolean = updateIfCurrent(profileId, expectedRecoveryGeneration) { current ->
        val retained = attemptedPendingID?.let { attemptedID ->
            current.pendingExports.filterNot { it.id == attemptedID }
        } ?: current.pendingExports
        val normalized = (retained + replacements)
            .filter { it.ownerEpochDays.isNotEmpty() }
            .distinctBy { it.id }
            .sortedWith(
                compareBy<ScheduledProfilePendingExport> { it.fireAtMillis }
                    .thenBy { it.ownerEpochDays.minOrNull() ?: Long.MAX_VALUE }
                    .thenBy { it.id },
            )
        current.copy(
            lastSuccessEpochMillis = fireAtMillis?.let { latest(current.lastSuccessEpochMillis, it) }
                ?: current.lastSuccessEpochMillis,
            pendingExports = normalized,
        )
    }

    /** Atomically writes the migrated entry plus a durable completion marker. */
    suspend fun beginLegacyMigration(entry: ScheduledProfileEntry): Boolean {
        var persisted = false
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            if (
                existing.isNotEmpty() ||
                entry.profileId in prefs[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()
            ) {
                return@edit
            }
            prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, listOf(entry))
            prefs[Keys.LEGACY_MIGRATION_PENDING_PROFILE_ID] = entry.profileId
            persisted = true
        }
        return persisted
    }

    suspend fun pendingLegacyMigrationProfileId(): String? =
        dataStore.data.map { it[Keys.LEGACY_MIGRATION_PENDING_PROFILE_ID] }.first()

    /** Clears the marker only after legacy settings and runtime work are disabled. */
    suspend fun finishLegacyMigration(profileId: String): Boolean {
        var finished = false
        dataStore.edit { prefs ->
            if (prefs[Keys.LEGACY_MIGRATION_PENDING_PROFILE_ID] == profileId) {
                prefs.remove(Keys.LEGACY_MIGRATION_PENDING_PROFILE_ID)
                finished = true
            }
        }
        return finished
    }

    private fun scheduleChanged(first: ScheduledProfileEntry, second: ScheduledProfileEntry): Boolean =
        first.isEnabled != second.isEnabled || first.anchorEpochDay != second.anchorEpochDay ||
            first.cadenceUnit != second.cadenceUnit || first.cadenceValue != second.cadenceValue ||
            first.weekdayIso != second.weekdayIso || first.dateWindow != second.dateWindow ||
            first.hour != second.hour || first.minute != second.minute || first.lookbackDays != second.lookbackDays ||
            first.zoneId != second.zoneId || first.todayRefreshEnabled != second.todayRefreshEnabled ||
            first.todayRefreshIntervalHours != second.todayRefreshIntervalHours

    private fun latest(first: Long?, second: Long?): Long? =
        listOfNotNull(first, second).maxOrNull()

    /** Malformed present state blocks writes; missing state alone represents a fresh store. */
    private fun decode(raw: String?): List<ScheduledProfileEntry>? {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching { json.decodeFromString(listSerializer, raw) }.getOrElse {
            Timber.e("Scheduled profile entries failed to decode; blocking entry writes")
            null
        }
    }
}

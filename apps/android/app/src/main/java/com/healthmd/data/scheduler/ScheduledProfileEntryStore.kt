package com.healthmd.data.scheduler

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
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

    private object Keys {
        val ENTRIES = stringPreferencesKey("scheduled_profile_entries")
        val LEGACY_MIGRATION_PENDING_PROFILE_ID =
            stringPreferencesKey("scheduled_profile_legacy_migration_pending_profile_id")
    }

    val entries: Flow<List<ScheduledProfileEntry>> = dataStore.data.map { prefs ->
        decode(prefs[Keys.ENTRIES]).orEmpty()
    }

    suspend fun getEntries(): List<ScheduledProfileEntry> = entries.first()

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
            val previous = existing.firstOrNull { it.profileId == entry.profileId }
            // UI drafts may have been opened before a worker recorded success. Configuration
            // saves must never move the durable catch-up frontier backwards.
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
    ): Boolean {
        var persisted = false
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            val index = existing.indexOfFirst { it.profileId == profileId }
            if (index < 0) return@edit
            val changed = change(existing[index])
            require(changed.profileId == profileId) { "Scheduled profile update cannot change identity." }
            val updated = existing.toMutableList().apply { set(index, changed) }
            prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, updated.sortedBy { it.profileId })
            persisted = true
        }
        return persisted
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

    /** Records a successful occurrence and clears only the residual group it completed. */
    suspend fun recordSuccess(
        profileId: String,
        fireAtMillis: Long,
        completedPendingID: String? = null,
    ) {
        update(profileId) { current ->
            current.copy(
                lastSuccessEpochMillis = latest(current.lastSuccessEpochMillis, fireAtMillis),
                pendingExports = completedPendingID?.let { completedID ->
                    current.pendingExports.filterNot { it.id == completedID }
                } ?: current.pendingExports,
            )
        }
    }

    /**
     * Advances the occurrence frontier while replacing only the attempted residual group with the
     * exact unresolved owner-date groups. This prevents completed dates from being re-exported.
     */
    suspend fun recordCancellation(
        profileId: String,
        fireAtMillis: Long,
        attemptedPendingID: String?,
        replacements: List<ScheduledProfilePendingExport>,
    ): Boolean = update(profileId) { current ->
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
            lastSuccessEpochMillis = latest(current.lastSuccessEpochMillis, fireAtMillis),
            pendingExports = normalized,
        )
    }

    /** Atomically writes the migrated entry plus a durable completion marker. */
    suspend fun beginLegacyMigration(entry: ScheduledProfileEntry): Boolean {
        var persisted = false
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES]) ?: return@edit
            if (existing.isNotEmpty()) return@edit
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

    /**
     * Decodes the persisted list. A missing or blank key is the legitimate fresh-store state and
     * behaves as an empty list. Only a malformed *present* payload returns null, so write paths
     * still fail closed instead of overwriting other entries after a corrupt read.
     */
    private fun latest(first: Long?, second: Long?): Long? =
        listOfNotNull(first, second).maxOrNull()

    private fun decode(raw: String?): List<ScheduledProfileEntry>? {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching { json.decodeFromString(listSerializer, raw) }.getOrElse { error ->
            Timber.e(error, "Scheduled profile entries failed to decode; blocking entry writes")
            null
        }
    }
}

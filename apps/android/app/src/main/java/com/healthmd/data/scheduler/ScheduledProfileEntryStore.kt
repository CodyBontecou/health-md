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
    }

    val entries: Flow<List<ScheduledProfileEntry>> = dataStore.data.map { prefs ->
        decode(prefs[Keys.ENTRIES])
    }

    suspend fun getEntries(): List<ScheduledProfileEntry> = entries.first()

    suspend fun entry(profileId: String): ScheduledProfileEntry? =
        getEntries().firstOrNull { it.profileId == profileId }

    /** Inserts or replaces the single entry bound to the profile. */
    suspend fun upsert(entry: ScheduledProfileEntry) {
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES])
            val updated = existing.filterNot { it.profileId == entry.profileId } + entry
            prefs[Keys.ENTRIES] = json.encodeToString(listSerializer, updated.sortedBy { it.profileId })
        }
    }

    suspend fun update(profileId: String, change: (ScheduledProfileEntry) -> ScheduledProfileEntry) {
        val current = entry(profileId) ?: return
        upsert(change(current))
    }

    suspend fun delete(profileId: String) {
        dataStore.edit { prefs ->
            val existing = decode(prefs[Keys.ENTRIES])
            prefs[Keys.ENTRIES] = json.encodeToString(
                listSerializer,
                existing.filterNot { it.profileId == profileId },
            )
        }
    }

    /** Records a successful occurrence for catch-up math; no-op when the entry is unknown. */
    suspend fun recordSuccess(profileId: String, fireAtMillis: Long) {
        update(profileId) { it.copy(lastSuccessEpochMillis = fireAtMillis) }
    }

    private fun decode(raw: String?): List<ScheduledProfileEntry> {
        if (raw.isNullOrBlank()) return emptyList()
        return runCatching { json.decodeFromString(listSerializer, raw) }.getOrDefault(emptyList())
    }
}

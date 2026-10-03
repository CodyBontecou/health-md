package com.healthmd.data.drive

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ConfigurationProtectionPersistence
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first

/** Foreground disconnect: revoke first, then admit all local configuration changes together. */
@Singleton
class GoogleDriveDisconnectService @Inject constructor(
    private val dataStore: DataStore<Preferences>,
    private val destinations: GoogleDriveDestinationStore,
    private val managedObjects: GoogleDriveManagedObjectStore,
    private val selection: GoogleDriveSelectionStore,
    private val profiles: ExportProfileRepository,
    private val schedules: ScheduledProfileEntryStore,
) {
    suspend fun disconnect(destinationId: String, revoke: suspend (String) -> Unit): Boolean {
        if (!admitted()) return false
        val destination = destinations.find(destinationId)
        if (!admitted()) return false
        val accountName = destination?.let { destinations.accountName(it) }
        // Account lookup may suspend. Never start destructive SDK revocation using old admission.
        if (!admitted()) return false
        if (accountName != null) {
            try {
                revoke(accountName)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // Preserve best-effort revocation behavior; remote files are never deleted.
            }
            if (!admitted()) return false
        }
        var removed = false
        dataStore.edit { prefs ->
            currentCoroutineContext().ensureActive()
            if (prefs[ConfigurationProtectionPersistence.enabledKey] == true) return@edit
            // Prepare/validate all preference changes before touching encrypted authority.
            // These helpers operate on this snapshot, never call DataStore.edit recursively.
            val affected = profiles.detachGoogleDriveDestination(prefs, destinationId)
            schedules.disableForDisconnect(prefs, affected)
            SettingsRepositoryImpl.disableGoogleDriveSchedule(prefs)
            managedObjects.removeForDisconnect(prefs, destinationId)
            selection.clearForDisconnect(prefs, destinationId)
            currentCoroutineContext().ensureActive()
            destinations.removeForDisconnect(prefs, destinationId)
            removed = true
        }
        // An already-issued remote revocation cannot be rolled back if admission was denied.
        return removed
    }

    private suspend fun admitted(): Boolean {
        currentCoroutineContext().ensureActive()
        val protected = dataStore.data.first()[ConfigurationProtectionPersistence.enabledKey] == true
        currentCoroutineContext().ensureActive()
        return !protected
    }
}

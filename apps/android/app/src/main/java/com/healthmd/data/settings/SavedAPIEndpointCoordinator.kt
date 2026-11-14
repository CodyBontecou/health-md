package com.healthmd.data.settings

import com.healthmd.data.export.SavedAPIEndpointResult
import com.healthmd.data.export.SavedAPIEndpointStore
import com.healthmd.data.export.TokenChange
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointRules
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.util.runCatchingCancellable
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import timber.log.Timber

/** Profile/live-settings operations the coordinator needs; faked in tests. */
interface EndpointBindingOps {
    suspend fun profiles(): List<ExportProfile>
    suspend fun activeProfileId(): String?
    suspend fun liveEndpointUrl(): String
    /** Points the live settings (the active profile's projection) at [url]; "" clears it. */
    suspend fun setLiveEndpointUrl(url: String)
    /** Live settings target the API at [url]; the active profile is re-frozen from them. */
    suspend fun bindActive(url: String)
    /** Re-freezes the active profile from live settings. */
    suspend fun flushActive()
    /** Re-freezes an inactive profile's snapshot for [newUrl]; false when its snapshot is invalid. */
    suspend fun rebindInactive(profile: ExportProfile, newUrl: String): Boolean
    /** Removes the profile's endpoint binding; it fails closed as "not configured". */
    suspend fun unbind(profileId: String)
}

/**
 * Saved endpoints are shared: editing one updates every automation that uses it (their frozen
 * destination identity is re-captured for the new URL), and deleting one leaves those
 * automations unconfigured rather than letting them fall back to another destination.
 * Tokens need no propagation: requests resolve a saved endpoint's token from its URL.
 */
@Singleton
class SavedAPIEndpointCoordinator @Inject constructor(
    private val store: SavedAPIEndpointStore,
    private val ops: EndpointBindingOps,
) {
    val endpoints = store.endpoints

    suspend fun load(): List<SavedAPIEndpoint> = store.load()

    suspend fun save(editingId: String?, name: String, url: String, token: TokenChange): SavedAPIEndpointResult {
        val result = store.save(editingId, name, url, token)
        if (result is SavedAPIEndpointResult.Saved) {
            val previous = result.previousUrl
            if (previous != null && previous != result.endpoint.url) {
                withContext(NonCancellable) { moveBindings(previous, result.endpoint.url) }
            }
        }
        return result
    }

    suspend fun delete(id: String): SavedAPIEndpoint? {
        val removed = store.delete(id) ?: return null
        withContext(NonCancellable) {
            val profiles = ops.profiles()
            profiles.filter { SavedAPIEndpointRules.uses(it, removed) }.forEach { profile ->
                runCatchingCancellable { ops.unbind(profile.id) }
                    .onFailure { Timber.e(it, "Could not unbind a deleted endpoint") }
            }
            if (APIExportEndpoint.normalizedOrNull(ops.liveEndpointUrl()) == removed.url) {
                ops.setLiveEndpointUrl("")
            }
        }
        return removed
    }

    /** Makes [endpoint] the Daily note's (active automation's) destination. */
    suspend fun bindToActive(endpoint: SavedAPIEndpoint) = ops.bindActive(endpoint.url)

    /** Names of automations using [endpoint]. */
    suspend fun usedBy(endpoint: SavedAPIEndpoint): List<String> =
        SavedAPIEndpointRules.profilesUsing(endpoint, ops.profiles()).map { it.name }

    private suspend fun moveBindings(oldUrl: String, newUrl: String) {
        val activeId = ops.activeProfileId()
        val moved = ops.profiles().filter {
            it.target == ExportTarget.API_ENDPOINT && it.apiEndpointUrl?.let(APIExportEndpoint::normalizedOrNull) == oldUrl
        }
        var activeMoved = false
        moved.forEach { profile ->
            if (profile.id == activeId) {
                activeMoved = true
            } else {
                runCatchingCancellable { ops.rebindInactive(profile, newUrl) }
                    .onFailure { Timber.e(it, "Could not move an automation to the edited endpoint") }
            }
        }
        if (activeMoved || APIExportEndpoint.normalizedOrNull(ops.liveEndpointUrl()) == oldUrl) {
            ops.setLiveEndpointUrl(newUrl)
            if (activeMoved) ops.flushActive()
        }
    }
}

/** Production [EndpointBindingOps] over the profile store, live settings and snapshot factory. */
class ProfileEndpointBindingOps @Inject constructor(
    private val profileRepository: ExportProfileRepository,
    private val settingsRepository: SettingsRepository,
    private val snapshotFactory: ScheduledProfileSnapshotFactory,
    private val profileCoordinator: ExportProfileCoordinator,
) : EndpointBindingOps {
    override suspend fun profiles(): List<ExportProfile> = profileRepository.getProfiles()

    override suspend fun activeProfileId(): String? = profileRepository.getActiveProfile()?.id

    override suspend fun liveEndpointUrl(): String = settingsRepository.getExportSettings().apiEndpointUrl

    override suspend fun setLiveEndpointUrl(url: String) {
        settingsRepository.updateExportSettingsAtomically { it.copy(apiEndpointUrl = url) }
    }

    override suspend fun bindActive(url: String) {
        settingsRepository.updateExportSettingsAtomically {
            it.copy(
                apiEndpointUrl = url,
                exportTarget = ExportTarget.API_ENDPOINT,
                scheduledExportTarget = ExportTarget.API_ENDPOINT,
            )
        }
        profileCoordinator.flushEdits()
    }

    override suspend fun flushActive() = profileCoordinator.flushEdits()

    override suspend fun rebindInactive(profile: ExportProfile, newUrl: String): Boolean {
        val current = settingsRepository.getExportSettings()
        val restored = snapshotFactory.applyForActivation(profile, current) ?: return false
        val json = snapshotFactory.captureFromCurrent(restored, ExportTarget.API_ENDPOINT, apiEndpointUrl = newUrl)
        return profileRepository.updateProfile(
            id = profile.id,
            settingsSnapshotJson = json,
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = newUrl,
        )
    }

    override suspend fun unbind(profileId: String) {
        profileRepository.clearApiEndpoint(profileId)
    }
}

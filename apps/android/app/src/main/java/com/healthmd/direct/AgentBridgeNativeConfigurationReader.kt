package com.healthmd.direct

import android.os.Looper
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.data.health.HealthConnectNativePlanningMetadata
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotException
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.registry.HealthMdCoreRegistryAdapter
import java.io.IOException
import java.time.DateTimeException
import java.time.ZoneId
import java.util.Collections
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/** Native lifecycle state, never a wire DTO or a permission issuer. Its publisher records
 * advertised capability/readiness changes in signed issuer storage before offering v4. */
internal data class AgentBridgeNativePlanningFacts(
    val availableNativeMetricIds: Set<String>,
    val deviceSettingsObjectId: String,
    val sourceCalendarTimezone: String,
    val configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
    val nativeGrants: AgentBridgeDiscoveryNativeGrants,
    val entitlement: AgentBridgeDiscoveryEntitlement,
    val userStartedServiceActive: Boolean,
    val firstUnlockComplete: Boolean,
    // Android exposes actual granted-permission metadata; Apple cannot reveal per-type read grants.
    // Private observation only, not a new wire field or authorization token.
    val nativePermissionObservationSha256: String? = null,
)

/** Other arguments are cached native observations. This adapter performs no quota/settings reads;
 * permission summary is not an all-metrics grant. The full private digest fences partial changes. */
internal fun HealthConnectNativePlanningMetadata.planningFacts(deviceSettingsObjectId: String,
    sourceCalendarTimezone: String, configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
    entitlement: AgentBridgeDiscoveryEntitlement, userStartedServiceActive: Boolean,
    firstUnlockComplete: Boolean): AgentBridgeNativePlanningFacts = AgentBridgeNativePlanningFacts(
        availableNativeMetricIds, deviceSettingsObjectId, sourceCalendarTimezone, configurationProtection,
        when {
            !providerAvailable -> AgentBridgeDiscoveryNativeGrants.REQUIRED
            hasAnyForegroundReadPermission == null -> AgentBridgeDiscoveryNativeGrants.UNVERIFIED
            hasAnyForegroundReadPermission -> AgentBridgeDiscoveryNativeGrants.SATISFIED
            else -> AgentBridgeDiscoveryNativeGrants.REQUIRED
        }, entitlement, userStartedServiceActive, firstUnlockComplete, grantedPermissionsSha256)

/** Actual native stores plus compiled catalog. The synchronous issuer transaction may call this
 * only from a worker: the single preferences read must never block the Android main looper.
 * Discovery/explicit requests do not collect private preferences. Selected settings/profile and
 * their pin/rebind state come from one committed DataStore image. No SDK health/provider work. */
internal class AgentBridgeNativeConfigurationReader(
    private val dataStore: DataStore<Preferences>,
    private val settings: SettingsRepositoryImpl,
    private val profiles: ExportProfileRepository,
    private val nativeState: () -> AgentBridgeNativePlanningFacts,
    private val registry: () -> CoreMetricRegistrySnapshot = {
        HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_FROZEN_V4)
    },
) : AgentBridgeExportPlanningConfigurationReader {
    override fun readConfiguration(policy: AgentBridgeSettingsPolicy?, catalogPublication: AgentBridgeNativeCatalogPublication?): AgentBridgeExportPlanningConfiguration {
        if (Looper.myLooper() == Looper.getMainLooper()) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        val publication = catalogPublication ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
        publication.validate()
        return try { readSelectedConfiguration(policy, publication) }
        catch (_: AndroidExportSettingsSnapshotException) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
        catch (_: DateTimeException) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
    }

    private fun readSelectedConfiguration(policy: AgentBridgeSettingsPolicy?, publication: AgentBridgeNativeCatalogPublication): AgentBridgeExportPlanningConfiguration {
        val state = detachedState()
        if (state.fingerprint(publication.sourceInstallationId) != publication.factsSha256) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        val catalog = AgentBridgeRequestSettingsCatalog(registry(), state.availableNativeMetricIds, publication.revision)
        var saved: AgentBridgeRequestSettingsSnapshot? = null
        var selectedProfiles: List<AgentBridgeRequestSettingsProfile> = emptyList()
        if (policy is AgentBridgeSettingsPolicySavedDeviceSettings || policy is AgentBridgeSettingsPolicyProfile) {
            val prefs = try {
                runBlocking(Dispatchers.IO) { dataStore.data.first() }
            } catch (_: IOException) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
            when (policy) {
                is AgentBridgeSettingsPolicySavedDeviceSettings -> {
                    val snapshot = settings.readSavedExportConfiguration(prefs, policy.expectedRevision)
                        ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
                    // Discard installation plumbing, credentials/recovery metadata and any native
                    // renderer authority. Only output choices enter the independent host request.
                    val outputOnly = snapshot.settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER,
                        scheduledExportTarget = ExportTarget.DEVICE_FOLDER, apiEndpointUrl = "", executionEnginePin = null)
                    val frozen = AndroidExportSettingsSnapshot.capture(outputOnly, null, ZoneId.of(state.sourceCalendarTimezone))
                    saved = AgentBridgeRequestSettingsSnapshot(snapshot.revision, frozen.restoreOnto(ExportSettings()))
                }
                is AgentBridgeSettingsPolicyProfile -> {
                    val snapshot = profiles.readConfigurationProfile(prefs, policy.profileId, policy.expectedRevision)
                        ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
                    val outputOnly = snapshot.settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER,
                        scheduledExportTarget = ExportTarget.DEVICE_FOLDER, apiEndpointIdentitySha256 = null, enginePin = null)
                    selectedProfiles = listOf(AgentBridgeRequestSettingsProfile(policy.profileId,
                        AgentBridgeRequestSettingsSnapshot(snapshot.revision, outputOnly.restoreOnto(ExportSettings())), snapshot.executionBlocked))
                }
                else -> error("Selected native policy changed type")
            }
        }
        if (detachedState() != state) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        return AgentBridgeExportPlanningConfiguration(AgentBridgeRequestSettingsInputs(catalog, saved, selectedProfiles),
            state.deviceSettingsObjectId, state.sourceCalendarTimezone, state.configurationProtection,
            state.nativeGrants, state.entitlement, state.userStartedServiceActive, state.firstUnlockComplete)
    }

    private fun detachedState(): AgentBridgeNativePlanningFacts {
        val value = nativeState()
        return value.copy(availableNativeMetricIds = Collections.unmodifiableSet(value.availableNativeMetricIds.toSortedSet()))
    }

    private fun fail(code: AgentBridgeErrorCode): Nothing = throw AgentBridgeException(code)
}

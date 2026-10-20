package com.healthmd.direct

import android.content.Context
import android.os.Looper
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.sharedsetup.SharedSetupV2ProfilePersistence
import io.mockk.*
import java.io.IOException
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.junit.*
import org.junit.rules.TemporaryFolder

/** Real private DataStore/repositories and planning service. Only Looper, SDK lifecycle facts and
 * the JNI registry load are intercepted; no installed service, device, permission or health work. */
class AgentBridgeNativeConfigurationReaderTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private lateinit var scope: CoroutineScope
    private lateinit var backing: DataStore<Preferences>
    private lateinit var observed: DataStore<Preferences>
    private lateinit var settings: SettingsRepositoryImpl
    private lateinit var profiles: ExportProfileRepository
    private var reads = 0
    private var writes = 0
    private var onRead: (() -> Unit)? = null
    private var state = initialState()
    private lateinit var main: Looper

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("native.preferences_pb")
        backing = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        observed = object : DataStore<Preferences> {
            override val data = backing.data.map { reads++; onRead?.invoke(); it }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                writes++; return backing.updateData(transform)
            }
        }
        settings = SettingsRepositoryImpl(observed, mockk<Context>(relaxed = true))
        profiles = ExportProfileRepository(observed, mockk<Context>(relaxed = true))
        mockkStatic(Looper::class)
        main = mockk()
        every { Looper.getMainLooper() } returns main
        every { Looper.myLooper() } returns null // Worker boundary only; not native thread qualification.
        state = initialState()
    }
    @After fun tearDown() { unmockkStatic(Looper::class); scope.cancel() }
    private fun reader(store: DataStore<Preferences> = observed) = AgentBridgeNativeConfigurationReader(
        store, settings, profiles, { state }, { AgentBridgeExportTestRegistry.load() })
    private fun reset() { reads = 0; writes = 0 }

    @Test fun `discovery and explicit never read private preferences`() {
        val reader = reader()
        for (policy in listOf(null, AgentBridgeSettingsPolicyExplicit(AgentBridgeExportPlanningFixture.output(), "explicit"))) {
            val configuration = reader.readConfiguration(policy)
            assertThat(configuration.settings.savedDevice).isNull()
            assertThat(configuration.settings.profiles).isEmpty()
        }
        assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
    }

    @Test fun `actual saved and nonactive profile policies reach real planner and native review without mutation`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val native = AgentBridgeRequestSettingsResolver.resolve(f.intent(), f.configuration.readConfiguration(f.intent().settingsPolicy).settings, f.clock)
                .exporterSettings().copy(apiEndpointUrl = "https://synthetic.invalid/never-contact", scheduleEnabled = true,
                    exportTarget = ExportTarget.API_ENDPOINT, scheduledExportTarget = ExportTarget.API_ENDPOINT)
            settings.updateExportSettings(native)
            val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(AndroidExportSettingsSnapshot.capture(native, null, ZoneId.of("UTC")))
            val selected = profiles.add("Selected", snapshot, ExportTarget.API_ENDPOINT)
            val other = profiles.add("Active", snapshot, ExportTarget.DEVICE_FOLDER)
            profiles.activate(other.id)
            val before = backing.data.first().asMap()
            f.enrolled()
            val service = AgentBridgeExportPlanningService(f.store, reader(), f.clock)
            val discovery = service.discover(f.peerContext, f.discoveryRequest())
            val policies = listOf(AgentBridgeSettingsPolicyExplicit(AgentBridgeExportPlanningFixture.output(), "explicit"),
                AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings"), AgentBridgeSettingsPolicyProfile(1, selected.id, "profile"))
            for ((index, policy) in policies.withIndex()) {
                reset()
                val configuration = reader().readConfiguration(policy)
                assertThat(reads).isEqualTo(if (index == 0) 0 else 1)
                val actual = configuration.settings.savedDevice?.settings ?: configuration.settings.profiles.singleOrNull()?.snapshot?.settings
                if (actual != null) {
                    assertThat(actual.apiEndpointUrl).isEmpty()
                    assertThat(actual.scheduleEnabled).isFalse()
                    assertThat(actual.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
                }
                val plan = service.plan(f.peerContext, f.request(discovery, f.intent(policy = policy), AgentBridgeExportPlanningFixture.id(70 + index)))
                assertThat(plan.effectiveSettings).isEqualTo(AgentBridgeExportPlanningFixture.output())
                assertThat(service.reviewNativePlan(f.peerContext, plan.planId)).isEqualTo(plan)
                assertThat(writes).isEqualTo(0)
            }
            assertThat(backing.data.first().asMap()).isEqualTo(before)
            assertThat(profiles.getActiveProfileId()).isEqualTo(other.id)
        }
    }

    @Test fun `stale malformed and blocked selected state never falls back`() = runBlocking {
        settings.updateExportSettings(ExportSettings())
        val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(AndroidExportSettingsSnapshot.capture(ExportSettings(), null, ZoneId.of("UTC")))
        val selected = profiles.add("Selected", snapshot, ExportTarget.DEVICE_FOLDER)
        backing.edit { it[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] = setOf(selected.id) }
        val reader = reader()
        assertThat(reader.readConfiguration(AgentBridgeSettingsPolicyProfile(1, selected.id, "profile")).settings.profiles.single().executionBlocked).isTrue()
        AgentBridgeExportPlanningFixture().use { f ->
            for (policy in listOf(AgentBridgeSettingsPolicySavedDeviceSettings(1, "saved_device_settings"),
                AgentBridgeSettingsPolicyProfile(2, selected.id, "profile"), AgentBridgeSettingsPolicyProfile(1, AgentBridgeExportPlanningFixture.id(99), "profile"))) {
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader.readConfiguration(policy) }
            }
            backing.edit { it[intPreferencesKey("export_profiles")] = 7 }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader.readConfiguration(AgentBridgeSettingsPolicyProfile(1, selected.id, "profile")) }
        }
    }

    @Test fun `main looper rejects before native state or preferences access`() {
        every { Looper.myLooper() } returns main
        var calls = 0
        val reader = AgentBridgeNativeConfigurationReader(observed, settings, profiles, { calls++; state }, { error("must not load") })
        AgentBridgeExportPlanningFixture().use { f -> f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { reader.readConfiguration(null) } }
        assertThat(calls).isEqualTo(0); assertThat(reads).isEqualTo(0)
    }

    @Test fun `native metadata drift and mutable availability aliases invalidate exact read`() = runBlocking {
        settings.updateExportSettings(ExportSettings())
        val available = state.availableNativeMetricIds.toMutableSet()
        state = state.copy(availableNativeMetricIds = available)
        onRead = { available.remove("steps") }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader().readConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
        }
    }

    @Test fun `storage failures and malformed native timezone return fixed errors`() = runBlocking {
        val unavailable = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = flow { throw IOException("synthetic private path must not escape") }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences = error("must not write")
        }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader(unavailable).readConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
            settings.updateExportSettings(ExportSettings())
            state = state.copy(sourceCalendarTimezone = "invalid-zone")
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader().readConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
        }
    }

    private fun initialState() = AgentBridgeNativePlanningState(3, setOf("steps", "avg_hr", "min_hr", "max_hr", "resting_hr", "hrv"),
        AgentBridgeExportPlanningFixture.id(2), "America/Los_Angeles", AgentBridgeDiscoveryConfigurationProtection.LOCKED,
        AgentBridgeDiscoveryNativeGrants.SATISFIED, AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)
}

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
import java.nio.file.Files
import java.time.ZoneId
import javax.crypto.Mac
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
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
    private fun AgentBridgeNativeConfigurationReader.readPublishedConfiguration(policy: AgentBridgeSettingsPolicy?) =
        readConfiguration(policy, AgentBridgeNativeCatalogPublication(1, AgentBridgeExportPlanningFixture.id(1),
            state.fingerprint(AgentBridgeExportPlanningFixture.id(1))))

    @Test fun `discovery and explicit never read private preferences`() {
        val reader = reader()
        for (policy in listOf(null, AgentBridgeSettingsPolicyExplicit(AgentBridgeExportPlanningFixture.output(), "explicit"))) {
            val configuration = reader.readPublishedConfiguration(policy)
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
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val service = AgentBridgeExportPlanningService(f.store, reader(), f.clock)
            val discovery = service.discover(f.peerContext, f.discoveryRequest())
            val policies = listOf(AgentBridgeSettingsPolicyExplicit(AgentBridgeExportPlanningFixture.output(), "explicit"),
                AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings"), AgentBridgeSettingsPolicyProfile(1, selected.id, "profile"))
            for ((index, policy) in policies.withIndex()) {
                reset()
                val configuration = reader().readPublishedConfiguration(policy)
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
        assertThat(reader.readPublishedConfiguration(AgentBridgeSettingsPolicyProfile(1, selected.id, "profile")).settings.profiles.single().executionBlocked).isTrue()
        AgentBridgeExportPlanningFixture().use { f ->
            for (policy in listOf(AgentBridgeSettingsPolicySavedDeviceSettings(1, "saved_device_settings"),
                AgentBridgeSettingsPolicyProfile(2, selected.id, "profile"), AgentBridgeSettingsPolicyProfile(1, AgentBridgeExportPlanningFixture.id(99), "profile"))) {
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader.readPublishedConfiguration(policy) }
            }
            backing.edit { it[intPreferencesKey("export_profiles")] = 7 }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader.readPublishedConfiguration(AgentBridgeSettingsPolicyProfile(1, selected.id, "profile")) }
        }
    }

    @Test fun `main looper rejects before native state or preferences access`() {
        every { Looper.myLooper() } returns main
        var calls = 0
        val reader = AgentBridgeNativeConfigurationReader(observed, settings, profiles, { calls++; state }, { error("must not load") })
        AgentBridgeExportPlanningFixture().use { f -> f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { reader.readPublishedConfiguration(null) } }
        assertThat(calls).isEqualTo(0); assertThat(reads).isEqualTo(0)
    }

    @Test fun `catalog publication rejects main looper before facts keys or storage access`() {
        every { Looper.myLooper() } returns main
        var samples = 0
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state }
            }
            assertThat(samples).isEqualTo(0)
            assertThat(f.keys.calls).isEqualTo(0)
            assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
        }
    }

    @Test fun `native metadata drift and mutable availability aliases invalidate exact read`() = runBlocking {
        settings.updateExportSettings(ExportSettings())
        val available = state.availableNativeMetricIds.toMutableSet()
        state = state.copy(availableNativeMetricIds = available)
        onRead = { available.remove("steps") }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader().readPublishedConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
        }
    }

    @Test fun `storage failures and malformed native timezone return fixed errors`() = runBlocking {
        val unavailable = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = flow { throw IOException("synthetic private path must not escape") }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences = error("must not write")
        }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader(unavailable).readPublishedConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
            settings.updateExportSettings(ExportSettings())
            state = state.copy(sourceCalendarTimezone = "invalid-zone")
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader().readPublishedConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
        }
    }

    @Test fun `signed catalog survives restart and unchanged publication while readiness ABA advances revisions`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val legacy = Files.readAllBytes(file)
            val before = f.store.access { requireNotNull(it).state }
            assertThat(before.nativeCatalog).isNull()
            assertThat(Files.readAllBytes(file)).isEqualTo(legacy)
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            assertThat(first.revision).isEqualTo(1)
            val bytes = Files.readAllBytes(file)
            val generation = f.store.access { requireNotNull(it).state.revision }
            val restarted = AgentBridgeExportAuthorityStore.inPrivateDirectory(f.parent, f.keys)
            assertThat(restarted.access { requireNotNull(it).state.nativeCatalog }).isEqualTo(first)
            assertThat(restarted.publishNativeCatalog(f.peer.sourceInstallationId) { state }).isEqualTo(first)
            assertThat(restarted.access { requireNotNull(it).state.revision }).isEqualTo(generation)
            assertThat(Files.readAllBytes(file)).isEqualTo(bytes)
            state = state.copy(userStartedServiceActive = false)
            val second = restarted.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            state = state.copy(userStartedServiceActive = true)
            val third = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            assertThat(listOf(second.revision, third.revision)).containsExactly(2, 3).inOrder()
            assertThat(third.factsSha256).isEqualTo(first.factsSha256)
            val after = restarted.access { requireNotNull(it).state }
            assertThat(after.version).isEqualTo(2)
            assertThat(after.grants).isEqualTo(before.grants)
            assertThat(after.plans).isEmpty(); assertThat(after.decisions).isEmpty()
        }
    }

    @Test fun `wire planning cannot publish missing or stale catalog and readiness ABA invalidates old plans`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val service = AgentBridgeExportPlanningService(f.store, reader(), f.clock)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.discover(f.peerContext, f.discoveryRequest()) }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val discovery = service.discover(f.peerContext, f.discoveryRequest())
            val plan = service.plan(f.peerContext, f.request(discovery))
            val accepted = Files.readAllBytes(file)
            state = state.copy(userStartedServiceActive = false)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.reviewNativePlan(f.peerContext, plan.planId) }
            assertThat(Files.readAllBytes(file)).isEqualTo(accepted)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            state = state.copy(userStartedServiceActive = true)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.reviewNativePlan(f.peerContext, plan.planId) }
            f.store.access { tx ->
                assertThat(requireNotNull(tx).state.plans).hasSize(1)
                assertThat(tx.state.decisions).isEmpty()
            }
        }
    }

    @Test fun `publisher never initializes missing state repairs keys or rebinds a source`() {
        AgentBridgeExportPlanningFixture().use { f ->
            var samples = 0
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state }
            }
            assertThat(samples).isEqualTo(0)
            assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
            f.enrolled()
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.store.publishNativeCatalog(AgentBridgeExportPlanningFixture.id(99)) { state } }
            val key = f.keys.key
            f.keys.key = null
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state } }
            assertThat(samples).isEqualTo(0); assertThat(Files.readAllBytes(file)).isEqualTo(before)
            f.keys.key = key
            assertThat(f.store.access { requireNotNull(it).state.nativeCatalog }).isEqualTo(first)
            Files.delete(file)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state } }
            assertThat(samples).isEqualTo(0); assertThat(Files.exists(file)).isFalse()
        }
    }

    @Test fun `native facts are rechecked after signing staging and root fsync without rolling publication back`() {
        for (boundary in listOf("signing", "staging", "return")) AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            state = initialState()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            var observed = false
            var sampled = false
            // Install the protected-key wrapper before key loading. Arm it only after the first
            // facts sample, so the injected change occurs during publication signing, not reading.
            f.keys.onEncode = {
                if (sampled && !observed && boundary == "signing") {
                    observed = true; state = state.copy(userStartedServiceActive = false)
                }
            }
            // File observations are test-only boundary interception, not production SDK work.
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId) {
                    sampled = true
                    if (!observed && boundary == "staging") Files.newDirectoryStream(file.parent).use { paths ->
                        if (paths.any { it.fileName.toString().startsWith("pending-") }) {
                            observed = true; state = state.copy(userStartedServiceActive = false)
                        }
                    }
                    if (!observed && boundary == "return" && !Files.readAllBytes(file).contentEquals(before)) {
                        observed = true; state = state.copy(userStartedServiceActive = false)
                    }
                    state
                }
            }
            f.keys.onEncode = null
            assertThat(observed).isTrue()
            if (boundary == "return") {
                val retained = f.store.access { requireNotNull(it).state.nativeCatalog }
                assertThat(requireNotNull(retained).factsSha256).isNotEqualTo(state.fingerprint(f.peer.sourceInstallationId))
                assertThat(f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }.revision).isEqualTo(2)
            } else { assertThat(Files.readAllBytes(file)).isEqualTo(before) }
        }
    }

    @Test fun `exhausted catalog accepts exact retry and rejects a changed publication without reset`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            // Populate a valid signed boundary fixture through the real internal issuer writer.
            f.store.access { tx ->
                val current = requireNotNull(tx)
                current.state = current.state.copy(nativeCatalog = first.copy(revision = Int.MAX_VALUE))
            }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            assertThat(f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }.revision).isEqualTo(Int.MAX_VALUE)
            state = state.copy(userStartedServiceActive = false)
            f.expect(AgentBridgeErrorCode.BUSY) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state } }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
        }
    }

    @Test fun `each advertised native fact changes catalog identity without creating authority`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val base = initialState()
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { base }
            val alternatives = listOf(base.copy(availableNativeMetricIds = setOf("steps")),
                base.copy(deviceSettingsObjectId = AgentBridgeExportPlanningFixture.id(99)), base.copy(sourceCalendarTimezone = "UTC"),
                base.copy(configurationProtection = AgentBridgeDiscoveryConfigurationProtection.UNLOCKED_NATIVE),
                base.copy(nativeGrants = AgentBridgeDiscoveryNativeGrants.REQUIRED), base.copy(nativeGrants = AgentBridgeDiscoveryNativeGrants.UNVERIFIED),
                base.copy(entitlement = AgentBridgeDiscoveryEntitlement.REQUIRED), base.copy(userStartedServiceActive = false), base.copy(firstUnlockComplete = false))
            var revision = 1
            for (changed in alternatives) {
                val next = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { changed }
                assertThat(next.revision).isEqualTo(++revision)
                assertThat(next.factsSha256).isNotEqualTo(first.factsSha256)
                val restored = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { base }
                assertThat(restored.revision).isEqualTo(++revision)
                assertThat(restored.factsSha256).isEqualTo(first.factsSha256)
            }
            f.store.access { tx ->
                assertThat(requireNotNull(tx).state.grants).isEmpty()
                assertThat(tx.state.plans).isEmpty(); assertThat(tx.state.decisions).isEmpty()
            }
        }
    }

    @Test fun `private catalog version and publication shape must agree even with a valid fixture MAC`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val valid = f.store.access { requireNotNull(it).state }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val json = Json { encodeDefaults = true }
            for (dropCatalog in listOf(false, true)) {
                val fixture = if (dropCatalog) valid.copy(nativeCatalog = null) else valid.copy(version = 1)
                val payload = AgentBridgeCodec.canonicalize(json.encodeToString(fixture).toByteArray())
                val signer = Mac.getInstance("HmacSHA256")
                signer.init(requireNotNull(f.keys.key))
                signer.update("HealthMd.AgentBridge.AndroidExportAuthorityStore.v1\u0000".toByteArray())
                val mac = signer.doFinal(payload).joinToString("") { "%02x".format(it) }
                val bytes = AgentBridgeCodec.canonicalize(json.encodeToString(AgentBridgeExportLedgerFile(fixture, mac)).toByteArray())
                Files.write(file, bytes)
                var samples = 0
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state } }
                assertThat(samples).isEqualTo(0); assertThat(Files.readAllBytes(file)).isEqualTo(bytes)
            }
        }
    }

    private fun initialState() = AgentBridgeNativePlanningFacts(setOf("steps", "avg_hr", "min_hr", "max_hr", "resting_hr", "hrv"),
        AgentBridgeExportPlanningFixture.id(2), "America/Los_Angeles", AgentBridgeDiscoveryConfigurationProtection.LOCKED,
        AgentBridgeDiscoveryNativeGrants.SATISFIED, AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)
}

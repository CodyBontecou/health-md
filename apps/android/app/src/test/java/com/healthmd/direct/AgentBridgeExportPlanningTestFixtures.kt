package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreRegistryMetric
import com.healthmd.direct.protocol.*
import com.healthmd.domain.model.*
import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*

/** All authorities, identities, configuration and keys here are synthetic and temp-root-only. */
internal class AgentBridgeExportPlanningFixture : AutoCloseable {
    val parent: Path = Files.createTempDirectory("bridge-planning-test-").toRealPath()
    val clock = AgentBridgeExportTestClock(Instant.parse("2026-05-29T00:00:00Z"))
    val peer = AgentBridgePeer(id(1), AgentBridgePlatform.ANDROID, id(2))
    val peerContext = AgentBridgeExportTestPeer(peer)
    val hostReference = AgentBridgeAuthorityReference(id(3), 1, "b".repeat(64), AgentBridgeIssuer.AUTHORIZED_HOST)
    val keys = AgentBridgeExportTestKeys()
    val native = AgentBridgeExportTestNativeAuthorization()
    val store = AgentBridgeExportAuthorityStore.inPrivateDirectory(parent, keys)
    val configuration = AgentBridgeExportTestConfiguration()
    val service = AgentBridgeExportPlanningService(store, configuration, clock)
    val preferencesBefore = configuration.preferenceBytes()

    fun discoveryRequest() = AgentBridgeDiscoveryRequest(peer, id(4), "healthmd.agent_discovery_request", 1)
    fun request(discovery: AgentBridgeDiscovery, intent: AgentBridgeGeneratedIntent = intent(), requestId: String = id(5)) =
        AgentBridgePlanRequest(id(6), 1, discovery.capabilitySha256, hostReference, intent, requestId, "healthmd.agent_plan_request", 1)
    fun intent(output: AgentBridgeOutputSettings = output(), metrics: List<String> = listOf("heart_rate_avg", "steps"),
        dates: AgentBridgeDates = AgentBridgeDatesExact(AgentBridgeRange("2026-03-08", "2026-03-07"), "exact"),
        policy: AgentBridgeSettingsPolicy = AgentBridgeSettingsPolicyExplicit(output, "explicit")) =
        AgentBridgeGeneratedIntent("America/Los_Angeles", AgentBridgeCapture(AgentBridgeCompatibilityDetail.SUMMARY,
            AgentBridgeArchiveNone("none"), AgentBridgeSelection(false, emptyList(), metrics.sorted(), emptyList(), listOf("health_connect"))),
            dates, AgentBridgeDestination(id(7), peer.hostInstallationId, "a".repeat(64), 1), id(8), peer,
            AgentBridgeGeneratedIntentProduct("generated_files"), "healthmd.agent_export_intent", 1, policy, "UTC")
    fun delegation(expiry: String = "2026-05-29T01:00:00Z") = AgentBridgeExportDelegation(id(6),
        AgentBridgeExportDelegationBounds(listOf("America/Los_Angeles"), listOf(AgentBridgeCompatibilityDetail.SUMMARY),
            AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory(true, 4096, "authorized_history"),
            AgentBridgeExportDelegationBoundsDestinationPolicyAuthenticatedHostBindings("authenticated_host_bindings"),
            listOf(AgentBridgeFormat.JSON), listOf("android.hrv_rmssd", "heart_rate_avg", "heart_rate_max", "heart_rate_min", "resting_heart_rate", "steps"),
            listOf(AgentBridgeOutputSupportNativeArchiveProductsItem.NONE), listOf(AgentBridgeOutputProfile.ANDROID_FROZEN_V4),
            listOf(AgentBridgeExportDelegationBoundsProductsItem.GENERATED_FILES), emptyList(), emptyList(), emptyList(), listOf(AgentBridgeWriteMode.OVERWRITE)),
        expiry, 1, AgentBridgeIssuer.NATIVE_SOURCE, peer,
        listOf(AgentBridgeExportDelegationRightsItem.DISCOVER, AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE, AgentBridgeExportDelegationRightsItem.PLAN),
        "healthmd.agent_export_delegation", 1)
    fun enrolled(): AgentBridgeDiscovery {
        store.initialize(native)
        store.putDelegation(native, delegation(), 0)
        return service.discover(peerContext, discoveryRequest())
    }
    fun approvalRequest(plan: AgentBridgeGeneratedPlan) = AgentBridgeApprovalRequest(AgentBridgeValidation.bindingFor(plan), plan.planId,
        id(9), "healthmd.agent_approval_request", 1)
    fun restart() = AgentBridgeExportPlanningService(AgentBridgeExportAuthorityStore.inPrivateDirectory(parent, keys), configuration, clock)
    fun expect(code: AgentBridgeErrorCode, block: () -> Any?) {
        try { block(); throw AssertionError("Expected fixed failure") } catch (e: AgentBridgeException) {
            assertThat(e.code).isEqualTo(code)
            assertThat(e.message).isEqualTo(code.name.lowercase(java.util.Locale.ROOT))
            assertThat(e.cause).isNull()
        }
    }
    override fun close() { parent.toFile().deleteRecursively() }
    companion object {
        fun id(n: Int) = "00000000-0000-4000-8000-" + n.toString(16).padStart(12, '0')
        fun output() = AgentBridgeOutputSettings(AgentBridgeDailyNotes(false, false, "{date}", "", false, emptyList()),
            AgentBridgeDictionaryNone("none"), "{date}", "{year}", listOf(AgentBridgeFormat.JSON),
            AgentBridgeIndividualEntries(false, false, "{metric}-{date}", "", emptyList()), AgentBridgeOutputProfile.ANDROID_FROZEN_V4,
            AgentBridgePackagingLooseFiles("loose_files"), AgentBridgePresentation(AgentBridgePresentationDisplayUnits.METRIC,
                AgentBridgeFrontmatter(emptyList(), emptyList(), false, true), true, true, "en-US", "canonical",
                AgentBridgeMarkdown("", emptyList(), AgentBridgeMarkdownStyle.LISTS)), "", AgentBridgeWriteMode.OVERWRITE)
    }
}

internal class AgentBridgeExportTestPeer(var current: AgentBridgePeer) : AgentBridgeExportAuthenticatedPeer() {
    var trusted = true
    var checks = 0
    var onCheck: (() -> Unit)? = null
    override fun requireCurrent(): AgentBridgePeer {
        checks++
        onCheck?.invoke()
        if (!trusted) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        return current
    }
}
internal class AgentBridgeExportTestNativeAuthorization : AgentBridgeExportNativeAuthorization() {
    val decisions: MutableList<AgentBridgeExportNativeDecision> = java.util.Collections.synchronizedList(mutableListOf())
    var allowed = true
    var afterDecision: ((AgentBridgeExportNativeDecision) -> Unit)? = null
    override fun requireDecision(decision: AgentBridgeExportNativeDecision) {
        if (!allowed) throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        decisions += decision
        afterDecision?.invoke(decision)
    }
}
internal class AgentBridgeExportTestKeys : AgentBridgeExportProtectedKeyProvider {
    var calls = 0
    var key: SecretKey? = SecretKeySpec(ByteArray(32) { 0x37 }, "HmacSHA256")
    override fun loadExisting(): SecretKey? { calls++; return key }
}
internal class AgentBridgeExportTestClock(var now: Instant) : Clock() {
    override fun instant(): Instant = now
    override fun getZone() = ZoneOffset.UTC
    override fun withZone(zone: java.time.ZoneId): Clock = Clock.fixed(now, zone)
}
internal class AgentBridgeExportTestConfiguration : AgentBridgeExportPlanningConfigurationReader {
    var calls = 0
    private val json = Json { encodeDefaults = true }
    var saved: AgentBridgeRequestSettingsSnapshot? = null
    var profiles = emptyList<AgentBridgeRequestSettingsProfile>()
    var catalog = AgentBridgeRequestSettingsCatalog(AgentBridgeExportTestRegistry.load(), setOf("steps", "avg_hr", "min_hr", "max_hr", "resting_hr", "hrv"), 3)
    var grants = AgentBridgeDiscoveryNativeGrants.SATISFIED
    var entitlement = AgentBridgeDiscoveryEntitlement.SATISFIED
    var active = true
    var unlocked = true
    var sourceZone = "America/Los_Angeles"
    var onRead: (() -> Unit)? = null
    private val unrelatedPreferences = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://synthetic.invalid/never-contact", scheduleEnabled = true)
    fun preferenceBytes() = json.encodeToString(unrelatedPreferences)
    override fun readConfiguration(): AgentBridgeExportPlanningConfiguration {
        calls++
        val snapshot = AgentBridgeExportPlanningConfiguration(AgentBridgeRequestSettingsInputs(catalog, saved, profiles),
            AgentBridgeExportPlanningFixture.id(2), sourceZone, AgentBridgeDiscoveryConfigurationProtection.LOCKED,
            grants, entitlement, active, unlocked)
        onRead?.invoke()
        return snapshot
    }
}
internal object AgentBridgeExportTestRegistry {
    fun load(): CoreMetricRegistrySnapshot {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        var file: File? = null
        while (directory != null && file == null) {
            val candidate = File(directory, "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json")
            if (candidate.isFile) file = candidate else directory = directory.parentFile
        }
        val root = Json.parseToJsonElement(requireNotNull(file).readText()).jsonObject
        val profile = root.getValue("profiles").jsonArray.map { it.jsonObject }.single { it.getValue("id").jsonPrimitive.content == "android_frozen_v4" }
        val metrics = root.getValue("metrics").jsonArray.mapNotNull { element ->
            val row = element.jsonObject
            val native = row.getValue("android").jsonObject
            if (native.getValue("status").jsonPrimitive.content != "backed") return@mapNotNull null
            fun text(key: String) = native.getValue(key).jsonPrimitive.content
            CoreRegistryMetric(row.getValue("semantic_id").jsonPrimitive.content, text("selection_id"), text("label_key"), row.getValue("reference_name").jsonPrimitive.content,
                text("category_id"), text("unit"), "captured", text("source_aggregation"), text("default_enabled").toBoolean(), false, text("availability_key"), "health_connect",
                row.getValue("capability_id").jsonPrimitive.content, text("selection_id"), native.getValue("related_semantic_ids").jsonArray.map { it.jsonPrimitive.content }, text("ordinal").toUInt())
        }.sortedBy { it.ordinal }
        fun profileText(key: String) = profile.getValue(key).jsonPrimitive.content
        return CoreMetricRegistrySnapshot(root.getValue("registry_version").jsonPrimitive.content.toUInt(), HEALTHMD_CORE_REGISTRY_SHA256, "android_frozen_v4",
            profileText("public_profile_id"), profileText("public_schema"), profileText("public_schema_version").toUInt(), profileText("profile_revision").toUInt(), emptyList(), metrics, emptyList(), emptyList())
    }
}

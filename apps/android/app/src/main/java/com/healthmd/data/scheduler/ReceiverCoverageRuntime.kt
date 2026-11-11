package com.healthmd.data.scheduler

import android.content.Context
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.receivercoverage.*
import com.healthmd.domain.repository.EntitlementRepository
import java.nio.file.Files
import java.nio.file.Path
import java.time.Instant
import java.time.LocalDate
import java.util.Locale
import kotlinx.serialization.json.*

/** Scheduler-owned secure authority and atomic admission/configuration adapter. */
class ReceiverCoverageRuntime(
    context: Context,
    private val credentials: APIExportCredentialStore,
    private val entitlements: EntitlementRepository,
) {
    private val directory = context.filesDir.toPath().resolve("receiver-coverage")
    private val journal = ReceiverCoverageJournal(directory.resolve("plans"))
    data class Lease(val id: String, val authority: String, val plan: ReceiverCoveragePlan, val fingerprint: String)
    companion object {
        private val lock = Any()
        /** Wide legacy catch-up stays full lookback; never truncate dates to fit the query. */
        fun withinSelectionBounds(dates: List<LocalDate>, zone: String, now: Instant): Boolean {
            if (dates.isEmpty()) return true // Refresh-only work has no coverage query.
            val normalized = dates.distinct().sorted()
            val today = now.atZone(java.time.ZoneId.of(zone)).toLocalDate()
            return dates == normalized && dates.size <= 30 && dates.last() < today &&
                java.time.temporal.ChronoUnit.DAYS.between(dates.first(), dates.last()) < 30
        }
        private fun path(context: Context, scope: String): Path {
            require(Regex("[A-Za-z0-9_-]{1,128}").matches(scope))
            return context.filesDir.toPath().resolve("receiver-coverage/configuration-$scope.json")
        }
        fun configuration(context: Context, scope: String): String? = synchronized(lock) {
            val file = path(context, scope)
            if (!Files.exists(file)) null else String(Files.readAllBytes(file), Charsets.UTF_8).also { ReceiverCoverageConfiguration.parse(it) }
        }
        suspend fun save(context: Context, scope: String, configuration: ReceiverCoverageConfiguration?, uploadUrl: String,
                         credentials: APIExportCredentialStore) {
            if (configuration == null) { synchronized(lock) { Files.deleteIfExists(path(context, scope)) }; return }
            val plans = context.filesDir.toPath().resolve("receiver-coverage/plans").toFile()
            val key = credentials.receiverCoverageKey(create = plans.list()?.isEmpty() != false)
            ReceiverCoveragePreflight.prepare(ReceiverCoveragePreflight.Policy.MISSING_DAYS, uploadUrl,
                configuration.preflightUrl, emptyMap(), configuration.scopeId, "UTC", "{}".toByteArray(), configuration.refreshRecentDays, key)
            synchronized(lock) { ReceiverCoverageAtomicFile.write(path(context, scope), configuration.json().toByteArray()) }
        }
    }
    /** Freezes both opt-in AND the absent/full-lookback default once for a legacy admission. */
    fun configurationForOccurrence(id: String, scope: String, eligible: Boolean, requireExisting: Boolean = false): String? = synchronized(lock) {
        require(Regex("[A-Za-z0-9_-]{1,128}").matches(id))
        val path = directory.resolve("admission-$id.json")
        if (Files.exists(path)) {
            val value = Json.parseToJsonElement(String(Files.readAllBytes(path), Charsets.UTF_8)).jsonObject
            require(value.keys == setOf("configuration","scope","version") && value.getValue("scope").jsonPrimitive.content == scope && value.getValue("version").jsonPrimitive.int == 1)
            value.getValue("configuration").takeUnless { it == JsonNull }?.jsonPrimitive?.content
        } else {
            check(!requireExisting) { "Original receiver configuration is missing" }
            val value = if (eligible) configurationAt(scope) else null
            val json = buildJsonObject { put("configuration", value?.let(::JsonPrimitive) ?: JsonNull); put("scope",scope); put("version",1) }
            ReceiverCoverageAtomicFile.write(path, json.toString().toByteArray()); value
        }
    }
    private fun configurationAt(scope: String): String? {
        val file = directory.resolve("configuration-$scope.json")
        return if (Files.exists(file)) String(Files.readAllBytes(file), Charsets.UTF_8).also { ReceiverCoverageConfiguration.parse(it) } else null
    }
    fun hasPlan(id: String): Boolean = journal.exists(id)
    class Destination(val preflight: ReceiverCoveragePreflight, val fingerprint: String)
    suspend fun destination(configJson: String, endpoint: String, snapshot: String, zone: String): Destination {
        val outputSettings = ReceiverCoverageSnapshot.outputSettings(snapshot)
        val config = ReceiverCoverageConfiguration.parse(configJson)
        check(entitlements.verifyAccess()) { "Receiver-aware selection needs independent API access" }
        val sponsored = entitlements.sponsoredEndpoint.value?.let(com.healthmd.domain.billing.ClinicExportAuthorization::canonicalClinicEndpoint)
        val managed = sponsored != null && sponsored == com.healthmd.domain.billing.ClinicExportAuthorization.canonicalClinicEndpoint(endpoint)
        check(!managed && entitlements.clinicUploadAuthorization(endpoint) == null) { "Managed rotating credentials are unsupported for receiver selection" }
        val request = requireNotNull(credentials.requestConfiguration(endpoint))
        val headers = mutableMapOf<String,String>()
        request.authorizationHeader?.let { headers["authorization"] = it }
        request.requestHeaders.forEach { headers[it.name.lowercase(Locale.ROOT)] = it.value }
        val key = credentials.receiverCoverageKey()
        val preflight = requireNotNull(ReceiverCoveragePreflight.prepare(ReceiverCoveragePreflight.Policy.MISSING_DAYS,
            request.endpointUrl, config.preflightUrl, headers, config.scopeId, zone, outputSettings.toByteArray(), config.refreshRecentDays,
            key))
        synchronized(lock) {
            val mac = javax.crypto.Mac.getInstance("HmacSHA256")
            mac.init(javax.crypto.spec.SecretKeySpec(key, "HmacSHA256"))
            val digest = mac.doFinal("receiver-coverage-scope-v1:$outputSettings".toByteArray()).joinToString("") { "%02x".format(it) }
            val scopeFile = directory.resolve("scope-${config.scopeId}.binding")
            if (Files.exists(scopeFile)) check(String(Files.readAllBytes(scopeFile), Charsets.UTF_8) == digest) {
                "This receiver scope belongs to another frozen output profile; choose a new scope"
            } else ReceiverCoverageAtomicFile.write(scopeFile, digest.toByteArray())
        }
        return Destination(preflight, request.destinationFingerprint)
    }
    suspend fun resolve(id: String, authority: String, configJson: String, endpoint: String, snapshot: String,
                        zone: String, dates: List<LocalDate>, todayRefresh: Boolean, now: Instant,
                        restoreOnly: Boolean = false, expectedBinding: String? = null,
                        admit: suspend (ReceiverCoveragePlan) -> Unit = {},
                        query: suspend (ReceiverCoverageRequest) -> ReceiverCoverageOutcome = { ReceiverCoverageHTTPClient().query(it) },
                        authorized: suspend () -> Boolean): Lease {
        val destination = destination(configJson, endpoint, snapshot, zone)
        val preflight = destination.preflight
        if (expectedBinding != null) check(preflight.destinationBinding == expectedBinding) { "Original receiver destination changed" }
        val plan = if (restoreOnly) requireNotNull(journal.restore(id, authority, preflight.destinationBinding))
            else journal.resolve(id, authority, preflight, dates.map(LocalDate::toString), now, todayRefresh, authorized, admit, query)
        if (!authorized()) throw kotlinx.coroutines.CancellationException("Receiver occurrence invalidated")
        return Lease(id, authority, plan, destination.fingerprint)
    }
    fun acknowledge(lease: Lease, dates: Collection<LocalDate>) {
        journal.acknowledge(lease.id, lease.authority, lease.plan.destinationBinding, dates.map(LocalDate::toString))
    }
}

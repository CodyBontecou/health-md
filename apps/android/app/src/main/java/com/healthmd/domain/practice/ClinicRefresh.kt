package com.healthmd.domain.practice

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred

/** Native-local metadata only; never a credential, health payload or imported setup. */
data class ClinicRefreshRequest(
    val requestId: String, val subjectId: String, val deviceId: String, val connectionId: String,
    val profileId: String, val revision: String, val startMillis: Long, val endMillis: Long, val expiresAtMillis: Long,
    /** Explicit patient-approved owner days; null retains exact timestamp bounds. */
    val ownerDayZone: String? = null,
) {
    fun validate(now: Long) {
        require(listOf(requestId, subjectId, deviceId, connectionId, profileId, revision).all {
            it.isNotEmpty() && it.toByteArray(Charsets.UTF_8).size <= 200 && it.none(Char::isISOControl)
        }) { "unavailable" }
        require(startMillis < endMillis && startMillis <= now && expiresAtMillis > now) { "unavailable" }
        if (ownerDayZone != null) {
            require(ownerDayZone.isNotEmpty() && ownerDayZone.toByteArray(Charsets.UTF_8).size <= 100) { "unavailable" }
            val zone = ZoneId.of(ownerDayZone)
            val start = Instant.ofEpochMilli(startMillis).atZone(zone); val end = Instant.ofEpochMilli(endMillis).atZone(zone)
            val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
            require(start.toLocalDate().atStartOfDay(zone).toInstant() == start.toInstant()
                && end.toLocalDate().atStartOfDay(zone).toInstant() == end.toInstant()
                && end.toLocalDate() <= today.plusDays(1)
                && ChronoUnit.DAYS.between(start.toLocalDate(), end.toLocalDate()) in 1..366) { "unavailable" }
        } else require(endMillis <= now && endMillis - startMillis in 1..(366L * 86_400_000)) { "unavailable" }
    }
    /** No implicit rounding of a timestamp request, and no replacement of its approved zone. */
    fun ownerDates(zone: ZoneId, now: Long = System.currentTimeMillis()): List<LocalDate> {
        validate(now); check(ownerDayZone == null || ownerDayZone == zone.id) { "timezone_changed" }
        val start = Instant.ofEpochMilli(startMillis).atZone(zone); val end = Instant.ofEpochMilli(endMillis).atZone(zone)
        check(start.toLocalDate().atStartOfDay(zone).toInstant() == start.toInstant()
            && end.toLocalDate().atStartOfDay(zone).toInstant() == end.toInstant()) { "partial_day_scope_unsupported" }
        val dates = generateSequence(start.toLocalDate()) { it.plusDays(1) }.takeWhile { it < end.toLocalDate() }.take(367).toList()
        check(dates.isNotEmpty() && dates.size <= 366) { "unavailable" }; return dates
    }
}
data class ClinicRefreshRecord(val request: ClinicRefreshRequest, val state: State, val exportId: String? = null, val uploadedAtMillis: Long? = null) {
    enum class State { REQUESTED, EXECUTING, UPLOADED, FAILED }
}

/** Must be rooted in app-private noBackupFilesDir. Atomic replace and fsync precede export/report side effects.
 * The per-directory lock protects multiple coordinator instances; corrupt entries fail closed. */
class ClinicRefreshJournal(private val root: File) {
    companion object {
        private val locks = ConcurrentHashMap<String, Any>()
        private val active = ConcurrentHashMap<String, ActiveExecution>()
    }
    private class ActiveExecution(val request: ClinicRefreshRequest) {
        val outcome = CompletableDeferred<Result<ClinicRefreshRecord>>()
    }
    suspend fun singleFlight(request: ClinicRefreshRequest, operation: suspend () -> ClinicRefreshRecord): ClinicRefreshRecord {
        val identity = file(request).canonicalPath
        val execution = ActiveExecution(request)
        val existing = active.putIfAbsent(identity, execution)
        if (existing != null) {
            check(existing.request == request) { "profile_changed" }
            return existing.outcome.await().getOrThrow()
        }
        try {
            return operation().also { execution.outcome.complete(Result.success(it)) }
        } catch (error: Throwable) {
            execution.outcome.complete(Result.failure(error)); throw error
        } finally { active.remove(identity, execution) }
    }
    private val lock = locks.computeIfAbsent(root.canonicalPath) { Any() }
    init {
        check(root.mkdirs() || root.isDirectory)
        check(!Files.isSymbolicLink(root.toPath())) { "invalid_journal" }
    }
    private fun file(request: ClinicRefreshRequest): File {
        val key = listOf(request.subjectId, request.deviceId, request.requestId).joinToString("\u0000")
        val name = MessageDigest.getInstance("SHA-256").digest(key.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
        return File(root, "$name.record")
    }
    fun load(request: ClinicRefreshRequest): ClinicRefreshRecord? = synchronized(lock) {
        val file = file(request)
        if (!Files.exists(file.toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS)) return@synchronized null
        check(!Files.isSymbolicLink(file.toPath()) && file.isFile && file.length() <= 16_384) { "invalid_journal" }
        try {
            DataInputStream(FileInputStream(file)).use { input ->
                val version = input.readInt(); check(version in 1..2) { "invalid_journal" }
                val stored = ClinicRefreshRequest(input.readUTF(), input.readUTF(), input.readUTF(), input.readUTF(),
                    input.readUTF(), input.readUTF(), input.readLong(), input.readLong(), input.readLong(),
                    if (version == 2) input.readUTF().takeIf(String::isNotEmpty) else null)
                val state = ClinicRefreshRecord.State.valueOf(input.readUTF())
                val exportId = input.readUTF().takeIf(String::isNotEmpty)
                val time = input.readLong().takeIf { it >= 0 }
                check(if (state == ClinicRefreshRecord.State.UPLOADED) exportId != null && time != null else exportId == null && time == null) { "invalid_journal" }
                check(stored == request && input.read() == -1) { "profile_changed" }
                ClinicRefreshRecord(stored, state, exportId, time)
            }
        } catch (_: Exception) { error("invalid_journal") }
    }
    fun reserve(request: ClinicRefreshRequest): Boolean = synchronized(lock) {
        if (load(request)?.state?.let { it != ClinicRefreshRecord.State.REQUESTED } == true) return@synchronized false
        save(ClinicRefreshRecord(request, ClinicRefreshRecord.State.EXECUTING)); true
    }
    fun save(record: ClinicRefreshRecord) = synchronized(lock) {
        val destination = file(record.request)
        check(destination.exists() || (root.listFiles()?.size ?: 1000) < 1000) { "capacity" }
        val temporary = File.createTempFile("clinic-", ".pending", root)
        try {
            FileOutputStream(temporary).use { file ->
                val out = DataOutputStream(file)
                out.writeInt(2)
                with(record.request) {
                    listOf(requestId, subjectId, deviceId, connectionId, profileId, revision).forEach(out::writeUTF)
                    out.writeLong(startMillis); out.writeLong(endMillis); out.writeLong(expiresAtMillis); out.writeUTF(ownerDayZone.orEmpty())
                }
                out.writeUTF(record.state.name); out.writeUTF(record.exportId.orEmpty()); out.writeLong(record.uploadedAtMillis ?: -1)
                out.flush(); file.fd.sync()
            }
            Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            java.nio.channels.FileChannel.open(root.toPath(), java.nio.file.StandardOpenOption.READ).use { it.force(true) }
            Unit
        } finally { temporary.delete() }
    }
}

class ClinicForegroundRefresh(
    private val journal: ClinicRefreshJournal,
    private val enabled: () -> Boolean = { PracticeFeaturePolicy.current().isEnabled },
) {
    suspend fun run(
        request: ClinicRefreshRequest, now: () -> Long = System::currentTimeMillis,
        authenticate: suspend () -> Unit, authorize: suspend () -> Unit,
        export: suspend (check: suspend () -> Unit) -> String,
        report: suspend (ClinicRefreshRecord) -> Unit,
    ): ClinicRefreshRecord {
        check(enabled()) { "unavailable" }; authenticate()
        return journal.singleFlight(request) { runOwned(request, now, authenticate, authorize, export, report) }
    }
    private suspend fun runOwned(
        request: ClinicRefreshRequest, now: () -> Long, authenticate: suspend () -> Unit, authorize: suspend () -> Unit,
        export: suspend (check: suspend () -> Unit) -> String, report: suspend (ClinicRefreshRecord) -> Unit,
    ): ClinicRefreshRecord {
        // Only a journal with no live in-process owner is eligible for restart recovery.
        val existing = journal.load(request)
        if (existing != null && existing.state != ClinicRefreshRecord.State.REQUESTED) {
            val recovered = if (existing.state == ClinicRefreshRecord.State.EXECUTING) existing.copy(state = ClinicRefreshRecord.State.FAILED) else existing
            journal.save(recovered); report(recovered); return recovered
        }
        request.validate(now())
        if (existing == null) journal.save(ClinicRefreshRecord(request, ClinicRefreshRecord.State.REQUESTED))
        val authorityCheck: suspend () -> Unit = { check(enabled()) { "unavailable" }; request.validate(now()); authenticate(); authorize() }
        authorityCheck(); check(journal.reserve(request)) { "already_running" }
        val uploaded = try {
            val id = export(authorityCheck)
            require(id.isNotEmpty() && id.toByteArray(Charsets.UTF_8).size <= 200) { "incomplete_export" }
            ClinicRefreshRecord(request, ClinicRefreshRecord.State.UPLOADED, id, now())
        } catch (error: Throwable) {
            val failed = ClinicRefreshRecord(request, ClinicRefreshRecord.State.FAILED)
            journal.save(failed); report(failed); throw error
        }
        // An acknowledgment error leaves persisted upload evidence intact. No recapture on retry.
        journal.save(uploaded); report(uploaded); return uploaded
    }
}

/** Independent trusted state sources; these facts never come from setup/QR parameters. */
data class ClinicExportGates(
    val subjectId: String, val deviceId: String, val connectionId: String,
    val foreground: Boolean, val sharingConsent: Boolean, val healthDataAvailable: Boolean,
    val consumerAllowsExport: Boolean, val verifiedClinicGrant: Boolean,
    val clinicEntitlementRouteEnabled: Boolean = false,
) {
    fun requireFor(request: ClinicRefreshRequest) {
        check(subjectId == request.subjectId && deviceId == request.deviceId && connectionId == request.connectionId
            && foreground && sharingConsent && healthDataAvailable
            && (consumerAllowsExport || (clinicEntitlementRouteEnabled && verifiedClinicGrant))) { "unavailable" }
    }
}

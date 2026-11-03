package com.healthmd.domain.practice

import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/** Native-local metadata only; never a credential, health payload or imported setup. */
data class ClinicRefreshRequest(
    val requestId: String, val subjectId: String, val deviceId: String, val connectionId: String,
    val profileId: String, val revision: String, val startMillis: Long, val endMillis: Long, val expiresAtMillis: Long,
) {
    fun validate(now: Long) {
        require(listOf(requestId, subjectId, deviceId, connectionId, profileId, revision).all {
            it.isNotEmpty() && it.toByteArray(Charsets.UTF_8).size <= 200 && it.none(Char::isISOControl)
        }) { "unavailable" }
        require(startMillis < endMillis && endMillis <= now && endMillis - startMillis in 1..(366L * 86_400_000) && expiresAtMillis > now) { "unavailable" }
    }
}
data class ClinicRefreshRecord(val request: ClinicRefreshRequest, val state: State, val exportId: String? = null, val uploadedAtMillis: Long? = null) {
    enum class State { REQUESTED, EXECUTING, UPLOADED, FAILED }
}

/** Must be rooted in app-private noBackupFilesDir. Atomic replace and fsync precede export/report side effects.
 * The per-directory lock protects multiple coordinator instances; corrupt entries fail closed. */
class ClinicRefreshJournal(private val root: File) {
    companion object { private val locks = ConcurrentHashMap<String, Any>() }
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
                check(input.readInt() == 1) { "invalid_journal" }
                val stored = ClinicRefreshRequest(input.readUTF(), input.readUTF(), input.readUTF(), input.readUTF(),
                    input.readUTF(), input.readUTF(), input.readLong(), input.readLong(), input.readLong())
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
                out.writeInt(1)
                with(record.request) {
                    listOf(requestId, subjectId, deviceId, connectionId, profileId, revision).forEach(out::writeUTF)
                    out.writeLong(startMillis); out.writeLong(endMillis); out.writeLong(expiresAtMillis)
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

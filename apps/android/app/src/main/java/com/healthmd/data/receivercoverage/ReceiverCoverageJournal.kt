package com.healthmd.data.receivercoverage

import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*

class ReceiverCoverageConfiguration(val preflightUrl: String, val scopeId: String, val refreshRecentDays: Int) {
    fun json(): String = buildJsonObject {
        put("preflight_url", preflightUrl); put("scope_id", scopeId); put("refresh_recent_days", refreshRecentDays)
    }.toString()
    companion object {
        const val WARNING = "Already retained completed days may be skipped. Late source updates outside the correction window will not be resent automatically. Use full lookback or a manual re-export to refresh older snapshots."
        fun parse(json: String): ReceiverCoverageConfiguration {
            val o = Json.parseToJsonElement(json).jsonObject
            require(o.keys == setOf("preflight_url","scope_id","refresh_recent_days"))
            return ReceiverCoverageConfiguration(o.getValue("preflight_url").jsonPrimitive.content,
                o.getValue("scope_id").jsonPrimitive.content, o.getValue("refresh_recent_days").jsonPrimitive.int)
        }
    }
}

object ReceiverCoverageAtomicFile {
    fun write(path: Path, bytes: ByteArray) {
        Files.createDirectories(path.parent)
        val temp = Files.createTempFile(path.parent, ".receiver-", ".tmp")
        try {
            FileChannel.open(temp, StandardOpenOption.WRITE).use { channel ->
                val buffer = ByteBuffer.wrap(bytes)
                while (buffer.hasRemaining()) channel.write(buffer)
                channel.force(true)
            }
            Files.move(temp, path, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            FileChannel.open(path.parent, StandardOpenOption.READ).use { it.force(true) }
        } finally { Files.deleteIfExists(temp) }
    }
}

/** Exact v2 plans, atomically committed before source capture. A pending preflight is recovered as
 * its already-saved full fallback; cancellation/crash never causes another receiver query. */
class ReceiverCoverageJournal(private val directory: Path) {
    private data class Envelope(val authority: String, val pending: Boolean, val plan: String) {
        fun json() = buildJsonObject {
            put("authority", authority); put("plan", plan); put("preflightPending", pending); put("version", 1)
        }.toString()
    }
    companion object { private val lock = Any() }
    private fun path(id: String): Path {
        require(Regex("[A-Za-z0-9_-]{1,128}").matches(id))
        return directory.resolve("$id.json")
    }
    private fun load(id: String): Envelope? {
        val path = path(id)
        if (!Files.exists(path)) return null
        require(Files.size(path) <= 128 * 1024)
        val raw = String(Files.readAllBytes(path), Charsets.UTF_8)
        val value = Json.parseToJsonElement(raw).jsonObject
        require(value.getValue("version").jsonPrimitive.int == 1)
        val record = Envelope(value.getValue("authority").jsonPrimitive.content,
            value.getValue("preflightPending").jsonPrimitive.boolean, value.getValue("plan").jsonPrimitive.content)
        require(record.json() == raw) // Reject extra/duplicate/coerced/corrupt state without rewriting it.
        return record
    }
    private fun save(id: String, envelope: Envelope) = ReceiverCoverageAtomicFile.write(path(id), envelope.json().toByteArray())
    fun exists(id: String): Boolean = synchronized(lock) { load(id) != null }
    fun restore(id: String, authority: String, binding: String): ReceiverCoveragePlan? = synchronized(lock) {
        val value = load(id) ?: return@synchronized null
        require(value.authority == authority)
        val plan = ReceiverCoveragePlan.restore(value.plan, binding)
        if (value.pending) save(id, value.copy(pending = false))
        plan
    }
    suspend fun resolve(id: String, authority: String, preflight: ReceiverCoveragePreflight,
                        candidates: List<String>, now: Instant, todayRefresh: Boolean,
                        authorized: suspend () -> Boolean,
                        query: suspend (ReceiverCoverageRequest) -> ReceiverCoverageOutcome = { ReceiverCoverageHTTPClient().query(it) }): ReceiverCoveragePlan {
        restore(id, authority, preflight.destinationBinding)?.let { return it }
        val today = now.atZone(ZoneId.of(preflight.calendarTimezone)).toLocalDate().toString()
        val requestId = UUID.randomUUID().toString()
        val fallback = ReceiverCoveragePlan.select(requestId, preflight.scopeId, preflight.calendarTimezone, candidates, today,
            preflight.destinationBinding, preflight.refreshRecentDays, todayRefresh, ReceiverCoverageOutcome.FallbackFull)
        val accepted = synchronized(lock) {
            val existing = load(id)
            if (existing != null) false else {
                save(id, Envelope(authority, true, fallback.json())); true
            }
        }
        if (!accepted) return requireNotNull(restore(id, authority, preflight.destinationBinding))
        currentCoroutineContext().ensureActive()
        if (!authorized()) throw kotlinx.coroutines.CancellationException("Receiver occurrence invalidated")
        val outcome = query(ReceiverCoverageRequest.freeze(preflight, requestId, candidates, now))
        currentCoroutineContext().ensureActive()
        if (!authorized()) throw kotlinx.coroutines.CancellationException("Receiver occurrence invalidated")
        val chosen = ReceiverCoveragePlan.select(requestId, preflight.scopeId, preflight.calendarTimezone, candidates, today,
            preflight.destinationBinding, preflight.refreshRecentDays, todayRefresh, outcome)
        synchronized(lock) {
            val original = requireNotNull(load(id))
            require(original.authority == authority && original.pending && original.plan == fallback.json())
            save(id, Envelope(authority, false, chosen.json()))
        }
        return chosen
    }
    fun acknowledge(id: String, authority: String, binding: String, dates: Collection<String>) = synchronized(lock) {
        val value = requireNotNull(load(id))
        require(value.authority == authority && !value.pending)
        val plan = ReceiverCoveragePlan.restore(value.plan, binding).acknowledging(dates)
        save(id, value.copy(plan = plan.json()))
    }
}

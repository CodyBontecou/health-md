package com.healthmd.direct

import com.healthmd.direct.protocol.*
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.StandardOpenOption.*
import java.nio.file.StandardCopyOption.ATOMIC_MOVE
import java.nio.file.attribute.PosixFilePermissions
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.SecretKey
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Private captured bytes, not portable output or a permission. Independently versioned MAC
 * records bind the immutable accepted request/resolution, permanent claim and original expiry. */
internal class AgentBridgeNativeCaptureSpool(
    private val issuer: Path,
    private val reservation: AgentBridgeExportCaptureReservation,
    private val key: SecretKey,
    create: Boolean,
    private val check: () -> Unit,
    private val attributes: (Path, Boolean) -> Any,
) : AutoCloseable {
    @Serializable private data class Record(val version: Int, val requestSha256: String,
        val resolutionSha256: String, val claimId: String, val expiresAt: String,
        val kind: String, val day: String?, val payload: String)
    @Serializable private data class Signed(val record: Record, val mac: String)
    private val json = Json { encodeDefaults = true; explicitNulls = true; ignoreUnknownKeys = false }
    private val captures = issuer.resolve("captures")
    private val directory = captures.resolve(reservation.job.requestSha256)
    private var identities = emptyList<Any>()
    private var channel: FileChannel? = null
    private var held: FileLock? = null
    private var lockIdentity: Any? = null
    private var storedBytes = 0L
    private var closed = false

    init {
        try {
            reservation.job.validate()
            val claimID = UUID.fromString(reservation.claim.claimId)
            if (!reservation.job.requestSha256.matches(Regex("[0-9a-f]{64}")) || reservation.claim.version != 1 ||
                reservation.claim.requestSha256 != reservation.job.requestSha256 || claimID.toString() != reservation.claim.claimId ||
                claimID.version() != 4 || claimID.variant() != 2 || reservation.claim.claimedAt < reservation.job.acceptedAt ||
                reservation.claim.claimedAt >= reservation.job.expiresAt) fail()
            check()
            identities = listOf(attributes(issuer, true))
            guard()
            if (create) mkdir(captures, exclusive = false)
            identities = identities + attributes(captures, true)
            guard()
            if (create) mkdir(directory, exclusive = true)
            identities = identities + attributes(directory, true)
            guard()
            val lockPath = directory.resolve("lock")
            if (create) {
                FileChannel.open(lockPath, setOf(CREATE_NEW, WRITE, NOFOLLOW_LINKS), PosixFilePermissions.asFileAttribute(FILE_PERMISSIONS)).use { it.force(true) }
                attributes(lockPath, false); force(directory)
            }
            lockIdentity = attributes(lockPath, false)
            channel = FileChannel.open(lockPath, WRITE, NOFOLLOW_LINKS)
            held = try { channel!!.tryLock() } catch (_: OverlappingFileLockException) { fail(AgentBridgeErrorCode.BUSY) }
            if (held == null) fail(AgentBridgeErrorCode.BUSY)
            if (Files.size(lockPath) != 0L) fail()
            guard()
            Files.newDirectoryStream(directory).use { stream ->
                var count = 0
                for (path in stream) {
                    if (++count > 8258) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
                    val name = path.fileName.toString()
                    if (name !in setOf("lock", "header.json", "progress.json") && !DAY_NAME.matches(name) && !PENDING_NAME.matches(name)) fail()
                    attributes(path, false)
                    val size = Files.size(path)
                    if (size !in 0..(2 * PAYLOAD_LIMIT).toLong()) fail()
                    storedBytes += size
                    if (storedBytes > JOB_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
                }
            }
            if (create) {
                publish("header.json", record("job", null))
                publish("progress.json", record("progress", null, Base64.getEncoder().encodeToString(json.encodeToString(emptyList<String>()).toByteArray())))
            } else {
                if (read("header.json") != record("job", null)) fail()
                progress()
            }
            validateStoredProgress()
            guard()
        } catch (error: Exception) { close(); throw safe(error) }
    }
    /** An existing successful capture is reused verbatim. A started marker without bytes is
     * ambiguous and never grants a second SDK attempt, including across process restart. */
    @Synchronized fun loadOrBegin(day: String): ByteArray? = safeCall {
        validDay(day)
        guard()
        val started = "started-$day.json"; val captured = "day-$day.json"
        val (previous, days) = progress()
        if (day in days) {
            if (!exists(captured)) fail()
            if (read(started) != record("started", day)) fail()
            val value = read(captured)
            if (value.kind != "captured" || value.day != day || value.payload.isEmpty()) fail()
            val bytes = Base64.getDecoder().decode(value.payload)
            guard(); bytes
        } else {
            if (exists(started) || exists(captured)) fail()
            if (days.size >= 4096) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            if (storedBytes + 2 * PAYLOAD_LIMIT >= JOB_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            val next = Base64.getEncoder().encodeToString(json.encodeToString((days + day).sorted()).toByteArray())
            publish("progress.json", record("progress", null, next), previous)
            publish(started, record("started", day)); null
        }
    }
    @Synchronized fun commit(day: String, payload: ByteArray) = safeCall {
        validDay(day)
        val frozen = payload.copyOf()
        if (frozen.isEmpty() || frozen.size > PAYLOAD_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        guard()
        if (day !in progress().second) fail()
        if (read("started-$day.json") != record("started", day)) fail()
        publish("day-$day.json", record("captured", day, Base64.getEncoder().encodeToString(frozen)))
    }
    @Synchronized override fun close() {
        if (closed) return
        closed = true
        runCatching { held?.release() }; held = null
        runCatching { channel?.close() }; channel = null
    }
    private fun record(kind: String, day: String?, payload: String = "") = Record(1, reservation.job.requestSha256,
        AgentBridgeCodec.sha256(reservation.job.resolutionCanonical.toByteArray()), reservation.claim.claimId,
        reservation.job.expiresAt, kind, day, payload)
    private fun validateStoredProgress() {
        val (_, days) = progress()
        val expected = mutableSetOf("lock", "header.json", "progress.json")
        for (day in days) {
            val started = "started-$day.json"; val captured = "day-$day.json"
            expected += started; expected += captured
            if (read(started) != record("started", day)) fail()
            val value = read(captured)
            if (value.kind != "captured" || value.day != day || value.payload.isEmpty()) fail()
        }
        val names = Files.newDirectoryStream(directory).use { stream ->
            stream.map { it.fileName.toString() }.filter { !PENDING_NAME.matches(it) }.toSet()
        }
        if (names != expected) fail()
    }
    private fun progress(): Pair<Record, List<String>> {
        val value = read("progress.json")
        val bytes = Base64.getDecoder().decode(value.payload)
        val days = json.decodeFromString<List<String>>(bytes.decodeToString())
        if (value.kind != "progress" || value.day != null || days.size > 4096 || days.distinct().size != days.size ||
            days != days.sorted() || !json.encodeToString(days).toByteArray().contentEquals(bytes)) fail()
        days.forEach(::validDay)
        return value to days
    }
    private fun pins() {
        if (closed || identities.isEmpty()) fail()
        listOf(issuer, captures, directory).take(identities.size).forEachIndexed { index, path -> if (attributes(path, true) != identities[index]) fail(AgentBridgeErrorCode.BINDING_CHANGED) }
        lockIdentity?.let { if (attributes(directory.resolve("lock"), false) != it) fail(AgentBridgeErrorCode.BINDING_CHANGED) }
    }
    private fun guard() { pins(); check(); pins() }
    private fun exists(name: String): Boolean = present(directory.resolve(name))
    private fun present(path: Path): Boolean = try {
        Files.readAttributes(path, java.nio.file.attribute.BasicFileAttributes::class.java, NOFOLLOW_LINKS); true
    } catch (_: java.nio.file.NoSuchFileException) { false }
    private fun validDay(day: String) {
        if (!day.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}"))) fail(AgentBridgeErrorCode.INVALID_REQUEST)
        val parsed = java.time.LocalDate.parse(day)
        if (parsed.year !in 1..9999 || parsed.toString() != day) fail(AgentBridgeErrorCode.INVALID_REQUEST)
    }
    private fun read(name: String): Record {
        guard()
        val path = directory.resolve(name)
        val identity = attributes(path, false)
        val size = Files.size(path)
        if (size !in 1..(2 * PAYLOAD_LIMIT).toLong()) fail()
        val bytes = FileChannel.open(path, READ, NOFOLLOW_LINKS).use { input ->
            val output = ByteArray(size.toInt()); val buffer = ByteBuffer.wrap(output)
            while (buffer.hasRemaining()) if (input.read(buffer) <= 0) fail()
            if (input.read(ByteBuffer.allocate(1)) != -1) fail()
            output
        }
        if (attributes(path, false) != identity) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        val signed = try {
            val canonicalBytes = AgentBridgeCodec.canonicalize(bytes)
            val value = json.decodeFromString<Signed>(canonicalBytes.decodeToString())
            if (!MessageDigest.isEqual(canonical(value), canonicalBytes) || value.record != record(value.record.kind, value.record.day, value.record.payload)) fail()
            val payload = Base64.getDecoder().decode(value.record.payload)
            if (payload.size > PAYLOAD_LIMIT || Base64.getEncoder().encodeToString(payload) != value.record.payload) fail()
            val expected = mac(canonical(value.record))
            if (!MessageDigest.isEqual(expected.toByteArray(), value.mac.toByteArray())) fail()
            value
        } catch (_: Exception) { fail() } // Stored bytes are never a malformed incoming request.
        guard(); return signed.record
    }
    private fun publish(name: String, value: Record, previous: Record? = null) {
        val bytes = canonical(Signed(value, mac(canonical(value))))
        if (bytes.size > 2 * PAYLOAD_LIMIT || storedBytes + bytes.size > JOB_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        val previousBytes = previous?.let { canonical(Signed(it, mac(canonical(it)))) }
        guard()
        if (previousBytes != null) {
            if (!currentBytes(name).contentEquals(previousBytes)) fail()
        } else if (exists(name)) fail(AgentBridgeErrorCode.BUSY)
        val temporary = directory.resolve("pending-" + UUID.randomUUID())
        var identity: Any? = null
        try {
            FileChannel.open(temporary, setOf(CREATE_NEW, WRITE, NOFOLLOW_LINKS), PosixFilePermissions.asFileAttribute(FILE_PERMISSIONS)).use { output ->
                identity = attributes(temporary, false)
                val buffer = ByteBuffer.wrap(bytes)
                while (buffer.hasRemaining()) if (output.write(buffer) <= 0) fail()
                output.force(true)
            }
            if (attributes(temporary, false) != identity) fail(AgentBridgeErrorCode.BINDING_CHANGED)
            guard()
            if (attributes(temporary, false) != identity) fail(AgentBridgeErrorCode.BINDING_CHANGED)
            if (previousBytes != null) {
                if (!currentBytes(name).contentEquals(previousBytes)) fail()
            } else if (exists(name)) fail(AgentBridgeErrorCode.BUSY)
            // Cooperating writers hold the original job lock. Sampled path/inode fences do not
            // claim protection against an arbitrary same-UID writer or privileged rollback.
            Files.move(temporary, directory.resolve(name), ATOMIC_MOVE)
            force(directory)
            if (attributes(directory.resolve(name), false) != identity) fail(AgentBridgeErrorCode.BINDING_CHANGED)
            storedBytes += bytes.size - (previousBytes?.size ?: 0)
            guard()
        } finally {
            if (identity != null) {
                val stillOriginal = runCatching { pins(); attributes(temporary, false) == identity }.getOrDefault(false)
                if (stillOriginal) Files.delete(temporary)
            }
        }
    }
    private fun currentBytes(name: String): ByteArray {
        val path = directory.resolve(name)
        val identity = attributes(path, false)
        if (Files.size(path) !in 1..(2 * PAYLOAD_LIMIT).toLong()) fail()
        val bytes = FileChannel.open(path, READ, NOFOLLOW_LINKS).use { input ->
            val output = ByteArray(Files.size(path).toInt()); val buffer = ByteBuffer.wrap(output)
            while (buffer.hasRemaining()) if (input.read(buffer) <= 0) fail()
            if (input.read(ByteBuffer.allocate(1)) != -1) fail()
            output
        }
        if (attributes(path, false) != identity) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        return bytes
    }
    private fun mkdir(path: Path, exclusive: Boolean) {
        if (present(path)) {
            if (exclusive) fail()
            attributes(path, true)
        } else {
            try { Files.createDirectory(path, PosixFilePermissions.asFileAttribute(DIRECTORY_PERMISSIONS)) }
            catch (error: java.nio.file.FileAlreadyExistsException) { if (exclusive) throw error }
            attributes(path, true); force(path); force(path.parent)
        }
    }
    private fun force(path: Path) { FileChannel.open(path, READ, NOFOLLOW_LINKS).use { it.force(true) } }
    private inline fun <reified T> canonical(value: T): ByteArray = AgentBridgeCodec.canonicalize(json.encodeToString(value).toByteArray())
    private fun mac(bytes: ByteArray): String = Mac.getInstance("HmacSHA256").run {
        init(key); update("HealthMd.AgentBridge.AndroidCaptureSpool.v1\u0000".toByteArray())
        doFinal(bytes).joinToString("") { "%02x".format(it) }
    }
    private inline fun <T> safeCall(operation: () -> T): T = try { operation() } catch (error: Exception) { throw safe(error) }
    private fun safe(error: Exception): Exception = when (error) {
        is CancellationException, is AgentBridgeException -> error
        else -> AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
    }
    private fun fail(code: AgentBridgeErrorCode = AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED): Nothing = throw AgentBridgeException(code)
    companion object {
        private const val PAYLOAD_LIMIT = 64 * 1024
        private const val JOB_LIMIT = 64L * 1024 * 1024
        private val FILE_PERMISSIONS = PosixFilePermissions.fromString("rw-------")
        private val DIRECTORY_PERMISSIONS = PosixFilePermissions.fromString("rwx------")
        private val DAY_NAME = Regex("^(started|day)-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json$")
        private val PENDING_NAME = Regex("^pending-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}

/** Private native capture payload v1. Public HealthData serializers are not journal codecs. */
@Serializable
internal data class AgentBridgeCapturedScalarDay(val version: Int, val day: String,
    val calendarTimezone: String, val values: Map<String, Double>)

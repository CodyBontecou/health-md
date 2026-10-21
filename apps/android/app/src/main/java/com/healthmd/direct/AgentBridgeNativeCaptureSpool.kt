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

/** Private captured values, engine identity and immutable artifacts, never transfer authority.
 * MAC records bind the exact accepted request/resolution, permanent claim and original expiry. */
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
    @Serializable private data class Progress(val version: Int = 2, val captures: List<String>,
        val artifacts: List<String> = emptyList(), val engine: String = "", val publicArtifactIDs: String? = null)
    // Preserve existing v2 bytes. Version3 adds exactly16 UUID bytes per sorted artifact day.
    @Serializable private data class LegacyProgress(val version: Int, val captures: List<String>,
        val artifacts: List<String>, val engine: String)
    class ArtifactCheckpoint(val engine: ByteArray, val payload: ByteArray)

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
                    if (++count > 16450) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
                    val name = path.fileName.toString()
                    if (name !in setOf("lock", "header.json", "progress.json") && !DAY_NAME.matches(name) && !PENDING_NAME.matches(name)) fail()
                    attributes(path, false)
                    val size = Files.size(path)
                    if (size !in 0..RECORD_LIMIT.toLong()) fail()
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
    val acceptedRequestSha256: String get() = reservation.job.requestSha256

    /** An existing successful capture is reused verbatim. A started marker without bytes is
     * ambiguous and never grants a second SDK attempt, including across process restart. */
    @Synchronized fun loadOrBegin(day: String): ByteArray? = safeCall {
        validDay(day)
        guard()
        val started = "started-$day.json"; val captured = "day-$day.json"
        val (previous, state) = progress()
        val days = state.captures
        if (day in days) {
            if (!exists(captured)) fail()
            if (read(started) != record("started", day)) fail()
            val value = read(captured)
            if (value.kind != "captured" || value.day != day || value.payload.isEmpty()) fail()
            val bytes = Base64.getDecoder().decode(value.payload)
            guard(); bytes
        } else {
            if (exists(started) || exists(captured)) fail()
            if (state.publicArtifactIDs != null) fail(AgentBridgeErrorCode.BINDING_CHANGED)
            if (days.size >= 4096) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            if (storedBytes + 2 * PAYLOAD_LIMIT >= JOB_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            val next = progressPayload(state.copy(captures = (days + day).sorted()))
            publish("progress.json", record("progress", null, next), previous)
            publish(started, record("started", day)); null
        }
    }
    @Synchronized fun commit(day: String, payload: ByteArray) = safeCall {
        validDay(day)
        val frozen = payload.copyOf()
        if (frozen.isEmpty() || frozen.size > PAYLOAD_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        guard()
        if (day !in progress().second.captures) fail()
        if (read("started-$day.json") != record("started", day)) fail()
        publish("day-$day.json", record("captured", day, Base64.getEncoder().encodeToString(frozen)))
    }
    @Synchronized fun retainedArtifact(day: String): ArtifactCheckpoint? = safeCall {
        validDay(day); guard()
        val state = progress().second
        if (day !in state.artifacts) null else {
            if (day !in state.captures || state.engine.isEmpty() || read("artifact-started-$day.json") != record("artifact-started", day)) fail()
            val value = read("artifact-$day.json")
            if (value.kind != "artifact" || value.day != day || value.payload.isEmpty()) fail()
            val result = ArtifactCheckpoint(Base64.getDecoder().decode(state.engine), Base64.getDecoder().decode(value.payload))
            guard(); result
        }
    }
    @Synchronized fun beginArtifact(day: String, engine: ByteArray) = safeCall {
        validDay(day); guard()
        val frozen = engine.copyOf()
        if (frozen.isEmpty() || frozen.size > 4096) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        val encoded = Base64.getEncoder().encodeToString(frozen)
        val (previous, state) = progress()
        if (state.engine.isNotEmpty() && state.engine != encoded) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        if (state.publicArtifactIDs != null) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        if (state.artifacts.size >= 4096) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        if (day in state.artifacts || exists("artifact-started-$day.json") || exists("artifact-$day.json")) fail(AgentBridgeErrorCode.BUSY)
        val next = state.copy(artifacts = (state.artifacts + day).sorted(), engine = encoded)
        publish("progress.json", record("progress", null, progressPayload(next)), previous)
        publish("artifact-started-$day.json", record("artifact-started", day))
    }
    @Synchronized fun commitArtifact(day: String, engine: ByteArray, payload: ByteArray) = safeCall {
        validDay(day); guard()
        val frozen = payload.copyOf(); val state = progress().second
        if (state.engine != Base64.getEncoder().encodeToString(engine) || day !in state.artifacts || day !in state.captures ||
            read("artifact-started-$day.json") != record("artifact-started", day)) fail()
        val captured = read("day-$day.json")
        if (captured.kind != "captured" || captured.day != day || captured.payload.isEmpty()) fail()
        if (frozen.isEmpty() || frozen.size > PAYLOAD_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
        publish("artifact-$day.json", record("artifact", day, Base64.getEncoder().encodeToString(frozen)))
    }
    /** Signed progress is the one issuance point. Exact recovery never creates another UUID. */
    @Synchronized fun bindPublicArtifactIDs(approvedDays: List<String>): Map<String, String> = safeCall {
        val approved = approvedDays.toList()
        approved.forEach(::validDay)
        guard()
        val (previous, state) = progress()
        if (approved.isEmpty() || approved.distinct().size != approved.size ||
            approved.sorted() != state.captures || state.captures != state.artifacts) fail()
        validateStoredProgress()
        if (state.publicArtifactIDs == null) {
            val buffer = ByteBuffer.allocate(state.artifacts.size * 16)
            state.artifacts.forEach { _ ->
                val id = UUID.randomUUID()
                buffer.putLong(id.mostSignificantBits); buffer.putLong(id.leastSignificantBits)
            }
            val next = state.copy(version = 3, publicArtifactIDs = Base64.getEncoder().encodeToString(buffer.array()))
            publicIDs(next)
            publish("progress.json", record("progress", null, progressPayload(next)), previous)
        }
        val result = publicIDs(progress().second)
        guard(); result
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
        val (_, state) = progress()
        val days = state.captures
        val expected = mutableSetOf("lock", "header.json", "progress.json")
        for (day in days) {
            val started = "started-$day.json"; val captured = "day-$day.json"
            expected += started; expected += captured
            if (read(started) != record("started", day)) fail()
            val value = read(captured)
            if (value.kind != "captured" || value.day != day || value.payload.isEmpty()) fail()
        }
        for (day in state.artifacts) {
            expected += "artifact-started-$day.json"; expected += "artifact-$day.json"
            if (day !in days || state.engine.isEmpty() || read("artifact-started-$day.json") != record("artifact-started", day)) fail()
            val value = read("artifact-$day.json")
            if (value.kind != "artifact" || value.day != day || value.payload.isEmpty()) fail()
        }
        val names = Files.newDirectoryStream(directory).use { stream ->
            stream.map { it.fileName.toString() }.filter { !PENDING_NAME.matches(it) }.toSet()
        }
        if (names != expected) fail()
    }
    private fun progressPayload(state: Progress): String {
        val bytes = if (state.publicArtifactIDs == null && state.engine.isEmpty() && state.artifacts.isEmpty()) json.encodeToString(state.captures).toByteArray()
            else if (state.publicArtifactIDs == null) AgentBridgeCodec.canonicalize(json.encodeToString(LegacyProgress(state.version, state.captures, state.artifacts, state.engine)).toByteArray())
            else AgentBridgeCodec.canonicalize(json.encodeToString(state).toByteArray())
        return Base64.getEncoder().encodeToString(bytes)
    }
    private fun progress(): Pair<Record, Progress> {
        val value = read("progress.json")
        val bytes = Base64.getDecoder().decode(value.payload)
        val state = if (bytes.firstOrNull() == '['.code.toByte()) Progress(captures = json.decodeFromString<List<String>>(bytes.decodeToString()))
            else json.decodeFromString<Progress>(bytes.decodeToString())
        if (value.kind != "progress" || value.day != null ||
            !((state.version == 2 && state.publicArtifactIDs == null) || (state.version == 3 && state.publicArtifactIDs != null)) ||
            state.engine.length > 5500 || state.artifacts.isEmpty() != state.engine.isEmpty() || progressPayload(state) != value.payload) fail()
        listOf(state.captures, state.artifacts).forEach { days ->
            if (days.size > 4096 || days.distinct().size != days.size || days != days.sorted()) fail()
            days.forEach(::validDay)
        }
        if (state.version == 3) publicIDs(state)
        return value to state
    }
    private fun publicIDs(state: Progress): Map<String, String> {
        if (state.version != 3 || state.publicArtifactIDs == null || state.artifacts.isEmpty() ||
            state.artifacts.size > 4096 || state.captures != state.artifacts) fail()
        val bytes = Base64.getDecoder().decode(state.publicArtifactIDs)
        if (bytes.size != state.artifacts.size * 16 || Base64.getEncoder().encodeToString(bytes) != state.publicArtifactIDs) fail()
        val buffer = ByteBuffer.wrap(bytes)
        val result = linkedMapOf<String, String>()
        state.artifacts.forEach { day ->
            val id = UUID(buffer.long, buffer.long)
            if (id.version() != 4 || id.variant() != 2) fail()
            result[day] = id.toString()
        }
        if (result.values.toSet().size != state.artifacts.size) fail()
        return java.util.Collections.unmodifiableMap(result)
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
        if (size !in 1..RECORD_LIMIT.toLong()) fail()
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
            if (payload.size > (if (value.record.kind == "progress") PROGRESS_LIMIT else PAYLOAD_LIMIT) || Base64.getEncoder().encodeToString(payload) != value.record.payload) fail()
            val expected = mac(canonical(value.record))
            if (!MessageDigest.isEqual(expected.toByteArray(), value.mac.toByteArray())) fail()
            value
        } catch (_: Exception) { fail() } // Stored bytes are never a malformed incoming request.
        guard(); return signed.record
    }
    private fun publish(name: String, value: Record, previous: Record? = null) {
        val bytes = canonical(Signed(value, mac(canonical(value))))
        if (bytes.size > RECORD_LIMIT || storedBytes + bytes.size > JOB_LIMIT) fail(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
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
        if (Files.size(path) !in 1..RECORD_LIMIT.toLong()) fail()
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
        private const val PROGRESS_LIMIT = 256 * 1024
        private const val RECORD_LIMIT = 512 * 1024
        private const val JOB_LIMIT = 64L * 1024 * 1024
        private val FILE_PERMISSIONS = PosixFilePermissions.fromString("rw-------")
        private val DIRECTORY_PERMISSIONS = PosixFilePermissions.fromString("rwx------")
        private val DAY_NAME = Regex("^(artifact-started|artifact|started|day)-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json$")
        private val PENDING_NAME = Regex("^pending-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}

/** Private native capture payload v1. Public HealthData serializers are not journal codecs. */
@Serializable
internal data class AgentBridgeCapturedScalarDay(val version: Int, val day: String,
    val calendarTimezone: String, val values: Map<String, Double>)

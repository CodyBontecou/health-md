package com.healthmd.diagnostics

import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.time.format.DateTimeFormatterBuilder
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.FutureTask
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.serialization.json.*

sealed interface DiagnosticValue {
    data class Text(val value: String) : DiagnosticValue
    data class Integer(val value: Long) : DiagnosticValue
    data class Boolean(val value: kotlin.Boolean) : DiagnosticValue
    fun json(): JsonPrimitive = when (this) {
        is Text -> JsonPrimitive(value)
        is Integer -> JsonPrimitive(value)
        is Boolean -> JsonPrimitive(value)
    }
    companion object {
        fun decode(value: JsonElement): DiagnosticValue? {
            val primitive = value as? JsonPrimitive ?: return null
            if (primitive is JsonNull) return null
            return when {
                primitive.isString -> Text(primitive.content)
                primitive.booleanOrNull != null -> Boolean(primitive.boolean)
                primitive.longOrNull != null -> Integer(primitive.long)
                else -> null
            }
        }
    }
}

enum class DiagnosticVerbosity {
    INFO, DEBUG, TRACE;
    fun includes(severity: String) = when (severity) {
        "trace" -> this == TRACE
        "debug" -> this != INFO
        else -> severity in setOf("info", "warning", "error")
    }
}

data class DiagnosticSettings(val enabled: Boolean = true, val verbosity: DiagnosticVerbosity = DiagnosticVerbosity.DEBUG, val privateContextUntil: Long = 0)

data class DiagnosticEvent(val document: JsonObject) {
    val timestamp get() = document.getValue("timestamp").jsonPrimitive.content
    val eventId get() = document.getValue("event_id").jsonPrimitive.content
    val subsystem get() = document.getValue("subsystem").jsonPrimitive.content
    val severity get() = document.getValue("severity").jsonPrimitive.content
    val fields get() = document.getValue("fields").jsonObject
    val id get() = "${document.getValue("session_id").jsonPrimitive.content.lowercase()}:${document["sequence"]}"

    fun filtered(includePrivate: Boolean): DiagnosticEvent? = runCatching {
        val event = DiagnosticEventID.entries.firstOrNull { it.wire == eventId } ?: return null
        require(document["schema"]?.jsonPrimitive?.content == "healthmd.diagnostic_event")
        require(document["schema_version"]?.jsonPrimitive?.let { !it.isString && it.intOrNull == 1 } == true)
        require(subsystem == event.subsystem && severity == event.severity)
        val session = document.getValue("session_id").jsonPrimitive.content
        require(session.length == 36 && UUID.fromString(session).toString().equals(session, ignoreCase = true))
        require(document.getValue("sequence").jsonPrimitive.let { !it.isString && (it.longOrNull?.let { number -> number in 0..9_007_199_254_740_991L } == true) })
        require(document.getValue("monotonic_ms").jsonPrimitive.let { !it.isString && (it.longOrNull?.let { number -> number in 0..9_007_199_254_740_991L } == true) })
        require(document.getValue("platform").jsonPrimitive.content in setOf("ios", "macos", "android"))
        require(DiagnosticStore.timestamp(Instant.parse(timestamp).toEpochMilli()) == timestamp)
        require(Regex("^[A-Za-z0-9_]+/[A-Za-z0-9_+.-]+\\.(swift|kt):[0-9]+$").matches(document.getValue("source").jsonPrimitive.content))
        val accepted = mutableMapOf<String, JsonElement>()
        val omitted = document["omitted_fields"]?.jsonObject.orEmpty().filter { (key, value) ->
            DiagnosticField.entries.any { it.wire == key } && (value as? JsonPrimitive)?.content in setOf("not_recorded", "redacted", "unavailable", "truncated", "invalid")
        }.toMutableMap()
        fields.forEach { (key, raw) ->
            val field = DiagnosticField.entries.firstOrNull { it.wire == key } ?: return@forEach
            val value = DiagnosticValue.decode(raw)
            when {
                value == null || !field.accepts(value) -> omitted[key] = JsonPrimitive("invalid")
                field.isPrivate && !includePrivate -> omitted[key] = JsonPrimitive("redacted")
                else -> { accepted[key] = raw; omitted.remove(key) }
            }
        }
        // Reconstruct known root keys too: unrecognized free text never travels.
        val safeKeys = setOf("schema", "schema_version", "timestamp", "session_id", "sequence", "monotonic_ms", "platform", "event_id", "subsystem", "severity", "source")
        DiagnosticEvent(JsonObject(document.filterKeys { it in safeKeys } + mapOf("fields" to JsonObject(accepted), "omitted_fields" to JsonObject(omitted))))
    }.getOrNull()
}

data class DiagnosticSnapshot(val events: List<DiagnosticEvent>, val droppedEventCount: Int, val invalidEventCount: Int, val truncated: Boolean)

/** Pure JVM disk seam. No health repository, Android logger, telemetry or HTTP dependency. */
class DiagnosticStore(
    val directory: File,
    private val byteLimit: Long = DEFAULT_BYTE_LIMIT,
    private val clock: () -> Long = System::currentTimeMillis,
) : AutoCloseable {
    private val executor = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(128), { task -> Thread(task, "healthmd-diagnostics").apply { isDaemon = true } })
    private val dropped = AtomicInteger()
    private val sessionId = UUID.randomUUID().toString()
    private val startedAt = System.nanoTime()
    private var sequence = 0L
    private val aliasLock = Any()
    private val aliases = mutableMapOf<String, String>()
    private val activeFiles = mutableMapOf<Boolean, File>()
    private var settingsValue = runCatching {
        val file = File(directory, "settings.json")
        require(file.length() <= 16 * 1024 && !Files.isSymbolicLink(file.toPath()))
        val json = Json.parseToJsonElement(file.readText()).jsonObject
        DiagnosticSettings(
            enabled = json.getValue("enabled").jsonPrimitive.boolean,
            verbosity = DiagnosticVerbosity.valueOf(json.getValue("verbosity").jsonPrimitive.content.uppercase()),
            privateContextUntil = json.getValue("private_context_until_ms").jsonPrimitive.long,
        ).let { if (it.privateContextUntil > clock() + 15 * 60 * 1000) it.copy(privateContextUntil = 0) else it }
    }.getOrDefault(DiagnosticSettings())

    private var privateDeadlineNanos = System.nanoTime() + (settingsValue.privateContextUntil - clock()).coerceIn(0, 15 * 60 * 1000L) * 1_000_000
    @Volatile private var admissionConfiguration = settingsValue to privateDeadlineNanos
    init { require(byteLimit >= 1024); executor.execute { prune() } }
    val settings: DiagnosticSettings get() = control { settingsValue }

    fun configure(enabled: Boolean, verbosity: DiagnosticVerbosity) = control {
        settingsValue = settingsValue.copy(enabled = enabled, verbosity = verbosity, privateContextUntil = if (enabled) settingsValue.privateContextUntil else 0)
        admissionConfiguration = settingsValue to privateDeadlineNanos
        saveSettings()
    }
    fun startPrivateContextRecording() {
        control {
            settingsValue = settingsValue.copy(privateContextUntil = if (settingsValue.enabled) clock() + 15 * 60 * 1000 else 0)
            privateDeadlineNanos = System.nanoTime() + if (settingsValue.enabled) 15 * 60 * 1_000_000_000L else 0
            admissionConfiguration = settingsValue to privateDeadlineNanos
            saveSettings()
        }
        record(DiagnosticEventID.RECORDING_STARTED)
    }
    fun stopPrivateContextRecording() {
        control { settingsValue = settingsValue.copy(privateContextUntil = 0); admissionConfiguration = settingsValue to privateDeadlineNanos; saveSettings() }
        record(DiagnosticEventID.RECORDING_STOPPED)
    }
    fun peerFields(name: String): Map<DiagnosticField, DiagnosticValue> = synchronized(aliasLock) {
        if (name !in aliases && aliases.size < 128) aliases[name] = "peer_${aliases.size + 1}"
        mapOf(DiagnosticField.PEER_ALIAS to DiagnosticValue.Text(aliases[name] ?: "peer_0"), DiagnosticField.PEER_NAME to DiagnosticValue.Text(name))
    }

    fun record(event: DiagnosticEventID, fields: Map<DiagnosticField, DiagnosticValue> = emptyMap(), source: String = "HealthMd/DiagnosticStore.kt:0", unavailable: Set<DiagnosticField> = emptySet()) {
        val configuration = admissionConfiguration
        if (!configuration.first.enabled || !configuration.first.verbosity.includes(event.severity)) return
        val observedAt = clock()
        val observedNanos = System.nanoTime()
        val privateAtAdmission = configuration.first.privateContextUntil > observedAt && observedNanos < configuration.second
        val capturedFields = fields.toMap()
        try {
            executor.execute {
                if (!settingsValue.enabled || !settingsValue.verbosity.includes(event.severity)) return@execute
                runCatching {
                    prepareDirectory()
                    prune()
                    val now = clock()
                    val accepted = mutableMapOf<String, JsonElement>()
                    val omitted: MutableMap<String, JsonElement> = unavailable.associate { it.wire to JsonPrimitive("unavailable") as JsonElement }.toMutableMap()
                    capturedFields.forEach { (field, value) ->
                        when {
                            !field.accepts(value) -> omitted[field.wire] = JsonPrimitive("invalid")
                            field.isPrivate && (!privateAtAdmission || settingsValue.privateContextUntil <= now || System.nanoTime() >= privateDeadlineNanos) -> omitted[field.wire] = JsonPrimitive("not_recorded")
                            else -> { accepted[field.wire] = value.json(); omitted.remove(field.wire) }
                        }
                    }
                    val item = DiagnosticEvent(buildJsonObject {
                        put("schema", "healthmd.diagnostic_event"); put("schema_version", 1)
                        put("timestamp", timestamp(observedAt)); put("session_id", sessionId); put("sequence", ++sequence)
                        put("monotonic_ms", (observedNanos - startedAt).coerceAtLeast(0) / 1_000_000)
                        put("platform", "android"); put("event_id", event.wire)
                        put("subsystem", event.subsystem); put("severity", event.severity); put("source", source)
                        put("fields", JsonObject(accepted)); put("omitted_fields", JsonObject(omitted))
                    })
                    require(item.filtered(true) != null)
                    val bytes = (item.document.toString() + "\n").toByteArray(Charsets.UTF_8)
                    require(bytes.size <= 16 * 1024 && bytes.size <= byteLimit)
                    val isPrivate = accepted.keys.any { key -> DiagnosticField.entries.any { it.wire == key && it.isPrivate } }
                    var target = activeFiles[isPrivate]
                    if (target == null || !target.exists() || target.length() + bytes.size > minOf(1024 * 1024L, byteLimit)) {
                        target = File(directory, "${if (isPrivate) "private" else "operational"}-$now-${UUID.randomUUID()}.jsonl")
                        target.createNewFile(); protect(target)
                        activeFiles[isPrivate] = target
                    }
                    require(target.isFile && !Files.isSymbolicLink(target.toPath()))
                    target.appendBytes(bytes)
                    prune()
                }.onFailure { dropped.incrementAndGet() }
            }
        } catch (_: RejectedExecutionException) { dropped.incrementAndGet() }
    }

    fun snapshot(includePrivate: Boolean = false, since: Long? = null, subsystem: String? = null, operationId: String? = null): DiagnosticSnapshot = control {
        prune()
        val events = mutableListOf<DiagnosticEvent>()
        val seen = mutableSetOf<String>()
        var invalid = 0
        var truncated = false
        segmentFiles().filter(::isRetained).forEach { file ->
            // Each segment is bounded; do not read an unbounded corrupt file.
            if (file.length() > minOf(1024 * 1024L, byteLimit)) { invalid++; return@forEach }
            runCatching {
                file.bufferedReader().useLines { lines -> lines.forEach lineLoop@{ line ->
                    val event = if (line.toByteArray(Charsets.UTF_8).size <= 16 * 1024) runCatching { DiagnosticEvent(Json.parseToJsonElement(line).jsonObject).filtered(includePrivate) }.getOrNull() else null
                    if (event == null) { invalid++; return@lineLoop }
                    if (!seen.add(event.id)) { invalid++; return@lineLoop }
                    if (since != null && Instant.parse(event.timestamp).toEpochMilli() < since) return@lineLoop
                    if (subsystem != null && event.subsystem != subsystem) return@lineLoop
                    if (operationId != null && event.fields["operation_id"]?.jsonPrimitive?.content != operationId) return@lineLoop
                    events.add(event)
                    if (events.size > 10_000) truncated = true
                } }
            }.onFailure { invalid++ }
        }
        DiagnosticSnapshot(events.sortedWith(compareBy({ it.timestamp }, { it.document["session_id"].toString() }, { it.document.getValue("sequence").jsonPrimitive.long })).takeLast(10_000), dropped.get(), invalid, truncated)
    }

    fun clear() = control {
        settingsValue = settingsValue.copy(privateContextUntil = 0)
        admissionConfiguration = settingsValue to privateDeadlineNanos
        activeFiles.clear(); synchronized(aliasLock) { aliases.clear() }
        var cleared = true
        segmentFiles().forEach { if (!it.delete()) cleared = false }
        val bundles = File(directory, "bundles")
        if (!Files.isSymbolicLink(bundles.toPath()) && bundles.exists() && !bundles.deleteRecursively()) cleared = false
        dropped.set(0); saveSettings()
        cleared
    }
    private fun prepareDirectory() {
        require(!Files.isSymbolicLink(directory.toPath()))
        require(directory.isDirectory || directory.mkdirs())
        protect(directory)
    }
    private fun saveSettings() {
        runCatching {
            prepareDirectory()
            val bytes = buildJsonObject {
                put("enabled", settingsValue.enabled); put("verbosity", settingsValue.verbosity.name.lowercase())
                put("private_context_until_ms", settingsValue.privateContextUntil)
            }.toString().toByteArray(Charsets.UTF_8)
            val temp = File(directory, "settings-${UUID.randomUUID()}.tmp")
            try { temp.writeBytes(bytes); protect(temp); Files.move(temp.toPath(), File(directory, "settings.json").toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE) }
            finally { temp.delete() }
        }.onFailure { dropped.incrementAndGet() }
    }
    private fun segmentFiles(): List<File> {
        if (Files.isSymbolicLink(directory.toPath())) return emptyList()
        return directory.listFiles().orEmpty().filter { it.isFile && !Files.isSymbolicLink(it.toPath()) && Regex("^(operational|private)-[0-9]+-[A-Fa-f0-9-]{36}\\.jsonl$").matches(it.name) }.sortedBy(::segmentTime)
    }
    private fun segmentTime(file: File): Long = file.name.split('-')[1].toLongOrNull() ?: 0
    private fun isRetained(file: File): Boolean {
        val age = clock() - segmentTime(file)
        val ttl = if (file.name.startsWith("private-")) PRIVATE_RETENTION_MS else RETENTION_MS
        return age in -60_000 until ttl
    }
    private fun prune() {
        val bundles = File(directory, "bundles")
        if (!Files.isSymbolicLink(bundles.toPath())) DiagnosticBundleBuilder.sweep(bundles)
        val now = clock()
        val keep = segmentFiles().filter { file ->
            val age = now - segmentTime(file)
            val ttl = if (file.name.startsWith("private-")) PRIVATE_RETENTION_MS else RETENTION_MS
            if (age >= ttl || age < -60_000 || file.length() > minOf(1024 * 1024L, byteLimit)) { file.delete(); false } else true
        }
        var total = keep.sumOf(File::length)
        keep.forEach { if (total > byteLimit) { val size = it.length(); it.delete(); total -= size } }
    }
    private fun <T> control(block: () -> T): T {
        val task = FutureTask(block)
        try { executor.execute(task) } catch (_: RejectedExecutionException) { check(!executor.isShutdown); executor.queue.put(task) }
        return task.get()
    }
    override fun close() { executor.shutdown(); executor.awaitTermination(10, TimeUnit.SECONDS) }

    companion object {
        const val DEFAULT_BYTE_LIMIT = 20 * 1024 * 1024L
        const val RETENTION_MS = 7 * 24 * 60 * 60 * 1000L
        const val PRIVATE_RETENTION_MS = 24 * 60 * 60 * 1000L
        fun timestamp(millis: Long): String = DateTimeFormatterBuilder().appendInstant(3).toFormatter().format(Instant.ofEpochMilli(millis))
        fun protect(file: File) {
            // One chmod: temporarily revoking owner traversal races the composer.
            Files.setPosixFilePermissions(file.toPath(), java.nio.file.attribute.PosixFilePermissions.fromString(if (file.isDirectory) "rwx------" else "rw-------"))
        }
    }
}

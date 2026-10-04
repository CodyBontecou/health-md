package com.healthmd.data.export

import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.rawexport.RawExportResult
import com.healthmd.rawexport.RawSnapshotRequest
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Exact no-backup raw artifacts. No credentials, provider cursors, or fresh capture on ambiguity. */
internal class ScheduledRawAPIExportStore(private val root: File) {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }

    @Serializable
    data class Operation(
        val version: Int = 1,
        val operationId: String,
        val authorityJson: String,
        val settingsSnapshotJson: String?,
        val ownerEpochDays: List<Long>,
        val request: RawSnapshotRequest,
        val providerIds: List<String>,
        val slots: List<Slot> = providerIds.map { Slot() },
    )

    @Serializable
    data class Slot(val captureStarted: Boolean = false, val result: RawExportResult? = null, val acknowledged: Boolean = false)

    suspend fun open(expected: Operation, requireExisting: Boolean): Operation = transaction {
        require(expected.operationId.matches(Regex("[A-Za-z0-9._-]{1,128}")))
        require(APIRecoveryAuthorities.isValid(expected.authorityJson))
        require(expected.providerIds.size in 1..32 && expected.providerIds == expected.providerIds.distinct().sorted())
        require(expected.ownerEpochDays.isNotEmpty() && expected.ownerEpochDays == expected.ownerEpochDays.distinct().sorted())
        val stored = load(expected.operationId)
        if (stored != null) {
            require(stored.copy(slots = expected.slots) == expected) { "Raw API recovery binding changed." }
            stored
        } else {
            check(!requireExisting) { "Raw API recovery artifact is unavailable." }
            check(root.mkdirs() || root.isDirectory)
            check(root.listFiles().orEmpty().count { it.isDirectory } < MAX_OPERATIONS)
            check(directory(expected.operationId).mkdir())
            save(expected)
            expected
        }
    }

    suspend fun markCaptureStarted(operation: Operation, index: Int): Operation = transaction {
        val slot = operation.slots[index]
        check(!slot.captureStarted && slot.result == null) { "Raw API capture cannot be repeated." }
        replace(operation, index, slot.copy(captureStarted = true))
    }

    suspend fun prepare(operation: Operation, index: Int, result: RawExportResult): Operation = transaction {
        check(operation.slots[index].captureStarted && operation.slots[index].result == null)
        val source = File(result.finalLocation)
        require(result.bytesWritten in 0..MAX_TOTAL_BYTES && source.length() == result.bytesWritten)
        check(retainedBytes() + result.bytesWritten <= MAX_TOTAL_BYTES) { "Raw API journal budget exhausted." }
        val target = File(directory(operation.operationId), artifactName(index))
        check(!target.exists())
        val partial = File(target.parentFile, "${target.name}.partial")
        val digest = MessageDigest.getInstance("SHA-256")
        var count = 0L
        try {
            source.inputStream().use { input ->
                FileOutputStream(partial).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        coroutineContext.ensureActive()
                        val read = input.read(buffer)
                        if (read < 0) break
                        count += read
                        check(count <= result.bytesWritten)
                        output.write(buffer, 0, read)
                        digest.update(buffer, 0, read)
                    }
                    output.flush(); output.fd.sync()
                }
            }
            require(count == result.bytesWritten && digest.digest().hex() == result.artifactChecksumSha256)
            move(partial, target)
            replace(operation, index, Slot(true, result.copy(finalLocation = artifactName(index))))
        } finally {
            partial.delete()
        }
    }

    suspend fun artifact(operation: Operation, index: Int): File = transaction {
        val result = requireNotNull(operation.slots[index].result) { "Raw API artifact is unavailable; restart required." }
        require(result.finalLocation == artifactName(index))
        val file = File(directory(operation.operationId), artifactName(index))
        require(file.isFile && file.length() == result.bytesWritten)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                coroutineContext.ensureActive()
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        require(digest.digest().hex() == result.artifactChecksumSha256)
        file
    }

    suspend fun acknowledge(operation: Operation, index: Int): Operation = transaction {
        check(operation.slots[index].result != null)
        replace(operation, index, operation.slots[index].copy(acknowledged = true))
    }

    /** Only a successfully reconciled operation may be purged automatically. */
    suspend fun discardCompleted(operationId: String) = transaction {
        val operation = load(operationId) ?: return@transaction
        if (operation.slots.all { it.acknowledged }) check(directory(operationId).deleteRecursively())
    }

    private suspend fun <T> transaction(action: suspend CoroutineScope.() -> T): T =
        withContext(Dispatchers.IO) { mutex.withLock { action() } }

    private fun replace(operation: Operation, index: Int, slot: Slot): Operation {
        require(load(operation.operationId) == operation) { "Raw API journal frontier changed." }
        return operation.copy(slots = operation.slots.toMutableList().apply { set(index, slot) }).also(::save)
    }

    private fun load(operationId: String): Operation? {
        val directory = directory(operationId)
        if (!directory.exists()) return null
        val file = File(directory, "journal.json")
        require(file.isFile && file.length() in 1..MAX_METADATA_BYTES)
        val result = json.decodeFromString<Operation>(file.readText())
        require(result.version == 1 && result.operationId == operationId && result.slots.size == result.providerIds.size)
        return result
    }

    private fun save(operation: Operation) {
        val bytes = json.encodeToString(operation).encodeToByteArray()
        require(bytes.size <= MAX_METADATA_BYTES)
        val directory = directory(operation.operationId)
        val temporary = File(directory, "journal.tmp")
        FileOutputStream(temporary).use { it.write(bytes); it.flush(); it.fd.sync() }
        move(temporary, File(directory, "journal.json"))
        runCatching { java.nio.channels.FileChannel.open(directory.toPath(), java.nio.file.StandardOpenOption.READ).use { it.force(true) } }
    }

    private fun retainedBytes(): Long = root.walkTopDown().filter { it.isFile && it.name.endsWith(".bin") }.sumOf { it.length() }
    private fun directory(operationId: String): File = File(root, sha256Hex(operationId.encodeToByteArray()))
    private fun artifactName(index: Int): String = "artifact-$index.bin"
    private fun move(source: File, target: File) {
        Files.move(source.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }
    private fun ByteArray.hex(): String = joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') }
    private companion object {
        val mutex = Mutex()
        const val MAX_METADATA_BYTES = 1_048_576L
        const val MAX_TOTAL_BYTES = 536_870_912L
        const val MAX_OPERATIONS = 64
    }
}

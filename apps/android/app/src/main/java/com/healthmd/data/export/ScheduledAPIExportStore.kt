package com.healthmd.data.export

import android.content.Context
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.FailedDateDetail
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Exact immutable API body plus its contiguous owner-date scope. */
internal class DurableAPIExportBatch(
    val index: Int,
    val relativePath: String,
    ownerDates: List<LocalDate>,
    bytes: ByteArray,
) {
    val ownerDates: List<LocalDate> = ownerDates.toList()
    private val storedBytes = bytes.copyOf()
    val bytes: ByteArray get() = storedBytes.copyOf()
    val byteCount: Int = storedBytes.size
    val sha256: String = sha256Hex(storedBytes)

    internal fun contentEquals(other: DurableAPIExportBatch): Boolean =
        index == other.index && relativePath == other.relativePath &&
            ownerDates == other.ownerDates && storedBytes.contentEquals(other.storedBytes)
}

/** Durable pre-POST operation. Body bytes can contain PHI and are never included in diagnostics. */
internal data class DurableAPIExportOperation(
    val operationId: String,
    val destinationFingerprint: String,
    val mode: ExportEngineMode,
    val enginePinJson: String?,
    val settingsSnapshotJson: String?,
    val requestedDates: List<LocalDate>,
    val recordDates: Set<LocalDate>,
    val captureFailures: List<FailedDateDetail>,
    val batches: List<DurableAPIExportBatch>,
    val acknowledgedBatchCount: Int = 0,
) {
    init {
        require(operationId.matches(OPERATION_ID_PATTERN))
        require(destinationFingerprint.matches(SHA256_PATTERN))
        require(requestedDates.isNotEmpty() && requestedDates == requestedDates.distinct().sorted())
        require(recordDates.intersect(captureFailures.mapTo(hashSetOf()) { it.date }).isEmpty())
        require(recordDates + captureFailures.map { it.date }.toSet() == requestedDates.toSet())
        require(batches.isNotEmpty() && batches.size <= MAX_BATCH_COUNT)
        require(batches.map { it.index } == batches.indices.toList())
        require(batches.sumOf { it.byteCount.toLong() } <= MAX_TOTAL_BODY_BYTES)
        require(batches.flatMap { it.ownerDates } == requestedDates)
        require(acknowledgedBatchCount in 0..batches.size)
    }

    internal fun immutableContentEquals(other: DurableAPIExportOperation): Boolean =
        operationId == other.operationId &&
            destinationFingerprint == other.destinationFingerprint &&
            mode == other.mode && enginePinJson == other.enginePinJson &&
            settingsSnapshotJson == other.settingsSnapshotJson &&
            requestedDates == other.requestedDates && recordDates == other.recordDates &&
            captureFailures == other.captureFailures && batches.size == other.batches.size &&
            batches.zip(other.batches).all { (a, b) -> a.contentEquals(b) }

    companion object {
        private val OPERATION_ID_PATTERN = Regex("[A-Za-z0-9._-]{1,128}")
        private val SHA256_PATTERN = Regex("[0-9a-f]{64}")
        private const val MAX_BATCH_COUNT = 4_096
        private const val MAX_TOTAL_BODY_BYTES = 33_554_432L
    }
}

internal interface APIExportOperationStore {
    suspend fun load(operationId: String): DurableAPIExportOperation?
    suspend fun create(operation: DurableAPIExportOperation)
    suspend fun acknowledge(operationId: String, expectedFrontier: Int)
    suspend fun delete(operationId: String)
}

/**
 * App-private, no-backup journal. Bodies are written and fsynced before metadata becomes visible;
 * frontier replacement is atomic. Unknown/corrupt state fails closed and is never logged.
 */
@Singleton
internal class FileAPIExportOperationStore @Inject constructor(
    @ApplicationContext context: Context,
) : APIExportOperationStore {
    private val root = File(context.noBackupFilesDir, "scheduled-api-export-v1")
    private val lock = Any()
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO
    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
    }

    override suspend fun load(operationId: String): DurableAPIExportOperation? =
        withContext(ioDispatcher) { synchronized(lock) { loadLocked(operationId) } }

    override suspend fun create(operation: DurableAPIExportOperation) = withContext(ioDispatcher) {
        synchronized(lock) {
            val existing = loadLocked(operation.operationId)
            if (existing != null) {
                require(existing.immutableContentEquals(operation)) {
                    "Durable API export operation conflicts with existing state."
                }
                return@synchronized
            }
            check(root.mkdirs() || root.isDirectory)
            val target = operationDirectory(operation.operationId)
            val temporary = File(root, ".${target.name}.${System.nanoTime()}.tmp")
            check(temporary.mkdirs())
            try {
                operation.batches.forEach { batch ->
                    durableWrite(File(temporary, bodyName(batch.index)), batch.bytes)
                }
                durableWrite(
                    File(temporary, METADATA_FILE),
                    json.encodeToString(operation.toMetadata()).encodeToByteArray(),
                )
                check(!target.exists())
                moveAtomically(temporary, target)
                syncDirectory(root)
            } catch (error: Throwable) {
                temporary.deleteRecursively()
                throw error
            }
        }
    }

    override suspend fun acknowledge(operationId: String, expectedFrontier: Int) =
        withContext(ioDispatcher) {
            synchronized(lock) {
                val operation = requireNotNull(loadLocked(operationId)) {
                    "Durable API export operation is unavailable."
                }
                require(operation.acknowledgedBatchCount == expectedFrontier)
                require(expectedFrontier < operation.batches.size)
                val metadata = operation.toMetadata().copy(
                    acknowledgedBatchCount = expectedFrontier + 1,
                )
                val directory = operationDirectory(operationId)
                durableReplace(
                    File(directory, METADATA_FILE),
                    json.encodeToString(metadata).encodeToByteArray(),
                )
            }
        }

    override suspend fun delete(operationId: String) = withContext(ioDispatcher) {
        synchronized(lock) {
            val directory = operationDirectory(operationId)
            if (directory.exists()) check(directory.deleteRecursively())
        }
    }

    private fun loadLocked(operationId: String): DurableAPIExportOperation? {
        require(operationId.matches(OPERATION_ID_PATTERN))
        val directory = operationDirectory(operationId)
        if (!directory.exists()) return null
        require(directory.isDirectory)
        val metadataBytes = File(directory, METADATA_FILE).readBytes()
        require(metadataBytes.size <= MAX_METADATA_BYTES)
        val metadataText = metadataBytes.decodeToString()
        require(metadataText.encodeToByteArray().contentEquals(metadataBytes))
        val metadata = json.decodeFromString<OperationMetadata>(metadataText)
        require(metadata.schema == SCHEMA && metadata.version == VERSION)
        require(metadata.operationId == operationId)
        require(metadata.batches.size in 1..MAX_BATCH_COUNT)
        require(metadata.batches.sumOf { it.byteCount.toLong() } <= MAX_TOTAL_BODY_BYTES)
        val batches = metadata.batches.map { stored ->
            require(stored.byteCount in 0..MAX_BODY_BYTES)
            val bodyFile = File(directory, bodyName(stored.index))
            require(bodyFile.length() == stored.byteCount.toLong())
            val bytes = bodyFile.readBytes()
            require(bytes.size == stored.byteCount && sha256Hex(bytes) == stored.sha256)
            DurableAPIExportBatch(
                index = stored.index,
                relativePath = stored.relativePath,
                ownerDates = stored.ownerDates.map(LocalDate::parse),
                bytes = bytes,
            )
        }
        val mode = ExportEngineMode.entries.singleOrNull { it.name == metadata.mode }
            ?: error("Durable API export mode is invalid.")
        return DurableAPIExportOperation(
            operationId = metadata.operationId,
            destinationFingerprint = metadata.destinationFingerprint,
            mode = mode,
            enginePinJson = metadata.enginePinJson,
            settingsSnapshotJson = metadata.settingsSnapshotJson,
            requestedDates = metadata.requestedDates.map(LocalDate::parse),
            recordDates = metadata.recordDates.mapTo(linkedSetOf(), LocalDate::parse),
            captureFailures = metadata.captureFailures.map {
                FailedDateDetail(
                    date = LocalDate.parse(it.date),
                    reason = ExportFailureReason.valueOf(it.reason),
                    errorDetails = it.errorDetails,
                )
            },
            batches = batches,
            acknowledgedBatchCount = metadata.acknowledgedBatchCount,
        )
    }

    private fun DurableAPIExportOperation.toMetadata(): OperationMetadata = OperationMetadata(
        operationId = operationId,
        destinationFingerprint = destinationFingerprint,
        mode = mode.name,
        enginePinJson = enginePinJson,
        settingsSnapshotJson = settingsSnapshotJson,
        requestedDates = requestedDates.map(LocalDate::toString),
        recordDates = recordDates.sorted().map(LocalDate::toString),
        captureFailures = captureFailures.map {
            StoredFailure(it.date.toString(), it.reason.name, it.errorDetails)
        },
        batches = batches.map {
            StoredBatch(
                index = it.index,
                relativePath = it.relativePath,
                ownerDates = it.ownerDates.map(LocalDate::toString),
                byteCount = it.byteCount,
                sha256 = it.sha256,
            )
        },
        acknowledgedBatchCount = acknowledgedBatchCount,
    )

    private fun operationDirectory(operationId: String): File =
        File(root, sha256Hex(operationId.encodeToByteArray()))

    private fun durableWrite(file: File, bytes: ByteArray) {
        FileOutputStream(file).use { stream ->
            stream.write(bytes)
            stream.flush()
            stream.fd.sync()
        }
    }

    private fun durableReplace(file: File, bytes: ByteArray) {
        val temporary = File(file.parentFile, ".${file.name}.${System.nanoTime()}.tmp")
        durableWrite(temporary, bytes)
        moveAtomically(temporary, file)
        syncDirectory(requireNotNull(file.parentFile))
    }

    private fun moveAtomically(source: File, target: File) {
        try {
            Files.move(
                source.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
                StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
            Files.move(source.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun syncDirectory(directory: File) {
        runCatching { FileOutputStream(directory).use { it.fd.sync() } }
    }

    @Serializable
    private data class OperationMetadata(
        val schema: String = SCHEMA,
        val version: Int = VERSION,
        val operationId: String,
        val destinationFingerprint: String,
        val mode: String,
        val enginePinJson: String? = null,
        val settingsSnapshotJson: String? = null,
        val requestedDates: List<String>,
        val recordDates: List<String>,
        val captureFailures: List<StoredFailure>,
        val batches: List<StoredBatch>,
        val acknowledgedBatchCount: Int,
    )

    @Serializable
    private data class StoredFailure(
        val date: String,
        val reason: String,
        val errorDetails: String? = null,
    )

    @Serializable
    private data class StoredBatch(
        val index: Int,
        val relativePath: String,
        val ownerDates: List<String>,
        val byteCount: Int,
        val sha256: String,
    )

    private companion object {
        const val SCHEMA = "healthmd.android_scheduled_api_export"
        const val VERSION = 1
        const val METADATA_FILE = "journal.json"
        const val MAX_METADATA_BYTES = 1_048_576
        const val MAX_BODY_BYTES = 33_554_432
        const val MAX_TOTAL_BODY_BYTES = 33_554_432L
        const val MAX_BATCH_COUNT = 4_096
        val OPERATION_ID_PATTERN = Regex("[A-Za-z0-9._-]{1,128}")
        fun bodyName(index: Int): String = "body-${index.toString().padStart(4, '0')}.bin"
    }
}

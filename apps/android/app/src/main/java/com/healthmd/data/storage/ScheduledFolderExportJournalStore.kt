package com.healthmd.data.storage

import android.content.Context
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.domain.model.ExportFailureReason
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.text.Normalizer
import java.util.Base64
import java.util.Locale
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
internal enum class ScheduledFolderJournalPhase { CAPTURING, READY }

@Serializable
internal enum class ScheduledFolderArtifactState {
    PREPARED,
    BINDING,
    STAGING_BOUND,
    STAGING_WRITTEN,
    BOUND,
    ACKNOWLEDGED,
}

@Serializable
internal data class ScheduledFolderJournalArtifact(
    val artifactId: String,
    val relativePath: String,
    val stagingRelativePath: String,
    val mediaType: String,
    val writeMode: String = "overwrite",
    val byteCount: Int,
    val sha256: String,
    val contentBase64: String,
    val state: ScheduledFolderArtifactState = ScheduledFolderArtifactState.PREPARED,
    val documentId: String? = null,
)

@Serializable
internal data class ScheduledFolderJournalDay(
    val ownerDate: String,
    val artifacts: List<ScheduledFolderJournalArtifact>,
)

@Serializable
internal data class ScheduledFolderJournalFailure(
    val ownerDate: String,
    val reason: String,
)

@Serializable
internal data class ScheduledFolderExportJournal(
    val schema: String = SCHEMA,
    val version: Int = VERSION,
    val operationId: String,
    val folderUri: String,
    val settingsSnapshotSha256: String,
    val enginePinJson: String,
    val ownerDates: List<String>,
    val phase: ScheduledFolderJournalPhase,
    val planSha256: String? = null,
    val days: List<ScheduledFolderJournalDay> = emptyList(),
    val captureFailures: List<ScheduledFolderJournalFailure> = emptyList(),
) {
    companion object {
        const val SCHEMA = "healthmd.android.scheduled_folder_export"
        const val VERSION = 1
    }
}

internal sealed interface ScheduledFolderJournalLoad {
    data object Missing : ScheduledFolderJournalLoad
    data object Corrupt : ScheduledFolderJournalLoad
    data class Found(val journal: ScheduledFolderExportJournal) : ScheduledFolderJournalLoad
}

@Singleton
class ScheduledFolderExportJournalStore private constructor(
    private val directory: File,
    private val directorySync: (File) -> Boolean,
) {
    @Inject
    constructor(@ApplicationContext context: Context) : this(
        File(context.noBackupFilesDir, DIRECTORY_NAME),
        ::syncDirectoryOnAndroid,
    )

    internal constructor(directory: File, @Suppress("UNUSED_PARAMETER") testOnly: Unit = Unit) :
        this(directory, { true })

    private val mutex = Mutex()
    private val json = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
        isLenient = false
    }

    internal suspend fun load(operationId: String): ScheduledFolderJournalLoad =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (!validOperationId(operationId)) return@withLock ScheduledFolderJournalLoad.Corrupt
                purgeTemporaryFiles()
                val file = fileFor(operationId)
                if (!file.exists()) return@withLock ScheduledFolderJournalLoad.Missing
                if (!file.isFile || file.length() !in 1..MAX_JOURNAL_FILE_BYTES) {
                    return@withLock ScheduledFolderJournalLoad.Corrupt
                }
                val journal = runCatching {
                    json.decodeFromString<ScheduledFolderExportJournal>(file.readText())
                }.getOrNull() ?: return@withLock ScheduledFolderJournalLoad.Corrupt
                if (!isStructurallyValid(journal) || journal.operationId != operationId) {
                    ScheduledFolderJournalLoad.Corrupt
                } else {
                    ScheduledFolderJournalLoad.Found(journal)
                }
            }
        }

    internal suspend fun save(journal: ScheduledFolderExportJournal): Boolean =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                if (!isStructurallyValid(journal)) return@withLock false
                if (!directory.exists() && !directory.mkdirs()) return@withLock false
                purgeTemporaryFiles()
                val target = fileFor(journal.operationId)
                val temporary = File(directory, ".${target.name}.${System.nanoTime()}.tmp")
                try {
                    val encodedBytes = json.encodeToString(journal)
                        .toByteArray(StandardCharsets.UTF_8)
                    check(encodedBytes.size <= MAX_JOURNAL_FILE_BYTES)
                    FileOutputStream(temporary).use { output ->
                        output.write(encodedBytes)
                        output.flush()
                        output.fd.sync()
                    }
                    try {
                        Files.move(
                            temporary.toPath(),
                            target.toPath(),
                            StandardCopyOption.ATOMIC_MOVE,
                            StandardCopyOption.REPLACE_EXISTING,
                        )
                    } catch (_: java.nio.file.AtomicMoveNotSupportedException) {
                        Files.move(
                            temporary.toPath(),
                            target.toPath(),
                            StandardCopyOption.REPLACE_EXISTING,
                        )
                    }
                    check(directorySync(directory))
                    true
                } catch (_: Exception) {
                    false
                } finally {
                    if (temporary.exists()) temporary.delete()
                }
            }
        }

    internal suspend fun discard(operationId: String) = withContext(Dispatchers.IO) {
        mutex.withLock {
            if (validOperationId(operationId)) runCatching { fileFor(operationId).delete() }
        }
    }

    internal fun isStructurallyValid(journal: ScheduledFolderExportJournal): Boolean {
        if (journal.schema != ScheduledFolderExportJournal.SCHEMA ||
            journal.version != ScheduledFolderExportJournal.VERSION ||
            !validOperationId(journal.operationId) ||
            journal.folderUri.isBlank() || journal.folderUri.length > MAX_FOLDER_URI_LENGTH ||
            !journal.settingsSnapshotSha256.isSha256()
        ) return false

        val pin = ExportEnginePinCodec.decodeOrNull(journal.enginePinJson) ?: return false
        if (pin.engine == ExportEngineMode.legacy || !ExportEnginePinCodec.isStructurallyValid(pin)) {
            return false
        }

        if (journal.ownerDates.isEmpty() || journal.ownerDates.size > MAX_OWNER_DATES ||
            journal.ownerDates != journal.ownerDates.distinct().sorted() ||
            journal.ownerDates.any { !isCanonicalDate(it) }
        ) return false

        if (journal.phase == ScheduledFolderJournalPhase.CAPTURING) {
            return journal.planSha256 == null &&
                journal.days.isEmpty() && journal.captureFailures.isEmpty()
        }
        if (journal.planSha256?.isSha256() != true ||
            scheduledFolderImmutablePlanSha256(journal) != journal.planSha256
        ) return false

        val dayDates = journal.days.map { it.ownerDate }
        val failureDates = journal.captureFailures.map { it.ownerDate }
        if (dayDates != dayDates.distinct().sorted() ||
            failureDates != failureDates.distinct().sorted() ||
            dayDates.any { it !in journal.ownerDates } ||
            failureDates.any { it !in journal.ownerDates } ||
            dayDates.toSet().intersect(failureDates.toSet()).isNotEmpty() ||
            (dayDates + failureDates).toSet() != journal.ownerDates.toSet()
        ) return false

        if (journal.captureFailures.any { failure ->
                runCatching { ExportFailureReason.valueOf(failure.reason) }.isFailure
            }
        ) return false

        val artifacts = journal.days.flatMap { day ->
            if (!isCanonicalDate(day.ownerDate) || day.artifacts.isEmpty() ||
                day.artifacts.size > MAX_ARTIFACTS_PER_DAY
            ) return false
            day.artifacts
        }
        if (artifacts.size > MAX_ARTIFACTS) return false
        if (artifacts.map { it.artifactId }.distinct().size != artifacts.size) return false
        val allPathKeys = artifacts.flatMap { artifact ->
            listOf(
                collisionKey(artifact.relativePath),
                collisionKey(artifact.stagingRelativePath),
            )
        }
        if (allPathKeys.distinct().size != allPathKeys.size) return false

        var totalBytes = 0L
        for (artifact in artifacts) {
            if (!artifact.artifactId.matches(OPAQUE_ID) ||
                !validRelativePath(artifact.relativePath) ||
                !validRelativePath(artifact.stagingRelativePath) ||
                artifact.relativePath == artifact.stagingRelativePath ||
                !artifact.mediaType.matches(MEDIA_TYPE) ||
                artifact.writeMode != "overwrite" ||
                artifact.byteCount !in 0..MAX_ARTIFACT_BYTES ||
                !artifact.sha256.isSha256() ||
                artifact.documentId?.let { it.isBlank() || it.length > MAX_DOCUMENT_ID_LENGTH || it.hasControl() } == true ||
                (artifact.state == ScheduledFolderArtifactState.PREPARED && artifact.documentId != null) ||
                (artifact.state in setOf(
                    ScheduledFolderArtifactState.STAGING_BOUND,
                    ScheduledFolderArtifactState.STAGING_WRITTEN,
                    ScheduledFolderArtifactState.BOUND,
                    ScheduledFolderArtifactState.ACKNOWLEDGED,
                ) && artifact.documentId == null)
            ) return false
            val bytes = runCatching { Base64.getDecoder().decode(artifact.contentBase64) }.getOrNull()
                ?: return false
            if (bytes.size != artifact.byteCount ||
                Base64.getEncoder().encodeToString(bytes) != artifact.contentBase64 ||
                sha256Hex(bytes) != artifact.sha256
            ) return false
            totalBytes += bytes.size
            if (totalBytes > MAX_TOTAL_ARTIFACT_BYTES) return false
        }
        return true
    }

    private fun purgeTemporaryFiles() {
        directory.listFiles { file -> file.name.startsWith('.') && file.name.endsWith(".tmp") }
            ?.take(MAX_TEMP_FILES_TO_PURGE)
            ?.forEach { file -> runCatching { file.delete() } }
    }

    private fun fileFor(operationId: String): File =
        File(directory, "${sha256Hex(operationId.toByteArray(StandardCharsets.UTF_8))}.json")

    private fun validOperationId(value: String): Boolean = value.matches(OPERATION_ID)

    private fun isCanonicalDate(value: String): Boolean =
        value.matches(DATE) && runCatching { java.time.LocalDate.parse(value).toString() == value }.getOrDefault(false)

    private fun validRelativePath(value: String): Boolean {
        if (value.isBlank() || value.length > MAX_PATH_LENGTH || value.startsWith('/') || '\\' in value || value.hasControl()) {
            return false
        }
        return value.split('/').all { it.isNotBlank() && it != "." && it != ".." }
    }

    private fun collisionKey(value: String): String =
        Normalizer.normalize(value, Normalizer.Form.NFC).lowercase(Locale.ROOT)

    private fun String.isSha256(): Boolean = matches(SHA256)
    private fun String.hasControl(): Boolean = any(Char::isISOControl)

    companion object {
        private const val DIRECTORY_NAME = "scheduled-folder-export-v1"
        private const val MAX_JOURNAL_FILE_BYTES = 48_000_000
        private const val MAX_TEMP_FILES_TO_PURGE = 64
        private const val MAX_FOLDER_URI_LENGTH = 8_192
        private const val MAX_DOCUMENT_ID_LENGTH = 8_192
        private const val MAX_PATH_LENGTH = 1_024
        private const val MAX_OWNER_DATES = 4_096
        private const val MAX_ARTIFACTS_PER_DAY = 4
        private const val MAX_ARTIFACTS = MAX_OWNER_DATES * MAX_ARTIFACTS_PER_DAY
        private const val MAX_ARTIFACT_BYTES = 8_388_608
        private const val MAX_TOTAL_ARTIFACT_BYTES = 33_554_432L
        private val OPERATION_ID = Regex("[A-Za-z0-9._-]{1,128}")
        private val OPAQUE_ID = Regex("[A-Za-z0-9._:-]{1,256}")
        private val MEDIA_TYPE = Regex("[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+(?:; charset=utf-8)?")
        private val SHA256 = Regex("[0-9a-f]{64}")
        private val DATE = Regex("\\d{4}-\\d{2}-\\d{2}")

        private fun syncDirectoryOnAndroid(directory: File): Boolean = try {
            val descriptor = android.system.Os.open(
                directory.absolutePath,
                android.system.OsConstants.O_RDONLY,
                0,
            )
            try {
                android.system.Os.fsync(descriptor)
            } finally {
                android.system.Os.close(descriptor)
            }
            true
        } catch (_: Exception) {
            false
        }
    }
}

internal fun scheduledFolderImmutablePlanSha256(
    journal: ScheduledFolderExportJournal,
): String {
    val digest = MessageDigest.getInstance("SHA-256")
    fun add(value: String) {
        val bytes = value.toByteArray(StandardCharsets.UTF_8)
        digest.update(
            byteArrayOf(
                (bytes.size ushr 24).toByte(),
                (bytes.size ushr 16).toByte(),
                (bytes.size ushr 8).toByte(),
                bytes.size.toByte(),
            ),
        )
        digest.update(bytes)
    }
    add(journal.schema)
    add(journal.version.toString())
    add(journal.operationId)
    add(journal.folderUri)
    add(journal.settingsSnapshotSha256)
    add(journal.enginePinJson)
    journal.ownerDates.forEach(::add)
    journal.days.forEach { day ->
        add(day.ownerDate)
        day.artifacts.forEach { artifact ->
            add(artifact.artifactId)
            add(artifact.relativePath)
            add(artifact.stagingRelativePath)
            add(artifact.mediaType)
            add(artifact.writeMode)
            add(artifact.byteCount.toString())
            add(artifact.sha256)
        }
    }
    journal.captureFailures.forEach { failure ->
        add(failure.ownerDate)
        add(failure.reason)
    }
    return digest.digest().joinToString("") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }
}

internal fun sha256Hex(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
    .digest(bytes)
    .joinToString("") { byte -> (byte.toInt() and 0xff).toString(16).padStart(2, '0') }

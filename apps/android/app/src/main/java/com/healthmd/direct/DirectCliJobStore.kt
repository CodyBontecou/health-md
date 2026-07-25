package com.healthmd.direct

import com.healthmd.direct.protocol.PreparedTransfer
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Singleton
class DirectCliJobStore @Inject constructor(
    trustStore: DirectCliTrustStore,
) {
    private val root = File(trustStore.rootDirectory(), "jobs").apply {
        check(mkdirs() || isDirectory) { "Unable to create Direct CLI job storage." }
    }
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }

    @Synchronized
    fun load(jobId: String, requestFingerprint: String): DirectJobJournal? {
        sweepExpired()
        val directory = jobDirectory(jobId)
        val file = File(directory, JOURNAL_NAME)
        if (!file.isFile) {
            require(directory.listFiles().isNullOrEmpty()) {
                "The durable Direct CLI spool is incomplete."
            }
            return null
        }
        val journal = runCatching { json.decodeFromString<DirectJobJournal>(file.readText()) }
            .getOrElse { throw IllegalArgumentException("The durable Direct CLI journal is corrupt.", it) }
        require(journal.requestFingerprint == requestFingerprint) {
            "The durable Direct CLI request changed."
        }
        require(Instant.parse(journal.expiresAt).isAfter(Instant.now())) {
            "The durable Direct CLI job expired."
        }
        require(journal.transfer.artifactPaths.values.all { File(it).isFile }) {
            "A resumable Direct CLI artifact is missing."
        }
        return journal
    }

    @Synchronized
    fun beginPreparation(jobId: String, requestFingerprint: String, expiresAt: String) {
        val directory = jobDirectory(jobId).apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
        }
        val pending = File(directory, PENDING_NAME)
        if (pending.isFile) {
            val saved = json.decodeFromString<PendingJob>(pending.readText())
            require(saved.requestFingerprint == requestFingerprint) {
                "The pending Direct CLI request changed."
            }
            throw IllegalStateException("A prior Direct CLI preparation did not finish.")
        }
        atomicWrite(
            pending,
            json.encodeToString(PendingJob(requestFingerprint, expiresAt)).toByteArray(),
        )
    }

    @Synchronized
    fun hasIncompletePreparation(jobId: String, requestFingerprint: String): Boolean {
        sweepExpired()
        val pending = File(jobDirectory(jobId), PENDING_NAME)
        if (!pending.isFile) return false
        val saved = runCatching { json.decodeFromString<PendingJob>(pending.readText()) }
            .getOrElse { return true }
        require(saved.requestFingerprint == requestFingerprint) {
            "The pending Direct CLI request changed."
        }
        return true
    }

    @Synchronized
    fun save(journal: DirectJobJournal) {
        require(UUID.fromString(journal.transfer.accepted.jobId).toString() == journal.transfer.accepted.jobId)
        val directory = jobDirectory(journal.transfer.accepted.jobId).apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
        }
        atomicWrite(File(directory, JOURNAL_NAME), json.encodeToString(journal).toByteArray())
        File(directory, PENDING_NAME).delete()
    }

    @Synchronized
    fun markAccounted(jobId: String) {
        val journal = requireNotNull(loadUnvalidated(jobId))
        if (!journal.accounted) save(journal.copy(accounted = true))
    }

    @Synchronized
    fun markCompleted(jobId: String) {
        val journal = requireNotNull(loadUnvalidated(jobId))
        // Keep exact artifacts through the bounded job lifetime so a lost completion confirmation
        // can replay idempotently without rereading a non-transactional provider.
        save(journal.copy(completed = true))
    }

    @Synchronized
    fun cancel(jobId: String) {
        jobDirectory(jobId).deleteRecursively()
    }

    @Synchronized
    fun purgeAll() {
        root.deleteRecursively()
        check(root.mkdirs() || root.isDirectory) { "Unable to recreate the Direct CLI job store." }
    }

    @Synchronized
    fun sweepExpired(now: Instant = Instant.now()) {
        root.listFiles()?.filter(File::isDirectory)?.forEach { directory ->
            val journal = runCatching {
                json.decodeFromString<DirectJobJournal>(File(directory, JOURNAL_NAME).readText())
            }.getOrNull()
            val pending = runCatching {
                json.decodeFromString<PendingJob>(File(directory, PENDING_NAME).readText())
            }.getOrNull()
            val expiresAt = journal?.expiresAt ?: pending?.expiresAt
            val expired = expiresAt?.let { runCatching { !Instant.parse(it).isAfter(now) }.getOrNull() }
            val corruptRetentionElapsed = expired == null &&
                directory.lastModified() > 0L &&
                directory.lastModified() <= now.minusSeconds(MAXIMUM_RETENTION_SECONDS).toEpochMilli()
            if (expired == true || corruptRetentionElapsed) directory.deleteRecursively()
        }
    }

    fun directory(jobId: String): File = jobDirectory(jobId).apply {
        check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
    }

    private fun loadUnvalidated(jobId: String): DirectJobJournal? {
        val file = journalFile(jobId)
        return if (file.isFile) {
            runCatching { json.decodeFromString<DirectJobJournal>(file.readText()) }
                .getOrElse { throw IllegalStateException("The durable Direct CLI journal is corrupt.", it) }
        } else {
            null
        }
    }

    private fun journalFile(jobId: String): File = File(jobDirectory(jobId), JOURNAL_NAME)

    private fun jobDirectory(jobId: String): File =
        File(root, UUID.fromString(jobId).toString())

    private fun atomicWrite(file: File, bytes: ByteArray) {
        val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}.tmp")
        temporary.outputStream().use { output ->
            output.write(bytes)
            output.flush()
            output.fd.sync()
        }
        check(temporary.renameTo(file)) { "Unable to persist Direct CLI job atomically." }
    }

    companion object {
        private const val JOURNAL_NAME = "job.json"
        private const val PENDING_NAME = "pending.json"
        private const val MAXIMUM_RETENTION_SECONDS = 7L * 24L * 60L * 60L
    }

    @Serializable
    private data class PendingJob(
        val requestFingerprint: String,
        val expiresAt: String,
    )
}

@Serializable
data class DirectJobJournal(
    val requestFingerprint: String,
    val expiresAt: String,
    val transfer: PreparedTransfer,
    val accounted: Boolean = false,
    val completed: Boolean = false,
)

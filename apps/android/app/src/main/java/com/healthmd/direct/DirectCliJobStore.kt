package com.healthmd.direct

import com.healthmd.direct.protocol.PreparedTransfer
import com.healthmd.direct.protocol.ArtifactKind
import com.healthmd.direct.protocol.ArtifactSchema
import com.healthmd.direct.protocol.ProductId
import com.healthmd.direct.protocol.MINIMUM_PARTITION_BYTES
import com.healthmd.direct.protocol.MAXIMUM_PARTITION_BYTES
import com.healthmd.direct.protocol.MAXIMUM_CHUNK_BYTES
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import java.io.File
import java.io.RandomAccessFile
import java.time.Instant
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.FileVisitResult
import java.nio.file.attribute.BasicFileAttributes
import java.io.IOException
import java.time.LocalDate
import java.util.UUID
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.JsonNull

internal class DirectCliNamespaceJobStore(
    internal val root: File,
    internal val namespace: DirectJobNamespace,
    private val directorySync: (File) -> Boolean,
) {
    private val json = Json { encodeDefaults = true; explicitNulls = true; ignoreUnknownKeys = false }

    fun load(jobId: String, requestFingerprint: String): DirectJobJournal? = withStoreLock {
        val directory = jobDirectory(jobId)
        val file = File(directory, JOURNAL_NAME)
        if (!file.isFile) {
            require(directory.listFiles().isNullOrEmpty()) {
                "The durable Direct CLI spool is incomplete."
            }
            return@withStoreLock null
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
        journal
    }

    fun beginPreparation(
        jobId: String,
        requestFingerprint: String,
        expiresAt: String,
        enginePin: ExportEnginePin? = null,
        protocolPin: AndroidDirectProtocolPin? = null,
    ): DirectPreparationLease = withStoreLock {
        requireValidOptionalPin(enginePin)
        requireValidOptionalProtocolPin(protocolPin)
        val directory = jobDirectory(jobId).apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
        }
        check(!File(directory, JOURNAL_NAME).exists()) {
            "An accepted Direct CLI job cannot start another preparation."
        }
        val pending = File(directory, PENDING_NAME)
        if (pending.isFile) {
            val saved = decodePendingJob(pending.readText())
            require(saved.requestFingerprint == requestFingerprint) {
                "The pending Direct CLI request changed."
            }
            require(saved.expiresAt == expiresAt) {
                "The pending Direct CLI expiration changed."
            }
            requireDirectPinContinuity(saved.enginePin, enginePin)
            requireDirectProtocolPinContinuity(saved.protocolPin, protocolPin)
            throw IllegalStateException("A prior Direct CLI preparation did not finish.")
        }
        val pendingImage = encodePendingJob(
            PendingJob(
                version = DirectJobJournal.CURRENT_VERSION,
                requestFingerprint = requestFingerprint,
                expiresAt = expiresAt,
                enginePin = enginePin,
                protocolPin = protocolPin,
            ),
        )
        atomicWrite(pending, pendingImage.toByteArray())
        val token = UUID.randomUUID().toString()
        atomicWrite(File(directory, OWNER_NAME), token.toByteArray(Charsets.US_ASCII))
        DirectPreparationLease(jobId, token, pendingImage, namespace)
    }

    fun hasIncompletePreparation(jobId: String, requestFingerprint: String): Boolean = withStoreLock {
        val pending = File(jobDirectory(jobId), PENDING_NAME)
        if (!pending.isFile) return@withStoreLock false
        val saved = runCatching { decodePendingJob(pending.readText()) }
            .getOrElse { return@withStoreLock true }
        require(saved.requestFingerprint == requestFingerprint) {
            "The pending Direct CLI request changed."
        }
        true
    }

    fun savePrepared(journal: DirectJobJournal, lease: DirectPreparationLease): Unit = withStoreLock {
        check(journal.transfer.accepted.jobId == lease.jobId) { "Direct CLI preparation identity changed." }
        requirePendingPreparation(lease)
        save(journal)
    }

    fun cancelPreparation(lease: DirectPreparationLease): Boolean = withStoreLock {
        val directory = jobDirectory(lease.jobId)
        if (!hasPreparationOwner(directory, lease)) return@withStoreLock false
        deleteOwnedDirectory(directory)
    }

    fun save(journal: DirectJobJournal): Unit = withStoreLock {
        require(UUID.fromString(journal.transfer.accepted.jobId).toString() == journal.transfer.accepted.jobId)
        if (namespace == DirectJobNamespace.WAKE_DATE) {
            validateSuccessorJournal(jobDirectory(journal.transfer.accepted.jobId), journal)
        }
        val directory = jobDirectory(journal.transfer.accepted.jobId).apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI job directory." }
        }
        loadUnvalidated(journal.transfer.accepted.jobId)?.let { existing ->
            require(existing.version == journal.version &&
                existing.requestFingerprint == journal.requestFingerprint &&
                existing.expiresAt == journal.expiresAt &&
                existing.transfer == journal.transfer) {
                "The accepted Direct CLI authority changed."
            }
            requireDirectPinContinuity(existing.enginePin, journal.enginePin)
            requireDirectProtocolPinContinuity(existing.protocolPin, journal.protocolPin)
            require(!existing.accounted || journal.accounted) {
                "Direct CLI accounting cannot be rolled back."
            }
            require(!existing.completed || journal.completed) {
                "Direct CLI completion cannot be rolled back."
            }
        }
        val pendingFile = File(directory, PENDING_NAME)
        if (pendingFile.isFile) {
            val pending = decodePendingJob(pendingFile.readText())
            require(pending.version == journal.version) {
                "The pending Direct CLI journal version changed."
            }
            require(pending.requestFingerprint == journal.requestFingerprint) {
                "The pending Direct CLI request changed."
            }
            require(pending.expiresAt == journal.expiresAt) {
                "The pending Direct CLI expiration changed."
            }
            requireDirectPinContinuity(pending.enginePin, journal.enginePin)
            requireDirectProtocolPinContinuity(pending.protocolPin, journal.protocolPin)
        }
        atomicWrite(File(directory, JOURNAL_NAME), json.encodeToString(journal).toByteArray())
        check(!pendingFile.exists() || pendingFile.delete()) { "Unable to remove Direct CLI preparation marker." }
        syncAuthorityDirectories(directory)
    }

    fun acquireAcceptedLease(expected: DirectJobJournal): DirectAcceptedLease = withStoreLock {
        val jobId = expected.transfer.accepted.jobId
        val current = requireNotNull(load(jobId, expected.requestFingerprint))
        check(sameAuthority(current, expected)) { "The accepted Direct CLI authority changed." }
        val directory = jobDirectory(jobId)
        val owner = File(directory, OWNER_NAME)
        val token = if (owner.exists()) {
            check(owner.isFile && owner.length() == 36L) { "Invalid Direct CLI ownership." }
            owner.readText(Charsets.US_ASCII).also {
                check(runCatching { UUID.fromString(it).toString() == it }.getOrDefault(false)) {
                    "Invalid Direct CLI ownership."
                }
            }
        } else {
            UUID.randomUUID().toString().also { atomicWrite(owner, it.toByteArray(Charsets.US_ASCII)) }
        }
        // Re-establish durability even after a previous rename succeeded but its sync failed.
        syncAuthorityDirectories(directory)
        DirectAcceptedLease(DirectPreparationLease(jobId, token, namespace = namespace), current)
    }

    fun validatePreparationLease(lease: DirectPreparationLease): Unit = withStoreLock {
        requirePendingPreparation(lease)
    }

    fun <T> withAcceptedOwnership(lease: DirectAcceptedLease, action: () -> T): T = withStoreLock {
        validateAcceptedLease(lease)
        action()
    }

    fun <T> withPreparationOwnership(lease: DirectPreparationLease, action: () -> T): T = withStoreLock {
        requirePendingPreparation(lease)
        action()
    }

    fun cancelAcceptedPacketSendAuthorization(
        lease: DirectAcceptedLease,
        onRevoked: () -> Unit = {},
    ) = com.healthmd.direct.protocol.DirectPacketSendAuthorization { enqueue ->
        withStoreLock {
            requiredOwnedJournal(lease)
            check(deleteOwnedDirectory(jobDirectory(lease.owner.jobId))) {
                "Unable to cancel the Direct CLI operation."
            }
            onRevoked()
            enqueue()
        }
    }

    fun preparationPacketSendAuthorization(
        lease: DirectPreparationLease,
        cancelBeforeEnqueue: Boolean = false,
        onRevoked: () -> Unit = {},
    ) = com.healthmd.direct.protocol.DirectPacketSendAuthorization { enqueue ->
        withStoreLock {
            val directory = requirePendingPreparation(lease)
            if (cancelBeforeEnqueue) {
                check(deleteOwnedDirectory(directory)) { "Unable to cancel the Direct CLI preparation." }
                onRevoked()
            }
            enqueue()
        }
    }

    fun packetSendAuthorization(lease: DirectAcceptedLease) =
        com.healthmd.direct.protocol.DirectPacketSendAuthorization { enqueue ->
            withAcceptedOwnership(lease, enqueue)
        }

    /** A small owner read per frame; complete authority is checked at state transitions. */
    fun validateAcceptedLease(lease: DirectAcceptedLease): Unit = withStoreLock {
        val directory = requirePreparationOwner(lease.owner)
        check(File(directory, JOURNAL_NAME).isFile && lease.expiresAt.isAfter(Instant.now())) {
            "The accepted Direct CLI operation is no longer available."
        }
    }

    fun markAccounted(lease: DirectAcceptedLease, account: () -> Unit = {}): Boolean = withStoreLock {
        val journal = requiredOwnedJournal(lease)
        if (journal.accounted) return@withStoreLock false
        account()
        save(journal.copy(accounted = true))
        true
    }

    fun markCompleted(lease: DirectAcceptedLease, complete: () -> Unit = {}): Boolean = withStoreLock {
        val journal = requiredOwnedJournal(lease)
        if (journal.completed) return@withStoreLock false
        // The callback must persist an idempotent receipt before this checkpoint.
        complete()
        // Keep artifacts for replay after a lost completion confirmation.
        save(journal.copy(completed = true))
        true
    }

    fun cancelAccepted(lease: DirectAcceptedLease): Boolean = withStoreLock {
        val directory = jobDirectory(lease.owner.jobId)
        if (!hasPreparationOwner(directory, lease.owner)) return@withStoreLock false
        val current = loadUnvalidated(lease.owner.jobId) ?: return@withStoreLock false
        if (!sameAuthority(current, lease.authority)) return@withStoreLock false
        deleteOwnedDirectory(directory)
    }

    private fun requiredOwnedJournal(lease: DirectAcceptedLease): DirectJobJournal {
        validateAcceptedLease(lease)
        val journal = requireNotNull(loadUnvalidated(lease.owner.jobId))
        if (namespace == DirectJobNamespace.WAKE_DATE) validateSuccessorJournal(jobDirectory(lease.owner.jobId), journal)
        check(sameAuthority(journal, lease.authority)) { "The accepted Direct CLI authority changed." }
        syncAuthorityDirectories(jobDirectory(lease.owner.jobId))
        return journal
    }

    private fun sameAuthority(left: DirectJobJournal, right: DirectJobJournal): Boolean =
        left.copy(accounted = false, completed = false) == right.copy(accounted = false, completed = false)

    fun cancel(jobId: String): Unit = withStoreLock {
        check(deleteOwnedDirectory(jobDirectory(jobId))) { "Unable to cancel the Direct CLI job." }
    }

    fun purgeAll(): Unit = withStoreLock {
        check(deleteTreeWithoutFollowingLinks(root)) { "Unable to purge Direct CLI job storage." }
        check(root.mkdirs() || root.isDirectory) { "Unable to recreate the Direct CLI job store." }
        syncAuthorityDirectories(root)
    }

    fun sweepExpired(now: Instant, protectedJobIds: Set<String>): Unit = withStoreLock {
        if (!storageExists()) return@withStoreLock
        check(root.isDirectory && !Files.isSymbolicLink(root.toPath())) { "Invalid Direct CLI storage root." }
        // Retry an ambiguous post-removal sync even when no job remains to scan.
        syncAuthorityDirectories(root)
        root.listFiles()?.filter(File::isDirectory)?.forEach { directory ->
            if (directory.name in protectedJobIds) return@forEach
            // Unknown, misplaced, incomplete and duplicate authority is never age-deleted.
            val expiresAt = runCatching {
                validatePlacement(directory.name)
                val journalFile = File(directory, JOURNAL_NAME)
                if (journalFile.isFile) {
                    val journal = json.decodeFromString<DirectJobJournal>(journalFile.readText())
                    Instant.parse(journal.expiresAt)
                } else {
                    Instant.parse(decodePendingJob(File(directory, PENDING_NAME).readText()).expiresAt)
                }
            }.getOrNull() ?: return@forEach
            if (!expiresAt.isAfter(now)) {
                syncAuthorityDirectories(directory)
                check(deleteOwnedDirectory(directory)) { "Unable to remove expired Direct CLI storage." }
            }
        }
    }

    internal fun <T> transaction(action: () -> T): T = withStoreLock(action)
    internal fun contains(jobId: String): Boolean = Files.exists(jobDirectory(jobId).toPath(), LinkOption.NOFOLLOW_LINKS)
    internal fun storageExists(): Boolean = Files.exists(root.toPath(), LinkOption.NOFOLLOW_LINKS)
    internal fun jobIds(): List<String> = root.listFiles()?.filter { it.isDirectory }?.map { it.name }.orEmpty()

    internal fun validatePlacement(jobId: String) {
        val directory = jobDirectory(jobId)
        check(directory.isDirectory && !Files.isSymbolicLink(directory.toPath()) &&
            !Files.isSymbolicLink(root.toPath()) && directory.canonicalFile.parentFile == root.canonicalFile) {
            "Invalid Direct CLI storage placement."
        }
        val journalFile = File(directory, JOURNAL_NAME)
        val pendingFile = File(directory, PENDING_NAME)
        val pin = if (journalFile.exists()) {
            check(journalFile.isFile && !Files.isSymbolicLink(journalFile.toPath())) { "Invalid Direct CLI journal storage." }
            val journal = runCatching { json.decodeFromString<DirectJobJournal>(journalFile.readText()) }
                .getOrElse { throw IllegalStateException("The durable Direct CLI journal is corrupt.", it) }
            check(journal.transfer.accepted.jobId == jobId) { "The Direct CLI journal identity changed." }
            if (namespace == DirectJobNamespace.WAKE_DATE) {
                check(journal.version == DirectJobJournal.CURRENT_VERSION && !pendingFile.exists()) {
                    "The successor Direct CLI journal is incomplete."
                }
                validateSuccessorJournal(directory, journal)
            }
            journal.enginePin
        } else {
            check(pendingFile.isFile && !Files.isSymbolicLink(pendingFile.toPath())) { "The Direct CLI preparation is incomplete." }
            val pending = runCatching { decodePendingJob(pendingFile.readText()) }
                .getOrElse { throw IllegalStateException("The Direct CLI preparation is corrupt.", it) }
            if (namespace == DirectJobNamespace.WAKE_DATE) {
                check(pending.version == DirectJobJournal.CURRENT_VERSION) { "The successor Direct CLI preparation version changed." }
            }
            pending.enginePin
        }
        check(DirectJobNamespace.forPin(pin) == namespace) { "The Direct CLI journal is in the wrong namespace." }
        if (namespace == DirectJobNamespace.WAKE_DATE) {
            val owner = File(directory, OWNER_NAME)
            check(owner.isFile && !Files.isSymbolicLink(owner.toPath()) && owner.length() == 36L &&
                runCatching { UUID.fromString(owner.readText()).toString() == owner.readText() }.getOrDefault(false)) {
                "The successor Direct CLI ownership is unavailable."
            }
        }
    }

    private fun validateSuccessorJournal(directory: File, journal: DirectJobJournal) {
        val transfer = journal.transfer
        val accepted = transfer.accepted
        val session = transfer.session
        check(accepted.productId == ProductId.GENERATED_FILES_V1 &&
            accepted.jobId == directory.name && session.jobId == accepted.jobId &&
            accepted.requestFingerprint == journal.requestFingerprint && session.requestFingerprint == journal.requestFingerprint &&
            accepted.peerBinding == session.peerBinding && UUID.fromString(session.sessionId).toString() == session.sessionId &&
            UUID.fromString(accepted.peerBinding.sourceInstallationId).toString() == accepted.peerBinding.sourceInstallationId &&
            UUID.fromString(accepted.peerBinding.destinationInstallationId).toString() == accepted.peerBinding.destinationInstallationId &&
            LocalDate.parse(accepted.resolvedRange.startDate) <= LocalDate.parse(accepted.resolvedRange.endDate) &&
            Instant.parse(accepted.acceptedAt) <= Instant.parse(journal.expiresAt) &&
            Instant.parse(session.createdAt) <= Instant.parse(journal.expiresAt) &&
            session.partitionTargetBytes in MINIMUM_PARTITION_BYTES..MAXIMUM_PARTITION_BYTES &&
            transfer.manifests.isNotEmpty() &&
            transfer.manifests.map { it.artifactId }.toSet().size == transfer.manifests.size &&
            transfer.manifests.map { it.artifactId }.toSet() == transfer.artifactPaths.keys &&
            transfer.manifests.all { it.jobId == accepted.jobId && it.artifactId.isNotBlank() &&
                it.kind == ArtifactKind.GENERATED_FILE && it.schema == ArtifactSchema("healthmd.generated-files", 1) &&
                it.byteCount >= 0 && it.sha256.matches(SHA256_PATTERN) &&
                !it.relativePath.isNullOrBlank() && it.writeMode != null } &&
            transfer.partitions.all { it.artifactId in transfer.artifactPaths &&
                UUID.fromString(it.transferId).toString() == it.transferId &&
                it.byteCount in 1..session.partitionTargetBytes && it.artifactOffset >= 0 &&
                it.chunkCount == (it.byteCount + MAXIMUM_CHUNK_BYTES - 1) / MAXIMUM_CHUNK_BYTES &&
                it.sha256.matches(SHA256_PATTERN) } &&
            transfer.partitions.map { it.index } == transfer.partitions.indices.map(Int::toLong) &&
            transfer.partitions.firstOrNull()?.previousSha256 == null &&
            transfer.partitions.zipWithNext().all { (left, right) -> right.previousSha256 == left.sha256 }) {
            "The successor Direct CLI transfer authority is incomplete."
        }
        transfer.artifactPaths.forEach { (id, path) ->
            val file = File(path)
            val manifest = transfer.manifests.single { it.artifactId == id }
            var offset = 0L
            transfer.partitions.filter { it.artifactId == id }.forEach { partition ->
                check(partition.artifactOffset == offset && partition.byteCount <= manifest.byteCount - offset) {
                    "The successor Direct CLI partition coverage is incomplete."
                }
                offset += partition.byteCount
            }
            check(offset == manifest.byteCount) { "The successor Direct CLI artifact coverage is incomplete." }
            check(file.isFile && file.length() == manifest.byteCount &&
                generateSequence(file) { it.parentFile }.takeWhile { it != directory }
                    .none { Files.isSymbolicLink(it.toPath()) } &&
                file.canonicalFile.toPath().startsWith(directory.canonicalFile.toPath())) {
                "The successor Direct CLI artifact is unavailable."
            }
        }
    }

    fun directory(lease: DirectPreparationLease): File = withStoreLock {
        val directory = requirePendingPreparation(lease)
        File(directory, "capture-${lease.token}").apply {
            check(mkdirs() || isDirectory) { "Unable to create Direct CLI capture storage." }
            syncAuthorityDirectories(this)
        }
    }

    private fun requirePendingPreparation(lease: DirectPreparationLease): File {
        val directory = requirePreparationOwner(lease)
        val pending = File(directory, PENDING_NAME)
        check(pending.isFile && !File(directory, JOURNAL_NAME).exists()) {
            "The Direct CLI preparation is no longer pending."
        }
        val image = checkNotNull(lease.pendingImage) { "The Direct CLI pending authority is missing." }
        check(pending.length() == image.toByteArray().size.toLong() && pending.readText() == image) {
            "The Direct CLI pending authority changed."
        }
        check(Instant.parse(decodePendingJob(image).expiresAt).isAfter(Instant.now())) {
            "The Direct CLI preparation expired."
        }
        return directory
    }

    private fun requirePreparationOwner(lease: DirectPreparationLease): File {
        val directory = jobDirectory(lease.jobId)
        check(hasPreparationOwner(directory, lease)) { "The Direct CLI preparation ownership changed." }
        return directory
    }

    private fun hasPreparationOwner(directory: File, lease: DirectPreparationLease): Boolean =
        File(directory, OWNER_NAME).let { owner ->
            owner.isFile && owner.length() == lease.token.length.toLong() &&
                owner.readText(Charsets.US_ASCII) == lease.token
        }

    /// Keep the lock outside jobs so purgeAll cannot replace its inode.
    /// Nested operations on the same root reuse the lock on their owning thread.
    private fun <T> withStoreLock(block: () -> T): T = transactionLock.withLock {
        val lockFile = File(root.parentFile, ".jobs.journal.lock").canonicalFile
        val active = checkNotNull(activeLockPaths.get())
        if (!active.add(lockFile.path)) return@withLock block()
        try {
            RandomAccessFile(lockFile, "rw").use { file ->
                file.channel.lock().use { block() }
            }
        } finally {
            active.remove(lockFile.path)
            if (active.isEmpty()) activeLockPaths.remove()
        }
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

    private fun encodePendingJob(pending: PendingJob): String = json.encodeToString(
        PendingJobWire(
            version = pending.version,
            requestFingerprint = pending.requestFingerprint,
            expiresAt = pending.expiresAt,
            enginePin = pending.enginePin?.let { json.parseToJsonElement(ExportEnginePinCodec.encodeCanonical(it)) },
            protocolPin = pending.protocolPin,
        ),
    )

    private fun decodePendingJob(raw: String): PendingJob {
        val wire = json.decodeFromString<PendingJobWire>(raw)
        val version = wire.version ?: DirectJobJournal.LEGACY_VERSION
        require(version in DirectJobJournal.SUPPORTED_VERSIONS) {
            "Unsupported pending Direct CLI journal version."
        }
        // Missing/older versions are authoritative: unexpected future pin data cannot upgrade work.
        val pin = if (version == DirectJobJournal.LEGACY_VERSION) null else decodeDurablePin(wire.enginePin)
        val protocolPin = if (version >= DirectJobJournal.PROTOCOL_PIN_VERSION) wire.protocolPin else null
        requireValidOptionalProtocolPin(protocolPin)
        return PendingJob(version, wire.requestFingerprint, wire.expiresAt, pin, protocolPin)
    }

    private fun journalFile(jobId: String): File = File(jobDirectory(jobId), JOURNAL_NAME)

    private fun jobDirectory(jobId: String): File =
        File(root, UUID.fromString(jobId).toString())

    /** Synchronize each changed entry through the app-private authority tree, child first. */
    private fun syncAuthorityDirectories(directory: File) {
        val boundary = requireNotNull(requireNotNull(root.parentFile).parentFile)
        var current = directory
        while (true) {
            check(directorySync(current)) { "Unable to synchronize Direct CLI storage." }
            if (current == boundary) return
            current = requireNotNull(current.parentFile)
        }
    }

    private fun deleteOwnedDirectory(directory: File): Boolean {
        if (!deleteTreeWithoutFollowingLinks(directory)) return false
        syncAuthorityDirectories(root)
        return true
    }

    private fun deleteTreeWithoutFollowingLinks(directory: File): Boolean = try {
        if (Files.exists(directory.toPath(), LinkOption.NOFOLLOW_LINKS)) {
            Files.walkFileTree(directory.toPath(), object : SimpleFileVisitor<Path>() {
                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    Files.delete(file)
                    return FileVisitResult.CONTINUE
                }
                override fun postVisitDirectory(dir: Path, error: IOException?): FileVisitResult {
                    if (error != null) throw error
                    Files.delete(dir)
                    return FileVisitResult.CONTINUE
                }
            })
        }
        true
    } catch (_: IOException) { false }

    private fun atomicWrite(file: File, bytes: ByteArray) {
        val directory = requireNotNull(file.parentFile)
        val temporary = File(directory, ".${file.name}.${UUID.randomUUID()}.tmp")
        try {
            temporary.outputStream().use { output ->
                output.write(bytes)
                output.flush()
                output.fd.sync()
            }
            check(temporary.renameTo(file)) { "Unable to persist Direct CLI job atomically." }
            syncAuthorityDirectories(directory)
        } finally {
            if (temporary.exists()) temporary.delete()
        }
    }

    companion object {
        internal fun syncDirectoryOnAndroid(directory: File): Boolean = try {
            val descriptor = android.system.Os.open(directory.absolutePath, android.system.OsConstants.O_RDONLY, 0)
            try {
                android.system.Os.fsync(descriptor)
            } finally {
                android.system.Os.close(descriptor)
            }
            true
        } catch (_: Exception) {
            false
        }

        private val SHA256_PATTERN = Regex("[0-9a-f]{64}")
        private val transactionLock = ReentrantLock()
        private val activeLockPaths = ThreadLocal.withInitial { mutableSetOf<String>() }
        private const val JOURNAL_NAME = "job.json"
        private const val PENDING_NAME = "pending.json"
        private const val OWNER_NAME = "preparation-owner"
    }

    private data class PendingJob(
        val version: Int,
        val requestFingerprint: String,
        val expiresAt: String,
        val enginePin: ExportEnginePin?,
        val protocolPin: AndroidDirectProtocolPin?,
    )

    @Serializable
    private data class PendingJobWire(
        val version: Int? = null,
        val requestFingerprint: String,
        val expiresAt: String,
        val enginePin: JsonElement? = null,
        val protocolPin: AndroidDirectProtocolPin? = null,
    )
}

/** Opaque live-capture authority; its token never enters the direct protocol. */
class DirectPreparationLease internal constructor(
    internal val jobId: String,
    internal val token: String,
    internal val pendingImage: String? = null,
    internal val namespace: DirectJobNamespace = DirectJobNamespace.HISTORICAL,
)

/** An accepted operation's live ownership and frozen authority, never serialized on the wire. */
class DirectAcceptedLease internal constructor(
    internal val owner: DirectPreparationLease,
    internal val authority: DirectJobJournal,
) {
    internal val expiresAt: Instant = Instant.parse(authority.expiresAt)
}

@Serializable(with = DirectJobJournal.Serializer::class)
data class DirectJobJournal(
    val version: Int = CURRENT_VERSION,
    val requestFingerprint: String,
    val expiresAt: String,
    val transfer: PreparedTransfer,
    val enginePin: ExportEnginePin? = null,
    val protocolPin: AndroidDirectProtocolPin? = null,
    val accounted: Boolean = false,
    val completed: Boolean = false,
) {
    init {
        require(version in SUPPORTED_VERSIONS) { "Unsupported Direct CLI journal version." }
        require(version != LEGACY_VERSION || enginePin == null) {
            "A v1 Direct CLI journal cannot contain an engine pin."
        }
        require(version >= PROTOCOL_PIN_VERSION || protocolPin == null) {
            "A pre-v3 Direct CLI journal cannot contain a protocol pin."
        }
        requireValidOptionalPin(enginePin)
        requireValidOptionalProtocolPin(protocolPin)
        require(enginePin == null || enginePin.ianaTimeZone == transfer.accepted.resolvedRange.timeZoneId) {
            "The Direct CLI resolved timezone changed after engine planning."
        }
    }

    object Serializer : KSerializer<DirectJobJournal> {
        override val descriptor: SerialDescriptor = Wire.serializer().descriptor

        override fun serialize(encoder: Encoder, value: DirectJobJournal) {
            val jsonEncoder = encoder as? JsonEncoder
                ?: throw SerializationException("DirectJobJournal supports JSON only.")
            val wire = Wire(
                version = value.version,
                requestFingerprint = value.requestFingerprint,
                expiresAt = value.expiresAt,
                transfer = value.transfer,
                enginePin = value.enginePin?.let {
                    CODEC.parseToJsonElement(ExportEnginePinCodec.encodeCanonical(it))
                },
                protocolPin = value.protocolPin,
                accounted = value.accounted,
                completed = value.completed,
            )
            jsonEncoder.encodeJsonElement(CODEC.encodeToJsonElement(Wire.serializer(), wire))
        }

        override fun deserialize(decoder: Decoder): DirectJobJournal {
            val jsonDecoder = decoder as? JsonDecoder
                ?: throw SerializationException("DirectJobJournal supports JSON only.")
            val wire = CODEC.decodeFromJsonElement(Wire.serializer(), jsonDecoder.decodeJsonElement())
            val version = wire.version ?: LEGACY_VERSION
            if (version !in SUPPORTED_VERSIONS) {
                throw SerializationException("Unsupported Direct CLI journal version.")
            }
            // Missing/older versions are authoritative: unexpected pin data cannot upgrade work.
            val pin = if (version == LEGACY_VERSION) null else decodeDurablePin(wire.enginePin)
            val protocolPin = if (version >= PROTOCOL_PIN_VERSION) wire.protocolPin else null
            return DirectJobJournal(
                version = version,
                requestFingerprint = wire.requestFingerprint,
                expiresAt = wire.expiresAt,
                transfer = wire.transfer,
                enginePin = pin,
                protocolPin = protocolPin,
                accounted = wire.accounted,
                completed = wire.completed,
            )
        }

        @Serializable
        private data class Wire(
            val version: Int? = null,
            val requestFingerprint: String,
            val expiresAt: String,
            val transfer: PreparedTransfer,
            val enginePin: JsonElement? = null,
            val protocolPin: AndroidDirectProtocolPin? = null,
            val accounted: Boolean = false,
            val completed: Boolean = false,
        )

        private val CODEC = Json {
            encodeDefaults = true
            explicitNulls = true
            ignoreUnknownKeys = false
        }
    }

    companion object {
        const val LEGACY_VERSION = 1
        const val EXPORT_PIN_VERSION = 2
        const val PROTOCOL_PIN_VERSION = 3
        const val CURRENT_VERSION = PROTOCOL_PIN_VERSION
        internal val SUPPORTED_VERSIONS = LEGACY_VERSION..CURRENT_VERSION
    }
}

internal fun requireDirectPinContinuity(
    pendingPin: ExportEnginePin?,
    journalPin: ExportEnginePin?,
) {
    require(pendingPin == journalPin) {
        "The Direct CLI engine pin changed after preparation began."
    }
}

internal fun requireDirectProtocolPinContinuity(
    pendingPin: AndroidDirectProtocolPin?,
    journalPin: AndroidDirectProtocolPin?,
) {
    require(pendingPin == journalPin) {
        "The Direct CLI protocol pin changed after preparation began."
    }
}

private fun decodeDurablePin(element: JsonElement?): ExportEnginePin? {
    if (element == null || element is JsonNull) return null
    return ExportEnginePinCodec.decodeOrNull(element.toString())
        ?: throw SerializationException("The durable Direct CLI engine pin is invalid.")
}

private fun requireValidOptionalPin(pin: ExportEnginePin?) {
    require(pin == null || pin.engine != ExportEngineMode.legacy) {
        "Legacy Direct CLI operations must omit the engine pin."
    }
    require(pin == null || ExportEnginePinCodec.isStructurallyValid(pin)) {
        "The Direct CLI engine pin is invalid."
    }
}

private fun requireValidOptionalProtocolPin(pin: AndroidDirectProtocolPin?) {
    require(pin == null || pin.engine != AndroidDirectProtocolEngineMode.legacy) {
        "Legacy Direct CLI operations must omit the protocol pin."
    }
    require(pin == null || pin.version == AndroidDirectProtocolPin.CURRENT_VERSION) {
        "The Direct CLI protocol pin is invalid."
    }
}

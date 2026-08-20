package com.healthmd.data.drive

import com.healthmd.data.export.MarkdownMerger
import java.nio.charset.StandardCharsets
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal fun generateDriveFinalBytes(
    intent: GeneratedArtifactWriteIntent,
    baseline: ByteArray,
    fragment: ByteArray,
): ByteArray = when (intent) {
    GeneratedArtifactWriteIntent.OVERWRITE -> fragment.copyOf()
    GeneratedArtifactWriteIntent.APPEND -> baseline + "\n".encodeToByteArray() + fragment
    GeneratedArtifactWriteIntent.MARKDOWN_UPDATE,
    GeneratedArtifactWriteIntent.DAILY_NOTE_MERGE -> MarkdownMerger().merge(
        baseline.toString(StandardCharsets.UTF_8),
        fragment.toString(StandardCharsets.UTF_8),
    ).encodeToByteArray()
}

/** Durable destination runner shared by manual, legacy-schedule, and profile-schedule entry points. */
@Singleton
class GoogleDriveDestinationRunner @Inject constructor(
    private val destinationStore: GoogleDriveDestinationStore,
    private val managedStore: GoogleDriveManagedObjectStore,
    private val journalStore: GoogleDriveJournalStore,
    private val authorization: GoogleDriveAccessTokenProvider,
    private val api: GoogleDriveApi,
) {
    private val destinationLocks = mutableMapOf<String, Mutex>()
    private val locksMutex = Mutex()
    suspend fun run(bundle: GeneratedExportBundle, destinationId: String): GoogleDriveRunResult {
        val destination = destinationStore.find(destinationId)
            ?: return GoogleDriveRunResult.Stopped(GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        val journal = when (val existing = journalStore.load(bundle.operationId)) {
            GoogleDriveJournalLoad.Missing -> try {
                journalStore.create(bundle, destination)
            } catch (_: Exception) {
                return GoogleDriveRunResult.Stopped(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
            }
            GoogleDriveJournalLoad.Corrupt ->
                return GoogleDriveRunResult.Stopped(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
            is GoogleDriveJournalLoad.Found -> existing.journal.takeIf {
                it.destinationId == destinationId &&
                    it.destinationFingerprint == destination.fingerprint &&
                    it.bundleDigest == bundle.digest
            } ?: return GoogleDriveRunResult.Stopped(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        return withDestinationLock(destinationId) { execute(journal, destination) }
    }

    suspend fun resume(operationId: String): GoogleDriveRunResult {
        val journal = when (val loaded = journalStore.load(operationId)) {
            GoogleDriveJournalLoad.Missing, GoogleDriveJournalLoad.Corrupt ->
                return GoogleDriveRunResult.Stopped(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
            is GoogleDriveJournalLoad.Found -> loaded.journal
        }
        val destination = destinationStore.find(journal.destinationId)
            ?: return stopped(journal, GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        if (destination.fingerprint != journal.destinationFingerprint) {
            return stopped(journal, GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        return withDestinationLock(destination.id) { execute(journal, destination) }
    }

    private suspend fun execute(
        initialJournal: GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
    ): GoogleDriveRunResult {
        val token = when (val authorizationResult = authorization.silentToken(destination)) {
            is GoogleDriveAccessTokenResult.Granted -> authorizationResult.accessToken
            GoogleDriveAccessTokenResult.ResolutionRequired ->
                return stopped(initialJournal, GoogleDriveErrorId.REAUTHORIZATION_REQUIRED)
            is GoogleDriveAccessTokenResult.Failed -> return stopped(initialJournal, authorizationResult.error)
        }
        val folder = when (val result = api.getMetadata(token, destination.folderId, destination.resourceKeys())) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return stopped(initialJournal, result.error, result.retryable)
        }
        if (!validDestinationFolder(destination, folder)) {
            return stopped(initialJournal, GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        }

        var journal = initialJournal
        // Prepare every final byte and exact object baseline before content upload begins.
        for (index in journal.artifacts.indices) {
            if (journal.artifacts[index].phase >= GoogleDriveArtifactPhase.FINAL_BYTES_STAGED) continue
            when (val prepared = prepareArtifact(journal, index, destination, token)) {
                is PrepareResult.Ready -> journal = prepared.journal
                is PrepareResult.Skipped -> journal = prepared.journal
                is PrepareResult.Failed -> return stopped(journal, prepared.error, prepared.retryable)
            }
        }

        // Content commits are deterministic and checkpointed one artifact at a time.
        for (index in journal.artifacts.indices) {
            if (journal.artifacts[index].phase == GoogleDriveArtifactPhase.VERIFIED ||
                journal.artifacts[index].phase == GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED
            ) continue
            when (val committed = commitArtifact(journal, index, destination, token)) {
                is CommitResult.Done -> journal = committed.journal
                is CommitResult.Failed -> return stopped(journal, committed.error, committed.retryable)
            }
        }
        journal = journal.copy(
            completedArtifactCount = journal.artifacts.count {
                it.phase == GoogleDriveArtifactPhase.VERIFIED || it.phase == GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED
            },
            historyAcknowledged = true,
            artifacts = journal.artifacts.map {
                if (it.phase == GoogleDriveArtifactPhase.VERIFIED) {
                    it.copy(phase = GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED)
                } else it
            },
        )
        journalStore.save(journal)
        journalStore.pruneCompleted()
        return GoogleDriveRunResult.Complete(journal.completedArtifactCount)
    }

    private suspend fun prepareArtifact(
        initial: GoogleDriveOperationJournal,
        index: Int,
        destination: GoogleDriveDestination,
        token: String,
    ): PrepareResult {
        var journal = initial
        var artifact = journal.artifacts[index]
        val parentPath = artifact.relativePath.substringBeforeLast('/', missingDelimiterValue = "")
        val fileName = artifact.relativePath.substringAfterLast('/')
        val parent = when (val result = resolveParent(journal, destination, token, parentPath)) {
            is ResolveObject.Success -> {
                journal = result.journal
                result.metadata
            }
            is ResolveObject.Failed -> return PrepareResult.Failed(result.error, result.retryable)
        }
        val existing = when (val result = resolveExistingFile(
            journal,
            destination,
            token,
            artifact,
            parent.id,
            fileName,
        )) {
            is ResolveFile.Success -> result.metadata
            is ResolveFile.Failed -> return PrepareResult.Failed(result.error, result.retryable)
        }

        if (existing == null && !artifact.createIfMissing) {
            artifact = artifact.copy(
                parentId = parent.id,
                phase = GoogleDriveArtifactPhase.VERIFIED,
            )
            journal = journal.replacing(index, artifact).withCompletedCount()
            journalStore.save(journal)
            return PrepareResult.Skipped(journal)
        }

        if (existing != null) {
            if (!validManagedFile(existing, parent.id, fileName, artifact.mediaType)) {
                return PrepareResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
            }
            artifact = artifact.copy(
                objectId = existing.id,
                parentId = parent.id,
                objectResourceKey = existing.resourceKey,
                baselineVersion = existing.version,
                baselineSize = existing.size,
                baselineMd5 = existing.md5Checksum,
                baselineSha256 = existing.sha256Checksum,
                phase = GoogleDriveArtifactPhase.BASELINE_STAGED,
            )
            journal = journal.replacing(index, artifact)
            journalStore.save(journal)
        } else {
            artifact = artifact.copy(parentId = parent.id)
        }

        val fragment = journalStore.readArtifact(journal.operationId, artifact)
            ?: return PrepareResult.Failed(GoogleDriveErrorId.CHECKSUM_MISMATCH)
        val baseline = if (artifact.writeIntent == GeneratedArtifactWriteIntent.OVERWRITE) {
            ByteArray(0)
        } else if (existing == null) {
            journalStore.readMissingPrefix(journal.operationId, artifact) ?: ByteArray(0)
        } else {
            when (val result = api.download(token, existing.id, resourceKeys(destination, existing))) {
                is DriveApiResult.Success -> result.value
                is DriveApiResult.Failure -> return PrepareResult.Failed(result.error, result.retryable)
            }.also { downloaded ->
                if (!metadataMatchesBytes(existing, downloaded)) {
                    return PrepareResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
                }
            }
        }
        val finalBytes = generateDriveFinalBytes(artifact.writeIntent, baseline, fragment)
        journal = journalStore.replaceFinalBytes(journal, index, finalBytes)
        artifact = journal.artifacts[index]

        if (artifact.objectId == null) {
            val reservedKey = artifact.relativePathHash
            val reserved = journal.reservedObjectIds[reservedKey] ?: when (val generated = api.generateId(token)) {
                is DriveApiResult.Success -> generated.value
                is DriveApiResult.Failure -> return PrepareResult.Failed(generated.error, generated.retryable)
            }.also { generatedId ->
                journal = journal.copy(reservedObjectIds = journal.reservedObjectIds + (reservedKey to generatedId))
                journalStore.save(journal) // required before create/session initialization
            }
            artifact = journal.artifacts[index].copy(
                objectId = reserved,
                phase = GoogleDriveArtifactPhase.ID_RESERVED,
            )
            journal = journal.replacing(index, artifact)
            journalStore.save(journal)
        }
        return PrepareResult.Ready(journal)
    }

    private suspend fun commitArtifact(
        initial: GoogleDriveOperationJournal,
        index: Int,
        destination: GoogleDriveDestination,
        token: String,
    ): CommitResult {
        var journal = initial
        var artifact = journal.artifacts[index]
        val objectId = artifact.objectId ?: return CommitResult.Failed(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
        val parentId = artifact.parentId ?: return CommitResult.Failed(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
        val bytes = journalStore.readArtifact(journal.operationId, artifact)
            ?: return CommitResult.Failed(GoogleDriveErrorId.CHECKSUM_MISMATCH)
        val fileName = artifact.relativePath.substringAfterLast('/')
        val resources = resourceKeys(destination, objectId, artifact.objectResourceKey)

        val remoteBefore = when (val result = api.getMetadata(token, objectId, resources)) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> if (
                artifact.baselineVersion == null && result.error == GoogleDriveErrorId.FOLDER_UNAVAILABLE
            ) null else return CommitResult.Failed(result.error, result.retryable)
        }
        if (artifact.baselineVersion != null && !sameBaseline(artifact, remoteBefore)) {
            return CommitResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        if (remoteBefore != null && !validManagedFile(remoteBefore, parentId, fileName, artifact.mediaType)) {
            return CommitResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
        }

        var sessionUri = artifact.resumableSessionUri
        var offset = artifact.acknowledgedOffset
        if (sessionUri != null && artifact.phase >= GoogleDriveArtifactPhase.SESSION_STARTED) {
            when (val status = api.queryUpload(token, sessionUri, bytes.size.toLong())) {
                is DriveApiResult.Success -> {
                    if (status.value.complete) {
                        artifact = artifact.copy(phase = GoogleDriveArtifactPhase.COMMITTED, acknowledgedOffset = bytes.size.toLong())
                        journal = journal.replacing(index, artifact)
                        journalStore.save(journal)
                    } else {
                        offset = status.value.acknowledgedBytes
                    }
                }
                is DriveApiResult.Failure -> {
                    // Expired sessions restart against the same final bytes and reserved identity.
                    sessionUri = null
                    offset = 0
                }
            }
        }
        if (artifact.phase < GoogleDriveArtifactPhase.COMMITTED) {
            if (sessionUri == null) {
                val appProperties = mapOf(
                    "healthmd" to "managed-v1",
                    "pathHash" to artifact.relativePathHash,
                    "contentHash" to artifact.sha256,
                )
                val session = if (artifact.baselineVersion == null && remoteBefore == null) {
                    api.startResumableCreate(
                        token,
                        objectId,
                        parentId,
                        fileName,
                        artifact.mediaType,
                        bytes.size.toLong(),
                        appProperties,
                        resources,
                    )
                } else {
                    api.startResumableUpdate(
                        token,
                        objectId,
                        artifact.mediaType,
                        bytes.size.toLong(),
                        appProperties,
                        resources,
                    )
                }
                sessionUri = when (session) {
                    is DriveApiResult.Success -> session.value.uri
                    is DriveApiResult.Failure -> {
                        val reconciled = reconcileIntended(token, destination, artifact, bytes)
                        if (reconciled != null) {
                            artifact = artifact.copy(phase = GoogleDriveArtifactPhase.COMMITTED)
                            journal = journal.replacing(index, artifact)
                            journalStore.save(journal)
                            null
                        } else return CommitResult.Failed(session.error, session.retryable)
                    }
                }
                if (sessionUri != null) {
                    artifact = artifact.copy(
                        resumableSessionUri = sessionUri,
                        acknowledgedOffset = 0,
                        phase = GoogleDriveArtifactPhase.SESSION_STARTED,
                    )
                    journal = journal.replacing(index, artifact)
                    journalStore.save(journal)
                }
            }
            if (artifact.phase < GoogleDriveArtifactPhase.COMMITTED && sessionUri != null) {
                artifact = journal.artifacts[index].copy(
                    phase = GoogleDriveArtifactPhase.UPLOADING,
                    acknowledgedOffset = offset,
                )
                journal = journal.replacing(index, artifact)
                journalStore.save(journal)
                when (val uploaded = api.upload(token, sessionUri, bytes, offset)) {
                    is DriveApiResult.Success -> {
                        artifact = journal.artifacts[index].copy(
                            phase = if (uploaded.value.complete) GoogleDriveArtifactPhase.COMMITTED else GoogleDriveArtifactPhase.UPLOADING,
                            acknowledgedOffset = uploaded.value.acknowledgedBytes,
                        )
                        journal = journal.replacing(index, artifact)
                        journalStore.save(journal)
                        if (!uploaded.value.complete) return CommitResult.Failed(GoogleDriveErrorId.AMBIGUOUS_COMMIT, true)
                    }
                    is DriveApiResult.Failure -> {
                        val reconciled = reconcileIntended(token, destination, artifact, bytes)
                        if (reconciled == null) return CommitResult.Failed(GoogleDriveErrorId.AMBIGUOUS_COMMIT, uploaded.retryable)
                        artifact = journal.artifacts[index].copy(phase = GoogleDriveArtifactPhase.COMMITTED)
                        journal = journal.replacing(index, artifact)
                        journalStore.save(journal)
                    }
                }
            }
        }

        val postflight = when (val result = api.getMetadata(token, objectId, resources)) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return CommitResult.Failed(GoogleDriveErrorId.AMBIGUOUS_COMMIT, result.retryable)
        }
        if (!validManagedFile(postflight, parentId, fileName, artifact.mediaType) ||
            !metadataMatchesBytes(postflight, bytes) ||
            (artifact.baselineVersion != null && postflight.version == artifact.baselineVersion)
        ) {
            return CommitResult.Failed(GoogleDriveErrorId.CHECKSUM_MISMATCH)
        }
        managedStore.put(
            GoogleDriveManagedObject(
                destinationId = destination.id,
                relativePathHash = artifact.relativePathHash,
                objectId = objectId,
                parentId = parentId,
                expectedName = fileName,
                mimeType = artifact.mediaType,
                resourceKey = postflight.resourceKey,
                remoteVersion = postflight.version,
                byteCount = postflight.size,
                md5Checksum = postflight.md5Checksum,
                sha256Checksum = postflight.sha256Checksum,
            ),
        )
        artifact = journal.artifacts[index].copy(
            phase = GoogleDriveArtifactPhase.VERIFIED,
            objectResourceKey = postflight.resourceKey,
        )
        journal = journal.replacing(index, artifact).withCompletedCount()
        journalStore.save(journal)
        return CommitResult.Done(journal)
    }

    private suspend fun resolveParent(
        initial: GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
        token: String,
        parentPath: String,
    ): ResolveObject {
        var journal = initial
        var current = GoogleDriveRemoteMetadata(
            id = destination.folderId,
            name = destination.folderLabel,
            mimeType = GOOGLE_DRIVE_FOLDER_MIME_TYPE,
            driveId = destination.sharedDriveId,
            resourceKey = destination.resourceKey,
            capabilities = destination.capabilities,
        )
        if (parentPath.isBlank()) return ResolveObject.Success(journal, current)
        var traversed = ""
        for (segment in parentPath.split('/')) {
            traversed = listOf(traversed, segment).filter(String::isNotBlank).joinToString("/")
            val hash = relativePathHash(destination.id, "$traversed/")
            val binding = managedStore.get(destination.id, hash)
            val resolved = if (binding != null) {
                when (val result = api.getMetadata(token, binding.objectId, resourceKeys(destination, binding.objectId, binding.resourceKey))) {
                    is DriveApiResult.Success -> result.value
                    is DriveApiResult.Failure -> return ResolveObject.Failed(result.error, result.retryable)
                }.takeIf { validFolder(it, current.id, segment) }
                    ?: return ResolveObject.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
            } else {
                val previouslyReserved = journal.reservedObjectIds[hash]
                val reconciledReserved = previouslyReserved?.let { reserved ->
                    when (val result = api.getMetadata(token, reserved, resourceKeys(destination, current))) {
                        is DriveApiResult.Success -> result.value.takeIf { validFolder(it, current.id, segment) }
                        is DriveApiResult.Failure -> null
                    }
                }
                if (reconciledReserved != null) {
                    reconciledReserved
                } else {
                    val matches = when (val result = api.findChildren(token, current.id, segment, resourceKeys(destination, current))) {
                        is DriveApiResult.Success -> result.value
                        is DriveApiResult.Failure -> return ResolveObject.Failed(result.error, result.retryable)
                    }.filter { it.mimeType == GOOGLE_DRIVE_FOLDER_MIME_TYPE }
                    // A name is only a reconciliation hint. Never adopt an unbound folder as authority.
                    if (matches.isNotEmpty()) return ResolveObject.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
                    val reserved = previouslyReserved ?: when (val result = api.generateId(token)) {
                        is DriveApiResult.Success -> result.value
                        is DriveApiResult.Failure -> return ResolveObject.Failed(result.error, result.retryable)
                    }.also { id ->
                        journal = journal.copy(reservedObjectIds = journal.reservedObjectIds + (hash to id))
                        journalStore.save(journal)
                    }
                    when (val result = api.createFolder(token, reserved, current.id, segment, resourceKeys(destination, current))) {
                        is DriveApiResult.Success -> result.value
                        is DriveApiResult.Failure -> {
                            val reconciled = api.getMetadata(token, reserved, resourceKeys(destination, current))
                            if (reconciled is DriveApiResult.Success && validFolder(reconciled.value, current.id, segment)) {
                                reconciled.value
                            } else return ResolveObject.Failed(GoogleDriveErrorId.AMBIGUOUS_COMMIT, result.retryable)
                        }
                    }
                }
            }
            managedStore.put(
                GoogleDriveManagedObject(
                    destinationId = destination.id,
                    relativePathHash = hash,
                    objectId = resolved.id,
                    parentId = current.id,
                    expectedName = segment,
                    mimeType = GOOGLE_DRIVE_FOLDER_MIME_TYPE,
                    resourceKey = resolved.resourceKey,
                    remoteVersion = resolved.version,
                ),
            )
            current = resolved
        }
        return ResolveObject.Success(journal, current)
    }

    private suspend fun resolveExistingFile(
        journal: GoogleDriveOperationJournal,
        destination: GoogleDriveDestination,
        token: String,
        artifact: GoogleDriveJournalArtifact,
        parentId: String,
        name: String,
    ): ResolveFile {
        val binding = managedStore.get(destination.id, artifact.relativePathHash)
        if (binding != null) {
            val metadata = when (val result = api.getMetadata(token, binding.objectId, resourceKeys(destination, binding.objectId, binding.resourceKey))) {
                is DriveApiResult.Success -> result.value
                is DriveApiResult.Failure -> return ResolveFile.Failed(result.error, result.retryable)
            }
            return if (validManagedFile(metadata, parentId, name, artifact.mediaType)) {
                ResolveFile.Success(metadata)
            } else ResolveFile.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        val matches = when (val result = api.findChildren(token, parentId, name, destination.resourceKeys())) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return ResolveFile.Failed(result.error, result.retryable)
        }.filter { it.mimeType != GOOGLE_DRIVE_FOLDER_MIME_TYPE }
        return if (matches.isEmpty()) {
            ResolveFile.Success(null)
        } else {
            // Stable object bindings, never names alone, authorize updates.
            ResolveFile.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
    }

    private suspend fun reconcileIntended(
        token: String,
        destination: GoogleDriveDestination,
        artifact: GoogleDriveJournalArtifact,
        bytes: ByteArray,
    ): GoogleDriveRemoteMetadata? {
        val id = artifact.objectId ?: return null
        return when (val result = api.getMetadata(token, id, resourceKeys(destination, id, artifact.objectResourceKey))) {
            is DriveApiResult.Success -> result.value.takeIf { metadataMatchesBytes(it, bytes) }
            is DriveApiResult.Failure -> null
        }
    }

    private fun validDestinationFolder(destination: GoogleDriveDestination, metadata: GoogleDriveRemoteMetadata): Boolean =
        metadata.id == destination.folderId && metadata.mimeType == GOOGLE_DRIVE_FOLDER_MIME_TYPE &&
            !metadata.trashed && metadata.capabilities.canAddChildren && metadata.driveId == destination.sharedDriveId

    private fun validFolder(metadata: GoogleDriveRemoteMetadata, parentId: String, name: String): Boolean =
        metadata.name == name && metadata.mimeType == GOOGLE_DRIVE_FOLDER_MIME_TYPE &&
            metadata.parents == listOf(parentId) && !metadata.trashed && metadata.capabilities.canAddChildren

    private fun validManagedFile(metadata: GoogleDriveRemoteMetadata, parentId: String, name: String, mediaType: String): Boolean =
        metadata.name == name && metadata.mimeType == mediaType.substringBefore(';') &&
            metadata.parents == listOf(parentId) && !metadata.trashed

    private fun metadataMatchesBytes(metadata: GoogleDriveRemoteMetadata, bytes: ByteArray): Boolean =
        metadata.size == bytes.size.toLong() && when {
            metadata.sha256Checksum != null -> metadata.sha256Checksum == com.healthmd.domain.exportengine.sha256Hex(bytes)
            metadata.md5Checksum != null -> metadata.md5Checksum == md5Hex(bytes)
            else -> false // Drive did not expose a verifiable checksum: fail closed.
        }

    private fun sameBaseline(artifact: GoogleDriveJournalArtifact, metadata: GoogleDriveRemoteMetadata?): Boolean =
        metadata != null && metadata.id == artifact.objectId && metadata.version == artifact.baselineVersion &&
            metadata.size == artifact.baselineSize && metadata.md5Checksum == artifact.baselineMd5 &&
            metadata.sha256Checksum == artifact.baselineSha256 && !metadata.trashed

    private fun resourceKeys(destination: GoogleDriveDestination, metadata: GoogleDriveRemoteMetadata): Map<String, String> =
        resourceKeys(destination, metadata.id, metadata.resourceKey)

    private fun resourceKeys(destination: GoogleDriveDestination, id: String, key: String?): Map<String, String> =
        destination.resourceKeys() + key?.let { mapOf(id to it) }.orEmpty()

    private suspend fun <T> withDestinationLock(id: String, block: suspend () -> T): T {
        val lock = locksMutex.withLock { destinationLocks.getOrPut(id) { Mutex() } }
        return lock.withLock { block() }
    }

    private fun stopped(
        journal: GoogleDriveOperationJournal,
        error: GoogleDriveErrorId,
        retryable: Boolean = false,
    ): GoogleDriveRunResult.Stopped {
        val completed = journal.artifacts.count {
            it.phase == GoogleDriveArtifactPhase.VERIFIED || it.phase == GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED
        }
        return GoogleDriveRunResult.Stopped(
            error = if (completed > 0) GoogleDriveErrorId.PARTIAL_COMPLETION else error,
            completedArtifactCount = completed,
            retryable = retryable,
        )
    }

    private fun GoogleDriveOperationJournal.replacing(index: Int, artifact: GoogleDriveJournalArtifact): GoogleDriveOperationJournal =
        copy(artifacts = artifacts.toMutableList().apply { set(index, artifact) })

    private fun GoogleDriveOperationJournal.withCompletedCount(): GoogleDriveOperationJournal = copy(
        completedArtifactCount = artifacts.count {
            it.phase == GoogleDriveArtifactPhase.VERIFIED || it.phase == GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED
        },
    )

    private sealed interface PrepareResult {
        data class Ready(val journal: GoogleDriveOperationJournal) : PrepareResult
        data class Skipped(val journal: GoogleDriveOperationJournal) : PrepareResult
        data class Failed(val error: GoogleDriveErrorId, val retryable: Boolean = false) : PrepareResult
    }
    private sealed interface CommitResult {
        data class Done(val journal: GoogleDriveOperationJournal) : CommitResult
        data class Failed(val error: GoogleDriveErrorId, val retryable: Boolean = false) : CommitResult
    }
    private sealed interface ResolveObject {
        data class Success(val journal: GoogleDriveOperationJournal, val metadata: GoogleDriveRemoteMetadata) : ResolveObject
        data class Failed(val error: GoogleDriveErrorId, val retryable: Boolean = false) : ResolveObject
    }
    private sealed interface ResolveFile {
        data class Success(val metadata: GoogleDriveRemoteMetadata?) : ResolveFile
        data class Failed(val error: GoogleDriveErrorId, val retryable: Boolean = false) : ResolveFile
    }
}

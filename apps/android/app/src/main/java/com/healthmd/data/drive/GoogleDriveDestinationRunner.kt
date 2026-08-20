package com.healthmd.data.drive

import com.healthmd.data.export.MarkdownMerger
import java.nio.charset.StandardCharsets
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal fun generateDriveFinalBytes(
    intent: GeneratedArtifactWriteIntent,
    baseline: ByteArray,
    fragment: ByteArray,
    baselineExists: Boolean = true,
): ByteArray = when (intent) {
    GeneratedArtifactWriteIntent.OVERWRITE -> fragment.copyOf()
    GeneratedArtifactWriteIntent.APPEND -> if (baselineExists) {
        baseline + "\n".encodeToByteArray() + fragment
    } else {
        fragment.copyOf()
    }
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

    /** Returns null only when no retained operation exists, allowing capture to begin safely. */
    suspend fun resumeIfPresent(
        operationId: String,
        expectedDestinationId: String? = null,
        expectedOwnerDates: List<java.time.LocalDate>? = null,
        expectedSettingsSnapshotSha256: String? = null,
    ): GoogleDriveRunResult? {
        val journal = when (val loaded = journalStore.load(operationId)) {
            GoogleDriveJournalLoad.Missing -> return null
            GoogleDriveJournalLoad.Corrupt ->
                return GoogleDriveRunResult.Stopped(GoogleDriveErrorId.AMBIGUOUS_COMMIT)
            is GoogleDriveJournalLoad.Found -> loaded.journal
        }
        if ((expectedDestinationId != null && journal.destinationId != expectedDestinationId) ||
            (expectedOwnerDates != null && journal.ownerDates != expectedOwnerDates.distinct().sorted().map(java.time.LocalDate::toString)) ||
            (expectedSettingsSnapshotSha256 != null && journal.settingsSnapshotSha256 != expectedSettingsSnapshotSha256)
        ) {
            return stopped(journal, GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        val destination = destinationStore.find(journal.destinationId)
            ?: return stopped(journal, GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        if (destination.fingerprint != journal.destinationFingerprint) {
            return stopped(journal, GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        return withDestinationLock(destination.id) { execute(journal, destination) }
    }

    suspend fun resume(operationId: String): GoogleDriveRunResult =
        resumeIfPresent(operationId)
            ?: GoogleDriveRunResult.Stopped(GoogleDriveErrorId.AMBIGUOUS_COMMIT)

    /** Called only after the completed operation has been durably represented in history. */
    suspend fun acknowledgeAfterHistory(operationId: String): Boolean {
        val retained = when (val loaded = journalStore.load(operationId)) {
            is GoogleDriveJournalLoad.Found -> loaded.journal
            GoogleDriveJournalLoad.Missing, GoogleDriveJournalLoad.Corrupt -> return false
        }
        return withDestinationLock(retained.destinationId) {
            val journal = when (val loaded = journalStore.load(operationId)) {
                is GoogleDriveJournalLoad.Found -> loaded.journal
                GoogleDriveJournalLoad.Missing, GoogleDriveJournalLoad.Corrupt -> return@withDestinationLock false
            }
            if (journal.artifacts.any {
                    it.phase != GoogleDriveArtifactPhase.VERIFIED &&
                        it.phase != GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED
                }
            ) return@withDestinationLock false
            val acknowledged = journal.copy(
                historyAcknowledged = true,
                artifacts = journal.artifacts.map {
                    if (it.phase == GoogleDriveArtifactPhase.VERIFIED) {
                        it.copy(phase = GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED)
                    } else it
                },
            )
            journalStore.save(acknowledged)
            journalStore.pruneAcknowledged()
            true
        }
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

        if (!managedStore.isMutationSafe()) {
            return stopped(initialJournal, GoogleDriveErrorId.REMOTE_CONFLICT)
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
        journal = journal.withCompletedCount()
        journalStore.save(journal)
        // VERIFIED remains retained until the history owner explicitly acknowledges persistence.
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
                is DriveApiResult.Failure -> return PrepareResult.Failed(result.error.forKnownFile(), result.retryable)
            }.also { downloaded ->
                if (!metadataMatchesBytes(existing, downloaded)) {
                    return PrepareResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
                }
            }
        }
        val finalBytes = generateDriveFinalBytes(
            intent = artifact.writeIntent,
            baseline = baseline,
            fragment = fragment,
            baselineExists = existing != null || artifact.missingPrefixFile != null,
        )
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
                artifact.baselineVersion == null &&
                artifact.phase < GoogleDriveArtifactPhase.SESSION_STARTED &&
                result.error == GoogleDriveErrorId.FOLDER_UNAVAILABLE
            ) {
                null
            } else {
                return CommitResult.Failed(result.error.forKnownFile(), result.retryable)
            }
        }
        // The server may have committed the final chunk before the process could checkpoint it.
        // Reconcile exact final identity and bytes before comparing against the old baseline.
        if (artifact.phase in GoogleDriveArtifactPhase.SESSION_STARTED..GoogleDriveArtifactPhase.UPLOADING &&
            remoteBefore != null &&
            validManagedFile(remoteBefore, parentId, fileName, artifact.mediaType) &&
            metadataMatchesBytes(remoteBefore, bytes)
        ) {
            artifact = artifact.copy(
                phase = GoogleDriveArtifactPhase.COMMITTED,
                acknowledgedOffset = bytes.size.toLong(),
            )
            journal = journal.replacing(index, artifact)
            journalStore.save(journal)
        }
        if (artifact.phase < GoogleDriveArtifactPhase.COMMITTED) {
            if (artifact.baselineVersion != null && !sameBaseline(artifact, remoteBefore)) {
                return CommitResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
            }
            if (remoteBefore != null && !validManagedFile(remoteBefore, parentId, fileName, artifact.mediaType)) {
                return CommitResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
            }
        }

        var sessionUri = artifact.resumableSessionUri
        var offset = artifact.acknowledgedOffset
        if (sessionUri != null && artifact.phase in GoogleDriveArtifactPhase.SESSION_STARTED..GoogleDriveArtifactPhase.UPLOADING) {
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
                    val reconciled = reconcileIntended(token, destination, artifact, bytes)
                    if (reconciled != null) {
                        artifact = artifact.copy(
                            phase = GoogleDriveArtifactPhase.COMMITTED,
                            acknowledgedOffset = bytes.size.toLong(),
                        )
                        journal = journal.replacing(index, artifact)
                        journalStore.save(journal)
                    } else if (status.error == GoogleDriveErrorId.FOLDER_UNAVAILABLE) {
                        // A missing resumable session is expired; restart against identical bytes/ID.
                        sessionUri = null
                        offset = 0
                    } else {
                        return CommitResult.Failed(status.error, status.retryable)
                    }
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
                        if (reconciled == null) return CommitResult.Failed(uploaded.error, uploaded.retryable)
                        artifact = journal.artifacts[index].copy(phase = GoogleDriveArtifactPhase.COMMITTED)
                        journal = journal.replacing(index, artifact)
                        journalStore.save(journal)
                    }
                }
            }
        }

        val postflight = when (val result = api.getMetadata(token, objectId, resources)) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return CommitResult.Failed(result.error.forKnownFile(), result.retryable)
        }
        if (!validManagedFile(postflight, parentId, fileName, artifact.mediaType)) {
            return CommitResult.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        if (!metadataMatchesBytes(postflight, bytes)) {
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
            val binding = when (val lookup = managedStore.lookup(destination.id, hash)) {
                GoogleDriveManagedObjectLookup.Missing -> null
                GoogleDriveManagedObjectLookup.Corrupt ->
                    return ResolveObject.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
                is GoogleDriveManagedObjectLookup.Found -> lookup.binding
            }
            val resolved = if (binding != null) {
                when (val result = api.getMetadata(token, binding.objectId, resourceKeys(destination, binding.objectId, binding.resourceKey))) {
                    is DriveApiResult.Success -> result.value
                    is DriveApiResult.Failure -> return ResolveObject.Failed(result.error.forKnownFile(), result.retryable)
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
        val binding = when (val lookup = managedStore.lookup(destination.id, artifact.relativePathHash)) {
            GoogleDriveManagedObjectLookup.Missing -> null
            GoogleDriveManagedObjectLookup.Corrupt ->
                return ResolveFile.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
            is GoogleDriveManagedObjectLookup.Found -> lookup.binding
        }
        if (binding != null) {
            val metadata = when (val result = api.getMetadata(token, binding.objectId, resourceKeys(destination, binding.objectId, binding.resourceKey))) {
                is DriveApiResult.Success -> result.value
                is DriveApiResult.Failure -> return ResolveFile.Failed(result.error.forKnownFile(), result.retryable)
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
        val parentId = artifact.parentId ?: return null
        val fileName = artifact.relativePath.substringAfterLast('/')
        return when (val result = api.getMetadata(token, id, resourceKeys(destination, id, artifact.objectResourceKey))) {
            is DriveApiResult.Success -> result.value.takeIf {
                validManagedFile(it, parentId, fileName, artifact.mediaType) && metadataMatchesBytes(it, bytes)
            }
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

    private fun GoogleDriveErrorId.forKnownFile(): GoogleDriveErrorId =
        if (this == GoogleDriveErrorId.FOLDER_UNAVAILABLE) GoogleDriveErrorId.REMOTE_CONFLICT else this

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
            error = error,
            completedArtifactCount = completed,
            retryable = retryable,
            partialCompletion = completed > 0,
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

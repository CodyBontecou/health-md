package com.healthmd.rawchanges

import android.content.Context
import com.healthmd.rawexport.HealthConnectRecordCatalog
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawIssue
import com.healthmd.rawexport.RawProviderCapabilities
import com.healthmd.rawexport.RawSnapshotManifest
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawSnapshotValidator
import com.healthmd.rawexport.RawValidationOptions
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock
import java.nio.channels.OverlappingFileLockException
import java.time.Instant
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.jsonObject

/** Backend-only API. Raw snapshots remain the default and only date-range product flow. */
interface RawChangesService {
    suspend fun append(
        scope: RawChangesScope,
        expectedChainId: String? = null,
        expectedScopeHash: String? = null,
    ): RawChangesResult

    /**
     * Strict bootstrap: token is durably checkpointed before [baseSnapshot] can run. The callback
     * must create/promote a full healthmd.raw-snapshot and index its mapped records. Catch-up is
     * drained from the pre-snapshot token before either chain state or identities are committed.
     */
    suspend fun bootstrap(scope: RawChangesScope, baseSnapshot: RawBaseSnapshotStep): RawChangesResult
}

internal enum class RawChangesDurabilityPoint { PREPARED, PROMOTED, SIDECAR_DURABLE, BEFORE_STATE_COMMIT }

internal fun interface RawChangesDurabilityHook {
    fun reached(point: RawChangesDurabilityPoint)
}

internal fun interface RawBaseSnapshotReceiptVerifier {
    fun verify(receipt: RawBaseSnapshotReceipt)
}

internal object DefaultRawBaseSnapshotReceiptVerifier : RawBaseSnapshotReceiptVerifier {
    override fun verify(receipt: RawBaseSnapshotReceipt) {
        val artifact = File(receipt.artifactPath)
        val sidecar = File(receipt.sidecarPath)
        require(artifact.isFile && sidecar.isFile) { "Base raw snapshot artifact and checksum sidecar are required." }
        require(sidecar.parentFile?.canonicalFile == artifact.parentFile?.canonicalFile) {
            "Base raw snapshot checksum sidecar must be adjacent to the artifact."
        }
        require(sidecar.name == "${artifact.name}.sha256") { "Base raw snapshot checksum sidecar name is invalid." }
        val validation = artifact.inputStream().use { input ->
            RawSnapshotValidator().validate(
                input = input,
                format = receipt.format,
                options = RawValidationOptions(
                    expectedArtifactChecksumSha256 = receipt.artifactChecksumSha256,
                    sidecarText = sidecar.readText(Charsets.UTF_8),
                    artifactFileName = artifact.name,
                ),
            )
        }
        require(
            validation.valid && validation.schema == "healthmd.raw-snapshot" && validation.majorVersion == 1 &&
                validation.artifactChecksumVerified && validation.sidecarChecksumVerified,
        ) { "Base raw snapshot artifact validation failed." }
        val header = readHeader(artifact, receipt.format)
        val manifest = readManifest(artifact, receipt.format)
        val requestedRecordTypes = when (header.request.scope) {
            com.healthmd.rawexport.RawSnapshotScope.SELECTED_RECORD_TYPES ->
                com.healthmd.rawexport.RawExportTypeCatalog.definitions
                    .filter { definition -> definition.metricIds.any(header.request.selectedMetricIds::contains) }
                    .map { it.wireType }
                    .toSet()
            com.healthmd.rawexport.RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ->
                com.healthmd.rawexport.RawExportTypeCatalog.definitions.map { it.wireType }.toSet()
        }
        require(
            header.snapshotId == receipt.snapshotId &&
                header.capabilities.providerId == "health_connect" &&
                requestedRecordTypes == receipt.recordTypeKeys,
        ) { "Base raw snapshot receipt does not match its validated request scope." }
        // Raw-snapshot v1 has no origin-filter field. An unfiltered artifact proves the empty-filter
        // scope only; scoped-origin incremental chains must wait for a versioned snapshot request.
        require(receipt.dataOriginPackageNames.isEmpty()) {
            "Base raw snapshot v1 cannot prove a data-origin-filtered scope."
        }
        require(
            manifest.snapshotId == receipt.snapshotId && manifest.status == RawSnapshotStatus.COMPLETE &&
                manifest.logicalChecksumSha256 == receipt.logicalChecksumSha256,
        ) { "Base raw snapshot receipt does not match its validated final manifest." }
    }

    private fun readHeader(
        artifact: File,
        format: com.healthmd.rawexport.RawExportFormat,
    ): com.healthmd.rawexport.RawSnapshotHeader {
        val element = when (format) {
            com.healthmd.rawexport.RawExportFormat.NDJSON -> {
                val line = artifact.bufferedReader(Charsets.UTF_8).use { it.readLine() }
                    ?: throw IllegalArgumentException("Base raw snapshot header is unavailable.")
                com.healthmd.rawexport.RawJson.codec.parseToJsonElement(line).jsonObject.getValue("header")
            }
            com.healthmd.rawexport.RawExportFormat.JSON -> {
                val marker = ",\"records\":["
                val prefix = artifact.inputStream().buffered().use { input ->
                    val bytes = java.io.ByteArrayOutputStream()
                    val buffer = ByteArray(8 * 1024)
                    var found = false
                    while (bytes.size() <= 1024 * 1024) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        bytes.write(buffer, 0, count)
                        if (bytes.toString(Charsets.UTF_8.name()).contains(marker)) {
                            found = true
                            break
                        }
                    }
                    require(found) { "Base raw snapshot header is unavailable." }
                    bytes.toString(Charsets.UTF_8.name())
                }
                val markerIndex = prefix.indexOf(marker)
                require(prefix.startsWith("{\"header\":") && markerIndex > 10) {
                    "Base raw snapshot header is unavailable."
                }
                com.healthmd.rawexport.RawJson.codec.parseToJsonElement(prefix.substring(10, markerIndex))
            }
        }
        return com.healthmd.rawexport.RawJson.codec.decodeFromJsonElement(
            com.healthmd.rawexport.RawSnapshotHeader.serializer(),
            element,
        )
    }

    private fun readManifest(artifact: File, format: com.healthmd.rawexport.RawExportFormat): RawSnapshotManifest {
        val marker = "],\"manifest\":"
        val tail: String = RandomAccessFile(artifact, "r").use { input ->
            var size = minOf(input.length(), 64L * 1024L)
            var result: String? = null
            while (result == null) {
                require(size <= Int.MAX_VALUE) { "Base raw snapshot final manifest is too large to verify." }
                val bytes = ByteArray(size.toInt())
                input.seek(input.length() - size)
                input.readFully(bytes)
                val candidate = String(bytes, Charsets.UTF_8)
                val hasCompleteManifest = when (format) {
                    com.healthmd.rawexport.RawExportFormat.JSON -> candidate.contains(marker)
                    com.healthmd.rawexport.RawExportFormat.NDJSON -> candidate.count { it == '\n' } >= 2
                }
                if (hasCompleteManifest || size == input.length()) result = candidate
                else size = minOf(input.length(), size * 2)
            }
            requireNotNull(result)
        }
        val element = when (format) {
            com.healthmd.rawexport.RawExportFormat.JSON -> {
                val index = tail.lastIndexOf(marker)
                require(index >= 0 && tail.endsWith("}")) { "Base raw snapshot final manifest is unavailable." }
                com.healthmd.rawexport.RawJson.codec.parseToJsonElement(
                    tail.substring(index + marker.length).dropLast(1),
                )
            }
            com.healthmd.rawexport.RawExportFormat.NDJSON -> {
                val line = tail.lineSequence().filter(String::isNotBlank).lastOrNull()
                    ?: throw IllegalArgumentException("Base raw snapshot final manifest is unavailable.")
                com.healthmd.rawexport.RawJson.codec.parseToJsonElement(line).jsonObject.getValue("manifest")
            }
        }
        return com.healthmd.rawexport.RawJson.codec.decodeFromJsonElement(RawSnapshotManifest.serializer(), element)
    }
}

@Singleton
class DefaultRawChangesService internal constructor(
    private val context: Context,
    private val source: RawChangesSource,
    private val state: RawChangesStateStore,
    private val destination: NoBackupRawChangesDestination,
    private val clock: () -> Instant = Instant::now,
    private val hook: RawChangesDurabilityHook = RawChangesDurabilityHook { },
    private val baseSnapshotVerifier: RawBaseSnapshotReceiptVerifier = DefaultRawBaseSnapshotReceiptVerifier,
    private val indexFactory: (File, String, (String, String) -> RawNativeIdentity?) -> RawChangesMutableIndex =
        { file, scopeHash, lookup -> RawChangesRunIndex(file, scopeHash, lookup) },
) : RawChangesService {
    override suspend fun append(
        scope: RawChangesScope,
        expectedChainId: String?,
        expectedScopeHash: String?,
    ): RawChangesResult {
        val canonical = validateScope(scope)
        val scopeHash = RawChangesCanonical.scopeHash(canonical)
        return serialized(scopeHash) {
            try {
                if (expectedScopeHash != null && expectedScopeHash != scopeHash) {
                    return@serialized RawChangesResult.ScopeMismatch(expectedScopeHash, scopeHash)
                }
                recover(scopeHash)
                garbageCollectStaleCheckpoints()
                val chain = state.load(scopeHash) ?: return@serialized RawChangesResult.BootstrapRequired(scopeHash)
                if (chain.scopeJson != RawChangesCanonical.scopeJson(canonical)) {
                    return@serialized RawChangesResult.ScopeMismatch(chain.scopeHash, scopeHash)
                }
                if (expectedChainId != null && expectedChainId != chain.chainId) {
                    return@serialized RawChangesResult.ScopeMismatch(chain.scopeHash, scopeHash)
                }
                val capabilities = source.capabilities()
                unavailableScope(canonical, capabilities)?.let { return@serialized it }
                runArchive(canonical, chain, chain.token, null, capabilities)
            } catch (_: RawChangesStateConflictException) {
                RawChangesResult.Conflict(scopeHash)
            }
        }
    }

    override suspend fun bootstrap(scope: RawChangesScope, baseSnapshot: RawBaseSnapshotStep): RawChangesResult {
        val canonical = validateScope(scope)
        val scopeHash = RawChangesCanonical.scopeHash(canonical)
        return serialized(scopeHash) {
            try {
                recover(scopeHash)
                garbageCollectStaleCheckpoints()
                val capabilities = source.capabilities()
                unavailableScope(canonical, capabilities)?.let { return@serialized it }
                // Required ordering: token creation/checkpointing occurs before callback entry.
                val token = try {
                    source.createToken(canonical)
                } catch (unavailable: RawChangesUnavailableScopeException) {
                    return@serialized RawChangesResult.UnavailableScope(
                        unavailable.recordTypeKeys.sorted(),
                        unavailable.requiredFeatures.sorted(),
                    )
                }
                val generated = clock()
                val predecessor = state.load(scopeHash)
                val pending = newPending(
                    scopeHash = scopeHash,
                    chainId = UUID.randomUUID().toString(),
                    sequence = 1,
                    previousHash = null,
                    expectedState = predecessor,
                    created = clock(),
                    tokenGenerated = generated,
                    generatedBeforeBase = true,
                )
                executePending(pending, token) { runIndex ->
                    val receipt = baseSnapshot.create(runIndex)
                    validateBaseSnapshotReceipt(canonical, receipt)
                    runArchiveBody(canonical, pending, token, runIndex, capabilities)
                }
            } catch (_: RawChangesStateConflictException) {
                RawChangesResult.Conflict(scopeHash)
            }
        }
    }

    private suspend fun runArchive(
        scope: RawChangesScope,
        chain: RawChangesChainState,
        token: SecretChangesToken,
        existingIndex: RawChangesMutableIndex?,
        capabilities: RawProviderCapabilities,
    ): RawChangesResult {
        val created = clock()
        val pending = newPending(
            scopeHash = chain.scopeHash,
            chainId = chain.chainId,
            sequence = chain.sequence + 1,
            previousHash = chain.previousLogicalHash,
            expectedState = chain,
            created = created,
            tokenGenerated = Instant.ofEpochSecond(chain.tokenGeneratedAtEpochSecond, chain.tokenGeneratedAtNano.toLong()),
            generatedBeforeBase = chain.tokenGeneratedBeforeBase,
        )
        return executePending(pending, token, existingIndex) { runIndex ->
            runArchiveBody(scope, pending, token, runIndex, capabilities)
        }
    }

    private suspend fun executePending(
        pending: PendingArchive,
        initialToken: SecretChangesToken,
        existingIndex: RawChangesMutableIndex? = null,
        block: suspend (RawChangesMutableIndex) -> RawChangesResult,
    ): RawChangesResult {
        val workDirectory = requireNotNull(File(pending.workDatabasePath).parentFile).apply { mkdirs() }
        val guard = CheckpointRunGuard.tryAcquire(workDirectory) ?: throw RawChangesStateConflictException()
        var runIndex: RawChangesMutableIndex? = null
        try {
            state.beginPending(pending, initialToken)
            runIndex = existingIndex ?: indexFactory(File(pending.workDatabasePath), pending.scopeHash) { scopeHash, id ->
                if (pending.sequence == 1L) null else state.identity(scopeHash, id)
            }
            return block(runIndex)
        } catch (cancelled: CancellationException) {
            discardUnpromoted(pending)
            throw cancelled
        } catch (error: Throwable) {
            preserveIfPreparedOtherwiseDiscard(pending)
            throw error
        } finally {
            runIndex?.close()
            guard.close()
            if (state.pending(pending.scopeHash)?.archiveId != pending.archiveId) workDirectory.deleteRecursively()
        }
    }

    private suspend fun runArchiveBody(
        scope: RawChangesScope,
        pending: PendingArchive,
        initialToken: SecretChangesToken,
        runIndex: RawChangesMutableIndex,
        capabilities: RawProviderCapabilities,
    ): RawChangesResult {
        val workDirectory = requireNotNull(File(pending.workDatabasePath).parentFile).apply { mkdirs() }
        val spool = RawChangesEventSpool(File(workDirectory, "events.ndjson"))
        val accounting = RawChangesAccounting()
        val observed = Instant.ofEpochSecond(pending.createdEpochSecond, pending.createdNano.toLong())
        var ordinal = 0L
        var token = initialToken
        var nextToken: SecretChangesToken? = null
        var nextTokenReceivedAt: Instant? = null
        try {
            while (true) {
                val page = source.getChanges(token)
                val pageReceivedAt = clock()
                accounting.pageCount++
                if (page.tokenExpired) {
                    spool.close()
                    discardUnpromoted(pending)
                    return RawChangesResult.RebaseRequired(
                        chainId = state.load(pending.scopeHash)?.chainId,
                        scopeHash = pending.scopeHash,
                    )
                }
                page.changes.forEach { change ->
                    currentCoroutineContext().ensureActive()
                    val event = when (change) {
                        is NativeChange.Upsert -> {
                            runIndex.upsert(change.record)
                            accounting.upsertionCount++
                            accounting.upsertsByType.increment(change.record.wireType)
                            RawChangesCanonical.signed(RawChangeEvent.Upsertion(++ordinal, change.record, ""))
                        }
                        is NativeChange.Delete -> {
                            val known = runIndex.delete(change.nativeRecordId)
                            accounting.deletionCount++
                            if (known == null) accounting.unknownDeletionCount++
                            else accounting.deletionsByType.increment(known.wireType)
                            RawChangesCanonical.signed(
                                RawChangeEvent.Deletion(
                                    ordinal = ++ordinal,
                                    nativeRecordId = change.nativeRecordId,
                                    wireType = known?.wireType,
                                    typeKey = known?.typeKey,
                                    dataOriginPackageName = known?.dataOriginPackageName,
                                    lastKnownRecordHash = known?.lastKnownRecordHash,
                                    observedAt = RawInstant(observed.epochSecond, observed.nano),
                                    eventHash = "",
                                ),
                            )
                        }
                    }
                    spool.append(event)
                    accounting.eventCount++
                }
                val pageNext = requireNotNull(page.nextToken) { "Health Connect changes page omitted its continuation checkpoint." }
                nextToken = pageNext
                nextTokenReceivedAt = pageReceivedAt
                if (!page.hasMore) break
                require(pageNext != token) { "Health Connect changes pagination did not advance." }
                token = pageNext
            }
            spool.durableClose()
            val created = Instant.ofEpochSecond(pending.createdEpochSecond, pending.createdNano.toLong())
            val header = RawChangesHeader(
                archiveId = pending.archiveId,
                chainId = pending.chainId,
                sequence = pending.sequence,
                previousArchiveLogicalHash = pending.previousLogicalHash,
                scopeHash = pending.scopeHash,
                recordTypeKeys = scope.recordTypeKeys.sorted(),
                dataOriginPackageNames = scope.dataOriginPackageNames.sorted(),
                createdAt = RawInstant(created.epochSecond, created.nano),
                capabilities = capabilities.copy(
                    grantedPermissions = capabilities.grantedPermissions.toSortedSet(),
                    availableFeatures = capabilities.availableFeatures.toSortedSet(),
                ),
                tokenSemantics = RawChangesTokenSemantics(
                    generatedAt = RawInstant(pending.tokenGeneratedAtEpochSecond, pending.tokenGeneratedAtNano),
                    generatedBeforeBaseSnapshot = pending.tokenGeneratedBeforeBase,
                ),
            )
            val (partial, final) = destination.files(pending.archiveId)
            val prepared = RawChangesArtifactWriter().write(
                header = header,
                completedAt = clock(),
                spool = spool,
                issues = emptyList<RawIssue>(),
                accounting = accounting,
                capabilities = capabilities,
                partialFile = partial,
                finalFile = final,
            )
            state.prepared(pending, final.absolutePath, prepared.logicalHash, prepared.artifactHash)
            hook.reached(RawChangesDurabilityPoint.PREPARED)
            val promoted = destination.promote(prepared)
            state.markPromoted(pending)
            hook.reached(RawChangesDurabilityPoint.PROMOTED)
            val sidecar = destination.writeSidecar(promoted, prepared.artifactHash)
            state.markSidecarDurable(pending, sidecar.absolutePath)
            hook.reached(RawChangesDurabilityPoint.SIDECAR_DURABLE)

            val committedPending = requireNotNull(state.pending(pending.scopeHash))
            withContext(NonCancellable) {
                hook.reached(RawChangesDurabilityPoint.BEFORE_STATE_COMMIT)
                val receivedAt = requireNotNull(nextTokenReceivedAt)
                state.commit(
                    committedPending,
                    RawChangesCanonical.scopeJson(scope),
                    requireNotNull(nextToken),
                    receivedAt.epochSecond,
                    receivedAt.nano,
                    runIndex.mutations(),
                )
            }
            return RawChangesResult.Complete(
                RawChangesArchiveResult(
                    archiveId = pending.archiveId,
                    chainId = pending.chainId,
                    sequence = pending.sequence,
                    location = promoted.absolutePath,
                    logicalChecksumSha256 = prepared.logicalHash,
                    artifactChecksumSha256 = prepared.artifactHash,
                    bytesWritten = prepared.bytesWritten,
                ),
            )
        } finally {
            spool.close()
        }
    }

    /**
     * Detects an interrupted archive by ID/hash. Because nextChangesToken is deliberately never
     * checkpointed before the final state transaction, an interrupted run is not committed here:
     * the prior token is reread and the changes are replayed at least once.
     */
    private fun recover(scopeHash: String) {
        var pending = state.pending(scopeHash) ?: return
        val workDirectory = requireNotNull(File(pending.workDatabasePath).parentFile)
        val guard = CheckpointRunGuard.tryAcquire(workDirectory) ?: throw RawChangesStateConflictException()
        try {
            if (pending.phase != PendingPhase.READING) {
                val expectedHash = requireNotNull(pending.artifactHash)
                val final = destination.finalFile(pending.archiveId)
                if (final.exists()) {
                    final.inputStream().use {
                        require(com.healthmd.rawexport.RawJson.sha256(it) == expectedHash) {
                            "Promoted incremental archive checksum mismatch."
                        }
                    }
                    destination.makeFileAndParentDurable(final)
                    if (pending.phase == PendingPhase.PREPARED) {
                        state.markPromoted(pending)
                        pending = requireNotNull(state.pending(scopeHash))
                    }
                    val sidecar = destination.writeSidecar(final, expectedHash)
                    if (pending.phase == PendingPhase.PROMOTED) {
                        state.markSidecarDurable(pending, sidecar.absolutePath)
                        pending = requireNotNull(state.pending(scopeHash))
                    }
                }
            }
            // Promoted files remain immutable orphaned evidence, but cannot advance chain state.
            destination.removePartial(pending.archiveId)
            state.discardPending(pending)
        } finally {
            guard.close()
            if (state.pending(scopeHash)?.archiveId != pending.archiveId) workDirectory.deleteRecursively()
        }
    }

    private fun newPending(
        scopeHash: String,
        chainId: String,
        sequence: Long,
        previousHash: String?,
        expectedState: RawChangesChainState?,
        created: Instant,
        tokenGenerated: Instant,
        generatedBeforeBase: Boolean,
    ): PendingArchive {
        val archiveId = com.healthmd.rawexport.RawJson.sha256(
            "healthmd.raw-changes.v1\n$chainId\n$sequence\n$scopeHash\n${created.epochSecond}:${created.nano}",
        ).take(32)
        val work = File(context.noBackupFilesDir, "raw-changes/checkpoints/$archiveId/run-index.db")
        work.parentFile?.mkdirs()
        return PendingArchive(
            scopeHash, archiveId, chainId, sequence, previousHash,
            expectedState?.chainId, expectedState?.sequence, expectedState?.previousLogicalHash,
            created.epochSecond, created.nano, work.absolutePath, null, null, null, null, PendingPhase.READING,
            tokenGenerated.epochSecond, tokenGenerated.nano, generatedBeforeBase,
        )
    }

    private fun validateScope(scope: RawChangesScope): RawChangesScope {
        val canonical = scope.canonical()
        val eligible = HealthConnectRecordCatalog.records.filter { it.changeEligible }.map { it.wireType }.toSet()
        require(canonical.recordTypeKeys.all(eligible::contains)) {
            "Incremental scope may contain only explicit Health Connect Record types; PHR and cloud data are unsupported."
        }
        return canonical
    }

    private fun unavailableScope(
        scope: RawChangesScope,
        capabilities: RawProviderCapabilities,
    ): RawChangesResult.UnavailableScope? {
        val selected = HealthConnectRecordCatalog.records.filter { it.wireType in scope.recordTypeKeys }
        val featureUnavailable = selected.filter { descriptor ->
            descriptor.featureName != null && descriptor.featureName !in capabilities.availableFeatures
        }
        if (capabilities.available && featureUnavailable.isEmpty()) return null
        val unavailableTypes = if (capabilities.available) featureUnavailable else selected
        return RawChangesResult.UnavailableScope(
            recordTypeKeys = unavailableTypes.map { it.wireType }.sorted(),
            requiredFeatures = unavailableTypes.mapNotNull { it.featureName }.distinct().sorted(),
            providerUnavailable = !capabilities.available,
        )
    }

    private fun validateBaseSnapshotReceipt(scope: RawChangesScope, receipt: RawBaseSnapshotReceipt) {
        require(receipt.schema == "healthmd.raw-snapshot" && receipt.version == 1) {
            "Base snapshot receipt must identify healthmd.raw-snapshot v1."
        }
        require(receipt.status == RawSnapshotStatus.COMPLETE) { "Base raw snapshot must be COMPLETE." }
        require(receipt.recordTypeKeys.toSortedSet() == scope.recordTypeKeys.toSortedSet()) {
            "Base raw snapshot record-type scope does not match the incremental scope."
        }
        require(receipt.dataOriginPackageNames.toSortedSet() == scope.dataOriginPackageNames.toSortedSet()) {
            "Base raw snapshot origin scope does not match the incremental scope."
        }
        require(receipt.historicalCoverage == RawBaseHistoricalCoverage.UNBOUNDED_ALL_READABLE_WITHIN_SCOPE) {
            "Base raw snapshot must cover all readable history without a date range."
        }
        baseSnapshotVerifier.verify(receipt)
    }

    internal fun garbageCollectStaleCheckpoints() {
        val root = File(context.noBackupFilesDir, "raw-changes/checkpoints")
        val referenced = state.allPending().mapNotNull { File(it.workDatabasePath).parentFile?.canonicalPath }.toSet()
        root.listFiles().orEmpty().filter(File::isDirectory).forEach { directory ->
            if (directory.canonicalPath !in referenced) {
                val guard = CheckpointRunGuard.tryAcquire(directory) ?: return@forEach
                guard.close()
                directory.deleteRecursively()
            }
        }
    }

    private fun preserveIfPreparedOtherwiseDiscard(pending: PendingArchive) {
        val actual = state.pending(pending.scopeHash)
        if (actual?.archiveId == pending.archiveId && actual.phase == PendingPhase.READING) discardUnpromoted(pending)
    }

    private fun discardUnpromoted(pending: PendingArchive) {
        destination.removePartial(pending.archiveId)
        if (state.pending(pending.scopeHash)?.archiveId == pending.archiveId) state.discardPending(pending)
    }

    private suspend fun serialized(scopeHash: String, block: suspend () -> RawChangesResult): RawChangesResult {
        val mutex = scopeMutexes.computeIfAbsent(scopeHash) { Mutex() }
        mutex.lock()
        return try {
            block()
        } finally {
            mutex.unlock()
        }
    }

    private fun MutableMap<String, Long>.increment(key: String) {
        this[key] = (this[key] ?: 0L) + 1
    }

    companion object {
        private val scopeMutexes = ConcurrentHashMap<String, Mutex>()
    }
}

private class CheckpointRunGuard private constructor(
    private val file: RandomAccessFile,
    private val lock: FileLock,
) : AutoCloseable {
    override fun close() {
        lock.release()
        file.close()
    }

    companion object {
        fun tryAcquire(directory: File): CheckpointRunGuard? {
            directory.mkdirs()
            val file = RandomAccessFile(File(directory, ".active.lock"), "rw")
            val lock = try {
                file.channel.tryLock()
            } catch (_: OverlappingFileLockException) {
                null
            } catch (error: Throwable) {
                file.close()
                throw error
            }
            if (lock == null) {
                file.close()
                return null
            }
            return CheckpointRunGuard(file, lock)
        }
    }
}

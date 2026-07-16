package com.healthmd.rawchanges

import android.content.Context
import com.healthmd.rawexport.HealthConnectRecordCatalog
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawIssue
import com.healthmd.rawexport.RawProviderCapabilities
import java.io.File
import java.time.Instant
import java.util.UUID
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

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

@Singleton
class DefaultRawChangesService internal constructor(
    private val context: Context,
    private val source: RawChangesSource,
    private val state: RawChangesStateStore,
    private val destination: NoBackupRawChangesDestination,
    private val clock: () -> Instant = Instant::now,
    private val hook: RawChangesDurabilityHook = RawChangesDurabilityHook { },
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
        if (expectedScopeHash != null && expectedScopeHash != scopeHash) {
            return RawChangesResult.ScopeMismatch(expectedScopeHash, scopeHash)
        }
        recover(scopeHash)
        val chain = state.load(scopeHash) ?: return RawChangesResult.BootstrapRequired(scopeHash)
        if (chain.scopeJson != RawChangesCanonical.scopeJson(canonical)) {
            return RawChangesResult.ScopeMismatch(chain.scopeHash, scopeHash)
        }
        if (expectedChainId != null && expectedChainId != chain.chainId) {
            return RawChangesResult.ScopeMismatch(chain.scopeHash, scopeHash)
        }
        val capabilities = source.capabilities()
        unavailableScope(canonical, capabilities)?.let { return it }
        return runArchive(canonical, chain, chain.token, null, capabilities)
    }

    override suspend fun bootstrap(scope: RawChangesScope, baseSnapshot: RawBaseSnapshotStep): RawChangesResult {
        val canonical = validateScope(scope)
        val scopeHash = RawChangesCanonical.scopeHash(canonical)
        recover(scopeHash)
        val capabilities = source.capabilities()
        unavailableScope(canonical, capabilities)?.let { return it }
        val generated = clock()
        // Required ordering: token creation/checkpointing occurs before callback entry.
        val token = try {
            source.createToken(canonical)
        } catch (unavailable: RawChangesUnavailableScopeException) {
            return RawChangesResult.UnavailableScope(
                unavailable.recordTypeKeys.sorted(),
                unavailable.requiredFeatures.sorted(),
            )
        }
        val chainId = UUID.randomUUID().toString()
        val created = clock()
        val pending = newPending(
            scopeHash = scopeHash,
            chainId = chainId,
            sequence = 1,
            previousHash = null,
            created = created,
            tokenGenerated = generated,
            generatedBeforeBase = true,
        )
        state.beginPending(pending, token)
        val workFile = File(pending.workDatabasePath)
        // Sequence 1 is a new chain/rebase. It must never resolve tombstones through identities
        // committed by an older chain with the same scope hash.
        val runIndex = indexFactory(workFile, scopeHash) { _, _ -> null }
        return try {
            val receipt = baseSnapshot.create(runIndex)
            require(receipt.durable) { "Base raw snapshot must be durable before incremental catch-up." }
            runArchiveBody(canonical, pending, token, runIndex, capabilities)
        } catch (cancelled: CancellationException) {
            runIndex.close()
            discardUnpromoted(pending)
            throw cancelled
        } catch (error: Throwable) {
            runIndex.close()
            preserveIfPreparedOtherwiseDiscard(pending)
            throw error
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
            created = created,
            tokenGenerated = Instant.ofEpochSecond(chain.tokenGeneratedAtEpochSecond, chain.tokenGeneratedAtNano.toLong()),
            generatedBeforeBase = chain.tokenGeneratedBeforeBase,
        )
        state.beginPending(pending, token)
        val runIndex = existingIndex ?: indexFactory(File(pending.workDatabasePath), chain.scopeHash, state::identity)
        return try {
            runArchiveBody(scope, pending, token, runIndex, capabilities)
        } catch (cancelled: CancellationException) {
            runIndex.close()
            discardUnpromoted(pending)
            throw cancelled
        } catch (error: Throwable) {
            runIndex.close()
            preserveIfPreparedOtherwiseDiscard(pending)
            throw error
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
        try {
            while (true) {
                val page = source.getChanges(token)
                accounting.pageCount++
                if (page.tokenExpired) {
                    spool.close()
                    runIndex.close()
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
            state.prepared(pending.scopeHash, final.absolutePath, prepared.logicalHash, prepared.artifactHash)
            hook.reached(RawChangesDurabilityPoint.PREPARED)
            val promoted = destination.promote(prepared)
            state.markPromoted(pending.scopeHash)
            hook.reached(RawChangesDurabilityPoint.PROMOTED)
            val sidecar = destination.writeSidecar(promoted, prepared.artifactHash)
            state.markSidecarDurable(pending.scopeHash, sidecar.absolutePath)
            hook.reached(RawChangesDurabilityPoint.SIDECAR_DURABLE)

            val committedPending = requireNotNull(state.pending(pending.scopeHash))
            withContext(NonCancellable) {
                hook.reached(RawChangesDurabilityPoint.BEFORE_STATE_COMMIT)
                state.commit(
                    committedPending,
                    RawChangesCanonical.scopeJson(scope),
                    requireNotNull(nextToken),
                    runIndex.mutations(),
                )
            }
            runIndex.close()
            workDirectory.deleteRecursively()
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
        val pending = state.pending(scopeHash) ?: return
        if (pending.phase != PendingPhase.READING) {
            val expectedHash = requireNotNull(pending.artifactHash)
            val final = destination.finalFile(pending.archiveId)
            if (final.exists()) {
                final.inputStream().use {
                    require(com.healthmd.rawexport.RawJson.sha256(it) == expectedHash) {
                        "Promoted incremental archive checksum mismatch."
                    }
                }
                destination.writeSidecar(final, expectedHash)
            }
        }
        // PREPARED partials are not consumer artifacts. Promoted files remain immutable orphaned
        // evidence, but cannot advance chain state. The caller now rereads the prior token.
        destination.removePartial(pending.archiveId)
        File(pending.workDatabasePath).parentFile?.deleteRecursively()
        state.discardPending(scopeHash)
    }

    private fun newPending(
        scopeHash: String,
        chainId: String,
        sequence: Long,
        previousHash: String?,
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
            scopeHash, archiveId, chainId, sequence, previousHash, created.epochSecond, created.nano,
            work.absolutePath, null, null, null, null, PendingPhase.READING,
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

    private fun preserveIfPreparedOtherwiseDiscard(pending: PendingArchive) {
        if (state.pending(pending.scopeHash)?.phase == PendingPhase.READING) discardUnpromoted(pending)
    }

    private fun discardUnpromoted(pending: PendingArchive) {
        destination.removePartial(pending.archiveId)
        File(pending.workDatabasePath).parentFile?.deleteRecursively()
        state.discardPending(pending.scopeHash)
    }

    private fun MutableMap<String, Long>.increment(key: String) {
        this[key] = (this[key] ?: 0L) + 1
    }
}

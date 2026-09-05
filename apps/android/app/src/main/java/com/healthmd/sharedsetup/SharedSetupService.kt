package com.healthmd.sharedsetup

import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Shared Setup v2-only facade.
 *
 * The pre-canonical v1 preview/apply/undo/export paths and their single-profile settings
 * transaction were removed with the v1 contract; production reads, writes, applies, and undoes
 * Shared Setup v2 exclusively. The v1-era repository rollback/pending-endpoint machinery was
 * removed with them (the stale `shared_setup_pending_endpoint_v1` DataStore key is now unread
 * and is deliberately not migrated).
 */
@Singleton
class SharedSetupService private constructor(
    private val versionedCodec: SharedSetupV2Codec,
    private val v2Mapper: SharedSetupV2Mapper,
) {
    @Inject
    constructor() : this(AndroidSharedSetupMetricRegistry())

    internal constructor(
        registry: SharedSetupMetricRegistry,
    ) : this(
        SharedSetupV2Codec(registry),
        SharedSetupV2Mapper(registry),
    )

    private val transactionMutex = Mutex()

    /**
     * Production v2 writer path. The source supplies ordered repository rows, active identity,
     * schedules, app version, and transaction-owned preserved foreign extensions.
     */
    suspend fun exportV2Bytes(source: SharedSetupV2ExportSource): ByteArray =
        exportV2Bytes(source.load())

    suspend fun exportV2Bytes(context: SharedSetupV2ExportContext): ByteArray {
        val document = v2Mapper.export(
            profiles = context.profiles,
            activeProfileId = context.activeProfileId,
            schedules = context.schedules,
            appVersion = context.appVersion,
            preservedAppleExtensionsByProfileId = context.preservedAppleExtensionsByProfileId,
        )
        return versionedCodec.encode(document)
    }

    /** Bounded strict version dispatch and compatibility analysis only; this performs zero writes. */
    suspend fun previewVersioned(bytes: ByteArray): Result<SharedSetupV2ImportPlan> =
        when (val decoded = versionedCodec.decode(bytes)) {
            is SharedSetupVersionedDecodeResult.Invalid ->
                Result.failure(IllegalArgumentException(decoded.message))
            is SharedSetupVersionedDecodeResult.Valid -> runCatching {
                v2Mapper.planImport(decoded.document)
            }
        }

    /**
     * Validates an untampered v2 plan and selection before invoking the post-merge transaction.
     * There is no default callback, so callers must pass an explicit transaction adapter.
     */
    suspend fun applyV2(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIds: List<String>,
        mode: SharedSetupV2ApplyMode,
        callback: SharedSetupV2ApplyCallback,
    ): Result<SharedSetupV2ApplyResult> = transactionMutex.withLock {
        withContext(NonCancellable) {
            val request = runCatching {
                val regenerated = v2Mapper.planImport(plan.source)
                require(regenerated == plan) {
                    "The Shared Setup v2 import plan changed after review. Review it again."
                }
                require(plan.compatibility.none { it.status == SharedSetupV2CompatibilityStatus.INVALID }) {
                    "An invalid Shared Setup v2 plan cannot be applied."
                }
                SharedSetupV2ApplyRequest(
                    plan = regenerated,
                    selectedBundleIds = normalizedV2Selection(regenerated, selectedBundleIds),
                    mode = mode,
                )
            }.getOrElse { return@withContext Result.failure(it) }

            val callbackResult = runCatching { callback.apply(request) }
                .getOrElse { return@withContext Result.failure(it) }
            callbackResult.map {
                SharedSetupV2ApplyResult(
                    selectedBundleIds = request.selectedBundleIds,
                    mode = request.mode,
                    canUndo = true,
                )
            }
        }
    }

    /** Explicit one-shot v2 Undo handoff to the injected transaction adapter. */
    suspend fun undoV2(callback: SharedSetupV2UndoCallback): Result<SharedSetupV2UndoResult> =
        transactionMutex.withLock {
            withContext(NonCancellable) {
                val callbackResult = runCatching { callback.undo() }
                    .getOrElse { return@withContext Result.failure(it) }
                callbackResult.map { SharedSetupV2UndoResult(didUndo = true) }
            }
        }

    private fun normalizedV2Selection(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIds: List<String>,
    ): List<String> {
        require(selectedBundleIds.isNotEmpty()) { "Select at least one Shared Setup v2 profile." }
        require(selectedBundleIds.size == selectedBundleIds.distinct().size) {
            "Shared Setup v2 profile selection contains duplicates."
        }
        val sourceOrder = plan.profiles.map { it.bundleId }
        val selected = selectedBundleIds.toSet()
        require(selected.all(sourceOrder::contains)) {
            "Shared Setup v2 profile selection contains an unknown bundle ID."
        }
        return sourceOrder.filter(selected::contains)
    }
}

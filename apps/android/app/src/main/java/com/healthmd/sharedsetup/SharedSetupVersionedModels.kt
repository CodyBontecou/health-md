package com.healthmd.sharedsetup

import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportProfile

/** A decode-specific v2 import plan; the pre-canonical v1 preview model was removed with v1. */

/**
 * Complete native inputs for the closed Shared Setup v2 writer.
 *
 * The profile rows stay in repository order. Native IDs exist only for mapper joins and are never
 * serialized. The preserved-extension map is supplied by the transaction/storage integration so
 * this IO lane never reaches into, guesses, or directly serializes DataStore state.
 */
data class SharedSetupV2ExportContext(
    val profiles: List<ExportProfile>,
    val activeProfileId: String?,
    val schedules: List<ScheduledProfileEntry>,
    val appVersion: String,
    val preservedAppleExtensionsByProfileId: Map<String, SharedSetupV2AppleExtension>,
) {
    init {
        require(appVersion.isNotBlank()) { "The app version is required for Shared Setup v2." }
        require(appVersion.length <= 256) { "The app version is too long for Shared Setup v2." }
        val profileIDs = profiles.map { it.id }.toSet()
        require(preservedAppleExtensionsByProfileId.keys.all(profileIDs::contains)) {
            "A preserved Apple extension does not belong to an exported profile."
        }
    }
}

/** Deferred source seam; no v2 writer is installed as the production default. */
fun interface SharedSetupV2ExportSource {
    suspend fun load(): SharedSetupV2ExportContext
}

/**
 * Narrow repository adapter for the production v2 writer.
 *
 * The extension loader is deliberately mandatory: a caller must read the transaction lane's
 * per-profile preservation state rather than silently dropping foreign typed extensions.
 */
class RepositorySharedSetupV2ExportSource(
    private val profileRepository: ExportProfileRepository,
    private val scheduledProfileEntryStore: ScheduledProfileEntryStore,
    private val appVersion: String,
    private val preservedAppleExtensions: suspend () -> Map<String, SharedSetupV2AppleExtension>,
) : SharedSetupV2ExportSource {
    override suspend fun load(): SharedSetupV2ExportContext = SharedSetupV2ExportContext(
        profiles = profileRepository.getProfiles(),
        activeProfileId = profileRepository.getActiveProfileId(),
        schedules = scheduledProfileEntryStore.getEntries(),
        appVersion = appVersion,
        preservedAppleExtensionsByProfileId = preservedAppleExtensions(),
    )
}

enum class SharedSetupV2ApplyMode { ADD, REPLACE }

/** Selection is normalized into source-document order before this request reaches an adapter. */
data class SharedSetupV2ApplyRequest(
    val plan: SharedSetupV2ImportPlan,
    val selectedBundleIds: List<String>,
    val mode: SharedSetupV2ApplyMode,
)

/** Explicit transaction seam. There is intentionally no default production implementation. */
fun interface SharedSetupV2ApplyCallback {
    suspend fun apply(request: SharedSetupV2ApplyRequest): Result<Unit>
}

/** Explicit one-shot Undo seam. There is intentionally no default production implementation. */
fun interface SharedSetupV2UndoCallback {
    suspend fun undo(): Result<Unit>
}

data class SharedSetupV2ApplyResult(
    val selectedBundleIds: List<String>,
    val mode: SharedSetupV2ApplyMode,
    val canUndo: Boolean = true,
)

data class SharedSetupV2UndoResult(val didUndo: Boolean = true)

/** Separate state for post-merge v2 UI; the current v1 screen remains unchanged. */
sealed interface SharedSetupV2TransactionState {
    data object Idle : SharedSetupV2TransactionState
    data object Applying : SharedSetupV2TransactionState
    data class Applied(val result: SharedSetupV2ApplyResult) : SharedSetupV2TransactionState
    data object Undoing : SharedSetupV2TransactionState
    data class Undone(val result: SharedSetupV2UndoResult) : SharedSetupV2TransactionState
    data class Error(val message: String) : SharedSetupV2TransactionState
}

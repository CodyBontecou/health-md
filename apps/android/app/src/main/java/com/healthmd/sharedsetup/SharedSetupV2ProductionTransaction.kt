package com.healthmd.sharedsetup

import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportTarget
import javax.inject.Inject
import javax.inject.Singleton

/** One imported profile still blocked pending an explicit local destination rebind. */
data class SharedSetupV2BlockedImportedProfile(
    val profileId: String,
    val name: String,
    val sourceDestinationKind: String,
    /**
     * The imported API endpoint URL retained by the v2 import, already normalized — exactly
     * what an in-flow endpoint confirmation would bind and show. Null unless the sidecar
     * retains an exact `api_endpoint` hint (fail closed, never guessed).
     */
    val importedApiEndpointUrl: String? = null,
    /**
     * The profile's current local endpoint binding (editor save or prior in-flow endpoint
     * confirmation). Null while the destination is still unbound, in which case the review
     * row offers the explicit in-flow URL confirmation instead of credential entry.
     */
    val boundApiEndpointUrl: String? = null,
)

/**
 * Production Shared Setup v2 transaction adapter.
 *
 * Implements the explicit cycle-2 service seams
 * ([SharedSetupV2ApplyCallback]/[SharedSetupV2UndoCallback]) over the single
 * [SharedSetupV2ProfileTransaction] singleton, which owns the one-edit Add/Replace candidate,
 * compare-and-set verification, rollback, the bounded 4 MiB sidecar and 8 MiB one-shot Undo
 * snapshot, and the blocked-ID bookkeeping. The service still requires every caller to pass a
 * callback explicitly; this class is the only production implementation and contains no
 * credential, network, scheduler, or destination access beyond the repository rebind path below.
 *
 * The per-profile Apple-extension loader is mandatory (contract: "A local transaction sidecar
 * may associate a source bundle ID with a separately generated native ID only to preserve the
 * source DTO"). It reads the bounded sidecar through
 * [SharedSetupV2ProfileTransaction.storedProfileState] — the same typed persistence the
 * transaction gates use — instead of re-reading raw DataStore state, and fails closed when the
 * sidecar cannot be decoded so a writer can never silently drop a preserved foreign extension.
 */
@Singleton
class SharedSetupV2ProductionTransaction @Inject constructor(
    private val transaction: SharedSetupV2ProfileTransaction,
    private val profileRepository: ExportProfileRepository,
    private val profileCoordinator: ExportProfileCoordinator,
) : SharedSetupV2ApplyCallback, SharedSetupV2UndoCallback {

    override suspend fun apply(request: SharedSetupV2ApplyRequest): Result<Unit> =
        transaction.apply(
            plan = request.plan,
            selectedBundleIds = request.selectedBundleIds,
            mode = when (request.mode) {
                SharedSetupV2ApplyMode.ADD -> SharedSetupV2ProfileImportMode.ADD
                SharedSetupV2ApplyMode.REPLACE -> SharedSetupV2ProfileImportMode.REPLACE
            },
        ).map { }

    override suspend fun undo(): Result<Unit> = transaction.undo().map { }

    /**
     * Mandatory per-profile preserved Apple-extension loader for the explicit v2 writer path
     * ([RepositorySharedSetupV2ExportSource]). Keys are native profile IDs; values are the exact
     * foreign typed extensions retained in the sidecar rows, never approximated defaults.
     */
    suspend fun preservedAppleExtensionsByProfileId(): Map<String, SharedSetupV2AppleExtension> =
        transaction.storedProfileState().getOrThrow()
            ?.profiles
            .orEmpty()
            .mapNotNull { row ->
                row.sourceProfile.platformExtensions.apple?.let { extension ->
                    row.profileId to extension
                }
            }
            .toMap()

    /**
     * Blocked imported-profile visibility for the post-apply review UI, in native profile-store
     * order. Fails closed when the sidecar cannot be read rather than guessing intent.
     */
    suspend fun blockedImportedProfiles(): List<SharedSetupV2BlockedImportedProfile> {
        val blocked = transaction.blockedProfileIds()
        if (blocked.isEmpty()) return emptyList()
        val sidecarState = transaction.storedProfileState().getOrThrow()
        val sidecarRows = sidecarState?.profiles.orEmpty()
        return profileRepository.getProfiles()
            .filter { it.id in blocked }
            .map { profile ->
                SharedSetupV2BlockedImportedProfile(
                    profileId = profile.id,
                    name = profile.name,
                    sourceDestinationKind = sidecarRows
                        .singleOrNull { it.profileId == profile.id }
                        ?.sourceProfile
                        ?.destination
                        ?.kind
                        ?: "unknown",
                    importedApiEndpointUrl = SharedSetupV2ProfilePersistence.retainedApiEndpointUrl(
                        sidecarState,
                        profile.id,
                    ),
                    boundApiEndpointUrl = profile.apiEndpointUrl
                        ?.takeIf { profile.target == ExportTarget.API_ENDPOINT },
                )
            }
    }

    /**
     * Explicit local folder rebind for one blocked imported profile, using the existing
     * blocked-state/rebind-clearing APIs. The repository [ExportProfileRepository.bindFolder]
     * clears a block only for a concrete SAF selection whose sidecar source destination kind is
     * exactly `device_folder`; API, connected-Mac, and cloud intent stay blocked here.
     *
     * The active profile routes through [ExportProfileCoordinator.folderWasSelected], which
     * stages the imported snapshot onto live settings before the block can clear and rolls live
     * settings back when the rebind does not clear the block. Non-active profiles bind directly.
     * Returns whether the profile's pending-destination block is gone after the attempt.
     */
    suspend fun rebindBlockedFolder(
        profileId: String,
        folderUri: String,
        folderDisplayName: String?,
    ): Boolean {
        if (profileRepository.getActiveProfileId() == profileId) {
            profileCoordinator.folderWasSelected(folderUri, folderDisplayName)
        } else {
            profileRepository.bindFolder(profileId, folderUri, folderDisplayName)
        }
        return !profileRepository.isSharedSetupV2Blocked(profileId)
    }
}

package com.healthmd.data.drive

import com.healthmd.domain.repository.SettingsRepository
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.first

/** Verifies Picker authority, then admits the durable binding using current protection state. */
@Singleton
class GoogleDriveBindingService @Inject constructor(
    private val destinationStore: GoogleDriveDestinationStore,
    private val api: GoogleDriveApi,
    private val settingsRepository: SettingsRepository,
) {
    suspend fun bind(
        grant: GoogleDriveAuthorizationGrant,
        expectedDestinationId: String? = null,
    ): DriveApiResult<GoogleDriveDestination> {
        if (!admitted()) return protectedFailure()
        if (!destinationStore.isMutationSafe()) return DriveApiResult.Failure(GoogleDriveErrorId.REMOTE_CONFLICT)
        if (grant.selectedFolderIds.size != 1) return DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        val about = when (val result = api.about(grant.accessToken)) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return result
        }
        if (!admitted()) return protectedFailure()
        val existing = expectedDestinationId?.let { destinationStore.find(it) }
        if (!admitted()) return protectedFailure()
        if (expectedDestinationId != null && existing == null) {
            return DriveApiResult.Failure(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        }
        if (existing != null && existing.permissionId != about.permissionId) {
            return DriveApiResult.Failure(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        }
        val folderId = grant.selectedFolderIds.single()
        if (existing != null && existing.folderId != folderId) {
            return DriveApiResult.Failure(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        val metadata = when (val result = api.getMetadata(grant.accessToken, folderId, existing?.resourceKeys().orEmpty())) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return result
        }
        if (metadata.id != folderId || metadata.mimeType != GOOGLE_DRIVE_FOLDER_MIME_TYPE ||
            metadata.trashed || !metadata.capabilities.canAddChildren
        ) {
            return DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        }
        // Never use consent-time/UI state after asynchronous REST verification.
        if (!admitted()) return protectedFailure()
        val destination = GoogleDriveDestination(
            id = existing?.id ?: UUID.randomUUID().toString(),
            accountReferenceId = existing?.accountReferenceId ?: UUID.randomUUID().toString(),
            permissionId = about.permissionId,
            folderId = metadata.id,
            sharedDriveId = metadata.driveId,
            resourceKey = metadata.resourceKey,
            accountLabel = grant.accountLabel.take(128).ifBlank { "Google account" },
            folderLabel = metadata.name.take(256).ifBlank { "Drive folder" },
            capabilities = metadata.capabilities,
            lastValidatedAtEpochMillis = System.currentTimeMillis(),
        )
        // The store rechecks inside its DataStore edit, before encrypted authority is saved.
        try {
            if (!destinationStore.saveBindingIfAllowed(destination, grant.accountName)) return protectedFailure()
        } catch (_: IllegalStateException) {
            return DriveApiResult.Failure(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        return DriveApiResult.Success(destination)
    }

    private suspend fun admitted(): Boolean {
        currentCoroutineContext().ensureActive()
        val protected = settingsRepository.preventAccidentalChanges.first()
        currentCoroutineContext().ensureActive()
        return !protected
    }

    private fun protectedFailure() = DriveApiResult.Failure(GoogleDriveErrorId.PERMISSION_DENIED)
}

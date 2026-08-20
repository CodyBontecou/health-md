package com.healthmd.data.drive

import android.accounts.Account
import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.google.android.gms.auth.api.identity.AuthorizationClient
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.RevokeAccessRequest
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.Scope
import com.google.android.gms.tasks.Task
import com.healthmd.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

sealed interface GoogleDriveAuthorizationAction {
    data class Authorized(val grant: GoogleDriveAuthorizationGrant) : GoogleDriveAuthorizationAction
    data class Launch(val pendingIntent: PendingIntent) : GoogleDriveAuthorizationAction
    data class Failed(val error: GoogleDriveErrorId) : GoogleDriveAuthorizationAction
}

data class GoogleDriveAuthorizationGrant(
    val accessToken: String,
    val accountName: String,
    val accountLabel: String,
    val selectedFolderIds: List<String>,
)

sealed interface GoogleDriveAccessTokenResult {
    data class Granted(val accessToken: String) : GoogleDriveAccessTokenResult
    data object ResolutionRequired : GoogleDriveAccessTokenResult
    data class Failed(val error: GoogleDriveErrorId) : GoogleDriveAccessTokenResult
}

interface GoogleDriveAccessTokenProvider {
    suspend fun silentToken(destination: GoogleDriveDestination): GoogleDriveAccessTokenResult
}

/** Official Play-services AuthorizationClient + mobile Picker integration. */
@Singleton
class GoogleDriveAuthorizationManager @Inject constructor(
    @ApplicationContext private val context: Context,
    private val destinationStore: GoogleDriveDestinationStore,
    private val api: GoogleDriveApi,
) : GoogleDriveAccessTokenProvider {
    private val scope = Scope(GOOGLE_DRIVE_SCOPE)
    private val client: AuthorizationClient get() = Identity.getAuthorizationClient(context)

    fun readiness(): GoogleDriveReadiness = if (BuildConfig.GOOGLE_DRIVE_ANDROID_CLIENT_ID.isBlank()) {
        GoogleDriveReadiness.Unavailable(GoogleDriveErrorId.CONFIGURATION_MISSING)
    } else {
        GoogleDriveReadiness.Ready
    }

    suspend fun beginPicker(
        destinationIdForReauthorization: String? = null,
    ): GoogleDriveAuthorizationAction {
        if (readiness() !is GoogleDriveReadiness.Ready) {
            return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.CONFIGURATION_MISSING)
        }
        val destination = destinationIdForReauthorization?.let { destinationStore.find(it) }
        val account = destination?.let { exactAccount(it) }
            ?: if (destinationIdForReauthorization == null) null else {
                return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH)
            }
        val result = runCatching { client.authorize(pickerRequest(account, destination)).awaitResult() }
            .getOrElse { return GoogleDriveAuthorizationAction.Failed(classifyAuthorizationFailure(it)) }
        return actionFromResult(result, destination)
    }

    fun finishPicker(data: Intent?, destinationIdForReauthorization: String? = null): GoogleDriveAuthorizationAction {
        val destination = runCatching {
            destinationIdForReauthorization?.let { id ->
                // Activity callback cannot suspend. Exact destination validation is repeated by bind().
                id
            }
        }.getOrNull()
        val result = try {
            client.getAuthorizationResultFromIntent(data ?: Intent())
        } catch (error: ApiException) {
            return GoogleDriveAuthorizationAction.Failed(classifyAuthorizationFailure(error))
        }
        return actionFromResult(result, expectedDestination = null, pickerExtras = data?.extras).let { action ->
            if (destination == null) action else action
        }
    }

    /** Verifies account permissionId and selected-folder capabilities before persisting authority. */
    suspend fun bind(grant: GoogleDriveAuthorizationGrant, expectedDestinationId: String? = null): DriveApiResult<GoogleDriveDestination> {
        if (grant.selectedFolderIds.size != 1) return DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        val about = when (val result = api.about(grant.accessToken)) {
            is DriveApiResult.Success -> result.value
            is DriveApiResult.Failure -> return result
        }
        val existing = expectedDestinationId?.let { destinationStore.find(it) }
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
        if (metadata.mimeType != GOOGLE_DRIVE_FOLDER_MIME_TYPE || metadata.trashed || !metadata.capabilities.canAddChildren) {
            return DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        }
        val destination = GoogleDriveDestination(
            id = existing?.id ?: UUID.randomUUID().toString(),
            accountReferenceId = existing?.accountReferenceId ?: UUID.randomUUID().toString(),
            permissionId = about.permissionId,
            folderId = metadata.id,
            sharedDriveId = metadata.driveId,
            resourceKey = metadata.resourceKey,
            accountLabel = privacySafeAccountLabel(grant.accountLabel),
            folderLabel = privacySafeFolderLabel(metadata.name),
            capabilities = metadata.capabilities,
            lastValidatedAtEpochMillis = System.currentTimeMillis(),
        )
        destinationStore.save(destination, grant.accountName)
        return DriveApiResult.Success(destination)
    }

    override suspend fun silentToken(destination: GoogleDriveDestination): GoogleDriveAccessTokenResult {
        if (readiness() !is GoogleDriveReadiness.Ready) {
            return GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.CONFIGURATION_MISSING)
        }
        val account = exactAccount(destination)
            ?: return GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        val result = runCatching { client.authorize(silentRequest(account)).awaitResult() }
            .getOrElse { return GoogleDriveAccessTokenResult.Failed(classifyAuthorizationFailure(it)) }
        if (result.hasResolution()) return GoogleDriveAccessTokenResult.ResolutionRequired
        val resultAccount = result.toGoogleSignInAccount()?.account?.name
        if (resultAccount != account.name) return GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        if (result.grantedScopes.toSet() != setOf(GOOGLE_DRIVE_SCOPE)) {
            return GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.PERMISSION_DENIED)
        }
        val token = result.accessToken?.takeIf(String::isNotBlank)
            ?: return GoogleDriveAccessTokenResult.ResolutionRequired
        val about = api.about(token)
        if (about !is DriveApiResult.Success || about.value.permissionId != destination.permissionId) {
            return GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        }
        return GoogleDriveAccessTokenResult.Granted(token)
    }

    suspend fun disconnect(destinationId: String) {
        val destination = destinationStore.find(destinationId) ?: return
        val account = exactAccount(destination)
        if (account != null) {
            runCatching {
                client.revokeAccess(
                    RevokeAccessRequest.builder()
                        .setAccount(account)
                        .setScopes(listOf(scope))
                        .build(),
                ).awaitResult()
            }
        }
        destinationStore.remove(destinationId)
    }

    private suspend fun exactAccount(destination: GoogleDriveDestination): Account? =
        destinationStore.accountName(destination)?.let { Account(it, "com.google") }

    private fun pickerRequest(account: Account?, destination: GoogleDriveDestination?): AuthorizationRequest =
        AuthorizationRequest.builder()
            .setRequestedScopes(listOf(scope))
            // Do not inherit broad previously-granted scopes into this authorization result.
            .setOptOutIncludingGrantedScopes(true)
            .setPrompt(AuthorizationRequest.Prompt.CONSENT)
            .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_OAUTH_TRIGGER, "true")
            .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_FOLDER_SELECTION, "true")
            .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_ALLOW_MULTIPLE, "false")
            .addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_MIMETYPES, GOOGLE_DRIVE_FOLDER_MIME_TYPE)
            .apply {
                account?.let(::setAccount)
                destination?.let {
                    addResourceParameter(AuthorizationRequest.ResourceParameter.PICKER_FILE_IDS, it.folderId)
                }
            }
            .build()

    private fun silentRequest(account: Account): AuthorizationRequest = AuthorizationRequest.builder()
        .setRequestedScopes(listOf(scope))
        .setOptOutIncludingGrantedScopes(true)
        .setAccount(account)
        .build()

    private fun actionFromResult(
        result: AuthorizationResult,
        expectedDestination: GoogleDriveDestination?,
        pickerExtras: Bundle? = null,
    ): GoogleDriveAuthorizationAction {
        if (result.hasResolution()) {
            return result.pendingIntent?.let(GoogleDriveAuthorizationAction::Launch)
                ?: GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.REAUTHORIZATION_REQUIRED)
        }
        if (result.grantedScopes.toSet() != setOf(GOOGLE_DRIVE_SCOPE)) {
            return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.PERMISSION_DENIED)
        }
        val signIn = result.toGoogleSignInAccount()
            ?: return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        val account = signIn.account ?: return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH)
        val token = result.accessToken?.takeIf(String::isNotBlank)
            ?: return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.REAUTHORIZATION_REQUIRED)
        val folderIds = (extractPickerFileIds(result.tokenResponseParams) + extractPickerFileIds(pickerExtras)).distinct()
        if (expectedDestination != null && folderIds.any { it != expectedDestination.folderId }) {
            return GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.REMOTE_CONFLICT)
        }
        return GoogleDriveAuthorizationAction.Authorized(
            GoogleDriveAuthorizationGrant(
                accessToken = token,
                accountName = account.name,
                accountLabel = signIn.displayName ?: signIn.email ?: "Google account",
                selectedFolderIds = folderIds,
            ),
        )
    }

    private fun extractPickerFileIds(bundle: Bundle?): List<String> {
        if (bundle == null) return emptyList()
        val acceptedKeys = setOf(
            "pickerFileIds", "picker_file_ids", "PICKER_FILE_IDS",
            AuthorizationRequest.ResourceParameter.PICKER_FILE_IDS.name,
        )
        return acceptedKeys.flatMap { key ->
            when (val value = bundle.get(key)) {
                is String -> value.split(',')
                is ArrayList<*> -> value.filterIsInstance<String>()
                is Array<*> -> value.filterIsInstance<String>()
                else -> emptyList()
            }
        }.map(String::trim).filter(String::isNotBlank).distinct()
    }

    private fun classifyAuthorizationFailure(error: Throwable): GoogleDriveErrorId = when (error) {
        is ApiException -> if (error.statusCode == 4 || error.statusCode == 16) {
            GoogleDriveErrorId.REAUTHORIZATION_REQUIRED
        } else {
            GoogleDriveErrorId.PERMISSION_DENIED
        }
        else -> GoogleDriveErrorId.REAUTHORIZATION_REQUIRED
    }

    private fun privacySafeAccountLabel(value: String): String =
        value.take(128).ifBlank { "Google account" }
    private fun privacySafeFolderLabel(value: String): String =
        value.take(256).ifBlank { "Drive folder" }

    private suspend fun <T> Task<T>.awaitResult(): T = suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { value -> if (continuation.isActive) continuation.resume(value) }
        addOnFailureListener { error -> if (continuation.isActive) continuation.resumeWith(Result.failure(error)) }
        addOnCanceledListener { if (continuation.isActive) continuation.cancel() }
    }
}

internal fun GoogleDriveDestination.resourceKeys(): Map<String, String> =
    resourceKey?.let { mapOf(folderId to it) }.orEmpty()

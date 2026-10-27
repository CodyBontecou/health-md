package com.healthmd.data.drive

import android.app.PendingIntent

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

internal fun GoogleDriveDestination.resourceKeys(): Map<String, String> =
    resourceKey?.let { mapOf(folderId to it) }.orEmpty()

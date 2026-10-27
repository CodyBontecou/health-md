package com.healthmd.data.drive

import android.content.Intent
import javax.inject.Inject
import javax.inject.Singleton

/** F-Droid never links proprietary Play-services authorization or acquires cloud authority. */
@Singleton
class GoogleDriveAuthorizationManager @Inject constructor(
    private val disconnectService: GoogleDriveDisconnectService,
) : GoogleDriveAccessTokenProvider {
    fun readiness(): GoogleDriveReadiness = GoogleDriveReadiness.Unavailable(GoogleDriveErrorId.CONFIGURATION_MISSING)

    suspend fun beginPicker(destinationIdForReauthorization: String? = null): GoogleDriveAuthorizationAction =
        GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.CONFIGURATION_MISSING)

    fun finishPicker(data: Intent?, destinationIdForReauthorization: String? = null): GoogleDriveAuthorizationAction =
        GoogleDriveAuthorizationAction.Failed(GoogleDriveErrorId.CONFIGURATION_MISSING)

    suspend fun bind(grant: GoogleDriveAuthorizationGrant, expectedDestinationId: String? = null): DriveApiResult<GoogleDriveDestination> =
        DriveApiResult.Failure(GoogleDriveErrorId.CONFIGURATION_MISSING)

    override suspend fun silentToken(destination: GoogleDriveDestination): GoogleDriveAccessTokenResult =
        GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.CONFIGURATION_MISSING)

    suspend fun disconnect(destinationId: String): Boolean =
        disconnectService.disconnect(destinationId) { /* No proprietary SDK in this channel. */ }
}

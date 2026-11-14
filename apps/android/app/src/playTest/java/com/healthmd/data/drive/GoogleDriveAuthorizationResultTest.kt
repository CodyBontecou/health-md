package com.healthmd.data.drive

import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.google.android.gms.auth.api.identity.AuthorizationClient
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class GoogleDriveAuthorizationResultTest {
    @Test fun `Drive-only picker result does not require a legacy sign-in account`() {
        val context = mockk<Context>()
        val client = mockk<AuthorizationClient>()
        val result = mockk<AuthorizationResult>()
        val extras = mockk<Bundle>()
        val intent = mockk<Intent>()
        every { intent.extras } returns extras
        every { extras.get(any()) } returns null
        every { extras.get("picked_file_ids") } returns "folder"
        every { result.hasResolution() } returns false
        every { result.grantedScopes } returns listOf(GOOGLE_DRIVE_SCOPE)
        every { result.toGoogleSignInAccount() } returns null
        every { result.accessToken } returns "synthetic-token"
        every { result.tokenResponseParams } returns null
        every { client.getAuthorizationResultFromIntent(intent) } returns result
        mockkStatic(Identity::class)
        try {
            every { Identity.getAuthorizationClient(context) } returns client
            val manager = GoogleDriveAuthorizationManager(context, mockk(), mockk(), mockk(), mockk(), mockk())
            val action = manager.finishPicker(intent)
            assertThat(action).isInstanceOf(GoogleDriveAuthorizationAction.Authorized::class.java)
            val grant = (action as GoogleDriveAuthorizationAction.Authorized).grant
            assertThat(grant.selectedFolderIds).containsExactly("folder")
            assertThat(grant.accessToken).isEqualTo("synthetic-token")
        } finally {
            unmockkStatic(Identity::class)
        }
    }
    @Test fun `silent authorization uses pinned Drive permission authority without sign-in identity`() = kotlinx.coroutines.test.runTest {
        val context = mockk<Context>()
        val client = mockk<AuthorizationClient>()
        val result = mockk<AuthorizationResult>()
        val task = mockk<com.google.android.gms.tasks.Task<AuthorizationResult>>()
        val destinations = mockk<GoogleDriveDestinationStore>()
        val api = mockk<GoogleDriveApi>()
        val destination = GoogleDriveDestination(
            id = "destination", accountReferenceId = "account", permissionId = "permission", folderId = "folder",
            accountLabel = "Google account", folderLabel = "Folder",
            capabilities = GoogleDriveFolderCapabilities(canAddChildren = true), lastValidatedAtEpochMillis = 1,
        )
        io.mockk.coEvery { destinations.accountName(destination) } returns "test@example.com"
        every { result.hasResolution() } returns false
        every { result.grantedScopes } returns listOf(GOOGLE_DRIVE_SCOPE)
        every { result.accessToken } returns "synthetic-token"
        every { task.addOnSuccessListener(any<com.google.android.gms.tasks.OnSuccessListener<AuthorizationResult>>()) } answers {
            firstArg<com.google.android.gms.tasks.OnSuccessListener<AuthorizationResult>>().onSuccess(result)
            task
        }
        every { task.addOnFailureListener(any<com.google.android.gms.tasks.OnFailureListener>()) } returns task
        every { task.addOnCanceledListener(any<com.google.android.gms.tasks.OnCanceledListener>()) } returns task
        every { client.authorize(any()) } returns task
        mockkStatic(Identity::class)
        try {
            every { Identity.getAuthorizationClient(context) } returns client
            val manager = GoogleDriveAuthorizationManager(context, destinations, mockk(), api, mockk(), mockk())
            io.mockk.coEvery { api.about("synthetic-token") } returns DriveApiResult.Success(GoogleDriveAbout("permission"))
            assertThat(manager.silentToken(destination)).isEqualTo(GoogleDriveAccessTokenResult.Granted("synthetic-token"))
            io.mockk.coEvery { api.about("synthetic-token") } returns DriveApiResult.Success(GoogleDriveAbout("other-permission"))
            assertThat(manager.silentToken(destination)).isEqualTo(GoogleDriveAccessTokenResult.Failed(GoogleDriveErrorId.ACCOUNT_MISMATCH))
        } finally {
            unmockkStatic(Identity::class)
        }
    }

}

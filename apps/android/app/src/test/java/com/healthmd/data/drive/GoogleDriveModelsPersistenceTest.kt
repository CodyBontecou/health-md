package com.healthmd.data.drive

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class GoogleDriveModelsPersistenceTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val scopes = mutableListOf<CoroutineScope>()

    @After
    fun tearDown() = scopes.forEach(CoroutineScope::cancel)

    @Test
    fun `configuration requires a nonblank public client id`() {
        assertThat(GoogleDriveConfiguration.isConfigured("")).isFalse()
        assertThat(GoogleDriveConfiguration.isConfigured("   ")).isFalse()
        assertThat(GoogleDriveConfiguration.isConfigured("android-client.apps.googleusercontent.com")).isTrue()
    }

    @Test
    fun `generated artifacts copy bytes and reject unsafe paths`() {
        val source = "exact bytes\n".encodeToByteArray()
        val artifact = GeneratedExportArtifact(
            artifactId = "artifact-1",
            relativePath = "daily/2026-01-02.md",
            mediaType = "text/markdown; charset=utf-8",
            writeIntent = GeneratedArtifactWriteIntent.OVERWRITE,
            bytes = source,
        )
        source[0] = 'X'.code.toByte()
        val returned = artifact.bytes
        returned[1] = 'X'.code.toByte()

        assertThat(artifact.bytes).isEqualTo("exact bytes\n".encodeToByteArray())
        assertThat(normalizeDriveRelativePath("../private.md")).isNull()
        assertThat(normalizeDriveRelativePath("daily\\private.md")).isNull()
    }

    @Test
    fun `destination persistence preserves opaque records and encrypted account indirection`() = runTest {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO).also(scopes::add)
        val dataStore = PreferenceDataStoreFactory.create(
            scope = scope,
            produceFile = { temporaryFolder.newFile("drive.preferences_pb") },
        )
        dataStore.edit { preferences ->
            preferences[stringPreferencesKey("export_destinations_v1")] =
                """{"version":1,"records":[{"version":99,"kind":"future_drive","id":"opaque-1","future":"kept"}]}"""
        }
        val accounts = FakeAccountStore()
        val store = GoogleDriveDestinationStore(dataStore, accounts)
        val destination = destination()

        store.save(destination, "person@example.test")

        assertThat(store.all()).containsExactly(destination)
        assertThat(store.hasOpaqueRecords()).isTrue()
        assertThat(store.accountName(destination)).isEqualTo("person@example.test")
        store.remove(destination.id)
        assertThat(store.all()).isEmpty()
        assertThat(store.hasOpaqueRecords()).isTrue()
        assertThat(accounts.values).isEmpty()
    }

    private fun destination() = GoogleDriveDestination(
        id = "destination-1",
        accountReferenceId = "account-reference-1",
        permissionId = "permission-1",
        folderId = "folder-1",
        sharedDriveId = null,
        resourceKey = "resource-key",
        accountLabel = "Google account",
        folderLabel = "Health exports",
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true, canEdit = true),
        lastValidatedAtEpochMillis = 1234,
    )

    private class FakeAccountStore : GoogleDriveAccountAuthorityStore {
        val values = mutableMapOf<String, String>()
        override suspend fun save(referenceId: String, accountName: String) {
            values[referenceId] = accountName
        }
        override suspend fun accountName(referenceId: String): String? = values[referenceId]
        override suspend fun remove(referenceId: String) {
            values.remove(referenceId)
        }
    }
}

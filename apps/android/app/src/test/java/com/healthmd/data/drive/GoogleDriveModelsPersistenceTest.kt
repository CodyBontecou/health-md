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
        assertThat(GoogleDriveConfiguration.isConfigured("$(GOOGLE_DRIVE_ANDROID_CLIENT_ID)")).isFalse()
        assertThat(GoogleDriveConfiguration.isConfigured("000000-example.apps.googleusercontent.com")).isFalse()
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

    @Test
    fun `managed store distinguishes missing from opaque corruption and blocks mutation`() = runTest {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO).also(scopes::add)
        val dataStore = PreferenceDataStoreFactory.create(
            scope = scope,
            produceFile = { temporaryFolder.newFile("managed.preferences_pb") },
        )
        val store = GoogleDriveManagedObjectStore(dataStore)
        val pathHash = relativePathHash("destination-1", "file.md")

        assertThat(store.lookup("destination-1", pathHash))
            .isEqualTo(GoogleDriveManagedObjectLookup.Missing)
        dataStore.edit { preferences ->
            preferences[stringPreferencesKey("google_drive_managed_objects_v1")] =
                """{"version":1,"records":[{"version":99,"destinationId":"destination-1"}]}"""
        }
        assertThat(store.lookup("destination-1", pathHash))
            .isEqualTo(GoogleDriveManagedObjectLookup.Corrupt)
        assertThat(store.isMutationSafe()).isFalse()
        val mutation = runCatching {
            store.put(
                GoogleDriveManagedObject(
                    destinationId = "destination-1",
                    relativePathHash = pathHash,
                    objectId = "file-1",
                    parentId = "folder-1",
                    expectedName = "file.md",
                    mimeType = "text/markdown",
                ),
            )
        }
        assertThat(mutation.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(store.lookup("destination-1", pathHash))
            .isEqualTo(GoogleDriveManagedObjectLookup.Corrupt)
    }

    @Test
    fun `duplicate managed bindings are corruption rather than absence`() = runTest {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO).also(scopes::add)
        val dataStore = PreferenceDataStoreFactory.create(
            scope = scope,
            produceFile = { temporaryFolder.newFile("managed-duplicates.preferences_pb") },
        )
        val pathHash = relativePathHash("destination-1", "file.md")
        val record = """{"version":1,"destinationId":"destination-1","relativePathHash":"$pathHash","objectId":"file-1","parentId":"folder-1","expectedName":"file.md","mimeType":"text/markdown"}"""
        dataStore.edit { preferences ->
            preferences[stringPreferencesKey("google_drive_managed_objects_v1")] =
                """{"version":1,"records":[$record,$record]}"""
        }

        assertThat(GoogleDriveManagedObjectStore(dataStore).lookup("destination-1", pathHash))
            .isEqualTo(GoogleDriveManagedObjectLookup.Corrupt)
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

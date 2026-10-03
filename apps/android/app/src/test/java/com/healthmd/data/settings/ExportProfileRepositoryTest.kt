package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Atomic editor updates on the DataStore-backed profile repository: rename uniqueness,
 * target rebinding (endpoint vs SAF folder), and snapshot replacement in one edit.
 */
class ExportProfileRepositoryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var repository: ExportProfileRepository

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStoreFile = temporaryFolder.newFolder().resolve("export_profiles.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { dataStoreFile },
        )
        repository = ExportProfileRepository(
            dataStore = dataStore,
            context = mockk<Context>(relaxed = true),
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    private suspend fun seededProfile(
        name: String = "Daily",
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        endpointUrl: String? = null,
        folderUri: String? = null,
    ): ExportProfile = repository.add(
        name = name,
        settingsSnapshotJson = "snapshot-a",
        target = target,
        apiEndpointUrl = endpointUrl,
        folderUri = folderUri,
        folderDisplayName = folderUri?.let { "Folder $name" },
    )

    @Test
    fun `concurrent deletes preserve the final profile`() = runTest {
        val first = seededProfile(name = "First")
        val second = seededProfile(name = "Second")

        val results = listOf(first.id, second.id).map { id ->
            async(Dispatchers.Default) { repository.delete(id) }
        }.awaitAll()

        assertThat(results.count { it }).isEqualTo(1)
        assertThat(repository.getProfiles()).hasSize(1)
        assertThat(repository.getActiveProfileId())
            .isEqualTo(repository.getProfiles().single().id)
    }

    @Test
    fun `concurrent adds use unique names without losing either profile`() = runTest {
        listOf("Profile", "profile").map { name ->
            async(Dispatchers.Default) {
                repository.add(name, "snapshot", ExportTarget.DEVICE_FOLDER)
            }
        }.awaitAll()

        val profiles = repository.getProfiles()
        assertThat(profiles).hasSize(2)
        assertThat(profiles.map { it.name.lowercase() }.toSet()).hasSize(2)
        assertThat(profiles.map { it.id }).contains(repository.getActiveProfileId())
    }

    @Test
    fun `concurrent migration never overwrites an added profile`() = runTest {
        val add = async(Dispatchers.Default) {
            repository.add("User", "user-snapshot", ExportTarget.DEVICE_FOLDER)
        }
        val migrate = async(Dispatchers.Default) {
            repository.migrateDefaultIfNeeded("default-snapshot", ExportTarget.DEVICE_FOLDER)
        }
        val added = add.await()
        migrate.await()

        assertThat(repository.getProfiles().map { it.id }).contains(added.id)
        assertThat(repository.getProfiles().size).isAtLeast(1)
    }

    @Test
    fun `malformed present inventory blocks mutation without replacing bytes`() = runTest {
        val corrupt = "{not-json"
        dataStore.edit { it[PROFILES_KEY] = corrupt }

        val addFailure = runCatching {
            repository.add("Must Not Replace", "snapshot", ExportTarget.DEVICE_FOLDER)
        }.exceptionOrNull()

        assertThat(addFailure).isNotNull()
        assertThat(repository.migrateDefaultIfNeeded("default", ExportTarget.DEVICE_FOLDER)).isNull()
        assertThat(repository.delete("anything")).isFalse()
        assertThat(dataStore.data.first()[PROFILES_KEY]).isEqualTo(corrupt)
    }

    @Test
    fun `editor update renames retargets rebinds and replaces the snapshot atomically`() = runTest {
        val profile = seededProfile(name = "Daily", folderUri = "content://tree/old")

        val stored = repository.applyEditorUpdate(
            id = profile.id,
            rawName = "  Morning  ",
            settingsSnapshotJson = "snapshot-b",
            target = ExportTarget.DEVICE_FOLDER,
            apiEndpointUrl = null,
            folderUri = "content://tree/new",
            folderDisplayName = "New Vault",
        )

        assertThat(stored).isEqualTo("Morning")
        val updated = repository.profiles.first().single()
        assertThat(updated.name).isEqualTo("Morning")
        assertThat(updated.settingsSnapshotJson).isEqualTo("snapshot-b")
        assertThat(updated.target).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(updated.folderUri).isEqualTo("content://tree/new")
        assertThat(updated.folderDisplayName).isEqualTo("New Vault")
        assertThat(updated.apiEndpointUrl).isNull()
        assertThat(updated.updatedAtEpochMillis).isAtLeast(profile.updatedAtEpochMillis)
    }

    @Test
    fun `editor update suffixes a name another profile already took`() = runTest {
        val first = seededProfile(name = "Morning")
        val second = seededProfile(name = "Evening")

        val stored = repository.applyEditorUpdate(
            id = second.id,
            rawName = "morning",
            settingsSnapshotJson = "snapshot-b",
            target = ExportTarget.DEVICE_FOLDER,
            apiEndpointUrl = null,
            folderUri = null,
            folderDisplayName = null,
        )

        // Unique suffixing is case-insensitive; the typed casing is preserved.
        assertThat(stored).isEqualTo("morning 2")
        assertThat(repository.profileById(second.id)!!.name).isEqualTo("morning 2")
        assertThat(repository.profileById(first.id)!!.name).isEqualTo("Morning")
    }

    @Test
    fun `switching to an API target binds the endpoint and clears the folder binding`() = runTest {
        val profile = seededProfile(name = "Daily", folderUri = "content://tree/old")

        val stored = repository.applyEditorUpdate(
            id = profile.id,
            rawName = "Daily",
            settingsSnapshotJson = "snapshot-b",
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/hook",
            folderUri = "content://tree/old",
            folderDisplayName = "Folder Daily",
        )

        assertThat(stored).isEqualTo("Daily")
        val updated = repository.profileById(profile.id)!!
        assertThat(updated.target).isEqualTo(ExportTarget.API_ENDPOINT)
        assertThat(updated.apiEndpointUrl).isEqualTo("https://example.test/hook")
        assertThat(updated.folderUri).isNull()
        assertThat(updated.folderDisplayName).isNull()
    }

    @Test
    fun `switching to a folder target clears the endpoint binding`() = runTest {
        val profile = seededProfile(
            name = "Hook",
            target = ExportTarget.API_ENDPOINT,
            endpointUrl = "https://example.test/hook",
        )

        repository.applyEditorUpdate(
            id = profile.id,
            rawName = "Hook",
            settingsSnapshotJson = "snapshot-b",
            target = ExportTarget.DEVICE_FOLDER,
            apiEndpointUrl = "https://example.test/hook",
            folderUri = "content://tree/vault",
            folderDisplayName = "Vault",
        )

        val updated = repository.profileById(profile.id)!!
        assertThat(updated.target).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(updated.apiEndpointUrl).isNull()
        assertThat(updated.folderUri).isEqualTo("content://tree/vault")
    }

    @Test
    fun `editor update rejects blank names and unknown ids without changing anything`() = runTest {
        val profile = seededProfile(name = "Daily")

        assertThat(
            repository.applyEditorUpdate(
                id = profile.id,
                rawName = "   ",
                settingsSnapshotJson = "snapshot-b",
                target = ExportTarget.DEVICE_FOLDER,
                apiEndpointUrl = null,
                folderUri = null,
                folderDisplayName = null,
            ),
        ).isNull()

        assertThat(
            repository.applyEditorUpdate(
                id = "missing",
                rawName = "Morning",
                settingsSnapshotJson = "snapshot-b",
                target = ExportTarget.DEVICE_FOLDER,
                apiEndpointUrl = null,
                folderUri = null,
                folderDisplayName = null,
            ),
        ).isNull()

        val unchanged = repository.profiles.first().single()
        assertThat(unchanged.name).isEqualTo("Daily")
        assertThat(unchanged.settingsSnapshotJson).isEqualTo("snapshot-a")
    }

    private companion object {
        val PROFILES_KEY = stringPreferencesKey("export_profiles")
    }
}

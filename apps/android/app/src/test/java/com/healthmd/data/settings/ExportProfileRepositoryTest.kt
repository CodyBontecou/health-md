package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportSettings
import com.healthmd.sharedsetup.SharedSetupV2ProfilePersistence
import java.time.ZoneId
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
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
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

    private fun configurationSnapshot(filename: String): String = AndroidExportSettingsSnapshotCodec.encodeCanonical(
        AndroidExportSettingsSnapshot.capture(ExportSettings(filenameFormat = filename), null, ZoneId.of("UTC")),
    )

    @Test
    fun `configuration read obtains row and gate from one committed image without writing`() = runTest {
        val profile = repository.add("Selected", configurationSnapshot("selected-{date}"), ExportTarget.DEVICE_FOLDER)
        val key = SharedSetupV2ProfilePersistence.blockedProfileIdsKey
        dataStore.edit { it[key] = setOf(profile.id) }
        var reads = 0
        var writes = 0
        val observingStore = object : DataStore<Preferences> {
            override val data = dataStore.data.map { reads++; it }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                writes++
                return dataStore.updateData(transform)
            }
        }
        val reader = ExportProfileRepository(observingStore, mockk<Context>(relaxed = true))
        assertThat(reader.readConfigurationProfile(profile.id, 1)?.executionBlocked).isTrue()
        assertThat(reads).isEqualTo(1)
        assertThat(writes).isEqualTo(0)
        dataStore.edit { it[stringPreferencesKey(key.name)] = "malformed" }
        val before = dataStore.data.first().asMap()
        assertThat(reader.readConfigurationProfile(profile.id, 1)).isNull()
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
    }

    @Test
    fun `configuration read uses exact persisted row without active or cached fallback`() = runTest {
        val original = configurationSnapshot("selected-{date}")
        val selected = repository.add("Selected", original, ExportTarget.DEVICE_FOLDER)
        val other = repository.add("Active", configurationSnapshot("other-{date}"), ExportTarget.DEVICE_FOLDER)
        assertThat(repository.activate(other.id)).isTrue()
        val before = dataStore.data.first().asMap()
        val read = requireNotNull(repository.readConfigurationProfile(selected.id, 1))
        assertThat(read.settings.filenameFormat).isEqualTo("selected-{date}")
        assertThat(read.revision).isEqualTo(1)
        assertThat(read.executionBlocked).isFalse()
        assertThat(repository.readConfigurationProfile("missing", 1)).isNull()
        assertThat(repository.readConfigurationProfile(selected.id, 0)).isNull()
        assertThat(repository.readConfigurationProfile(selected.id, 2)).isNull()
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        assertThat(repository.updateProfile(selected.id, settingsSnapshotJson = configurationSnapshot("changed-{date}"))).isTrue()
        assertThat(repository.updateProfile(selected.id, settingsSnapshotJson = original)).isTrue()
        assertThat(repository.readConfigurationProfile(selected.id, 1)).isNull()
        assertThat(repository.readConfigurationProfile(selected.id, 3)?.settings?.filenameFormat).isEqualTo("selected-{date}")
    }

    @Test
    fun `configuration read rejects malformed duplicate or missing rows without repair`() = runTest {
        val profile = repository.add("Selected", configurationSnapshot("selected-{date}"), ExportTarget.DEVICE_FOLDER)
        val rows = Json.parseToJsonElement(requireNotNull(dataStore.data.first()[PROFILES_KEY])).jsonArray
        val duplicate = JsonArray(listOf(rows[0], rows[0])).toString()
        val malformed = JsonArray(listOf(JsonObject(rows[0].jsonObject + ("configurationRevision" to JsonPrimitive("1"))))).toString()
        for (raw in listOf(duplicate, malformed, "invalid")) {
            dataStore.edit { it[PROFILES_KEY] = raw }
            assertThat(repository.readConfigurationProfile(profile.id, 1)).isNull()
            if (raw != duplicate) {
                assertThat(repository.updateProfile(profile.id, settingsSnapshotJson = configurationSnapshot("replacement-{date}"))).isFalse()
            }
            assertThat(dataStore.data.first()[PROFILES_KEY]).isEqualTo(raw)
        }
        dataStore.edit { it.remove(PROFILES_KEY) }
        assertThat(repository.readConfigurationProfile(profile.id, 1)).isNull()
        assertThat(dataStore.data.first()[PROFILES_KEY]).isNull()
    }

    @Test
    fun `configuration read observes rebind state in same datastore image and rejects corrupt output`() = runTest {
        val profile = repository.add("Selected", configurationSnapshot("selected-{date}"), ExportTarget.DEVICE_FOLDER)
        val key = SharedSetupV2ProfilePersistence.blockedProfileIdsKey
        dataStore.edit { it[key] = setOf(profile.id) }
        val before = dataStore.data.first().asMap()
        assertThat(repository.readConfigurationProfile(profile.id, 1)?.executionBlocked).isTrue()
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        dataStore.edit { it.remove(key) }
        assertThat(repository.readConfigurationProfile(profile.id, 1)?.executionBlocked).isFalse()
        assertThat(repository.updateProfile(profile.id, settingsSnapshotJson = "invalid")).isTrue()
        assertThat(repository.readConfigurationProfile(profile.id, 2)).isNull()
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
    fun `profile revisions survive reload and settings returning to their original values`() = runTest {
        val first = seededProfile()
        val other = seededProfile(name = "Other")
        assertThat(first.configurationRevision).isEqualTo(1)
        assertThat(repository.updateProfile(first.id, settingsSnapshotJson = "snapshot-b")).isTrue()
        assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(2)
        val reloaded = ExportProfileRepository(dataStore, mockk<Context>(relaxed = true))
        assertThat(reloaded.updateProfile(first.id, settingsSnapshotJson = "snapshot-a")).isTrue()
        assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(3)
        assertThat(repository.profileById(first.id)?.settingsSnapshotJson).isEqualTo(first.settingsSnapshotJson)
        assertThat(repository.profileById(other.id)?.configurationRevision).isEqualTo(1)
    }

    @Test
    fun `every native editor path advances its revision and a derived row starts fresh`() = runTest {
        val first = seededProfile()
        assertThat(repository.bindFolder(first.id, "content://synthetic/tree/review", "Review")).isTrue()
        assertThat(repository.updateProfile(first.id, settingsSnapshotJson = "snapshot-b")).isTrue()
        assertThat(repository.applyEditorUpdate(first.id, "Edited", "snapshot-c", ExportTarget.DEVICE_FOLDER,
            null, "content://synthetic/tree/review", "Review")).isEqualTo("Edited")
        assertThat(repository.rename(first.id, "Renamed")).isEqualTo("Renamed")
        assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(5)
        assertThat(repository.activate(first.id)).isTrue()
        assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(5)
        val derived = repository.add("Copy", "snapshot-c", ExportTarget.DEVICE_FOLDER, derivedFromProfileId = first.id)
        assertThat(derived.id).isNotEqualTo(first.id)
        assertThat(derived.configurationRevision).isEqualTo(1)
        assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(5)
    }

    @Test
    fun `legacy profile revision defaults without a read migration write`() = runTest {
        val first = seededProfile()
        val rows = Json.parseToJsonElement(requireNotNull(dataStore.data.first()[PROFILES_KEY])).jsonArray
        val legacy = JsonArray(rows.map { JsonObject(it.jsonObject.filterKeys { key -> key != "configurationRevision" }) }).toString()
        dataStore.edit { it[PROFILES_KEY] = legacy }
        val reloaded = ExportProfileRepository(dataStore, mockk<Context>(relaxed = true))
        assertThat(reloaded.profileById(first.id)?.configurationRevision).isEqualTo(1)
        assertThat(dataStore.data.first()[PROFILES_KEY]).isEqualTo(legacy)
        assertThat(reloaded.updateProfile(first.id, settingsSnapshotJson = "snapshot-a")).isTrue()
        assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(2)
    }

    @Test
    fun `invalid or exhausted profile revisions reject edits without changing persisted bytes`() = runTest {
        val first = seededProfile()
        for (revision in listOf(-1, 0, Int.MAX_VALUE)) {
            val rows = Json.parseToJsonElement(requireNotNull(dataStore.data.first()[PROFILES_KEY])).jsonArray
            val before = JsonArray(rows.map { JsonObject(it.jsonObject + ("configurationRevision" to JsonPrimitive(revision))) }).toString()
            dataStore.edit { it[PROFILES_KEY] = before }
            assertThat(repository.updateProfile(first.id, settingsSnapshotJson = "changed")).isFalse()
            assertThat(repository.bindFolder(first.id, "content://synthetic/tree/changed", "Changed")).isFalse()
            assertThat(repository.rename(first.id, "Changed")).isNull()
            assertThat(repository.applyEditorUpdate(first.id, "Changed", "changed", ExportTarget.DEVICE_FOLDER,
                null, null, null)).isNull()
            assertThat(dataStore.data.first()[PROFILES_KEY]).isEqualTo(before)
            assertThat(repository.profileById(first.id)?.configurationRevision).isEqualTo(revision)
        }
    }

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

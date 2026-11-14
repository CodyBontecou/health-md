package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SettingsRepositoryConfigurationRevisionTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private lateinit var scope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var repository: SettingsRepositoryImpl
    private val revisionKey = intPreferencesKey("native_export_settings_revision_v1")
    private val settingsKey = stringPreferencesKey("export_settings")

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("settings.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        repository = SettingsRepositoryImpl(dataStore, mockk<Context>(relaxed = true))
    }

    @After fun tearDown() { scope.cancel() }

    @Test fun `native update paths persist revisions and never reuse pins after settings return`() = runTest {
        assertThat(repository.readSavedExportConfiguration(1)).isNull()
        val original = ExportSettings(filenameFormat = "first-{date}")
        repository.updateExportSettings(original)
        val first = requireNotNull(repository.readSavedExportConfiguration(2))
        repository.updateExportSettingsAtomically { it.copy(filenameFormat = "changed-{date}") }
        repository.updateExportSettings(original)
        assertThat(repository.readSavedExportConfiguration(2)).isNull()
        assertThat(repository.readSavedExportConfiguration(4)?.settings).isEqualTo(first.settings)
        assertThat(repository.readSavedExportConfiguration(0)).isNull()
    }

    @Test fun `legacy exact reads do not migrate and malformed state never uses defaults`() = runTest {
        val raw = Json.encodeToString(ExportSettings.serializer(), ExportSettings(filenameFormat = "legacy-{date}"))
        dataStore.edit { it[settingsKey] = raw }
        val before = dataStore.data.first().asMap()
        assertThat(repository.readSavedExportConfiguration(1)?.settings?.filenameFormat).isEqualTo("legacy-{date}")
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        for (invalid in listOf("invalid", "null", "[]")) {
            dataStore.edit { it[settingsKey] = invalid }
            val malformed = dataStore.data.first().asMap()
            assertThat(repository.readSavedExportConfiguration(1)).isNull()
            assertThat(dataStore.data.first().asMap()).isEqualTo(malformed)
        }
        dataStore.edit { it[intPreferencesKey(settingsKey.name)] = 7 }
        assertThat(repository.readSavedExportConfiguration(1)).isNull()
    }

    @Test fun `malformed and exhausted metadata cannot be renewed into a valid pin`() = runTest {
        for (invalid in listOf(0, -1, Int.MAX_VALUE)) {
            dataStore.edit { it[revisionKey] = invalid }
            repository.updateExportSettings(ExportSettings(filenameFormat = "changed-{date}"))
            assertThat(dataStore.data.first()[revisionKey]).isEqualTo(0)
            assertThat(repository.readSavedExportConfiguration(1)).isNull()
            repository.updateExportSettingsAtomically { it.copy(filenameFormat = "changed-again-{date}") }
            assertThat(dataStore.data.first()[revisionKey]).isEqualTo(0)
        }
        dataStore.edit { it[stringPreferencesKey(revisionKey.name)] = "1" }
        assertThat(repository.readSavedExportConfiguration(1)).isNull()
        repository.updateExportSettings(ExportSettings())
        assertThat(dataStore.data.first()[revisionKey]).isEqualTo(0)
    }

    @Test fun `exact settings and revision come from one committed image without writes`() = runTest {
        repository.updateExportSettings(ExportSettings(filenameFormat = "selected-{date}"))
        var reads = 0
        var writes = 0
        val observingStore = object : DataStore<Preferences> {
            override val data = dataStore.data.map { reads++; it }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                writes++
                return dataStore.updateData(transform)
            }
        }
        val reader = SettingsRepositoryImpl(observingStore, mockk<Context>(relaxed = true))
        assertThat(reader.readSavedExportConfiguration(2)?.settings?.filenameFormat).isEqualTo("selected-{date}")
        assertThat(reads).isEqualTo(1)
        assertThat(writes).isEqualTo(0)
    }

    @Test fun `failed atomic update preserves settings and pin`() = runTest {
        repository.updateExportSettings(ExportSettings())
        val before = dataStore.data.first().asMap()
        var failed = false
        try {
            repository.updateExportSettingsAtomically { error("synthetic transform failure") }
        } catch (_: IllegalStateException) { failed = true }
        assertThat(failed).isTrue()
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        assertThat(repository.readSavedExportConfiguration(2)).isNotNull()
    }

    @Test fun `native readiness and destination changes do not mutate the output settings pin`() = runTest {
        repository.updateExportSettings(ExportSettings())
        repository.setPreventAccidentalChanges(true)
        repository.setPurchased(true)
        repository.saveExportFolderUri("content://synthetic/tree/review")
        assertThat(repository.readSavedExportConfiguration(2)).isNotNull()
        assertThat(dataStore.data.first()[revisionKey]).isEqualTo(2)
    }
}

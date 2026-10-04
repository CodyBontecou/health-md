package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportTarget
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Gateway destination binding on the DataStore-backed profile repository: the Agent Data
 * gateway URL mirrors the API endpoint binding flow (bound for gateway targets, cleared for
 * every other destination) in the same atomic editor update.
 */
class ExportProfileAgentDataGatewayBindingTest {
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
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        gatewayUrl: String? = null,
    ) = repository.add(
        name = "Daily",
        settingsSnapshotJson = "snapshot-a",
        target = target,
        agentDataGatewayUrl = gatewayUrl,
    )

    @Test
    fun `switching to a gateway target binds the URL and clears other bindings`() = runTest {
        val profile = seededProfile(target = ExportTarget.API_ENDPOINT)

        val stored = repository.applyEditorUpdate(
            id = profile.id,
            rawName = "Daily",
            settingsSnapshotJson = "snapshot-b",
            target = ExportTarget.AGENT_DATA_GATEWAY,
            apiEndpointUrl = "https://api.example.test/hook",
            agentDataGatewayUrl = "http://127.0.0.1:8791",
            folderUri = "content://tree/old",
            folderDisplayName = "Folder Daily",
        )

        assertThat(stored).isEqualTo("Daily")
        val updated = repository.profileById(profile.id)!!
        assertThat(updated.target).isEqualTo(ExportTarget.AGENT_DATA_GATEWAY)
        assertThat(updated.agentDataGatewayUrl).isEqualTo("http://127.0.0.1:8791")
        assertThat(updated.apiEndpointUrl).isNull()
        assertThat(updated.folderUri).isNull()
        assertThat(updated.folderDisplayName).isNull()
    }

    @Test
    fun `switching away from a gateway target clears the gateway binding`() = runTest {
        val profile = seededProfile(
            target = ExportTarget.AGENT_DATA_GATEWAY,
            gatewayUrl = "http://127.0.0.1:8791",
        )

        repository.applyEditorUpdate(
            id = profile.id,
            rawName = "Daily",
            settingsSnapshotJson = "snapshot-b",
            target = ExportTarget.DEVICE_FOLDER,
            apiEndpointUrl = null,
            agentDataGatewayUrl = "http://127.0.0.1:8791",
            folderUri = "content://tree/new",
            folderDisplayName = "New Folder",
        )

        val updated = repository.profileById(profile.id)!!
        assertThat(updated.target).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(updated.agentDataGatewayUrl).isNull()
        assertThat(updated.folderUri).isEqualTo("content://tree/new")
    }

    @Test
    fun `updateProfile rebinds the gateway URL`() = runTest {
        val profile = seededProfile(
            target = ExportTarget.AGENT_DATA_GATEWAY,
            gatewayUrl = "http://localhost:8791",
        )

        val applied = repository.updateProfile(
            id = profile.id,
            agentDataGatewayUrl = "https://gateway.example.test",
        )

        assertThat(applied).isTrue()
        assertThat(repository.profileById(profile.id)!!.agentDataGatewayUrl)
            .isEqualTo("https://gateway.example.test")
    }

    @Test
    fun `migration binds the live gateway URL for gateway targets`() = runTest {
        val migrated = repository.migrateDefaultIfNeeded(
            settingsSnapshotJson = "snapshot-a",
            target = ExportTarget.AGENT_DATA_GATEWAY,
            agentDataGatewayUrl = "https://gateway.example.test",
        )

        assertThat(migrated).isNotNull()
        assertThat(migrated!!.target).isEqualTo(ExportTarget.AGENT_DATA_GATEWAY)
        assertThat(migrated.agentDataGatewayUrl).isEqualTo("https://gateway.example.test")
        assertThat(repository.getActiveProfile()!!.id).isEqualTo(migrated.id)
    }

    @Test
    fun `duplicating a gateway profile carries the binding`() = runTest {
        val profile = seededProfile(
            target = ExportTarget.AGENT_DATA_GATEWAY,
            gatewayUrl = "https://gateway.example.test",
        )

        val copy = repository.add(
            name = profile.name,
            settingsSnapshotJson = profile.settingsSnapshotJson,
            target = profile.target,
            agentDataGatewayUrl = profile.agentDataGatewayUrl,
        )

        assertThat(copy.agentDataGatewayUrl).isEqualTo("https://gateway.example.test")
    }
}

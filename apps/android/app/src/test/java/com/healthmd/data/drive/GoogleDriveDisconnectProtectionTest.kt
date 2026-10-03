package com.healthmd.data.drive

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfilePendingExport
import com.healthmd.data.settings.ConfigurationProtectionPersistence
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.drive.GoogleDriveViewModel
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Production disconnect service + ViewModel, real persisted protection/configuration stores. */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class GoogleDriveDisconnectProtectionTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private lateinit var scope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var destinations: GoogleDriveDestinationStore
    private lateinit var managed: GoogleDriveManagedObjectStore
    private lateinit var selection: GoogleDriveSelectionStore
    private lateinit var profiles: ExportProfileRepository
    private lateinit var schedules: ScheduledProfileEntryStore
    private lateinit var settings: SettingsRepositoryImpl
    private lateinit var service: GoogleDriveDisconnectService
    private lateinit var destination: GoogleDriveDestination
    private lateinit var profileId: String
    private val accounts = MemoryAccounts()
    private val pathHash = "a".repeat(64)

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("disconnect.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        destinations = GoogleDriveDestinationStore(dataStore, accounts)
        managed = GoogleDriveManagedObjectStore(dataStore)
        selection = GoogleDriveSelectionStore(dataStore)
        val context = mockk<Context>()
        profiles = ExportProfileRepository(dataStore, context)
        schedules = ScheduledProfileEntryStore(dataStore, context)
        settings = SettingsRepositoryImpl(dataStore, context)
        service = disconnectService(dataStore)
    }

    @After fun tearDown() { scope.cancel(); Dispatchers.resetMain() }

    @Test fun `lock before disconnect coroutine starts leaves all local configuration untouched`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        seed()
        val authorization = authorization { service.disconnect(it) { error("Must not revoke") } }
        val viewModel = viewModel(authorization)
        viewModel.state.first { it.destination != null }
        viewModel.disconnect() // UI was unlocked; body is still queued on Main.
        // Persist on IO without yielding this thread to the queued Main coroutine.
        val before = runBlocking(Dispatchers.IO) {
            settings.setPreventAccidentalChanges(true)
            snapshot()
        }
        advanceUntilIdle()
        viewModel.state.first { it.error == GoogleDriveErrorId.PERMISSION_DENIED }
        assertUnchanged(before)
        coVerify(exactly = 0) { authorization.disconnect(any()) }
    }

    @Test fun `delayed revocation then persisted lock denies all local disconnect writes`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        seed()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        var revocations = 0
        val authorization = authorization { id ->
            service.disconnect(id) { account ->
                assertThat(account).isEqualTo("synthetic-account")
                revocations++
                entered.complete(Unit)
                release.await()
            }
        }
        val viewModel = viewModel(authorization)
        viewModel.state.first { it.destination != null }
        viewModel.disconnect()
        entered.await()
        // Detach must not run before the awaited revocation, even while unlocked.
        assertThat(profiles.profileById(profileId)?.destinationId).isEqualTo(destination.id)
        assertThat(schedules.entry(profileId)?.isEnabled).isTrue()
        settings.setPreventAccidentalChanges(true)
        val before = snapshot()
        release.complete(Unit)
        viewModel.state.first { it.error == GoogleDriveErrorId.PERMISSION_DENIED }
        assertThat(revocations).isEqualTo(1) // Already-issued remote revocation is not rolled back.
        assertUnchanged(before)
        assertThat(viewModel.state.value.destination).isEqualTo(destination)
    }

    @Test fun `lock during account lookup prevents destructive revocation`() = runTest {
        seed()
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        accounts.onRead = { entered.complete(Unit); release.await() }
        var revocations = 0
        val result = async { service.disconnect(destination.id) { revocations++ } }
        entered.await()
        settings.setPreventAccidentalChanges(true)
        val before = snapshot()
        release.complete(Unit)
        assertThat(result.await()).isFalse()
        assertThat(revocations).isEqualTo(0)
        assertUnchanged(before)
    }

    @Test fun `actual disconnect commit serializes admission with persisted protection`() = runTest {
        seed()
        // Admission reads remain unlocked; enable the real key just before forwarding the edit.
        val guardedStore = object : DataStore<Preferences> by dataStore {
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                settings.setPreventAccidentalChanges(true)
                return dataStore.updateData(transform)
            }
        }
        val before = snapshot()
        assertThat(disconnectService(guardedStore).disconnect(destination.id) { }).isFalse()
        val expected = before.toMutableMap().apply { put(ConfigurationProtectionPersistence.enabledKey, true) }
        assertUnchanged(expected)
        assertThat(selection.selectIfAllowed(null)).isFalse()
        assertThat(destinations.remove(destination.id)).isFalse()
        assertUnchanged(expected)
    }

    @Test fun `unlocked disconnect clears bindings and schedules but preserves recovery frontiers`() = runTest {
        seed()
        val originalProfile = checkNotNull(profiles.profileById(profileId))
        val originalSchedule = checkNotNull(schedules.entry(profileId))
        val originalSettings = settings.getExportSettings()
        assertThat(service.disconnect(destination.id) { }).isTrue()
        assertThat(destinations.find(destination.id)).isNull()
        assertThat(accounts.values).isEmpty()
        assertThat(accounts.removals).isEqualTo(1)
        assertThat(selection.get()).isNull()
        val detached = checkNotNull(profiles.profileById(profileId))
        assertThat(detached.destinationId).isNull()
        assertThat(detached.target).isEqualTo(ExportTarget.GOOGLE_DRIVE)
        assertThat(detached.settingsSnapshotJson).isEqualTo(originalProfile.settingsSnapshotJson)
        assertThat(schedules.entry(profileId)).isEqualTo(originalSchedule.copy(isEnabled = false))
        assertThat(settings.getExportSettings()).isEqualTo(originalSettings.copy(scheduleEnabled = false))
        assertThat(dataStore.data.first()[stringPreferencesKey("export_settings")]).contains("\"retained_runtime_marker\":\"untouched\"")
        assertThat(managed.lookup(destination.id, pathHash)).isEqualTo(GoogleDriveManagedObjectLookup.Missing)
    }

    @Test fun `cancelled delayed revocation never removes local authority`() = runTest {
        seed()
        val entered = CompletableDeferred<Unit>()
        val result = async { service.disconnect(destination.id) { entered.complete(Unit); CompletableDeferred<Unit>().await() } }
        entered.await()
        val before = snapshot()
        result.cancel()
        result.join()
        assertUnchanged(before)
    }

    private fun disconnectService(store: DataStore<Preferences>) = GoogleDriveDisconnectService(
        store, destinations, managed, selection, profiles, schedules,
    )

    private fun authorization(disconnect: suspend (String) -> Boolean): GoogleDriveAuthorizationManager {
        val authorization = mockk<GoogleDriveAuthorizationManager>()
        every { authorization.readiness() } returns GoogleDriveReadiness.Ready
        coEvery { authorization.disconnect(any()) } coAnswers { disconnect(firstArg()) }
        return authorization
    }

    private fun viewModel(authorization: GoogleDriveAuthorizationManager) = GoogleDriveViewModel(
        authorization, destinations, selection, settings, SavedStateHandle(), mockk(),
    )

    private suspend fun seed() {
        destination = GoogleDriveDestination(
            id = "destination", accountReferenceId = "account", permissionId = "permission", folderId = "folder",
            accountLabel = "Google account", folderLabel = "Docs",
            capabilities = GoogleDriveFolderCapabilities(canAddChildren = true), lastValidatedAtEpochMillis = 1,
        )
        destinations.save(destination, "synthetic-account")
        selection.select(destination.id)
        val frozen = "{\"exportTarget\":\"GOOGLE_DRIVE\"}"
        profileId = profiles.add("Drive", frozen, ExportTarget.GOOGLE_DRIVE, destinationId = destination.id).id
        schedules.upsert(ScheduledProfileEntry(
            profileId = profileId, isEnabled = true, anchorEpochDay = 1,
            lastSuccessEpochMillis = 42, lastRefreshSuccessEpochMillis = 43,
            pendingExports = listOf(ScheduledProfilePendingExport(
                "residual", listOf(1), 44, frozen, ExportTarget.GOOGLE_DRIVE, "Drive",
                durableOperationId = "pending-operation", destinationId = destination.id,
            )),
        ))
        settings.updateExportSettings(ExportSettings(
            exportTarget = ExportTarget.GOOGLE_DRIVE, scheduledExportTarget = ExportTarget.GOOGLE_DRIVE,
            scheduleEnabled = true,
        ))
        // Raw opaque runtime metadata must not be normalized away by schedule disabling.
        dataStore.edit { prefs ->
            val key = stringPreferencesKey("export_settings")
            val root = kotlinx.serialization.json.Json.parseToJsonElement(checkNotNull(prefs[key]))
                as kotlinx.serialization.json.JsonObject
            prefs[key] = kotlinx.serialization.json.JsonObject(root + ("retained_runtime_marker" to
                kotlinx.serialization.json.JsonPrimitive("untouched"))).toString()
        }
        managed.put(GoogleDriveManagedObject(
            destinationId = destination.id, relativePathHash = pathHash, objectId = "object",
            parentId = "folder", expectedName = "health.md", mimeType = "text/markdown",
        ))
    }

    private suspend fun snapshot() = dataStore.data.first().asMap()

    private suspend fun assertUnchanged(before: Map<Preferences.Key<*>, Any>) {
        assertThat(snapshot()).isEqualTo(before)
        assertThat(accounts.values).containsExactly("account", "synthetic-account")
        assertThat(accounts.removals).isEqualTo(0)
        assertThat(destinations.find(destination.id)).isEqualTo(destination)
        assertThat(selection.get()).isEqualTo(destination.id)
        assertThat(profiles.profileById(profileId)?.destinationId).isEqualTo(destination.id)
        assertThat(schedules.entry(profileId)?.isEnabled).isTrue()
        assertThat(settings.getExportSettings().scheduleEnabled).isTrue()
    }

    private class MemoryAccounts : GoogleDriveAccountAuthorityStore {
        val values = mutableMapOf<String, String>()
        var removals = 0
        var onRead: suspend () -> Unit = { }
        override suspend fun save(referenceId: String, accountName: String) { values[referenceId] = accountName }
        override suspend fun accountName(referenceId: String): String? { onRead(); return values[referenceId] }
        override suspend fun remove(referenceId: String) { removals++; values.remove(referenceId) }
    }
}

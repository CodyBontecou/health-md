package com.healthmd.data.drive

import android.content.Context
import android.content.Intent
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.settings.ConfigurationProtectionPersistence
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.drive.GoogleDriveViewModel
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
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

/** Real durable stores + production REST binding service and Activity-result ViewModel path. */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class GoogleDriveBindingProtectionTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private lateinit var scope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var destinations: GoogleDriveDestinationStore
    private lateinit var selection: GoogleDriveSelectionStore
    private lateinit var settings: SettingsRepository
    private lateinit var api: GoogleDriveApi
    private lateinit var binding: GoogleDriveBindingService
    private lateinit var accounts: GoogleDriveAccountAuthorityStore
    private val credentialWrites = AtomicInteger()
    private val grant = GoogleDriveAuthorizationGrant("synthetic-token", "synthetic-account", "Google account", listOf("folder"))
    private val metadata = GoogleDriveRemoteMetadata(
        id = "folder", name = "Docs", mimeType = GOOGLE_DRIVE_FOLDER_MIME_TYPE,
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true),
    )

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("binding.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        accounts = mockk(relaxed = true)
        coEvery { accounts.save(any(), any()) } coAnswers { credentialWrites.incrementAndGet(); Unit }
        destinations = GoogleDriveDestinationStore(dataStore, accounts)
        selection = GoogleDriveSelectionStore(dataStore)
        settings = mockk()
        every { settings.preventAccidentalChanges } returns dataStore.data.map {
            it[ConfigurationProtectionPersistence.enabledKey] ?: false
        }
        api = mockk()
        coEvery { api.about(any()) } returns DriveApiResult.Success(GoogleDriveAbout("permission"))
        coEvery { api.getMetadata(any(), any(), any()) } returns DriveApiResult.Success(metadata)
        binding = GoogleDriveBindingService(destinations, api, settings)
    }

    @After fun tearDown() { scope.cancel(); Dispatchers.resetMain() }

    @Test fun `delayed Activity result after protection performs no binding or selection writes`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val authorization = mockk<GoogleDriveAuthorizationManager>()
        every { authorization.readiness() } returns GoogleDriveReadiness.Ready
        coEvery { authorization.beginPicker(any()) } returns GoogleDriveAuthorizationAction.Launch(mockk())
        every { authorization.finishPicker(any(), any()) } returns GoogleDriveAuthorizationAction.Authorized(grant)
        coEvery { authorization.bind(any(), any()) } coAnswers { binding.bind(firstArg(), secondArg()) }
        val viewModel = GoogleDriveViewModel(
            authorization, destinations, selection, settings, SavedStateHandle(), mockk<Context>(),
        )
        advanceUntilIdle()
        viewModel.begin { }
        advanceUntilIdle()
        assertThat(viewModel.state.value.busy).isTrue()
        lock()
        val before = dataStore.data.first().asMap()
        viewModel.finish(mockk<Intent>())
        advanceUntilIdle()
        viewModel.state.first { it.error == GoogleDriveErrorId.PERMISSION_DENIED }
        assertNoWrites(before)
        coVerify(exactly = 0) { authorization.bind(any(), any()) }
        assertThat(viewModel.state.value.error).isEqualTo(GoogleDriveErrorId.PERMISSION_DENIED)
    }

    @Test fun `lock while REST metadata is delayed prevents every durable authority write`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val entered = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        coEvery { api.getMetadata(any(), any(), any()) } coAnswers {
            entered.complete(Unit)
            release.await()
            DriveApiResult.Success(metadata)
        }
        val authorization = mockk<GoogleDriveAuthorizationManager>()
        every { authorization.readiness() } returns GoogleDriveReadiness.Ready
        every { authorization.finishPicker(any(), any()) } returns GoogleDriveAuthorizationAction.Authorized(grant)
        coEvery { authorization.bind(any(), any()) } coAnswers { binding.bind(firstArg(), secondArg()) }
        val viewModel = GoogleDriveViewModel(
            authorization, destinations, selection, settings, SavedStateHandle(), mockk(),
        )
        advanceUntilIdle()
        viewModel.finish(mockk())
        entered.await()
        lock()
        val before = dataStore.data.first().asMap()
        release.complete(Unit)
        viewModel.state.first { it.error == GoogleDriveErrorId.PERMISSION_DENIED }
        coVerify(exactly = 1) { authorization.bind(any(), any()) }
        assertNoWrites(before)
    }

    @Test fun `actual binding and selection commits check serialized current protection`() = runTest {
        val destination = (binding.bind(grant) as DriveApiResult.Success).value
        assertThat(credentialWrites.get()).isEqualTo(1)
        assertThat(selection.selectIfAllowed(destination.id)).isTrue()
        lock()
        val before = dataStore.data.first().asMap()
        assertThat(destinations.saveBindingIfAllowed(destination.copy(folderLabel = "Changed"), "changed-account"))
            .isFalse()
        assertThat(selection.selectIfAllowed("changed-selection")).isFalse()
        assertThat(credentialWrites.get()).isEqualTo(1)
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        coVerify(exactly = 1) { accounts.save(any(), any()) }
    }

    @Test fun `lock after authorization returns also prevents ViewModel selection commit`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val destination = (binding.bind(grant) as DriveApiResult.Success).value
        val authorization = mockk<GoogleDriveAuthorizationManager>()
        every { authorization.readiness() } returns GoogleDriveReadiness.Ready
        every { authorization.finishPicker(any(), any()) } returns GoogleDriveAuthorizationAction.Authorized(grant)
        coEvery { authorization.bind(any(), any()) } coAnswers {
            lock()
            DriveApiResult.Success(destination)
        }
        val viewModel = GoogleDriveViewModel(
            authorization, destinations, selection, settings, SavedStateHandle(), mockk(),
        )
        advanceUntilIdle()
        viewModel.finish(mockk())
        advanceUntilIdle()
        viewModel.state.first { it.error == GoogleDriveErrorId.PERMISSION_DENIED }
        assertThat(selection.get()).isNull()
        assertThat(credentialWrites.get()).isEqualTo(1) // Only the explicit pre-test unlocked binding.
        assertThat(viewModel.state.value.error).isEqualTo(GoogleDriveErrorId.PERMISSION_DENIED)
    }

    @Test fun `delayed about stops subsequent metadata acquisition for new and exact binding`() = runTest {
        val destination = (binding.bind(grant) as DriveApiResult.Success).value
        selection.select(destination.id)
        val metadataCalls = AtomicInteger()
        coEvery { api.getMetadata(any(), any(), any()) } coAnswers {
            metadataCalls.incrementAndGet()
            DriveApiResult.Success(metadata)
        }
        for (expectedId in listOf(null, destination.id)) {
            dataStore.edit { it[ConfigurationProtectionPersistence.enabledKey] = false }
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            coEvery { api.about(any()) } coAnswers {
                entered.complete(Unit)
                release.await()
                DriveApiResult.Success(GoogleDriveAbout("permission"))
            }
            val result = async { binding.bind(grant, expectedId) }
            entered.await()
            lock()
            val before = dataStore.data.first().asMap()
            release.complete(Unit)
            assertThat(result.await()).isEqualTo(DriveApiResult.Failure(GoogleDriveErrorId.PERMISSION_DENIED))
            assertThat(dataStore.data.first().asMap()).isEqualTo(before)
            assertThat(destinations.find(destination.id)).isEqualTo(destination)
            assertThat(selection.get()).isEqualTo(destination.id)
            assertThat(credentialWrites.get()).isEqualTo(1)
            assertThat(metadataCalls.get()).isEqualTo(0)
        }
    }

    private suspend fun lock() {
        dataStore.edit { it[ConfigurationProtectionPersistence.enabledKey] = true }
    }

    private suspend fun assertNoWrites(before: Map<Preferences.Key<*>, Any>) {
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        assertThat(credentialWrites.get()).isEqualTo(0)
        assertThat(destinations.all()).isEmpty()
        assertThat(selection.get()).isNull()
        coVerify(exactly = 0) { accounts.save(any(), any()) }
    }
}

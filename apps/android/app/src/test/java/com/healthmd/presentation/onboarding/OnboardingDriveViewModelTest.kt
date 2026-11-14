package com.healthmd.presentation.onboarding

import android.app.Application
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.drive.GoogleDriveAuthorizationManager
import com.healthmd.data.drive.GoogleDriveDestination
import com.healthmd.data.drive.GoogleDriveDestinationStore
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.data.drive.GoogleDriveFolderCapabilities
import com.healthmd.data.drive.GoogleDriveReadiness
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SavedAPIEndpointCoordinator
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import com.healthmd.presentation.export.ExportUiState
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

/** Onboarding's Folder step with PR #138's Google Drive destination. */
@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingDriveViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val settingsState = MutableStateFlow(ExportSettings())
    private val folderState = MutableStateFlow<String?>(null)
    private val settingsRepository = mockk<SettingsRepository>(relaxed = true) {
        every { exportSettings } returns settingsState
        every { exportFolderUri } returns folderState
        every { isPurchased } returns MutableStateFlow(false)
        coEvery { getExportSettings() } answers { settingsState.value }
    }
    private val profileCoordinator = mockk<ExportProfileCoordinator>(relaxed = true)
    private val profileRepository = mockk<ExportProfileRepository>(relaxed = true)
    private val entryStore = mockk<ScheduledProfileEntryStore>(relaxed = true)
    private val destinationStore = mockk<GoogleDriveDestinationStore>(relaxed = true)

    private val destination = GoogleDriveDestination(
        id = "drive-1", accountReferenceId = "account-1", permissionId = "perm", folderId = "folder",
        accountLabel = "Google account", folderLabel = "Health",
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true), lastValidatedAtEpochMillis = 0L,
    )

    private fun viewModel(driveReady: Boolean, paid: Boolean = false) = OnboardingViewModel(
        application = mockk<Application>(relaxed = true),
        settingsRepository = settingsRepository,
        distributionPolicy = DistributionPolicy.play(),
        healthRepository = mockk(relaxed = true),
        exportRepository = mockk(relaxed = true),
        profileRepository = profileRepository,
        profileCoordinator = profileCoordinator,
        entryStore = entryStore,
        profileScheduler = mockk(relaxed = true),
        entitlementRepository = mockk<EntitlementRepository>(relaxed = true) {
            every { isUnlocked } returns MutableStateFlow(paid)
        },
        purchaseRepository = mockk<PurchaseRepository>(relaxed = true) {
            every { isAvailable } returns false
            every { offers } returns MutableStateFlow(emptyList())
            every { isPurchasing } returns MutableStateFlow(false)
            every { purchaseError } returns MutableStateFlow(null)
        },
        endpointCoordinator = mockk<SavedAPIEndpointCoordinator>(relaxed = true) {
            every { endpoints } returns MutableStateFlow(emptyList())
        },
        driveAuthorization = mockk<GoogleDriveAuthorizationManager> {
            every { readiness() } returns if (driveReady) GoogleDriveReadiness.Ready
            else GoogleDriveReadiness.Unavailable(GoogleDriveErrorId.CONFIGURATION_MISSING)
        },
        driveDestinationStore = destinationStore,
    )

    @Test
    fun connectingDriveBindsTheDestinationToTheDailyNoteAndStaysOnFolder() = runTest {
        coEvery { profileCoordinator.googleDriveDestinationWasSelected("drive-1") } returns true
        val vm = viewModel(driveReady = true)
        advanceUntilIdle()
        vm.goTo(OnboardingStep.FOLDER)
        vm.selectDestination(OnboardingDestination.GOOGLE_DRIVE)
        advanceUntilIdle()
        assertThat(vm.uiState.value.usesDrive).isTrue()
        assertThat(vm.uiState.value.destinationReady).isFalse()

        vm.onDriveConnectStarted()
        vm.onDriveConnected(destination)
        advanceUntilIdle()

        coVerify(exactly = 1) { profileCoordinator.googleDriveDestinationWasSelected("drive-1") }
        val state = vm.uiState.value
        assertThat(state.step).isEqualTo(OnboardingStep.FOLDER)
        assertThat(state.driveDestination).isEqualTo(destination)
        assertThat(state.driveConnecting).isFalse()
        assertThat(state.destinationReady).isTrue()
        assertThat(state.destinationLabel).isEqualTo("Google Drive/Health")
        assertThat(state.dailyScheduleReady).isTrue()
        // No folder picker binding happens for a Drive destination.
        coVerify(exactly = 0) { profileCoordinator.folderWasSelected(any(), any()) }
    }

    @Test
    fun cancelOrFailureKeepsTheFolderStepWithTheErrorAndNoBinding() = runTest {
        val vm = viewModel(driveReady = true)
        advanceUntilIdle()
        vm.goTo(OnboardingStep.FOLDER)
        vm.selectDestination(OnboardingDestination.GOOGLE_DRIVE)
        vm.onDriveConnectStarted()
        vm.onDriveConnectFailed(GoogleDriveErrorId.PERMISSION_DENIED)
        advanceUntilIdle()

        val state = vm.uiState.value
        assertThat(state.step).isEqualTo(OnboardingStep.FOLDER)
        assertThat(state.driveError).isEqualTo(GoogleDriveErrorId.PERMISSION_DENIED)
        assertThat(state.driveConnecting).isFalse()
        assertThat(state.destinationReady).isFalse()
        coVerify(exactly = 0) { profileCoordinator.googleDriveDestinationWasSelected(any()) }

        // A failed profile bind also surfaces inline instead of pretending to be connected.
        coEvery { profileCoordinator.googleDriveDestinationWasSelected(any()) } returns false
        vm.onDriveConnected(destination)
        advanceUntilIdle()
        assertThat(vm.uiState.value.driveDestination).isNull()
        assertThat(vm.uiState.value.driveError).isEqualTo(GoogleDriveErrorId.PERMISSION_DENIED)
    }

    @Test
    fun firstNoteSavesTheWeekToTheConnectedDriveFolder() = runTest {
        coEvery { profileCoordinator.googleDriveDestinationWasSelected(any()) } returns true
        val vm = viewModel(driveReady = true)
        advanceUntilIdle()
        vm.selectDestination(OnboardingDestination.GOOGLE_DRIVE)
        vm.onDriveConnected(destination)
        advanceUntilIdle()

        val dates = OnboardingFlow.firstNoteDates(LocalDate.of(2026, 11, 12))
        val ready = vm.uiState.value.copy(note = NotePreviewState.Ready(dates.map { OnboardingNoteDay(it, raw = "x") }))
        val freeLeft = ExportUiState(freeExportsRemaining = 1, isPurchased = false)
        // A save, not an API send; the manual export reads the Drive-bound profile.
        assertThat(firstNoteAction(ready, freeLeft))
            .isEqualTo(FirstNoteAction.Save(count = 7, destination = "Google Drive/Health", sends = false))
        // Not connected yet: nowhere to save, so finishing leaves the free export unused.
        assertThat(firstNoteAction(ready.copy(driveDestination = null), freeLeft)).isEqualTo(FirstNoteAction.Finish)
    }

    @Test
    fun dailyScheduleStaysOffUntilDriveIsConnected() = runTest {
        coEvery { profileRepository.getActiveProfile() } returns ExportProfile(
            id = "daily", name = "Daily note", settingsSnapshotJson = "{}", target = ExportTarget.GOOGLE_DRIVE,
            createdAtEpochMillis = 0L, updatedAtEpochMillis = 0L,
        )
        coEvery { entryStore.entry(any()) } returns null
        val vm = viewModel(driveReady = true, paid = true)
        advanceUntilIdle()
        vm.selectDestination(OnboardingDestination.GOOGLE_DRIVE)
        var completed = false
        vm.enableDailyAndFinish { completed = true }
        advanceUntilIdle()

        assertThat(completed).isTrue()
        coVerify(exactly = 0) { entryStore.upsert(any()) }
    }

    @Test
    fun unavailableDriveKeepsTheSystemPickerFallback() = runTest {
        folderState.value = "content://com.android.externalstorage.documents/tree/primary%3ADrive"
        val vm = viewModel(driveReady = false)
        advanceUntilIdle()
        vm.selectDestination(OnboardingDestination.GOOGLE_DRIVE)
        advanceUntilIdle()

        val state = vm.uiState.value
        assertThat(state.driveAvailable).isFalse()
        assertThat(state.usesDrive).isFalse()
        assertThat(state.usesFolder).isTrue()
        assertThat(state.dailyScheduleReady).isTrue()
        coVerify(exactly = 0) { profileCoordinator.googleDriveDestinationWasSelected(any()) }
        coVerify { profileCoordinator.folderWasSelected(folderState.value!!, any()) }
    }
}

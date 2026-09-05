package com.healthmd.sharedsetup

import android.content.Intent
import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SharedSetupViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    @Test
    fun `failed artifact creation clears reservation and schedules orphan cleanup`() = runTest {
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>()
        val attemptedIDs = mutableListOf<String>()
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.exportBytes() } returns byteArrayOf(1)
        every { coordinator.imports } returns MutableStateFlow(null)
        every { store.shareIntent(any(), any()) } answers {
            val artifactID = secondArg<String>()
            attemptedIDs += artifactID
            if (attemptedIDs.size == 1) error("synthetic creation failure")
            SharedSetupShare(Intent(Intent.ACTION_SEND), artifactID)
        }
        val viewModel = SharedSetupViewModel(service, store, coordinator, SavedStateHandle())
        advanceUntilIdle()

        assertThat(viewModel.shareIntent().isFailure).isTrue()
        coVerify(exactly = 1) { store.discardShareArtifact(attemptedIDs.single()) }
        assertThat(viewModel.shareIntent().isSuccess).isTrue()
        assertThat(attemptedIDs).hasSize(2)
    }

    @Test
    fun `applied setup survives process recreation and ignores replay of the same launch bytes`() = runTest {
        val bytes = byteArrayOf(4, 5, 6)
        val review = SharedSetupReviewSummary(
            formats = listOf("markdown"),
            metricCount = 1,
            filenameTemplate = "{date}",
            units = "metric",
            dailyNotesEnabled = false,
            individualEntriesEnabled = false,
            hasCustomContent = false,
            scheduleRequested = false,
            endpointDescription = null,
            items = emptyList(),
        )
        val preview = mockk<SharedSetupPreview>()
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle(
            mapOf(
                "sharedSetup.restorableDocumentBytes" to bytes,
                "sharedSetup.restorablePhase" to "success",
            )
        )
        every { preview.review } returns review
        coEvery { service.previewVersioned(any()) } returns
            Result.success(SharedSetupVersionedPreview.V1(preview))
        coEvery { service.pendingEndpoint() } returns "https://setup.invalid/health"
        every { coordinator.imports } returns imports

        val viewModel = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.Success::class.java)

        imports.value = PendingSharedSetupImport(id = 9, bytes = bytes.copyOf())
        advanceUntilIdle()

        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.Success::class.java)
        coVerify(exactly = 1) { service.previewVersioned(any()) }
        assertThat(imports.value?.id).isEqualTo(9)
    }

    @Test
    fun `new retained import wins over slower saved-state restoration`() = runTest {
        val restoredBytes = byteArrayOf(1)
        val newerBytes = byteArrayOf(2)
        val restoredPreview = mockk<SharedSetupPreview>(name = "restored")
        val newerPreview = mockk<SharedSetupPreview>(name = "newer")
        val restoredStarted = CompletableDeferred<Unit>()
        val releaseRestored = CompletableDeferred<SharedSetupPreview>()
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        every { coordinator.imports } returns imports
        coEvery { service.previewVersioned(match { it.contentEquals(restoredBytes) }) } coAnswers {
            restoredStarted.complete(Unit)
            Result.success(SharedSetupVersionedPreview.V1(releaseRestored.await()))
        }
        coEvery { service.previewVersioned(match { it.contentEquals(newerBytes) }) } returns
            Result.success(SharedSetupVersionedPreview.V1(newerPreview))
        val viewModel = SharedSetupViewModel(
            service,
            store,
            coordinator,
            SavedStateHandle(
                mapOf(
                    "sharedSetup.restorableDocumentBytes" to restoredBytes,
                    "sharedSetup.restorablePhase" to "review",
                ),
            ),
        )
        restoredStarted.await()

        imports.value = PendingSharedSetupImport(id = 42, bytes = newerBytes)
        advanceUntilIdle()
        assertThat((viewModel.state.value as SharedSetupUiState.Review).preview)
            .isSameInstanceAs(newerPreview)

        releaseRestored.complete(restoredPreview)
        advanceUntilIdle()
        assertThat((viewModel.state.value as SharedSetupUiState.Review).preview)
            .isSameInstanceAs(newerPreview)
    }

    @Test
    fun `v2 plan and apply receipt survive recreation without becoming a v1 review`() = runTest {
        val bytes = byteArrayOf(7, 8, 9)
        val firstProfile = mockk<SharedSetupV2ProfileImportPlan>()
        val secondProfile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { firstProfile.bundleId } returns "profile-001"
        every { secondProfile.bundleId } returns "profile-002"
        every { plan.profiles } returns listOf(firstProfile, secondProfile)
        val versioned = SharedSetupVersionedPreview.V2(plan)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns Result.success(versioned)
        val callback = SharedSetupV2ApplyCallback { Result.success(Unit) }
        coEvery {
            service.applyV2(
                plan,
                listOf("profile-002"),
                SharedSetupV2ApplyMode.REPLACE,
                callback,
            )
        } returns Result.success(
            SharedSetupV2ApplyResult(
                selectedBundleIds = listOf("profile-002"),
                mode = SharedSetupV2ApplyMode.REPLACE,
            ),
        )

        val viewModel = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 1, bytes = bytes)
        advanceUntilIdle()

        assertThat(viewModel.versionedPreview.value).isEqualTo(versioned)
        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.Error::class.java)
        assertThat(viewModel.state.value).isNotInstanceOf(SharedSetupUiState.Review::class.java)

        viewModel.applyV2(
            selectedBundleIds = listOf("profile-002"),
            mode = SharedSetupV2ApplyMode.REPLACE,
            callback = callback,
        )
        advanceUntilIdle()
        assertThat(viewModel.v2TransactionState.value)
            .isInstanceOf(SharedSetupV2TransactionState.Applied::class.java)
        assertThat(savedState.get<String>("sharedSetup.restorablePhase")).isEqualTo("v2_success")

        val recreated = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        assertThat(recreated.versionedPreview.value).isEqualTo(versioned)
        val restored = recreated.v2TransactionState.value as SharedSetupV2TransactionState.Applied
        assertThat(restored.result.selectedBundleIds).containsExactly("profile-002")
        assertThat(restored.result.mode).isEqualTo(SharedSetupV2ApplyMode.REPLACE)
    }

    @Test
    fun `oversized saved state bytes are discarded before versioned preview`() = runTest {
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>()
        every { coordinator.imports } returns MutableStateFlow(null)
        val savedState = SavedStateHandle(
            mapOf(
                "sharedSetup.restorableDocumentBytes" to
                    ByteArray(SHARED_SETUP_V2_MAX_BYTES + 1),
                "sharedSetup.restorablePhase" to "v2_review",
            ),
        )

        val viewModel = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()

        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.Error::class.java)
        assertThat((viewModel.state.value as SharedSetupUiState.Error).message).contains("4 MiB")
        assertThat(savedState.get<ByteArray>("sharedSetup.restorableDocumentBytes")).isNull()
        coVerify(exactly = 0) { service.previewVersioned(any()) }
    }

    @Test
    fun `pending share survives ViewModel recreation and serializes launcher results`() = runTest {
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>()
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.exportBytes() } returns byteArrayOf(1, 2, 3)
        every { coordinator.imports } returns imports
        every { store.shareIntent(any(), any()) } answers {
            SharedSetupShare(Intent(Intent.ACTION_SEND), secondArg())
        }

        val firstViewModel = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        val firstID = requireNotNull(firstViewModel.shareIntent().getOrNull()?.artifactID)
        assertThat(firstViewModel.shareIntent().exceptionOrNull()?.message).contains("already open")
        verify(exactly = 1) { store.shareIntent(any(), firstID) }

        val recreatedViewModel = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        assertThat(recreatedViewModel.shareIntent().exceptionOrNull()?.message).contains("already open")
        recreatedViewModel.completeShareArtifactHandoff()
        advanceUntilIdle()
        coVerify(exactly = 1) { store.scheduleShareArtifactCleanup(firstID) }

        val secondID = requireNotNull(recreatedViewModel.shareIntent().getOrNull()?.artifactID)
        assertThat(secondID).isNotEqualTo(firstID)
        recreatedViewModel.cancelPendingShareArtifact()
        advanceUntilIdle()
        coVerify(exactly = 1) { store.discardShareArtifact(secondID) }
    }
}

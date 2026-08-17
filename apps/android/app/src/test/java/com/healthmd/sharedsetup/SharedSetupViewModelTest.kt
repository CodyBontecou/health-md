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
        coEvery { service.preview(any()) } returns Result.success(preview)
        coEvery { service.pendingEndpoint() } returns "https://setup.invalid/health"
        every { coordinator.imports } returns imports

        val viewModel = SharedSetupViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.Success::class.java)

        imports.value = PendingSharedSetupImport(id = 9, bytes = bytes.copyOf())
        advanceUntilIdle()

        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.Success::class.java)
        coVerify(exactly = 1) { service.preview(any()) }
        verify(exactly = 1) { coordinator.consume(9) }
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

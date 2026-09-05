package com.healthmd.sharedsetup

import android.content.Intent
import android.net.Uri
import androidx.lifecycle.SavedStateHandle
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.APIExportAuthorizationValidationResult
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.settings.ExportProfileRepository
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

    private fun productionAdapter(): SharedSetupV2ProductionTransaction =
        mockk(relaxed = true)

    private val profileRepository = mockk<ExportProfileRepository>()
    private val credentialStore = InMemoryAPIExportCredentialStore()

    private fun newViewModel(
        service: SharedSetupService,
        store: SharedSetupDocumentStore,
        coordinator: SharedSetupCoordinator,
        savedState: SavedStateHandle,
        production: SharedSetupV2ProductionTransaction = productionAdapter(),
    ): SharedSetupViewModel = SharedSetupViewModel(
        service,
        store,
        coordinator,
        savedState,
        production,
        profileRepository,
        credentialStore,
    )

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
        val viewModel = newViewModel(service, store, coordinator, SavedStateHandle())
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

        val viewModel = newViewModel(service, store, coordinator, savedState)
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
        val viewModel = newViewModel(
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

        val viewModel = newViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 1, bytes = bytes)
        advanceUntilIdle()

        assertThat(viewModel.versionedPreview.value).isEqualTo(versioned)
        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.ReviewV2::class.java)
        assertThat(viewModel.state.value).isNotInstanceOf(SharedSetupUiState.Review::class.java)
        assertThat(viewModel.state.value).isNotInstanceOf(SharedSetupUiState.Error::class.java)

        viewModel.applyV2(
            selectedBundleIds = listOf("profile-002"),
            mode = SharedSetupV2ApplyMode.REPLACE,
            callback = callback,
        )
        advanceUntilIdle()
        assertThat(viewModel.v2TransactionState.value)
            .isInstanceOf(SharedSetupV2TransactionState.Applied::class.java)
        assertThat(savedState.get<String>("sharedSetup.restorablePhase")).isEqualTo("v2_success")

        val recreated = newViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        assertThat(recreated.versionedPreview.value).isEqualTo(versioned)
        assertThat(recreated.state.value).isInstanceOf(SharedSetupUiState.ReviewV2::class.java)
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

        val viewModel = newViewModel(service, store, coordinator, savedState)
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

        val firstViewModel = newViewModel(service, store, coordinator, savedState)
        advanceUntilIdle()
        val firstID = requireNotNull(firstViewModel.shareIntent().getOrNull()?.artifactID)
        assertThat(firstViewModel.shareIntent().exceptionOrNull()?.message).contains("already open")
        verify(exactly = 1) { store.shareIntent(any(), firstID) }

        val recreatedViewModel = newViewModel(service, store, coordinator, savedState)
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

    @Test
    fun `production apply passes the injected adapter through the service seam`() = runTest {
        val bytes = byteArrayOf(1, 3, 5)
        val firstProfile = mockk<SharedSetupV2ProfileImportPlan>()
        val secondProfile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { firstProfile.bundleId } returns "profile-001"
        every { secondProfile.bundleId } returns "profile-002"
        every { plan.profiles } returns listOf(firstProfile, secondProfile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(
                plan,
                listOf("profile-002", "profile-001"),
                SharedSetupV2ApplyMode.REPLACE,
                production,
            )
        } returns Result.success(
            SharedSetupV2ApplyResult(
                selectedBundleIds = listOf("profile-001", "profile-002"),
                mode = SharedSetupV2ApplyMode.REPLACE,
            ),
        )
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 4, bytes = bytes)
        advanceUntilIdle()

        viewModel.applyV2(
            selectedBundleIds = listOf("profile-002", "profile-001"),
            mode = SharedSetupV2ApplyMode.REPLACE,
        )
        advanceUntilIdle()

        val applied = viewModel.v2TransactionState.value as SharedSetupV2TransactionState.Applied
        assertThat(applied.result.selectedBundleIds)
            .containsExactly("profile-001", "profile-002")
            .inOrder()
        assertThat(savedState.get<String>("sharedSetup.restorablePhase")).isEqualTo("v2_success")
        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.ReviewV2::class.java)
        coVerify(exactly = 1) { production.blockedImportedProfiles() }
    }

    @Test
    fun `production undo keeps the v2 screen with an honest undone result and clears blocked visibility`() = runTest {
        val bytes = byteArrayOf(2, 4, 6)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { service.undoV2(production) } returns
            Result.success(SharedSetupV2UndoResult(didUndo = true))
        coEvery { production.blockedImportedProfiles() } returns listOf(
            SharedSetupV2BlockedImportedProfile(
                profileId = "30000000-0000-4000-8000-000000000001",
                name = "Daily",
                sourceDestinationKind = "device_folder",
            ),
        )
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 5, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)

        viewModel.undoV2()
        advanceUntilIdle()

        assertThat(viewModel.v2TransactionState.value)
            .isInstanceOf(SharedSetupV2TransactionState.Undone::class.java)
        assertThat(viewModel.state.value).isInstanceOf(SharedSetupUiState.ReviewV2::class.java)
        assertThat(viewModel.versionedPreview.value).isNull()
        assertThat(viewModel.v2BlockedProfiles.value).isNull()
        assertThat(savedState.get<String>("sharedSetup.restorablePhase")).isNull()
    }

    @Test
    fun `blocked imported profiles surface after apply and rebind failures stay honest`() = runTest {
        val bytes = byteArrayOf(9)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000001"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { production.blockedImportedProfiles() } returns listOf(
            SharedSetupV2BlockedImportedProfile(blockedId, "Daily", "api_endpoint"),
        )
        val rebindUri = mockk<Uri>()
        every { rebindUri.toString() } returns "content://synthetic/tree"
        coEvery {
            production.rebindBlockedFolder(blockedId, "content://synthetic/tree", "Docs")
        } returns false
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 6, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        val blocked = requireNotNull(viewModel.v2BlockedProfiles.value)
        assertThat(blocked.single().name).isEqualTo("Daily")
        assertThat(blocked.single().sourceDestinationKind).isEqualTo("api_endpoint")

        viewModel.rebindBlockedProfileFolder(blockedId, rebindUri, "Docs")
        advanceUntilIdle()

        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).isNotEmpty()
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)

        viewModel.dismissRebindFailure()
        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
    }

    @Test
    fun `api credential confirmation clears a blocked imported profile through the verified credential seam`() = runTest {
        val bytes = byteArrayOf(11)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000001"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(SharedSetupV2BlockedImportedProfile(blockedId, "Daily", "api_endpoint")),
            emptyList(),
            emptyList(),
        )
        credentialStore.authorization = "Bearer prior"
        credentialStore.saveRequestHeaders("X-Custom: prior")
        val confirmStarted = CompletableDeferred<Unit>()
        val releaseConfirm = CompletableDeferred<Boolean>()
        coEvery {
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(blockedId)
        } coAnswers {
            confirmStarted.complete(Unit)
            releaseConfirm.await()
        }
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 7, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)

        viewModel.confirmBlockedApiCredential(blockedId, "fresh-token")
        confirmStarted.await()
        assertThat(viewModel.v2RebindState.value)
            .isEqualTo(SharedSetupV2RebindState.ConfirmingApiCredential)

        releaseConfirm.complete(true)
        advanceUntilIdle()

        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
        assertThat(credentialStore.authorization).isEqualTo("Bearer fresh-token")
        assertThat(credentialStore.requestHeaders()).isEmpty()
        assertThat(viewModel.v2BlockedProfiles.value).isEmpty()
        coVerify(exactly = 1) {
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(blockedId)
        }
    }

    @Test
    fun `api credential confirmation failure restores the prior credential and keeps the block`() = runTest {
        val bytes = byteArrayOf(12)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000002"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(SharedSetupV2BlockedImportedProfile(blockedId, "Daily", "api_endpoint")),
            listOf(SharedSetupV2BlockedImportedProfile(blockedId, "Daily", "api_endpoint")),
        )
        credentialStore.authorization = "Bearer prior"
        credentialStore.saveRequestHeaders("X-Custom: prior")
        coEvery {
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(blockedId)
        } returns false
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 8, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        viewModel.confirmBlockedApiCredential(blockedId, "fresh-token")
        advanceUntilIdle()

        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).contains("profile editor")
        assertThat(credentialStore.authorization).isEqualTo("Bearer prior")
        assertThat(credentialStore.requestHeaders())
            .containsExactly(APIExportRequestHeader("X-Custom", "prior"))
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)
    }

    @Test
    fun `unreadable credential store fails closed before any mutation`() = runTest {
        val bytes = byteArrayOf(13)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        val production = productionAdapter()
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { production.blockedImportedProfiles() } returns listOf(
            SharedSetupV2BlockedImportedProfile(
                "30000000-0000-4000-8000-000000000003",
                "Daily",
                "api_endpoint",
            ),
        )
        val viewModel = newViewModel(service, store, coordinator, SavedStateHandle(), production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 9, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        credentialStore.failReads = true
        credentialStore.authorization = "Bearer prior"
        viewModel.confirmBlockedApiCredential(
            "30000000-0000-4000-8000-000000000003",
            "fresh-token",
        )
        advanceUntilIdle()

        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).contains("could not be read safely")
        assertThat(credentialStore.authorization).isEqualTo("Bearer prior")
        coVerify(exactly = 0) {
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(any())
        }
    }

    @Test
    fun `invalid api credential is rejected before the store is touched`() = runTest {
        val bytes = byteArrayOf(14)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        val production = productionAdapter()
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { production.blockedImportedProfiles() } returns emptyList()
        val viewModel = newViewModel(service, store, coordinator, SavedStateHandle(), production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 10, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        credentialStore.authorization = "Bearer prior"
        viewModel.confirmBlockedApiCredential(
            "30000000-0000-4000-8000-000000000004",
            "\u0007bad-value",
        )
        advanceUntilIdle()

        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).contains("valid bearer token")
        assertThat(credentialStore.authorization).isEqualTo("Bearer prior")
        assertThat(credentialStore.requestHeaders()).isEmpty()
    }

    @Test
    fun `endpoint url confirmation binds through the trusted hook and refreshes blocked visibility`() = runTest {
        val bytes = byteArrayOf(21)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000011"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        val importedUrl = "https://setup.invalid/import"
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(
                SharedSetupV2BlockedImportedProfile(
                    blockedId, "Daily", "api_endpoint", importedApiEndpointUrl = importedUrl,
                ),
            ),
            listOf(
                SharedSetupV2BlockedImportedProfile(
                    blockedId,
                    "Daily",
                    "api_endpoint",
                    importedApiEndpointUrl = importedUrl,
                    boundApiEndpointUrl = importedUrl,
                ),
            ),
        )
        val bindStarted = CompletableDeferred<Unit>()
        val releaseBind = CompletableDeferred<Boolean>()
        coEvery {
            profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(blockedId)
        } coAnswers {
            bindStarted.complete(Unit)
            releaseBind.await()
        }
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 21, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)

        viewModel.confirmBlockedApiEndpoint(blockedId)
        bindStarted.await()
        assertThat(viewModel.v2RebindState.value)
            .isEqualTo(SharedSetupV2RebindState.ConfirmingApiEndpoint)

        releaseBind.complete(true)
        advanceUntilIdle()

        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
        val refreshed = requireNotNull(viewModel.v2BlockedProfiles.value)
        assertThat(refreshed.single().boundApiEndpointUrl).isEqualTo(importedUrl)
        assertThat(refreshed.single().importedApiEndpointUrl).isEqualTo(importedUrl)
        coVerify(exactly = 1) {
            profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(blockedId)
        }
    }

    @Test
    fun `endpoint url confirmation refusal keeps the block and writes nothing`() = runTest {
        val bytes = byteArrayOf(22)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000012"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        val blockedRow = SharedSetupV2BlockedImportedProfile(
            blockedId,
            "Daily",
            "api_endpoint",
            importedApiEndpointUrl = "https://setup.invalid/import",
        )
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(blockedRow),
            listOf(blockedRow),
        )
        coEvery {
            profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(blockedId)
        } returns false
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 22, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        viewModel.confirmBlockedApiEndpoint(blockedId)
        advanceUntilIdle()

        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).contains("profile editor")
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)
        assertThat(viewModel.v2BlockedProfiles.value?.single()?.boundApiEndpointUrl).isNull()
    }

    @Test
    fun `endpoint confirmation then credential confirmation clears the block end to end`() = runTest {
        val bytes = byteArrayOf(23)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000013"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        val importedUrl = "https://setup.invalid/import"
        val unboundRow = SharedSetupV2BlockedImportedProfile(
            blockedId, "Daily", "api_endpoint", importedApiEndpointUrl = importedUrl,
        )
        val boundRow = unboundRow.copy(boundApiEndpointUrl = importedUrl)
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(unboundRow),
            listOf(boundRow),
            emptyList(),
        )
        coEvery {
            profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(blockedId)
        } returns true
        coEvery {
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(blockedId)
        } returns true
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 23, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        // Step 1: the user explicitly confirms the retained imported URL; the block stays.
        viewModel.confirmBlockedApiEndpoint(blockedId)
        advanceUntilIdle()
        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
        assertThat(viewModel.v2BlockedProfiles.value?.single()?.boundApiEndpointUrl)
            .isEqualTo(importedUrl)

        // Step 2: the existing verified credential write plus unchanged hook clears the block.
        viewModel.confirmBlockedApiCredential(blockedId, "fresh-token")
        advanceUntilIdle()

        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
        assertThat(credentialStore.authorization).isEqualTo("Bearer fresh-token")
        assertThat(viewModel.v2BlockedProfiles.value).isEmpty()
        coVerify(exactly = 1) {
            profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(blockedId)
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(blockedId)
        }
    }

    @Test
    fun `credential failure after a confirmed endpoint binding keeps the block and binding persists`() = runTest {
        val bytes = byteArrayOf(24)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000014"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        val importedUrl = "https://setup.invalid/import"
        val unboundRow = SharedSetupV2BlockedImportedProfile(
            blockedId, "Daily", "api_endpoint", importedApiEndpointUrl = importedUrl,
        )
        val boundRow = unboundRow.copy(boundApiEndpointUrl = importedUrl)
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(unboundRow),
            listOf(boundRow),
            listOf(boundRow),
        )
        coEvery {
            profileRepository.bindSharedSetupV2ApiEndpointAfterConfirmation(blockedId)
        } returns true
        credentialStore.authorization = "Bearer prior"
        coEvery {
            profileRepository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(blockedId)
        } returns false
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 24, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        viewModel.confirmBlockedApiEndpoint(blockedId)
        advanceUntilIdle()
        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)

        viewModel.confirmBlockedApiCredential(blockedId, "fresh-token")
        advanceUntilIdle()

        // Fail closed: the block stays and the unconfirmed credential never remains attached;
        // the explicitly confirmed URL binding persists (documented decision), exactly the
        // state an editor detour would have produced.
        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).contains("profile editor")
        assertThat(credentialStore.authorization).isEqualTo("Bearer prior")
        val blocked = requireNotNull(viewModel.v2BlockedProfiles.value)
        assertThat(blocked).hasSize(1)
        assertThat(blocked.single().boundApiEndpointUrl).isEqualTo(importedUrl)
    }

    @Test
    fun `mac pairing confirmation clears an attested connected-mac profile`() = runTest {
        val bytes = byteArrayOf(15)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000005"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(SharedSetupV2BlockedImportedProfile(blockedId, "Daily", "connected_mac")),
            emptyList(),
            emptyList(),
        )
        coEvery {
            profileRepository.clearSharedSetupV2BlockAfterMacPairingConfirmation(blockedId)
        } returns true
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 11, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        viewModel.confirmBlockedMacPairing(blockedId)
        advanceUntilIdle()

        assertThat(viewModel.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
        assertThat(viewModel.v2BlockedProfiles.value).isEmpty()
        coVerify(exactly = 1) {
            profileRepository.clearSharedSetupV2BlockAfterMacPairingConfirmation(blockedId)
        }
    }

    @Test
    fun `mac pairing confirmation failure keeps the block and resets after process recreation`() = runTest {
        val bytes = byteArrayOf(16)
        val profile = mockk<SharedSetupV2ProfileImportPlan>()
        val plan = mockk<SharedSetupV2ImportPlan>()
        every { profile.bundleId } returns "profile-001"
        every { plan.profiles } returns listOf(profile)
        val service = mockk<SharedSetupService>()
        val store = mockk<SharedSetupDocumentStore>(relaxed = true)
        val coordinator = mockk<SharedSetupCoordinator>(relaxUnitFun = true)
        val imports = MutableStateFlow<PendingSharedSetupImport?>(null)
        val savedState = SavedStateHandle()
        val production = productionAdapter()
        val blockedId = "30000000-0000-4000-8000-000000000006"
        every { coordinator.imports } returns imports
        coEvery { service.pendingEndpoint() } returns null
        coEvery { service.previewVersioned(bytes) } returns
            Result.success(SharedSetupVersionedPreview.V2(plan))
        coEvery {
            service.applyV2(plan, listOf("profile-001"), SharedSetupV2ApplyMode.ADD, production)
        } returns Result.success(
            SharedSetupV2ApplyResult(listOf("profile-001"), SharedSetupV2ApplyMode.ADD),
        )
        val blockedRow = SharedSetupV2BlockedImportedProfile(blockedId, "Daily", "connected_mac")
        coEvery { production.blockedImportedProfiles() } returnsMany listOf(
            listOf(blockedRow),
            listOf(blockedRow),
            listOf(blockedRow),
        )
        coEvery {
            profileRepository.clearSharedSetupV2BlockAfterMacPairingConfirmation(blockedId)
        } returns false
        val viewModel = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        imports.value = PendingSharedSetupImport(id = 12, bytes = bytes)
        advanceUntilIdle()
        viewModel.applyV2(listOf("profile-001"), SharedSetupV2ApplyMode.ADD)
        advanceUntilIdle()

        viewModel.confirmBlockedMacPairing(blockedId)
        advanceUntilIdle()

        val failed = viewModel.v2RebindState.value as SharedSetupV2RebindState.Failed
        assertThat(failed.message).contains("connected-Mac")
        assertThat(viewModel.v2BlockedProfiles.value).hasSize(1)

        // Process death: recreation restores the Applied review and honestly resets the rebind
        // machine to Idle while refreshing blocked visibility, matching ReviewV2 restore behavior.
        val recreated = newViewModel(service, store, coordinator, savedState, production)
        advanceUntilIdle()
        assertThat(recreated.v2TransactionState.value)
            .isInstanceOf(SharedSetupV2TransactionState.Applied::class.java)
        assertThat(recreated.v2RebindState.value).isEqualTo(SharedSetupV2RebindState.Idle)
        assertThat(recreated.v2BlockedProfiles.value).hasSize(1)
    }
}

/**
 * In-memory stand-in for [APIExportCredentialStore] with the same normalization semantics, so
 * ViewModel tests can assert the verified persistence shape of the v2 confirmation flows.
 */
private class InMemoryAPIExportCredentialStore : APIExportCredentialStore {
    var authorization: String? = null
    var requestHeadersRaw: String? = null
    var failReads = false

    override suspend fun authorizationHeader(): String? {
        if (failReads) error("secure store unavailable")
        return authorization
    }

    override suspend fun saveAuthorization(value: String) {
        val validated = APIExportAuthorization.validate(value)
        check(validated is APIExportAuthorizationValidationResult.Valid) { "invalid authorization" }
        authorization = validated.normalizedValue
    }

    override suspend fun clearAuthorization() {
        authorization = null
    }

    override suspend fun hasAuthorization(): Boolean = authorization != null

    override suspend fun requestHeaders(): List<APIExportRequestHeader> {
        if (failReads) error("secure store unavailable")
        return requestHeadersRaw
            ?.lineSequence()
            ?.filter { it.isNotBlank() }
            ?.map { line ->
                val separator = line.indexOf(':')
                APIExportRequestHeader(
                    name = line.substring(0, separator).trim(),
                    value = line.substring(separator + 1).trim(),
                )
            }
            ?.toList()
            ?: emptyList()
    }

    override suspend fun saveRequestHeaders(rawValue: String) {
        requestHeadersRaw = rawValue
    }

    override suspend fun clearRequestHeaders() {
        requestHeadersRaw = null
    }
}

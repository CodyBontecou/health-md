package com.healthmd.sharedsetup

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.io.File

class SharedSetupServiceTest {
    @Test
    fun `preview of canonical fixture performs zero writes`() = runTest {
        val repository = mockk<SettingsRepository>(relaxed = true)
        coEvery { repository.getExportSettings() } returns ExportSettings.newInstallDefaults()
        val service = SharedSetupService(
            repository,
            mockk<ExportScheduler>(relaxed = true),
            InMemoryCredentialStore(null, mutableListOf()),
            FixtureRegistry,
        )

        val result = service.preview(fixtureFile().readBytes())

        assertThat(result.isSuccess).isTrue()
        coVerify(exactly = 0) { repository.updateExportSettings(any()) }
        coVerify(exactly = 0) { repository.applySharedSetupTransaction(any(), any(), any(), any()) }
    }

    @Test
    fun `post commit verification failure rolls back imported settings`() = runTest {
        val previous = ExportSettings.newInstallDefaults().copy(filenameFormat = "before-{date}").normalized()
        var stored = previous
        var undo: ExportSettings? = null
        var committed = false
        val repository = mockk<SettingsRepository>(relaxed = true)
        coEvery { repository.getExportSettings() } answers {
            if (committed) stored.copy(filenameFormat = "verification-corrupt") else stored
        }
        coEvery { repository.applySharedSetupTransaction(any(), any(), any(), any()) } answers {
            undo = stored
            stored = secondArg<ExportSettings>()
            committed = true
            true
        }
        coEvery { repository.rollbackSharedSetupTransaction(any()) } answers {
            val restored = undo
            if (restored != null) {
                stored = restored!!
                committed = false
            }
            restored
        }
        val service = SharedSetupService(
            repository,
            mockk<ExportScheduler>(relaxed = true),
            InMemoryCredentialStore(null, mutableListOf()),
            FixtureRegistry,
        )
        val preview = service.preview(fixtureFile().readBytes()).getOrThrow()

        val result = service.apply(preview)

        assertThat(result.isFailure).isTrue()
        assertThat(stored).isEqualTo(previous)
        coVerify(exactly = 1) { repository.rollbackSharedSetupTransaction(any()) }
    }
    @Test
    fun `failed apply reports an unverified rollback instead of silently ignoring it`() = runTest {
        val previous = ExportSettings.newInstallDefaults().copy(filenameFormat = "before-{date}").normalized()
        var stored = previous
        var committed = false
        val repository = mockk<SettingsRepository>(relaxed = true)
        coEvery { repository.getExportSettings() } answers {
            if (committed) stored.copy(filenameFormat = "verification-corrupt") else stored
        }
        coEvery { repository.applySharedSetupTransaction(any(), any(), any(), any()) } answers {
            stored = secondArg<ExportSettings>()
            committed = true
            true
        }
        coEvery { repository.rollbackSharedSetupTransaction(any()) } returns null
        val service = SharedSetupService(
            repository,
            mockk<ExportScheduler>(relaxed = true),
            InMemoryCredentialStore(null, mutableListOf()),
            FixtureRegistry,
        )
        val preview = service.preview(fixtureFile().readBytes()).getOrThrow()

        val result = service.apply(preview)

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message).contains("could not be verified as restored")
    }

    @Test
    fun `endpoint confirmation clears old authorization and headers before saving new credential`() = runTest {
        val hint = "https://setup.invalid/health"
        var settings = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        var pending: String? = hint
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getPendingSharedSetupEndpoint() } answers { pending }
        coEvery { repository.getExportSettings() } answers { settings }
        coEvery { repository.confirmSharedSetupEndpoint(any(), any(), any()) } answers {
            val expected = firstArg<ExportSettings>()
            val expectedHint = secondArg<String>()
            val candidate = thirdArg<ExportSettings>()
            if (settings == expected && pending == expectedHint) {
                settings = candidate
                pending = null
                true
            } else false
        }
        val credentials = InMemoryCredentialStore(
            authorization = "Bearer old-secret",
            headers = mutableListOf(APIExportRequestHeader("X-Old-Tenant", "old")),
        )
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.confirmPendingEndpoint("new-local-secret")

        assertThat(result.isSuccess).isTrue()
        assertThat(settings.apiEndpointUrl).isEqualTo(hint)
        assertThat(pending).isNull()
        assertThat(credentials.authorization).isEqualTo("Bearer new-local-secret")
        assertThat(credentials.headers).isEmpty()
    }

    @Test
    fun `undo after endpoint confirmation clears new credentials before restoring old endpoint`() = runTest {
        val old = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        var stored = old.copy(apiEndpointUrl = "https://setup.invalid/health").normalized()
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getSharedSetupUndo() } returns old
        coEvery { repository.getExportSettings() } answers { stored }
        coEvery { repository.undoSharedSetupTransaction(any()) } answers {
            stored = old
            old
        }
        val credentials = InMemoryCredentialStore(
            authorization = "Bearer newly-confirmed-secret",
            headers = mutableListOf(APIExportRequestHeader("X-New-Tenant", "new")),
        )
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.undo()

        assertThat(result.isSuccess).isTrue()
        assertThat(stored).isEqualTo(old)
        assertThat(credentials.authorization).isNull()
        assertThat(credentials.headers).isEmpty()
    }

    @Test
    fun `credential cleanup failure leaves Undo snapshot and endpoint untouched`() = runTest {
        val old = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        val current = old.copy(apiEndpointUrl = "https://setup.invalid/health").normalized()
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getExportSettings() } returns current
        coEvery { repository.getSharedSetupUndo() } returns old
        val credentials = mockk<APIExportCredentialStore>()
        coEvery { credentials.authorizationHeader() } returns "Bearer new-secret"
        coEvery { credentials.requestHeaders() } returns emptyList()
        coEvery { credentials.clearAuthorization() } throws IllegalStateException("Synthetic secure-store failure")
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.undo()

        assertThat(result.isFailure).isTrue()
        coVerify(exactly = 0) { repository.undoSharedSetupTransaction(any()) }
    }

    @Test
    fun `failed DataStore Undo restores credential to still-current endpoint`() = runTest {
        val old = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        val current = old.copy(apiEndpointUrl = "https://setup.invalid/health").normalized()
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getExportSettings() } returns current
        coEvery { repository.getSharedSetupUndo() } returns old
        coEvery { repository.undoSharedSetupTransaction(current) } returns null
        val credentials = InMemoryCredentialStore(
            authorization = "Bearer new-secret",
            headers = mutableListOf(APIExportRequestHeader("X-New-Tenant", "new")),
        )
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.undo()

        assertThat(result.isFailure).isTrue()
        assertThat(credentials.authorization).isEqualTo("Bearer new-secret")
        assertThat(credentials.headers).containsExactly(APIExportRequestHeader("X-New-Tenant", "new"))
    }

    @Test
    fun `failed endpoint compare and set restores prior credentials without changing endpoint`() = runTest {
        val hint = "https://setup.invalid/health"
        val previous = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getPendingSharedSetupEndpoint() } returns hint
        coEvery { repository.getExportSettings() } returns previous
        coEvery { repository.confirmSharedSetupEndpoint(any(), any(), any()) } returns false
        val credentials = InMemoryCredentialStore(
            authorization = "Bearer old-secret",
            headers = mutableListOf(APIExportRequestHeader("X-Old-Tenant", "old")),
        )
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.confirmPendingEndpoint("new-local-secret")

        assertThat(result.isFailure).isTrue()
        assertThat(credentials.authorization).isEqualTo("Bearer old-secret")
        assertThat(credentials.headers).containsExactly(APIExportRequestHeader("X-Old-Tenant", "old"))
    }

    @Test
    fun `endpoint confirmation fails closed when prior credentials cannot be read`() = runTest {
        val hint = "https://setup.invalid/health"
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getPendingSharedSetupEndpoint() } returns hint
        coEvery { repository.getExportSettings() } returns ExportSettings.newInstallDefaults()
        val credentials = mockk<APIExportCredentialStore>()
        coEvery { credentials.authorizationHeader() } throws IllegalStateException("Synthetic secure-store read failure")
        coEvery { credentials.requestHeaders() } returns emptyList()
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.confirmPendingEndpoint("new-local-secret")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message).contains("could not be read safely")
        coVerify(exactly = 0) { credentials.saveAuthorization(any()) }
        coVerify(exactly = 0) { credentials.clearAuthorization() }
        coVerify(exactly = 0) { credentials.clearRequestHeaders() }
        coVerify(exactly = 0) { repository.confirmSharedSetupEndpoint(any(), any(), any()) }
    }

    @Test
    fun `endpoint confirmation fails closed when the new credential write cannot be verified`() = runTest {
        val hint = "https://setup.invalid/health"
        val previous = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getPendingSharedSetupEndpoint() } returns hint
        coEvery { repository.getExportSettings() } returns previous
        val credentials = NoOpSaveCredentialStore(authorization = "Bearer old-secret", headers = mutableListOf())
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.confirmPendingEndpoint("new-local-secret")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message).contains("could not be verified as restored")
        assertThat(credentials.authorization).isNull()
        assertThat(credentials.headers).isEmpty()
        coVerify(exactly = 0) { repository.confirmSharedSetupEndpoint(any(), any(), any()) }
    }

    @Test
    fun `endpoint confirmation reports unverified credential restoration after data store verification failure`() = runTest {
        val hint = "https://setup.invalid/health"
        val previous = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        val candidate = previous.copy(apiEndpointUrl = hint).normalized()
        var settings = previous
        var pending: String? = hint
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getPendingSharedSetupEndpoint() } answers { pending }
        coEvery { repository.getExportSettings() } answers {
            // Return a corrupted snapshot after the commit so post-commit verification fails.
            if (pending == null) settings.copy(filenameFormat = "verification-corrupt") else settings
        }
        coEvery { repository.confirmSharedSetupEndpoint(any(), any(), any()) } answers {
            settings = candidate
            pending = null
            true
        }
        coEvery { repository.rollbackSharedSetupEndpointConfirmation(any(), any(), any()) } answers {
            settings = previous
            pending = hint
            true
        }
        val credentials = FailAfterSavesCredentialStore(
            maxSuccessfulSaves = 1,
            authorization = "Bearer old-secret",
            headers = mutableListOf(),
        )
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.confirmPendingEndpoint("new-local-secret")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message).contains("could not be verified as restored")
        assertThat(credentials.authorization).isNull()
        assertThat(credentials.headers).isEmpty()
        assertThat(settings).isEqualTo(previous)
    }

    @Test
    fun `endpoint confirmation rejects a store that silently retains the old credential`() = runTest {
        val hint = "https://setup.invalid/health"
        val previous = ExportSettings.newInstallDefaults().copy(apiEndpointUrl = "https://old.invalid/path").normalized()
        val repository = mockk<SettingsRepository>()
        coEvery { repository.getPendingSharedSetupEndpoint() } returns hint
        coEvery { repository.getExportSettings() } returns previous
        val credentials = RetainingCredentialStore(
            authorization = "Bearer old-secret",
            headers = mutableListOf(APIExportRequestHeader("X-Old-Tenant", "old")),
        )
        val service = SharedSetupService(repository, mockk<ExportScheduler>(relaxed = true), credentials, EmptyRegistry)

        val result = service.confirmPendingEndpoint("new-local-secret")

        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message).contains("new endpoint credential could not be verified")
        assertThat(credentials.authorization).isEqualTo("Bearer old-secret")
        assertThat(credentials.headers).containsExactly(APIExportRequestHeader("X-Old-Tenant", "old"))
        coVerify(exactly = 0) { repository.confirmSharedSetupEndpoint(any(), any(), any()) }
    }

    /** Secure store whose save and clear operations silently retain the prior value. */
    private class RetainingCredentialStore(
        val authorization: String?,
        val headers: MutableList<APIExportRequestHeader>,
    ) : APIExportCredentialStore {
        override suspend fun authorizationHeader(): String? = authorization
        override suspend fun hasAuthorization(): Boolean = authorization != null
        override suspend fun saveAuthorization(value: String) = Unit
        override suspend fun clearAuthorization() = Unit
        override suspend fun requestHeaders(): List<APIExportRequestHeader> = headers.toList()
        override suspend fun saveRequestHeaders(rawValue: String) = Unit
        override suspend fun clearRequestHeaders() = Unit
    }

    private object EmptyRegistry : SharedSetupMetricRegistry {
        override val version = 1
        override val sha256 = "0".repeat(64)
        override val bySemanticId = emptyMap<String, SharedSetupRegistryBinding>()
        override val byAndroidSelectionId = emptyMap<String, SharedSetupRegistryBinding>()
    }

    private object FixtureRegistry : SharedSetupMetricRegistry {
        override val version = 1
        override val sha256 = "b78c44bf0feb723bed467da3bbe2471800842bc8a5eb118c4042e57d9e593319"
        private val bindings = listOf(
            SharedSetupRegistryBinding("active_energy", "active_energy", "active_calories", "mapped_alias"),
            SharedSetupRegistryBinding("blood_pressure_systolic", "blood_pressure_systolic", "bp_systolic", "mapped_alias"),
            SharedSetupRegistryBinding("heart_rate_avg", "heart_rate_avg", "avg_hr", "mapped_alias"),
            SharedSetupRegistryBinding("hrv", "hrv", null, "platform_exact_or_unavailable"),
            SharedSetupRegistryBinding("sleep_core", "sleep_core", "sleep_light", "mapped_alias"),
            SharedSetupRegistryBinding("steps", "steps", "steps", "platform_exact_or_unavailable"),
        )
        override val bySemanticId = bindings.associateBy { it.semanticId }
        override val byAndroidSelectionId = bindings.mapNotNull { binding ->
            binding.androidSelectionId?.let { it to binding }
        }.toMap()
    }

    private fun fixtureFile(): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, "packages/contracts/shared-setup/v1/fixtures/shared-setup-v1.json")
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: error("Could not locate shared-setup fixture")
        }
    }

    /** Secure store whose save operations are silent no-ops, like a disk that ignores writes. */
    private class NoOpSaveCredentialStore(
        var authorization: String?,
        val headers: MutableList<APIExportRequestHeader>,
    ) : APIExportCredentialStore {
        override suspend fun authorizationHeader(): String? = authorization
        override suspend fun hasAuthorization(): Boolean = authorization != null
        override suspend fun saveAuthorization(value: String) = Unit
        override suspend fun clearAuthorization() {
            authorization = null
        }
        override suspend fun requestHeaders(): List<APIExportRequestHeader> = headers.toList()
        override suspend fun saveRequestHeaders(rawValue: String) = Unit
        override suspend fun clearRequestHeaders() {
            headers.clear()
        }
    }

    /** Saves succeed until the quota is reached; later saves fail like a dying secure store. */
    private class FailAfterSavesCredentialStore(
        private val maxSuccessfulSaves: Int,
        authorization: String?,
        headers: MutableList<APIExportRequestHeader>,
    ) : APIExportCredentialStore {
        private val delegate = InMemoryCredentialStore(authorization, headers)
        private var saves = 0
        val authorization: String? get() = delegate.authorization
        val headers: List<APIExportRequestHeader> get() = delegate.headers.toList()
        override suspend fun authorizationHeader(): String? = delegate.authorizationHeader()
        override suspend fun hasAuthorization(): Boolean = delegate.hasAuthorization()
        override suspend fun saveAuthorization(value: String) {
            check(saves < maxSuccessfulSaves) { "Synthetic secure-store write failure" }
            saves += 1
            delegate.saveAuthorization(value)
        }
        override suspend fun clearAuthorization() = delegate.clearAuthorization()
        override suspend fun requestHeaders(): List<APIExportRequestHeader> = delegate.requestHeaders()
        override suspend fun hasRequestHeaders(): Boolean = delegate.hasRequestHeaders()
        override suspend fun saveRequestHeaders(rawValue: String) = delegate.saveRequestHeaders(rawValue)
        override suspend fun clearRequestHeaders() = delegate.clearRequestHeaders()
    }

    private class InMemoryCredentialStore(
        var authorization: String?,
        val headers: MutableList<APIExportRequestHeader>,
    ) : APIExportCredentialStore {
        override suspend fun authorizationHeader(): String? = authorization
        override suspend fun hasAuthorization(): Boolean = authorization != null
        override suspend fun saveAuthorization(value: String) {
            val trimmed = value.trim()
            require(trimmed.isNotEmpty())
            authorization = if (trimmed.startsWith("Bearer ", true) || trimmed.startsWith("Basic ", true)) {
                trimmed
            } else {
                "Bearer $trimmed"
            }
        }
        override suspend fun clearAuthorization() {
            authorization = null
        }
        override suspend fun requestHeaders(): List<APIExportRequestHeader> = headers.toList()
        override suspend fun saveRequestHeaders(rawValue: String) {
            headers.clear()
            rawValue.lineSequence().filter { it.isNotBlank() }.forEach { line ->
                val parts = line.split(':', limit = 2)
                require(parts.size == 2)
                headers += APIExportRequestHeader(parts[0].trim(), parts[1].trim())
            }
        }
        override suspend fun clearRequestHeaders() {
            headers.clear()
        }
    }
}

package com.healthmd.presentation.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import com.healthmd.presentation.common.APISettingsValidationError
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import java.time.LocalDate
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsDestinationsViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val history = mockk<ExportHistoryRepository>(relaxed = true) {
        every { getAllEntries() } returns MutableStateFlow(emptyList())
    }
    private val credentials = mockk<APIExportCredentialStore>(relaxed = true)
    private val tester = mockk<HeadRequestConnectionTester>()

    private fun viewModel(settings: SettingsRepository = mockk(relaxed = true)) =
        SettingsDestinationsViewModel(history, settings, credentials, tester, exportScheduler = null)

    private fun entry(target: ExportTarget, timestamp: Long, success: Int) = ExportHistoryEntry(
        timestamp = timestamp,
        source = ExportSource.MANUAL,
        dateRangeStart = LocalDate.of(2026, 10, 1),
        dateRangeEnd = LocalDate.of(2026, 10, 1),
        successCount = success,
        totalCount = 1,
        target = target,
    )

    @Test
    fun lastSuccessIsTheNewestRunThatWroteToThatDestination() {
        val runs = listOf(
            entry(ExportTarget.DEVICE_FOLDER, 100, 1),
            entry(ExportTarget.DEVICE_FOLDER, 300, 0),
            entry(ExportTarget.API_ENDPOINT, 400, 1),
            entry(ExportTarget.DEVICE_FOLDER, 200, 1),
        )
        assertThat(SettingsDestinationActivity.lastSuccess(ExportTarget.DEVICE_FOLDER, runs)).isEqualTo(200)
        assertThat(SettingsDestinationActivity.lastSuccess(ExportTarget.API_ENDPOINT, runs)).isEqualTo(400)
        assertThat(SettingsDestinationActivity.lastSuccess(ExportTarget.AGENT_DATA_GATEWAY, runs)).isNull()
    }

    @Test
    fun statusTextUsesProtocolReasonPhrasesAndReachabilityAcceptsPostOnlyRoutes() {
        assertThat(SettingsDestinationActivity.httpStatusText(200)).isEqualTo("200 OK")
        assertThat(SettingsDestinationActivity.httpStatusText(401)).isEqualTo("401 Unauthorized")
        assertThat(SettingsDestinationActivity.httpStatusText(418)).isEqualTo("HTTP 418")
        assertThat(SettingsDestinationActivity.isReachable(204)).isTrue()
        assertThat(SettingsDestinationActivity.isReachable(405)).isTrue()
        assertThat(SettingsDestinationActivity.isReachable(401)).isFalse()
        assertThat(SettingsDestinationActivity.isReachable(503)).isFalse()
    }

    @Test
    fun connectionTestUsesATypedTokenOrElseTheSavedCredentials() = runTest(mainDispatcherRule.testDispatcher) {
        val headers = listOf(APIExportRequestHeader("X-Tenant", "a"))
        coEvery { credentials.authorizationHeader() } returns "Bearer saved"
        coEvery { credentials.requestHeaders() } returns headers
        val sentAuthorization = mutableListOf<String?>()
        coEvery { tester.statusCode(any(), captureNullable(sentAuthorization), headers) } returns 405
        val model = viewModel()

        model.testConnection("https://example.com/ingest", draftAuthorization = "typed")
        advanceUntilIdle()
        assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Finished(405))

        model.testConnection("https://example.com/ingest", draftAuthorization = "")
        advanceUntilIdle()
        assertThat(sentAuthorization).containsExactly("Bearer typed", "Bearer saved").inOrder()

        model.resetConnectionTest()
        assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Idle)
    }

    @Test
    fun invalidReplacementTokenDoesNotSendSavedCredentials() = runTest(mainDispatcherRule.testDispatcher) {
        coEvery { credentials.authorizationHeader() } returns "Bearer saved"
        coEvery { tester.statusCode(any(), any(), any()) } returns 200
        val model = viewModel()

        model.testConnection("https://example.com/ingest", "bad\ntoken")
        advanceUntilIdle()

        assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Failed)
        coVerify(exactly = 0) { credentials.authorizationHeader() }
        coVerify(exactly = 0) { tester.statusCode(any(), any(), any()) }
    }

    @Test
    fun connectionTestUsesDraftHeadersWithoutReplacingStoredHeaders() = runTest(mainDispatcherRule.testDispatcher) {
        val savedHeaders = listOf(APIExportRequestHeader("X-Tenant", "saved"))
        val draftHeaders = listOf(APIExportRequestHeader("X-Tenant", "draft"), APIExportRequestHeader("X-Environment", "qa"))
        coEvery { credentials.authorizationHeader() } returns null
        coEvery { credentials.requestHeaders() } returns savedHeaders
        coEvery { tester.statusCode(any(), any(), draftHeaders) } returns 204
        val model = viewModel()

        model.testConnection("https://example.com/ingest", "", "X-Tenant: draft\nX-Environment: qa")
        advanceUntilIdle()

        assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Finished(204))
        coVerify(exactly = 1) { tester.statusCode("https://example.com/ingest", null, draftHeaders) }
        coVerify(exactly = 0) { credentials.requestHeaders() }
    }

    @Test
    fun malformedDraftHeadersDoNotSendARequestOrReadSavedCredentials() = runTest(mainDispatcherRule.testDispatcher) {
        val model = viewModel()

        for (headers in listOf("missing separator", "X-Tenant: a\nx-tenant: b", "Host: other.example", "X-Test: a\rb")) {
            model.testConnection("https://example.com/ingest", "", headers)
            advanceUntilIdle()
            assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Failed)
        }
        coVerify(exactly = 0) { tester.statusCode(any(), any(), any()) }
        coVerify(exactly = 0) { credentials.authorizationHeader() }
        coVerify(exactly = 0) { credentials.requestHeaders() }
    }

    @Test
    fun connectionTestIgnoresInvalidUrlsAndReportsNetworkFailure() = runTest(mainDispatcherRule.testDispatcher) {
        coEvery { tester.statusCode(any(), any(), any()) } throws java.io.IOException("offline")
        val model = viewModel()

        model.testConnection("not a url", "")
        advanceUntilIdle()
        assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Idle)

        model.testConnection("https://example.com", "")
        advanceUntilIdle()
        assertThat(model.connectionTest.value).isEqualTo(ConnectionTestState.Failed)
    }

    @Test
    fun removingTheEndpointClearsCredentialsAndReturnsExportNowToTheFolder() = runTest(mainDispatcherRule.testDispatcher) {
        val settings = mockk<SettingsRepository>(relaxed = true)
        val transform = slot<(ExportSettings) -> ExportSettings>()
        coEvery { settings.updateExportSettingsAtomically(capture(transform)) } returns ExportSettings()
        viewModel(settings).removeApiEndpoint()
        advanceUntilIdle()

        coVerify { credentials.clearAuthorization() }
        coVerify { credentials.clearRequestHeaders() }
        val updated = transform.captured(
            ExportSettings(apiEndpointUrl = "https://example.com", exportTarget = ExportTarget.API_ENDPOINT),
        )
        assertThat(updated.apiEndpointUrl).isEmpty()
        assertThat(updated.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
        val untouched = transform.captured(
            ExportSettings(apiEndpointUrl = "https://example.com", exportTarget = ExportTarget.AGENT_DATA_GATEWAY),
        )
        assertThat(untouched.exportTarget).isEqualTo(ExportTarget.AGENT_DATA_GATEWAY)
    }

    @Test
    fun removingTheGatewayClearsOnlyTheGateway() = runTest(mainDispatcherRule.testDispatcher) {
        val settings = mockk<SettingsRepository>(relaxed = true)
        val transform = slot<(ExportSettings) -> ExportSettings>()
        coEvery { settings.updateExportSettingsAtomically(capture(transform)) } returns ExportSettings()
        viewModel(settings).removeGateway()
        advanceUntilIdle()

        val updated = transform.captured(
            ExportSettings(
                apiEndpointUrl = "https://api.example.com",
                agentDataGatewayUrl = "https://gateway.example.com",
                exportTarget = ExportTarget.AGENT_DATA_GATEWAY,
            ),
        )
        assertThat(updated.agentDataGatewayUrl).isEmpty()
        assertThat(updated.apiEndpointUrl).isEqualTo("https://api.example.com")
        assertThat(updated.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
        coVerify(exactly = 0) { credentials.clearAuthorization() }
    }

    @Test
    fun clearHistoryEmptiesTheHistory() = runTest(mainDispatcherRule.testDispatcher) {
        viewModel().clearHistory()
        advanceUntilIdle()
        coVerify { history.clearAll() }
    }

    @Test
    fun apiDraftValidationReportsTheFirstProblem() {
        assertThat(validateApiDraft("ftp://x", "", "")).isEqualTo(APISettingsValidationError.InvalidEndpoint)
        assertThat(validateApiDraft("https://example.com", "tok\u0001en", ""))
            .isInstanceOf(APISettingsValidationError.InvalidAuthorization::class.java)
        assertThat(validateApiDraft("https://example.com", "", "no separator"))
            .isInstanceOf(APISettingsValidationError.InvalidHeaders::class.java)
        assertThat(validateApiDraft("https://example.com", "token", "X-Tenant: a")).isNull()
    }

    @Test
    fun folderSummaryCountsFoldersInUse() {
        assertThat(SettingsFolderSummary.of(null, "health", emptyList())).isEqualTo(SettingsFolderSummary.None)
        assertThat(SettingsFolderSummary.of("Vault", "health", emptyList()))
            .isEqualTo(SettingsFolderSummary.Default("Vault/health"))
        assertThat(SettingsFolderSummary.of("Vault", " ", listOf(null to null)))
            .isEqualTo(SettingsFolderSummary.Default("Vault"))
        assertThat(SettingsFolderSummary.of("Vault", "health", listOf("content://a" to "Notes")))
            .isEqualTo(SettingsFolderSummary.Own("Notes"))
        assertThat(SettingsFolderSummary.of("Vault", "health", listOf("content://a" to "Notes", null to null)))
            .isEqualTo(SettingsFolderSummary.Several(2))
        assertThat(SettingsFolderSummary.of("Vault", "health", listOf("content://a" to "A", "content://a" to "A")))
            .isEqualTo(SettingsFolderSummary.Own("A"))
    }
}

package com.healthmd.rawexport

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.RawSnapshotExportRunner
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.time.LocalDate
import kotlin.io.path.createTempDirectory
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.junit.Test

class RawSnapshotProductApiServiceTest {
    @Test
    fun apiServiceStreamsContractArtifactAndDeletesPrivateFileAfterSuccess() = runTest {
        withTlsServer(202) { server, client ->
            val fixture = fixture(client, server)
            val result = fixture.runner.exportRange(
                startDate = LocalDate.of(2026, 3, 8),
                endDate = LocalDate.of(2026, 3, 9),
                settings = fixture.settings,
                target = ExportTarget.API_ENDPOINT,
            )

            assertThat(result.isFullSuccess).isTrue()
            assertThat(result.exportMode).isEqualTo(ExportMode.RAW_SNAPSHOT)
            val request = server.takeRequest()
            assertThat(request.getHeader(RawSnapshotExportRunner.HEADER_SCHEMA)).isEqualTo("healthmd.raw-snapshot; version=1")
            assertThat(request.getHeader(RawSnapshotExportRunner.HEADER_EXPORT_ID)).isNotEmpty()
            assertThat(request.getHeader(RawSnapshotExportRunner.HEADER_CHECKSUM)).matches("[0-9a-f]{64}")
            assertThat(request.getHeader(RawSnapshotExportRunner.HEADER_ARTIFACT_CHECKSUM)).matches("[0-9a-f]{64}")
            assertThat(request.getHeader(RawSnapshotExportRunner.HEADER_CALENDAR_ZONE)).isNotEmpty()
            assertThat(request.bodySize).isGreaterThan(0)
            assertThat(completedArtifacts(fixture.root)).isEmpty()
        }
    }

    @Test
    fun allConnectedCreatesIndependentProviderAttemptsWithoutMergingOrHealthConnectFallback() = runTest {
        withTlsServer(202) { server, client ->
            val fixture = fixture(
                client,
                server,
                selectedProviderId = RawSnapshotExportRunner.ALL_CONNECTED_PROVIDER_ID,
                connectedProviderIds = setOf("health_connect", "garmin"),
            )

            val result = fixture.runner.exportRange(
                LocalDate.of(2026, 1, 1),
                LocalDate.of(2026, 1, 1),
                fixture.settings,
                ExportTarget.API_ENDPOINT,
            )

            assertThat(result.successCount).isEqualTo(1)
            assertThat(result.totalCount).isEqualTo(2)
            assertThat(result.isPartialSuccess).isTrue()
            assertThat(result.failedDateDetails.single().errorDetails.orEmpty()).contains("provider")
            assertThat(server.requestCount).isEqualTo(1)
            assertThat(fixture.credentialStore.requestConfigurationCalls).isEqualTo(1)
            assertThat(server.takeRequest().getHeader(RawSnapshotExportRunner.HEADER_PROVIDER)).isEqualTo("health_connect")
            assertThat(completedArtifacts(fixture.root)).isEmpty()
        }
    }

    @Test
    fun apiServiceDeletesPrivateFileAfterRejectedUpload() = runTest {
        withTlsServer(500) { server, client ->
            val fixture = fixture(client, server)
            val result = fixture.runner.exportRange(
                startDate = LocalDate.of(2026, 1, 1),
                endDate = LocalDate.of(2026, 1, 1),
                settings = fixture.settings,
                target = ExportTarget.API_ENDPOINT,
            )

            assertThat(result.isFailure).isTrue()
            assertThat(result.primaryFailureReason).isEqualTo(ExportFailureReason.API_REJECTED)
            assertThat(result.httpStatusCode).isEqualTo(500)
            assertThat(completedArtifacts(fixture.root)).isEmpty()
        }
    }

    private fun fixture(
        client: OkHttpClient,
        server: MockWebServer,
        selectedProviderId: String = RawSnapshotExportRunner.HEALTH_CONNECT_PROVIDER_ID,
        connectedProviderIds: Set<String> = setOf(RawSnapshotExportRunner.HEALTH_CONNECT_PROVIDER_ID),
    ): Fixture {
        val root = createTempDirectory("healthmd-raw-api-test").toFile()
        val context = mockk<Context>()
        every { context.noBackupFilesDir } returns root
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getSelectedHealthProviderId() } returns selectedProviderId
        coEvery { settingsRepository.getConnectedHealthProviderIds() } returns connectedProviderIds
        val credentialStore = CountingCredentialStore(server)
        val settings = ExportSettings(
            exportMode = ExportMode.RAW_SNAPSHOT,
            exportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = server.url("/raw").toString(),
            rawSnapshot = RawSnapshotSettings(format = RawExportFormat.NDJSON),
            metricSelection = MetricSelectionState(setOf("steps")),
        )
        return Fixture(
            root = root,
            settings = settings,
            credentialStore = credentialStore,
            runner = RawSnapshotExportRunner(
                context = context,
                rawRepository = EmptyCompleteRepository(),
                apiClient = RawSnapshotApiClient(client),
                credentialStore = credentialStore,
                settingsRepository = settingsRepository,
            ),
        )
    }

    private suspend fun withTlsServer(
        status: Int,
        block: suspend (MockWebServer, OkHttpClient) -> Unit,
    ) {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val clientCertificates = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer()
        server.useHttps(serverCertificates.sslSocketFactory(), false)
        server.start()
        try {
            server.enqueue(MockResponse().setResponseCode(status).setBody("{}"))
            val client = OkHttpClient.Builder()
                .sslSocketFactory(clientCertificates.sslSocketFactory(), clientCertificates.trustManager)
                .build()
            block(server, client)
        } finally {
            server.shutdown()
        }
    }

    private fun completedArtifacts(root: File): List<File> =
        root.walkTopDown().filter { it.isFile && !it.name.endsWith(".partial") }.toList()

    private data class Fixture(
        val root: File,
        val settings: ExportSettings,
        val credentialStore: CountingCredentialStore,
        val runner: RawSnapshotExportRunner,
    )

    private class CountingCredentialStore(private val server: MockWebServer) : APIExportCredentialStore {
        var requestConfigurationCalls = 0
        override suspend fun authorizationHeader(): String? = "Bearer secret"
        override suspend fun hasAuthorization(): Boolean = true
        override suspend fun saveAuthorization(value: String) = Unit
        override suspend fun clearAuthorization() = Unit
        override suspend fun requestConfiguration(endpointUrl: String): APIExportRequestConfiguration {
            requestConfigurationCalls++
            return APIExportRequestConfiguration(
                endpointUrl = server.url("/raw").toString(),
                authorizationHeader = "Bearer secret",
                requestHeaders = emptyList(),
                destinationFingerprint = "fingerprint",
            )
        }
    }

    private class EmptyCompleteRepository : RawHealthRepository {
        override suspend fun capabilities() = RawProviderCapabilities(available = true)

        override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
            emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
            RawExportTypeCatalog.definitions.forEach { definition ->
                val selected = RawExportTypeCatalog.isSelected(definition, request)
                emit(
                    RawExportItem.TypeReport(
                        RawTypeReport(
                            typeKey = definition.typeKey,
                            wireType = definition.wireType,
                            status = if (selected) RawTypeStatus.EXPORTED else RawTypeStatus.NOT_SELECTED,
                            permission = definition.permission,
                            feature = definition.feature,
                            rangeBehavior = definition.rangeBehavior,
                        ),
                    ),
                )
            }
            emit(RawExportItem.Status(RawSnapshotStatus.COMPLETE))
        }
    }
}

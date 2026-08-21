package com.healthmd.rawexport

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.export.RawSnapshotExportRunner
import com.healthmd.data.drive.GeneratedExportBundle
import com.healthmd.data.drive.GeneratedExportBundleFactory
import com.healthmd.data.drive.GoogleDriveDestinationRunner
import com.healthmd.data.drive.GoogleDriveRunResult
import com.healthmd.data.drive.GoogleDriveSelectionStore
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.slot
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
    fun previewBuildsRawRangeArtifactWithoutDestinationOrUploadAndDeletesPrivateFile() = runTest {
        withTlsServer(202) { server, client ->
            val fixture = fixture(client, server)

            val preview = fixture.runner.previewRange(
                startDate = LocalDate.of(2026, 3, 8),
                endDate = LocalDate.of(2026, 3, 9),
                settings = fixture.settings.copy(apiEndpointUrl = ""),
            )

            assertThat(preview.isRangeArtifact).isTrue()
            assertThat(preview.requestedDateCount).isEqualTo(2)
            assertThat(preview.previewedDateCount).isEqualTo(2)
            assertThat(preview.totalFileCount).isEqualTo(1)
            assertThat(preview.days.single().requestedDates)
                .containsExactly(LocalDate.of(2026, 3, 8), LocalDate.of(2026, 3, 9))
                .inOrder()
            val artifact = preview.days.single().files.single()
            assertThat(artifact.formatLabel).isEqualTo("NDJSON")
            assertThat(artifact.relativePath).contains("health/raw/healthmd-raw-health_connect-2026-03-08_to_2026-03-09-schema-v1")
            assertThat(artifact.content).contains("\"kind\":\"header\"")
            assertThat(artifact.content).contains("\"kind\":\"manifest\"")
            assertThat(server.requestCount).isEqualTo(0)
            assertThat(fixture.credentialStore.requestConfigurationCalls).isEqualTo(0)
            assertThat(completedArtifacts(fixture.root)).isEmpty()
        }
    }

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
            assertThat(result.failedDateDetails.single().errorDetails).isNull()
            assertThat(server.requestCount).isEqualTo(1)
            assertThat(fixture.credentialStore.requestConfigurationCalls).isEqualTo(1)
            assertThat(server.takeRequest().getHeader(RawSnapshotExportRunner.HEADER_PROVIDER)).isEqualTo("health_connect")
            assertThat(completedArtifacts(fixture.root)).isEmpty()
        }
    }

    @Test
    fun driveRawExportJournalsArtifactAndChecksumSidecarUnderOneOperation() = runTest {
        val root = createTempDirectory("healthmd-raw-drive-test").toFile()
        val context = mockk<Context>()
        every { context.noBackupFilesDir } returns root
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getSelectedHealthProviderId() } returns RawSnapshotExportRunner.HEALTH_CONNECT_PROVIDER_ID
        coEvery { settingsRepository.getConnectedHealthProviderIds() } returns setOf(RawSnapshotExportRunner.HEALTH_CONNECT_PROVIDER_ID)
        val selection = mockk<GoogleDriveSelectionStore>()
        coEvery { selection.get() } returns "destination-1"
        val driveRunner = mockk<GoogleDriveDestinationRunner>()
        coEvery { driveRunner.resumeIfPresent("raw-operation", "destination-1", null, any()) } returns null
        val bundle = slot<GeneratedExportBundle>()
        coEvery { driveRunner.run(capture(bundle), "destination-1") } returns GoogleDriveRunResult.Complete(2)
        val runner = RawSnapshotExportRunner(
            context = context,
            rawRepository = EmptyCompleteRepository(),
            apiClient = mockk(relaxed = true),
            credentialStore = mockk(relaxed = true),
            settingsRepository = settingsRepository,
            driveBundleFactory = GeneratedExportBundleFactory(
                MarkdownExporter(), JsonExporter(), CsvExporter(), ObsidianBasesExporter(),
            ),
            driveRunner = driveRunner,
            driveSelectionStore = selection,
        )
        val settings = ExportSettings(
            exportMode = ExportMode.RAW_SNAPSHOT,
            exportTarget = ExportTarget.GOOGLE_DRIVE,
            rawSnapshot = RawSnapshotSettings(format = RawExportFormat.NDJSON),
            metricSelection = MetricSelectionState(setOf("steps")),
        )

        val result = runner.exportRange(
            LocalDate.of(2026, 3, 8),
            LocalDate.of(2026, 3, 9),
            settings,
            ExportTarget.GOOGLE_DRIVE,
            googleDriveDestinationId = "destination-1",
            googleDriveProfileId = "profile-1",
            googleDriveOperationId = "raw-operation",
        )

        assertThat(result.isFullSuccess).isTrue()
        assertThat(bundle.captured.operationId).isEqualTo("raw-operation")
        assertThat(bundle.captured.profileId).isEqualTo("profile-1")
        assertThat(bundle.captured.artifacts).hasSize(2)
        assertThat(bundle.captured.artifacts.map { it.relativePath }.count { it.endsWith(".sha256") }).isEqualTo(1)
        assertThat(completedArtifacts(root)).isEmpty()
    }

    @Test
    fun driveRawRetryResumesBeforeProviderCapture() = runTest {
        val root = createTempDirectory("healthmd-raw-drive-resume-test").toFile()
        val context = mockk<Context>()
        every { context.noBackupFilesDir } returns root
        val repository = EmptyCompleteRepository()
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getSelectedHealthProviderId() } returns RawSnapshotExportRunner.HEALTH_CONNECT_PROVIDER_ID
        coEvery { settingsRepository.getConnectedHealthProviderIds() } returns setOf(RawSnapshotExportRunner.HEALTH_CONNECT_PROVIDER_ID)
        val selection = mockk<GoogleDriveSelectionStore>()
        coEvery { selection.get() } returns "destination-1"
        val driveRunner = mockk<GoogleDriveDestinationRunner>()
        coEvery { driveRunner.resumeIfPresent("raw-operation", "destination-1", null, any()) } returns
            GoogleDriveRunResult.Complete(2)
        val runner = RawSnapshotExportRunner(
            context = context,
            rawRepository = repository,
            apiClient = mockk(relaxed = true),
            credentialStore = mockk(relaxed = true),
            settingsRepository = settingsRepository,
            driveBundleFactory = mockk(relaxed = true),
            driveRunner = driveRunner,
            driveSelectionStore = selection,
        )
        val settings = ExportSettings(
            exportMode = ExportMode.RAW_SNAPSHOT,
            exportTarget = ExportTarget.GOOGLE_DRIVE,
            rawSnapshot = RawSnapshotSettings(format = RawExportFormat.NDJSON),
            metricSelection = MetricSelectionState(setOf("steps")),
        )

        val result = runner.exportRange(
            LocalDate.of(2026, 3, 8),
            LocalDate.of(2026, 3, 9),
            settings,
            ExportTarget.GOOGLE_DRIVE,
            googleDriveDestinationId = "destination-1",
            googleDriveOperationId = "raw-operation",
        )

        assertThat(result.isFullSuccess).isTrue()
        assertThat(repository.streamCalls).isEqualTo(0)
        coVerify(exactly = 0) { driveRunner.run(any(), any()) }
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
                driveBundleFactory = mockk(relaxed = true),
                driveRunner = mockk(relaxed = true),
                driveSelectionStore = mockk(relaxed = true),
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
        var streamCalls: Int = 0
            private set
        override suspend fun capabilities() = RawProviderCapabilities(available = true)

        override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
            streamCalls += 1
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

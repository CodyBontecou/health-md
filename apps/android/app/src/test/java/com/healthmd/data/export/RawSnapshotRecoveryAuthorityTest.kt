package com.healthmd.data.export

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.APIRecoveryExecution
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.export.FakeSettingsRepository
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawApiUploadResult
import com.healthmd.rawexport.RawExportItem
import com.healthmd.rawexport.RawExportTypeCatalog
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.RawProviderCapabilities
import com.healthmd.rawexport.RawSnapshotApiClient
import com.healthmd.rawexport.RawSnapshotApiException
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotStatus
import com.healthmd.rawexport.RawTypeReport
import com.healthmd.rawexport.RawTypeStatus
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.nio.file.Files
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import org.junit.Test

class RawSnapshotRecoveryAuthorityTest {
    private val day = LocalDate.ofEpochDay(10_000)
    private val endpoint = "https://synthetic.example.test/raw"

    @Test
    fun losingTheWholeRawJournalAfterAttemptedCaptureNeverRecapturesWithoutAnUpload() = runTest {
        withHarness { h ->
            h.repository.failCapture = true
            assertThat(h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT).isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            java.io.File(h.root, "scheduled-raw-api-v1").deleteRecursively()
            h.repository.failCapture = false
            assertThat(h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT).isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).isEmpty()
        }
    }

    @Test
    fun explicitDiscardAfterUnknownRawUploadOutcomePurgesRetainedCopiesAndPreventsRestartedDelivery() = runTest {
        withHarness { h ->
            h.failUpload = true
            h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).hasSize(1)
            RecoveryDiscardFence(h.root).discard(listOf("raw-operation"))
            h.failUpload = false
            assertThat(h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT).isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).hasSize(1)
            assertThat(h.root.walkTopDown().filter { it.name == "journal.json" || it.name.endsWith(".bin") || it.name.startsWith("spool-") }.toList()).isEmpty()
        }
    }

    @Test
    fun discardWhileRawMetadataIsSuspendedPreventsLateSpoolAllocationAndSourceRead() = runTest {
        withHarness { h ->
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            h.repository.beforeCapabilities = { entered.complete(Unit); release.await() }
            val late = async { h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT) }
            entered.await()
            RecoveryDiscardFence(h.root).discard(listOf("raw-operation"))
            release.complete(Unit)
            assertThat(late.await().isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(0)
            assertThat(h.bodies).isEmpty()
            assertThat(h.root.walkTopDown().filter { it.name.startsWith("spool-") || it.name == "journal.json" }.toList()).isEmpty()
        }
    }

    @Test
    fun discardDuringSuspendedRawReadPurgesOwnedSortSpoolsWithoutWaitingForCoroutineTeardown() = runTest {
        withHarness { h ->
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            h.repository.afterRead = { entered.complete(Unit); release.await() }
            val late = async { h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT) }
            entered.await()
            assertThat(h.root.walkTopDown().filter { it.name.startsWith("spool-") }.count()).isEqualTo(1)
            RecoveryDiscardFence(h.root).discard(listOf("raw-operation"))
            assertThat(h.root.walkTopDown().filter { it.name.startsWith("spool-") }.toList()).isEmpty()
            release.complete(Unit)
            assertThat(late.await().isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).isEmpty()
            assertThat(h.root.walkTopDown().filter { it.name.startsWith("spool-") || it.name == "journal.json" }.toList()).isEmpty()
        }
    }

    @Test
    fun explicitDiscardDuringRawPreparationCannotRecaptureAfterRunnerRestart() = runTest {
        withHarness { h ->
            h.repository.afterRead = { RecoveryDiscardFence(h.root).discard(listOf("raw-operation")) }
            val first = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(first.isFailure).isTrue()
            h.repository.afterRead = {}
            val restarted = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(restarted.isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).isEmpty()
            assertThat(h.root.walkTopDown().filter { it.name == "journal.json" || it.name.endsWith(".bin") || it.name.endsWith(".partial") }.toList()).isEmpty()
        }
    }

    @Test
    fun legacyAndRotatedEndpointAuthorizationHeaderOrProfileFailBeforeAnyRawReadOrUpload() = runTest {
        for (rotation in 0..6) withHarness { h ->
            var settings = h.settings
            when (rotation) {
                0 -> settings = settings.copy(executionAPIRecovery = APIRecoveryExecution(null, "profile", "raw-operation", h.snapshot) { true })
                1 -> settings = settings.copy(apiEndpointUrl = "$endpoint/rotated")
                2 -> h.credentials.authorization = "Bearer rotated"
                3 -> h.credentials.headers = emptyList()
                4 -> settings = settings.copy(executionAPIRecovery = APIRecoveryExecution(h.authority, "replacement", "raw-operation", h.snapshot) { true })
                5 -> settings = settings.copy(executionAPIRecovery = APIRecoveryExecution("{}", "profile", "raw-operation", h.snapshot) { true })
                6 -> settings = settings.copy(executionAPIRecovery = APIRecoveryExecution(h.authority.replace("\"version\":1", "\"version\":2"), "profile", "raw-operation", h.snapshot) { true })
            }
            val result = h.runner().exportRange(day, day, settings, ExportTarget.API_ENDPOINT)
            assertThat(result.successCount).isEqualTo(0)
            assertThat(h.repository.reads).isEqualTo(0)
            assertThat(h.bodies).isEmpty()
        }
    }

    @Test
    fun unknownUploadOutcomeRecoversExactArtifactAndHeadersWithoutFreshCapture() = runTest {
        withHarness { h ->
            h.failUpload = true
            val failed = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(failed.retryOperationIds.values).containsExactly("raw-operation")
            assertThat(h.repository.reads).isEqualTo(1)
            val body = h.bodies.single()
            val headers = h.headers.single()
            assertThat(body.decodeToString()).doesNotContain(h.authority)
            assertThat(body.decodeToString()).doesNotContain("synthetic-token")
            h.failUpload = false
            val recovered = h.runner().exportRange(day, day, h.settings.copy(includeMetadata = false), ExportTarget.API_ENDPOINT)
            assertThat(recovered.isFullSuccess).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).hasSize(2)
            assertThat(h.bodies.last()).isEqualTo(body)
            assertThat(h.headers.last()).isEqualTo(headers)
            h.runner().discardCompletedDurableOperation("raw-operation")
            assertThat(h.root.walkTopDown().filter { it.name.endsWith(".bin") }.toList()).isEmpty()
        }
    }

    @Test
    fun deliveryIsFencedBeforeUploadAndLosingTheEntireJournalCannotRecapture() = runTest {
        withHarness { h ->
            h.failUpload = true
            h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(h.journalRequired).isTrue()
            h.root.walkTopDown().first { it.name == "journal.json" }.delete()
            h.failUpload = false
            val missing = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(missing.isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).hasSize(1)
        }
        withHarness { h ->
            h.checkpointAllowed = false
            val notDurable = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(notDurable.isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(0)
            assertThat(h.bodies).isEmpty()
        }
    }

    @Test
    fun missingPreparedArtifactAndChangedRequestNeverRecaptureOrUpload() = runTest {
        withHarness { h ->
            h.failUpload = true
            h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            val reads = h.repository.reads
            val uploads = h.bodies.size
            h.failUpload = false
            val changed = h.settings.copy(metricSelection = MetricSelectionState(setOf("weight")))
            val mismatch = h.runner().exportRange(day, day, changed, ExportTarget.API_ENDPOINT)
            assertThat(mismatch.isFailure).isTrue()
            h.root.walkTopDown().first { it.name.endsWith(".bin") }.delete()
            val missing = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(missing.isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(reads)
            assertThat(h.bodies).hasSize(uploads)
        }
    }

    @Test
    fun discardDuringCaptureFencesUploadAndAnInterruptedCaptureCannotRestartUnderSameIdentity() = runTest {
        withHarness { h ->
            h.repository.afterRead = { h.authorized = false }
            val discarded = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(discarded.isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).isEmpty()
        }
        withHarness { h ->
            h.repository.failCapture = true
            h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            h.repository.failCapture = false
            val repeated = h.runner().exportRange(day, day, h.settings, ExportTarget.API_ENDPOINT)
            assertThat(repeated.isFailure).isTrue()
            assertThat(h.repository.reads).isEqualTo(1)
            assertThat(h.bodies).isEmpty()
        }
    }

    private suspend fun withHarness(test: suspend (Harness) -> Unit) {
        val root = Files.createTempDirectory("raw-authority").toFile()
        try { test(Harness(root)) } finally { root.deleteRecursively() }
    }

    private inner class Harness(val root: java.io.File) {
        val context = mockk<Context> { every { noBackupFilesDir } returns root }
        val repository = Repository()
        val credentials = Credentials()
        val authority = APIRecoveryAuthorities.create(credentials.configuration(endpoint), "profile")
        private val baseSettings = ExportSettings(exportMode = ExportMode.RAW_SNAPSHOT,
            exportTarget = ExportTarget.API_ENDPOINT, scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = endpoint, metricSelection = MetricSelectionState(setOf("steps")))
        val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(baseSettings, null, ZoneId.of("UTC")))
        var authorized = true
        var journalRequired = false
        var checkpointAllowed = true
        val settings get() = baseSettings.copy(executionAPIRecoveryRequired = true,
            executionAPIRecovery = APIRecoveryExecution(authority, "profile", "raw-operation", snapshot,
                requireExistingJournal = journalRequired, onJournalPrepared = {
                    if (checkpointAllowed) { journalRequired = true; true } else false
                }) { authorized })
        val settingsRepository = FakeSettingsRepository(initialSettings = baseSettings)
        val bodies = mutableListOf<ByteArray>()
        val headers = mutableListOf<List<com.healthmd.rawexport.RawApiHeader>>()
        var failUpload = false
        val apiClient = mockk<RawSnapshotApiClient>().apply {
            coEvery { upload(any(), any(), any(), any()) } coAnswers {
                assertThat(journalRequired).isTrue()
                val artifact = secondArg<com.healthmd.rawexport.CompletedRawSnapshot>()
                bodies += artifact.openStream().use { it.readBytes() }
                headers += arg<List<com.healthmd.rawexport.RawApiHeader>>(3)
                if (failUpload) throw RawSnapshotApiException(true, message = "synthetic unknown outcome")
                RawApiUploadResult(202, null)
            }
        }
        fun runner() = RawSnapshotExportRunner(context, repository, apiClient, credentials, settingsRepository)
    }

    private class Repository : RawHealthRepository {
        var reads = 0
        var failCapture = false
        var afterRead: suspend () -> Unit = {}
        var beforeCapabilities: suspend () -> Unit = {}
        override suspend fun capabilities(): RawProviderCapabilities {
            beforeCapabilities()
            return RawProviderCapabilities(available = true)
        }
        override fun stream(request: RawSnapshotRequest) = flow {
            reads++; afterRead()
            if (failCapture) error("synthetic capture interrupted")
            RawExportTypeCatalog.definitions.forEach { definition ->
                emit(RawExportItem.TypeReport(RawTypeReport(
                    typeKey = definition.typeKey, wireType = definition.wireType,
                    status = if (definition.typeKey == "steps") RawTypeStatus.EXPORTED else RawTypeStatus.NOT_SELECTED,
                    permission = definition.permission, feature = definition.feature, rangeBehavior = definition.rangeBehavior,
                )))
            }
            emit(RawExportItem.Status(RawSnapshotStatus.COMPLETE))
        }
    }

    private class Credentials : APIExportCredentialStore {
        var authorization: String? = "Bearer synthetic-token"
        var headers = listOf(APIExportRequestHeader("X-Key", "synthetic-header"))
        fun configuration(endpoint: String) = APIExportRequestConfiguration(endpoint, authorization, headers,
            com.healthmd.domain.model.APIExportEndpoint.fingerprint(endpoint)!!)
        override suspend fun authorizationHeader() = authorization
        override suspend fun hasAuthorization() = authorization != null
        override suspend fun requestHeaders() = headers
        override suspend fun saveAuthorization(value: String) { authorization = value }
        override suspend fun clearAuthorization() { authorization = null }
    }
}

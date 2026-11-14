package com.healthmd.data.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.APIExportNativePlanBuilder
import com.healthmd.domain.exportengine.APIExportRustPlanner
import com.healthmd.domain.exportengine.ProfileScopedAPIExportEnginePolicyResolver
import com.healthmd.domain.model.APIRecoveryExecution
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthData
import io.mockk.every
import io.mockk.mockk
import android.content.Context
import java.nio.file.Files
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class APIRecoveryAuthorityTest {
    private val date = LocalDate.ofEpochDay(10_000)
    private val endpoint = "https://synthetic.example.test/ingest"

    @Test
    fun evidenceIsBoundedPrivateNonceScopedAndBindsEveryAuthorityField() = runTest {
        val credentials = Credentials()
        val configuration = credentials.requestConfiguration(endpoint)!!
        val evidence = credentials.createRecoveryAuthority(endpoint, "synthetic-profile")!!
        assertThat(evidence.length).isAtMost(APIRecoveryAuthorities.MAX_EVIDENCE_CHARACTERS)
        assertThat(evidence).doesNotContain(endpoint)
        assertThat(evidence).doesNotContain("synthetic-profile")
        assertThat(evidence).doesNotContain("synthetic-token")
        assertThat(evidence).doesNotContain("synthetic-header")
        assertThat(credentials.matchesRecoveryAuthority(evidence, configuration, "synthetic-profile")).isTrue()
        assertThat(credentials.createRecoveryAuthority(endpoint, "synthetic-profile")).isNotEqualTo(evidence)
        val changes = listOf(
            configuration.copy(endpointUrl = "$endpoint/changed"),
            configuration.copy(authorizationHeader = "Bearer rotated"),
            configuration.copy(requestHeaders = listOf(APIExportRequestHeader("X-Key", "rotated"))),
            configuration.copy(requestHeaders = emptyList()),
            configuration.copy(authorizationHeader = null),
        )
        changes.forEach { assertThat(credentials.matchesRecoveryAuthority(evidence, it, "synthetic-profile")).isFalse() }
        assertThat(credentials.matchesRecoveryAuthority(evidence, configuration, "replacement-profile")).isFalse()
        assertThat(credentials.matchesRecoveryAuthority(null, configuration, "synthetic-profile")).isFalse()
        assertThat(credentials.matchesRecoveryAuthority("{".repeat(300), configuration, "synthetic-profile")).isFalse()
        assertThat(APIRecoveryAuthorities.isValid(evidence.replace("\"version\":1,", ""))).isFalse()
        val key = ByteArray(32) { 3 }
        val keyed = APIRecoveryAuthorities.create(configuration, null, key)
        assertThat(APIRecoveryAuthorities.matches(keyed, configuration, null, key)).isTrue()
        assertThat(APIRecoveryAuthorities.matches(keyed, configuration, null, ByteArray(32) { 4 })).isFalse()
        assertThat(APIRecoveryAuthorities.matches(keyed, configuration, null)).isFalse()
    }

    @Test
    fun preJournalLegacyEndpointAuthorizationHeaderAndProfileRotationHaveZeroReadsAndUploads() = runTest {
        for (rotation in 0..7) {
            val credentials = Credentials()
            val evidence = credentials.createRecoveryAuthority(endpoint, "profile")
            val capture = Capture()
            val uploader = Uploader()
            val runner = runner(credentials, capture, uploader)
            var settings = scheduledSettings(evidence, "profile")
            when (rotation) {
                0 -> settings = scheduledSettings(null, "profile")
                1 -> settings = settings.copy(apiEndpointUrl = "$endpoint/changed")
                2 -> credentials.authorization = "Bearer rotated"
                3 -> credentials.headers = listOf(APIExportRequestHeader("X-Key", "rotated"))
                4 -> settings = scheduledSettings(evidence, "replacement-profile")
                5 -> settings = settings.copy(executionAPIRecovery = null)
                6 -> settings = scheduledSettings("{}", "profile")
                7 -> settings = scheduledSettings(evidence!!.replace("\"version\":1", "\"version\":2"), "profile")
            }
            val result = runner.exportDates(listOf(date), settings, durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(result.successCount).isEqualTo(0)
            assertThat(result.primaryFailureReason).isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
            assertThat(capture.reads).isEqualTo(0)
            assertThat(uploader.bodies).isEmpty()
        }
    }

    @Test
    fun unknownPreparedOutcomeReusesExactBodySettingsAndAuthorityWithoutRecapture() = runTest {
        val root = Files.createTempDirectory("authority-journal").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val credentials = Credentials()
            val evidence = credentials.createRecoveryAuthority(endpoint, "profile")
            val capture = Capture()
            val uploader = Uploader().apply { fail = true }
            val firstStore = FileAPIExportOperationStore(context)
            val settings = scheduledSettings(evidence, "profile")
            val first = runner(credentials, capture, uploader, firstStore)
                .exportDates(listOf(date), settings, durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(first.retryOperationIds.values).containsExactly("operation")
            val original = firstStore.load("operation")!!
            assertThat(original.apiAuthorityJson).isEqualTo(evidence)
            val body = uploader.bodies.single()
            uploader.fail = false
            val recovered = runner(credentials, capture, uploader, FileAPIExportOperationStore(context))
                .exportDates(listOf(date), settings.copy(includeMetadata = false), durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(recovered.isFullSuccess).isTrue()
            assertThat(capture.reads).isEqualTo(1)
            assertThat(uploader.bodies).containsExactly(body, body).inOrder()
            assertThat(body).doesNotContain("authority")
            assertThat(body).doesNotContain("synthetic-token")
            credentials.headers = emptyList()
            val rotated = runner(credentials, capture, uploader, firstStore)
                .exportDates(listOf(date), settings, durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(rotated.primaryFailureReason).isEqualTo(ExportFailureReason.INVALID_API_ENDPOINT)
            assertThat(capture.reads).isEqualTo(1)
            assertThat(uploader.bodies).hasSize(2)
            assertThat(firstStore.load("operation")!!.batches.single().bytes).isEqualTo(original.batches.single().bytes)
        } finally { root.deleteRecursively() }
    }

    @Test
    fun missingJournalRefusalIsDurableBeforeUnknownDeliveryAndCheckpointFailurePreventsUpload() = runTest {
        val root = Files.createTempDirectory("authority-pre-delivery").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val store = FileAPIExportOperationStore(context)
            val credentials = Credentials()
            val evidence = credentials.createRecoveryAuthority(endpoint, null)
            val capture = Capture()
            var required = false
            val uploader = Uploader().apply { fail = true; beforeUpload = { assertThat(required).isTrue() } }
            fun settings() = scheduledSettings(evidence, null).copy(executionAPIRecovery =
                APIRecoveryExecution(evidence, null, "operation", "snapshot", required,
                    onJournalPrepared = { required = true; true }) { true })
            runner(credentials, capture, uploader, store).exportDates(listOf(date), settings(),
                durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(required).isTrue()
            store.delete("operation")
            uploader.fail = false
            val missing = runner(credentials, capture, uploader, store).exportDates(listOf(date), settings(),
                durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(missing.isFailure).isTrue()
            assertThat(capture.reads).isEqualTo(1)
            assertThat(uploader.bodies).hasSize(1)
            val blocked = settings().copy(executionAPIRecovery = APIRecoveryExecution(evidence, null, "operation", "snapshot",
                onJournalPrepared = { false }) { true })
            runner(credentials, capture, uploader, store).exportDates(listOf(date), blocked,
                durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(capture.reads).isEqualTo(2)
            assertThat(uploader.bodies).hasSize(1)
        } finally { root.deleteRecursively() }
    }

    @Test
    fun discardDuringCaptureBlocksUploadAndMissingPreparedJournalNeverRecaptures() = runTest {
        val credentials = Credentials()
        val evidence = credentials.createRecoveryAuthority(endpoint, null)
        var authorized = true
        val capture = Capture().apply { afterRead = { authorized = false } }
        val uploader = Uploader()
        val root = Files.createTempDirectory("authority-discard").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val store = FileAPIExportOperationStore(context)
            val settings = scheduledSettings(evidence, null) { authorized }
            val result = runner(credentials, capture, uploader, store)
                .exportDates(listOf(date), settings, durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(result.successCount).isEqualTo(0)
            assertThat(uploader.bodies).isEmpty()
            authorized = true
            val missing = settings.copy(executionAPIRecovery = APIRecoveryExecution(evidence, null, "operation", "snapshot", true) { true })
            runner(credentials, capture, uploader, store)
                .exportDates(listOf(date), missing, durableOperationId = "operation", durableSettingsSnapshotJson = "snapshot")
            assertThat(capture.reads).isEqualTo(1)
            assertThat(uploader.bodies).isEmpty()
        } finally { root.deleteRecursively() }
    }

    private fun scheduledSettings(evidence: String?, binding: String?, authorized: suspend () -> Boolean = { true }) = ExportSettings(
        exportTarget = ExportTarget.API_ENDPOINT, apiEndpointUrl = endpoint,
        executionAPIRecoveryRequired = true,
        executionAPIRecovery = APIRecoveryExecution(evidence, binding, "operation", "snapshot", isStillAuthorized = authorized),
    )

    private fun runner(credentials: Credentials, capture: Capture, uploader: Uploader, store: APIExportOperationStore? = null) = APIEndpointExportRunner(
        captureSource = capture, envelopeBuilder = APIExportEnvelopeBuilder(JsonExporter()), uploader = uploader,
        credentialStore = credentials, policyResolver = ProfileScopedAPIExportEnginePolicyResolver(),
        nativePlanner = APIExportNativePlanBuilder { error("Unexpected planner") },
        rustPlanner = APIExportRustPlanner { error("Unexpected planner") }, operationStore = store,
    )

    private class Capture : APIExportCaptureSource {
        var reads = 0
        var afterRead: () -> Unit = {}
        override fun isBeforeFirstUnlock() = false
        override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData {
            reads++; afterRead()
            return HealthData(date, activity = ActivityData(steps = 1))
        }
    }

    private class Uploader : APIExportUploader {
        var fail = false
        var beforeUpload: () -> Unit = {}
        val bodies = mutableListOf<String>()
        override suspend fun upload(endpointUrl: String, payload: String, authorizationHeader: String?, requestHeaders: List<APIExportRequestHeader>): APIExportUploadResult {
            beforeUpload()
            bodies += payload
            if (fail) throw APIExportClientException(ExportFailureReason.NETWORK_ERROR, retryable = true, message = "synthetic failure")
            return APIExportUploadResult(202, null)
        }
    }

    private class Credentials : APIExportCredentialStore {
        var authorization: String? = "Bearer synthetic-token"
        var headers = listOf(APIExportRequestHeader("X-Key", "synthetic-header"))
        override suspend fun authorizationHeader() = authorization
        override suspend fun hasAuthorization() = authorization != null
        override suspend fun requestHeaders() = headers
        override suspend fun saveAuthorization(value: String) { authorization = value }
        override suspend fun clearAuthorization() { authorization = null }
    }
}

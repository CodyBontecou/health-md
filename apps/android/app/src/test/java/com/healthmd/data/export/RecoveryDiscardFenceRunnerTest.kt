package com.healthmd.data.export

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.APIExportEnginePolicyResolver
import com.healthmd.domain.exportengine.APIExportNativePlanBuilder
import com.healthmd.domain.exportengine.APIExportRustPlan
import com.healthmd.domain.exportengine.APIExportRustPlanner
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePolicyTarget
import com.healthmd.domain.exportengine.ProductionAPIExportNativePlanBuilder
import com.healthmd.domain.exportengine.ResolvedExportEnginePolicy
import com.healthmd.domain.exportengine.testPin
import com.healthmd.domain.model.APIRecoveryExecution
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import io.mockk.every
import io.mockk.mockk
import java.nio.file.Files
import java.time.LocalDate
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test

class RecoveryDiscardFenceRunnerTest {
    @Test
    fun discardDuringPreparePreventsJournalCreateUploadAndRecapture() = runTest {
        withHarness { h ->
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            h.beforePlan = { entered.complete(Unit); release.await() }
            val late = async { h.runner().exportDates(listOf(h.day), h.settings,
                durableOperationId = h.id, durableSettingsSnapshotJson = "snapshot") }
            entered.await()
            RecoveryDiscardFence(h.root).discard(listOf(h.id))
            release.complete(Unit)
            assertThat(late.await().isFailure).isTrue()
            h.beforePlan = {}
            assertThat(h.runner().exportDates(listOf(h.day), h.settings,
                durableOperationId = h.id, durableSettingsSnapshotJson = "snapshot").isFailure).isTrue()
            assertThat(h.reads).isEqualTo(1)
            assertThat(h.uploads).isEqualTo(0)
            assertThat(h.root.walkTopDown().filter { it.name == "journal.json" || it.name.startsWith("body-") }.toList()).isEmpty()
        }
    }

    @Test
    fun discardAfterUnknownOutcomePreventsSecondUploadAndLateAcknowledgement() = runTest {
        withHarness { h ->
            h.afterUpload = {
                RecoveryDiscardFence(h.root).discard(listOf(h.id))
                throw APIExportClientException(ExportFailureReason.NETWORK_ERROR, retryable = true, message = "synthetic unknown outcome")
            }
            assertThat(h.runner().exportDates(listOf(h.day), h.settings,
                durableOperationId = h.id, durableSettingsSnapshotJson = "snapshot").isFailure).isTrue()
            assertThat(h.uploads).isEqualTo(1)
            assertThat(runCatching { FileAPIExportOperationStore(h.context).acknowledge(h.id, 0) }.isFailure).isTrue()
            h.afterUpload = {}
            h.runner().exportDates(listOf(h.day), h.settings, durableOperationId = h.id, durableSettingsSnapshotJson = "snapshot")
            assertThat(h.reads).isEqualTo(1)
            assertThat(h.uploads).isEqualTo(1)
        }
    }

    @Test
    fun discardDuringAlreadyAdmittedUploadAllowsNoLateFrontierOrRestartedDelivery() = runTest {
        withHarness { h ->
            val entered = CompletableDeferred<Unit>()
            val release = CompletableDeferred<Unit>()
            h.afterUpload = { entered.complete(Unit); release.await() }
            val late = async { h.runner().exportDates(listOf(h.day), h.settings,
                durableOperationId = h.id, durableSettingsSnapshotJson = "snapshot") }
            entered.await()
            RecoveryDiscardFence(h.root).discard(listOf(h.id))
            release.complete(Unit)
            assertThat(late.await().isFailure).isTrue()
            assertThat(h.uploads).isEqualTo(1)
            assertThat(h.root.walkTopDown().filter { it.name == "journal.json" }.toList()).isEmpty()
            h.afterUpload = {}
            h.runner().exportDates(listOf(h.day), h.settings, durableOperationId = h.id, durableSettingsSnapshotJson = "snapshot")
            assertThat(h.uploads).isEqualTo(1)
            assertThat(h.reads).isEqualTo(1)
        }
    }

    private suspend fun withHarness(test: suspend (Harness) -> Unit) {
        val root = Files.createTempDirectory("discard-runner").toFile()
        try { test(Harness(root)) } finally { root.deleteRecursively() }
    }

    private class Harness(val root: java.io.File) {
        val context = mockk<Context> { every { noBackupFilesDir } returns root }
        val day = LocalDate.ofEpochDay(10_000)
        val id = "synthetic-operation"
        var reads = 0
        var uploads = 0
        var beforePlan: suspend () -> Unit = {}
        var afterUpload: suspend () -> Unit = {}
        val credentials = object : APIExportCredentialStore {
            override suspend fun authorizationHeader(): String? = null
            override suspend fun hasAuthorization() = false
            override suspend fun saveAuthorization(value: String) = Unit
            override suspend fun clearAuthorization() = Unit
            override suspend fun destinationFingerprint(endpointUrl: String) = "a".repeat(64)
        }
        private val endpoint = "https://synthetic.example.test"
        private val configuration = APIExportRequestConfiguration(endpoint, null, emptyList(), "a".repeat(64))
        val settings = ExportSettings(apiEndpointUrl = endpoint, executionEnginePin = testPin(ExportEngineMode.rust),
            executionAPIRecoveryRequired = true, executionAPIRecovery = APIRecoveryExecution(
                APIRecoveryAuthorities.create(configuration, null), null, id, "snapshot") { true })
        fun runner(): APIEndpointExportRunner {
            val builder = APIExportEnvelopeBuilder(JsonExporter())
            return APIEndpointExportRunner(
                captureSource = object : APIExportCaptureSource {
                    override fun isBeforeFirstUnlock() = false
                    override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData {
                        reads++
                        return HealthData(date, activity = ActivityData(steps = 1))
                    }
                },
                envelopeBuilder = builder,
                uploader = object : APIExportUploader {
                    override suspend fun upload(endpointUrl: String, payload: String, authorizationHeader: String?,
                        requestHeaders: List<APIExportRequestHeader>): APIExportUploadResult {
                        uploads++
                        afterUpload()
                        return APIExportUploadResult(202, null)
                    }
                },
                credentialStore = credentials,
                policyResolver = APIExportEnginePolicyResolver { ResolvedExportEnginePolicy(ExportEngineMode.rust,
                    AndroidExportProfile.android_frozen_v4, ExportEnginePolicyTarget.API_V1_FROZEN_V4) },
                nativePlanner = APIExportNativePlanBuilder { error("synthetic unexpected native authority") },
                rustPlanner = APIExportRustPlanner { request ->
                    beforePlan()
                    APIExportRustPlan(testPin(ExportEngineMode.rust), ProductionAPIExportNativePlanBuilder(builder).plan(request))
                },
                operationStore = FileAPIExportOperationStore(context),
            )
        }
    }
}

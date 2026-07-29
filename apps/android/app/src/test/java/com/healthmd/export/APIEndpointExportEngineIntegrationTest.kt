package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCaptureSource
import com.healthmd.data.export.APIExportClientException
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.export.APIExportUploadResult
import com.healthmd.data.export.APIExportUploader
import com.healthmd.data.export.APIExportOperationStore
import com.healthmd.data.export.DurableAPIExportOperation
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.exportengine.APIExportEnginePolicyResolver
import com.healthmd.domain.exportengine.APIExportIdSource
import com.healthmd.domain.exportengine.APIExportIds
import com.healthmd.domain.exportengine.APIExportNativePlanBuilder
import com.healthmd.domain.exportengine.APIExportRustPlan
import com.healthmd.domain.exportengine.APIExportRustPlanner
import com.healthmd.domain.exportengine.API_MEDIA_TYPE
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportArtifactPlan
import com.healthmd.domain.exportengine.ExportArtifactPlanItem
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePolicyTarget
import com.healthmd.domain.exportengine.FrozenAPIExportRequest
import com.healthmd.domain.exportengine.ResolvedExportEnginePolicy
import com.healthmd.domain.exportengine.ShadowComparisonDiagnostic
import com.healthmd.domain.exportengine.ShadowExportDiagnostic
import com.healthmd.domain.exportengine.ShadowExportDiagnosticSink
import com.healthmd.domain.exportengine.apiArtifactPath
import com.healthmd.domain.exportengine.artifactIdHex
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.exportengine.testPin
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class APIEndpointExportEngineIntegrationTest {
    private val first = LocalDate.of(2026, 7, 24)
    private val second = first.plusDays(1)
    private val fixedInstant = Instant.parse("2026-07-26T12:00:00Z")
    private val fixedIds = APIExportIds("api-request", "api-session")

    @Test
    fun captureOnceAndCompletePlansExistBeforeFirstPostWithFrozenApiProfile() = runTest {
        val events = mutableListOf<String>()
        val capture = RecordingCapture(
            mapOf(
                first to HealthData(first, activity = ActivityData(steps = 10)),
                second to HealthData(second, activity = ActivityData(steps = 20)),
            ),
            events,
        )
        var nativeRequest: FrozenAPIExportRequest? = null
        var rustRequest: FrozenAPIExportRequest? = null
        val native = APIExportNativePlanBuilder { request ->
            events += "native-plan"
            nativeRequest = request
            apiPlan(request, listOf("same-body"))
        }
        val rust = APIExportRustPlanner { request ->
            events += "rust-plan"
            rustRequest = request
            APIExportRustPlan(testPin(ExportEngineMode.shadow), apiPlan(request, listOf("same-body")))
        }
        val uploader = RecordingUploader(events = events)
        val credentials = RecordingCredentials()
        var zoneCalls = 0
        var clockCalls = 0
        val runner = runner(
            mode = ExportEngineMode.shadow,
            capture = capture,
            native = native,
            rust = rust,
            uploader = uploader,
            credentials = credentials,
            zone = { zoneCalls += 1; ZoneId.of("America/Los_Angeles") },
            clock = { clockCalls += 1; fixedInstant },
        )

        val result = runner.exportDates(
            listOf(second, first, first),
            settings().copy(formatCustomization = FormatCustomization.analyticalDefault()),
        )

        assertThat(result.successCount).isEqualTo(2)
        assertThat(capture.calls).containsExactly(first, second).inOrder()
        assertThat(credentials.requestConfigurationCalls).isEqualTo(1)
        assertThat(zoneCalls).isEqualTo(1)
        assertThat(clockCalls).isEqualTo(1)
        assertThat(nativeRequest).isSameInstanceAs(rustRequest)
        assertThat(nativeRequest!!.profile).isEqualTo(AndroidExportProfile.android_frozen_v4)
        assertThat(nativeRequest!!.exportedAt).isEqualTo(fixedInstant)
        assertThat(nativeRequest!!.calendarTimeZone).isEqualTo("America/Los_Angeles")
        assertThat(nativeRequest!!.dateRangeStart).isEqualTo(first)
        assertThat(nativeRequest!!.dateRangeEnd).isEqualTo(second)
        assertThat(events.indexOf("upload"))
            .isGreaterThan(events.indexOf("rust-plan"))
        assertThat(events.indexOf("upload"))
            .isGreaterThan(events.indexOf("native-plan"))
    }

    @Test
    fun shadowUploadsNativeOnlyAndDiagnosticCannotCarryPhiOrCredentials() = runTest {
        val marker = "phi-secret-steps-98765"
        val diagnostics = mutableListOf<ShadowExportDiagnostic>()
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.shadow,
            capture = RecordingCapture(
                mapOf(first to HealthData(first, activity = ActivityData(steps = 98_765))),
            ),
            native = APIExportNativePlanBuilder { apiPlan(it, listOf("native-$marker")) },
            rust = APIExportRustPlanner {
                APIExportRustPlan(testPin(ExportEngineMode.shadow), apiPlan(it, listOf("rust-$marker")))
            },
            uploader = uploader,
            credentials = RecordingCredentials(
                authorization = "Bearer credential-secret",
                headers = listOf(APIExportRequestHeader("X-API-Key", "header-secret")),
            ),
            diagnosticSink = ShadowExportDiagnosticSink(diagnostics::add),
        )

        runner.exportDates(listOf(first), settings())

        assertThat(uploader.payloads).hasSize(1)
        assertThat(uploader.payloads.single()).contains("native-$marker")
        val diagnostic = diagnostics.single() as ShadowComparisonDiagnostic
        assertThat(diagnostic.comparison.matches).isFalse()
        val diagnosticText = diagnostic.toString()
        assertThat(diagnosticText).doesNotContain(marker)
        assertThat(diagnosticText).doesNotContain("98765")
        assertThat(diagnosticText).doesNotContain(first.toString())
        assertThat(diagnosticText).doesNotContain("credential-secret")
        assertThat(diagnosticText).doesNotContain("header-secret")
        assertThat(diagnosticText).doesNotContain("https://api.example.com/private")
    }

    @Test
    fun rustPlanIsAuthoritative() = runTest {
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(first to HealthData(first, activity = ActivityData(steps = 10))),
            ),
            native = APIExportNativePlanBuilder {
                error("Rust API authority must not invoke the native renderer")
            },
            rust = APIExportRustPlanner {
                APIExportRustPlan(testPin(ExportEngineMode.rust), apiPlan(it, listOf("rust")))
            },
            uploader = uploader,
        )

        val result = runner.exportDates(listOf(first), settings())

        assertThat(result.successCount).isEqualTo(1)
        assertThat(uploader.payloads).hasSize(1)
        assertThat(uploader.payloads.single()).contains("rust")
    }

    @Test
    fun precommitRustFailureFailsWithoutLegacyFallback() = runTest {
        var nativePlans = 0
        var rustPlans = 0
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(first to HealthData(first, activity = ActivityData(steps = 10))),
            ),
            native = APIExportNativePlanBuilder {
                nativePlans += 1
                apiPlan(it, listOf("native"))
            },
            rust = APIExportRustPlanner {
                rustPlans += 1
                error("fixed planner failure")
            },
            uploader = uploader,
        )

        val result = runner.exportDates(listOf(first), settings())

        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.UNKNOWN)
        assertThat(nativePlans).isEqualTo(0)
        assertThat(rustPlans).isEqualTo(1)
        assertThat(uploader.payloads).isEmpty()
    }

    @Test
    fun postSideEffectFailureNeverRendersOrFallsBack() = runTest {
        var nativePlans = 0
        var rustPlans = 0
        val uploader = RecordingUploader(failOnCall = 2)
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(
                    first to HealthData(first, activity = ActivityData(steps = 10)),
                    second to HealthData(second, activity = ActivityData(steps = 20)),
                ),
            ),
            native = APIExportNativePlanBuilder {
                nativePlans += 1
                apiPlan(it, listOf("native-one", "native-two"))
            },
            rust = APIExportRustPlanner {
                rustPlans += 1
                APIExportRustPlan(
                    testPin(ExportEngineMode.rust),
                    apiPlan(it, listOf("rust-one", "rust-two")),
                )
            },
            uploader = uploader,
        )

        val result = runner.exportDates(listOf(first, second), settings())

        assertThat(result.successCount).isEqualTo(0)
        assertThat(nativePlans).isEqualTo(0)
        assertThat(rustPlans).isEqualTo(1)
        assertThat(uploader.payloads).hasSize(2)
        assertThat(uploader.payloads[0]).contains("rust-one")
        assertThat(uploader.payloads[1]).contains("rust-two")
        assertThat(uploader.payloads.joinToString()).doesNotContain("native-")
    }

    @Test
    fun retryReusesPreparedBodyWithoutReplanning() = runTest {
        var nativePlans = 0
        var rustPlans = 0
        val uploader = RecordingUploader(retryableFailureOnFirstCall = true)
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(first to HealthData(first, activity = ActivityData(steps = 10))),
            ),
            native = APIExportNativePlanBuilder {
                nativePlans += 1
                apiPlan(it, listOf("native"))
            },
            rust = APIExportRustPlanner {
                rustPlans += 1
                APIExportRustPlan(testPin(ExportEngineMode.rust), apiPlan(it, listOf("immutable-rust")))
            },
            uploader = uploader,
        )

        val result = runner.exportDates(listOf(first), settings())

        assertThat(result.successCount).isEqualTo(1)
        assertThat(uploader.payloads).hasSize(2)
        assertThat(uploader.payloads[0]).isEqualTo(uploader.payloads[1])
        assertThat(uploader.payloads[0]).contains("immutable-rust")
        assertThat(nativePlans).isEqualTo(0)
        assertThat(rustPlans).isEqualTo(1)
    }

    @Test
    fun durableStoreMustCommitBeforeFirstPost() = runTest {
        val uploader = RecordingUploader()
        val store = object : APIExportOperationStore {
            override suspend fun load(operationId: String): DurableAPIExportOperation? = null
            override suspend fun create(operation: DurableAPIExportOperation) {
                error("fixed durable write failure")
            }
            override suspend fun acknowledge(operationId: String, expectedFrontier: Int) = Unit
            override suspend fun delete(operationId: String) = Unit
        }
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(first to HealthData(first, activity = ActivityData(steps = 10))),
            ),
            native = APIExportNativePlanBuilder { error("Rust must not invoke native") },
            rust = APIExportRustPlanner {
                APIExportRustPlan(
                    testPin(ExportEngineMode.rust),
                    apiPlan(it, listOf(previewBody(first, first, "prepared"))),
                )
            },
            uploader = uploader,
            credentials = RecordingCredentials(destinationFingerprint = "c".repeat(64)),
            operationStore = store,
        )

        val result = runner.exportDates(
            dates = listOf(first),
            settings = settings(),
            durableOperationId = "77777777-2222-3333-4444-555555555555",
            durableSettingsSnapshotJson = "snapshot-v1",
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(uploader.payloads).isEmpty()
    }

    @Test
    fun durableRestartUploadsOnlyUnacknowledgedPreparedBodiesWithoutRecapture() = runTest {
        val third = second.plusDays(1)
        val operationId = "11111111-2222-3333-4444-555555555555"
        val bodies = listOf(
            previewBody(first, second, "immutable-first"),
            previewBody(third, third, "immutable-second"),
        )
        val store = MemoryAPIExportOperationStore()
        val firstCapture = RecordingCapture(
            mapOf(
                first to HealthData(first, activity = ActivityData(steps = 10)),
                second to HealthData(second, activity = ActivityData(steps = 20)),
                third to HealthData(third, activity = ActivityData(steps = 30)),
            ),
        )
        val firstUploader = RecordingUploader(failOnCall = 2)
        val credentials = RecordingCredentials(destinationFingerprint = "a".repeat(64))
        val firstRunner = runner(
            mode = ExportEngineMode.rust,
            capture = firstCapture,
            native = APIExportNativePlanBuilder { error("Rust must not invoke native") },
            rust = APIExportRustPlanner {
                APIExportRustPlan(testPin(ExportEngineMode.rust), apiPlan(it, bodies))
            },
            uploader = firstUploader,
            credentials = credentials,
            operationStore = store,
        )

        val partial = firstRunner.exportDates(
            dates = listOf(first, second, third),
            settings = settings(),
            durableOperationId = operationId,
            durableSettingsSnapshotJson = "snapshot-v1",
        )

        assertThat(partial.successCount).isEqualTo(2)
        assertThat(partial.failedDateDetails.map { it.date }).containsExactly(third)
        assertThat(partial.retryOperationIds).containsExactly(third, operationId)
        assertThat(store.load(operationId)!!.acknowledgedBatchCount).isEqualTo(1)

        val resumedCapture = RecordingCapture(emptyMap())
        val resumedUploader = RecordingUploader()
        val resumedRunner = runner(
            mode = ExportEngineMode.rust,
            capture = resumedCapture,
            native = APIExportNativePlanBuilder { error("resume must not invoke native") },
            rust = APIExportRustPlanner { error("resume must not invoke Rust") },
            uploader = resumedUploader,
            credentials = credentials,
            operationStore = store,
        )

        val resumed = resumedRunner.exportDates(
            dates = listOf(third),
            settings = settings(),
            durableOperationId = operationId,
            durableSettingsSnapshotJson = "snapshot-v1",
        )

        assertThat(resumedCapture.calls).isEmpty()
        assertThat(resumedUploader.payloads).hasSize(1)
        assertThat(resumedUploader.payloads.single()).contains("immutable-second")
        assertThat(resumed.successCount).isEqualTo(1)
        assertThat(resumed.totalCount).isEqualTo(1)
        assertThat(resumed.failedDateDetails).isEmpty()
        assertThat(store.load(operationId)!!.acknowledgedBatchCount).isEqualTo(2)
    }

    @Test
    fun acknowledgedFailureOnlyBatchRetriesCaptureWithoutRepostingCompletedBody() = runTest {
        val operationId = "99999999-2222-3333-4444-555555555555"
        val bodies = listOf(
            previewBody(first, first, "failure-only"),
            previewBody(second, second, "unresolved"),
        )
        val store = MemoryAPIExportOperationStore()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(
                    first to HealthData(first),
                    second to HealthData(second, activity = ActivityData(steps = 20)),
                ),
            ),
            native = APIExportNativePlanBuilder { error("Rust must not invoke native") },
            rust = APIExportRustPlanner {
                APIExportRustPlan(testPin(ExportEngineMode.rust), apiPlan(it, bodies))
            },
            uploader = RecordingUploader(failOnCall = 2),
            credentials = RecordingCredentials(destinationFingerprint = "b".repeat(64)),
            operationStore = store,
        )

        val result = runner.exportDates(
            dates = listOf(first, second),
            settings = settings(),
            durableOperationId = operationId,
            durableSettingsSnapshotJson = "snapshot-v1",
        )

        assertThat(result.failedDateDetails.map { it.date }).containsExactly(first, second).inOrder()
        assertThat(result.failedDateDetails.first().reason).isEqualTo(ExportFailureReason.NO_HEALTH_DATA)
        assertThat(result.retryOperationIds).containsExactly(second, operationId)
        assertThat(result.freshCaptureRetryDates).containsExactly(first)
    }

    @Test
    fun previewUsesShadowNativePlanAndNeverUploads() = runTest {
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.shadow,
            capture = RecordingCapture(
                mapOf(first to HealthData(first, activity = ActivityData(steps = 10))),
            ),
            native = APIExportNativePlanBuilder {
                apiPlan(it, listOf(previewBody(first, first, "native-preview")))
            },
            rust = APIExportRustPlanner {
                APIExportRustPlan(
                    testPin(ExportEngineMode.shadow),
                    apiPlan(it, listOf(previewBody(first, first, "rust-preview"))),
                )
            },
            uploader = uploader,
        )

        val preview = runner.previewDates(listOf(first), settings())

        assertThat(preview.days.single().files.single().content).contains("native-preview")
        assertThat(preview.days.single().requestedDates).containsExactly(first)
        assertThat(uploader.payloads).isEmpty()
    }

    @Test
    fun previewPreservesExactOwnerDatesForMultiDayApiBatches() = runTest {
        val third = second.plusDays(1)
        val bodies = listOf(
            previewBody(first, second, "first-batch"),
            previewBody(third, third, "second-batch"),
        )
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(
                    first to HealthData(first, activity = ActivityData(steps = 10)),
                    second to HealthData(second, activity = ActivityData(steps = 20)),
                    third to HealthData(third, activity = ActivityData(steps = 30)),
                ),
            ),
            native = APIExportNativePlanBuilder { error("Rust preview must not invoke native") },
            rust = APIExportRustPlanner {
                APIExportRustPlan(testPin(ExportEngineMode.rust), apiPlan(it, bodies))
            },
            uploader = RecordingUploader(),
        )

        val preview = runner.previewDates(listOf(third, first, second), settings())

        assertThat(preview.days).hasSize(2)
        assertThat(preview.days[0].date).isEqualTo(first)
        assertThat(preview.days[0].requestedDates).containsExactly(first, second).inOrder()
        assertThat(preview.days[1].date).isEqualTo(third)
        assertThat(preview.days[1].requestedDates).containsExactly(third)
    }

    @Test
    fun malformedOrIncompleteRustEnvelopesFailBeforeForegroundPost() = runTest {
        val third = second.plusDays(1)
        val cases: List<(FrozenAPIExportRequest) -> List<ByteArray>> = listOf(
            { listOf(byteArrayOf(0xc3.toByte(), 0x28)) },
            { request ->
                listOf(validEnvelope(request, first, first, "missing-final").encodeToByteArray())
            },
            { request ->
                listOf(
                    validEnvelope(request, first, second, "overlap-all").encodeToByteArray(),
                    validEnvelope(request, second, second, "overlap-second").encodeToByteArray(),
                )
            },
            { request ->
                listOf(
                    validEnvelope(request, second, second, "reordered-second").encodeToByteArray(),
                    validEnvelope(request, first, first, "reordered-first").encodeToByteArray(),
                )
            },
            { request ->
                listOf(validEnvelope(request, first, third, "extra-date").encodeToByteArray())
            },
            { request ->
                val valid = validEnvelope(request, first, second, "wrong-count")
                listOf(mutateEnvelope(valid, "record_count", JsonPrimitive(99)))
            },
            { request ->
                val valid = validEnvelope(request, first, second, "wrong-schema")
                listOf(mutateEnvelope(valid, "schema", JsonPrimitive("future.api_export")))
            },
        )

        cases.forEach { bodies ->
            val uploader = RecordingUploader()
            val runner = runner(
                mode = ExportEngineMode.rust,
                capture = RecordingCapture(
                    mapOf(
                        first to HealthData(first, activity = ActivityData(steps = 10)),
                        second to HealthData(second, activity = ActivityData(steps = 20)),
                    ),
                ),
                native = APIExportNativePlanBuilder {
                    error("Rust API authority must not invoke native rendering")
                },
                rust = APIExportRustPlanner { request ->
                    APIExportRustPlan(
                        testPin(ExportEngineMode.rust),
                        rawApiPlan(request, bodies(request)),
                    )
                },
                uploader = uploader,
            )

            val result = runner.exportDates(listOf(first, second), settings())

            assertThat(result.successCount).isEqualTo(0)
            assertThat(result.failedDateDetails).hasSize(2)
            assertThat(uploader.payloads).isEmpty()
        }
    }

    @Test
    fun incompleteRustEnvelopeFailsPreviewWithoutUploaderSideEffects() = runTest {
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(
                    first to HealthData(first, activity = ActivityData(steps = 10)),
                    second to HealthData(second, activity = ActivityData(steps = 20)),
                ),
            ),
            native = APIExportNativePlanBuilder {
                error("Rust preview authority must not invoke native rendering")
            },
            rust = APIExportRustPlanner { request ->
                APIExportRustPlan(
                    testPin(ExportEngineMode.rust),
                    rawApiPlan(
                        request,
                        listOf(validEnvelope(request, first, first, "missing-final").encodeToByteArray()),
                    ),
                )
            },
            uploader = uploader,
        )

        val preview = runner.previewDates(listOf(second, first), settings())

        assertThat(preview.previewedDateCount).isEqualTo(0)
        assertThat(preview.days.single().failureReason).isEqualTo(ExportFailureReason.UNKNOWN)
        assertThat(uploader.payloads).isEmpty()
    }

    @Test
    fun missingCapturedFailureOutcomeFailsBeforePreviewDurabilityOrPost() = runTest {
        val uploader = RecordingUploader()
        val store = MemoryAPIExportOperationStore()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(
                mapOf(
                    first to HealthData(first),
                    second to HealthData(second, activity = ActivityData(steps = 20)),
                ),
            ),
            native = APIExportNativePlanBuilder {
                error("Rust API authority must not invoke native rendering")
            },
            rust = APIExportRustPlanner { request ->
                val valid = validEnvelope(request, first, second, "missing-failure")
                val body = mutateEnvelope(valid, "failed_date_details", JsonArray(emptyList()))
                APIExportRustPlan(
                    testPin(ExportEngineMode.rust),
                    rawApiPlan(request, listOf(body)),
                )
            },
            uploader = uploader,
            credentials = RecordingCredentials(destinationFingerprint = "d".repeat(64)),
            operationStore = store,
        )

        val result = runner.exportDates(
            dates = listOf(first, second),
            settings = settings(),
            durableOperationId = "88888888-2222-3333-4444-555555555555",
            durableSettingsSnapshotJson = "snapshot-v1",
        )

        assertThat(result.successCount).isEqualTo(0)
        assertThat(uploader.payloads).isEmpty()
        assertThat(store.load("88888888-2222-3333-4444-555555555555")).isNull()
    }

    @Test
    fun frozenNilAuthorityUsesLegacyBytesWithoutReadingCurrentRustPlanners() = runTest {
        val data = HealthData(first, activity = ActivityData(steps = 10))
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = RecordingCapture(mapOf(first to data)),
            native = APIExportNativePlanBuilder {
                error("frozen legacy must not invoke native plan comparison")
            },
            rust = APIExportRustPlanner {
                error("frozen legacy must not invoke Rust")
            },
            uploader = uploader,
        )

        val result = runner.exportDates(
            listOf(first),
            settings().copy(executionEngineAuthorityIsFrozen = true),
        )

        assertThat(result.successCount).isEqualTo(1)
        assertThat(uploader.payloads).hasSize(1)
        assertThat(uploader.payloads.single()).contains("healthmd.api_export")
    }

    @Test
    fun legacyModeKeepsTheExistingSingleEnvelopeBytesAndDoesNotInvokePlanners() = runTest {
        val data = HealthData(first, activity = ActivityData(steps = 10))
        val settings = settings().copy(formatCustomization = FormatCustomization.analyticalDefault())
        val uploader = RecordingUploader()
        val builder = APIExportEnvelopeBuilder(JsonExporter())
        val expected = builder.build(
            records = listOf(data),
            failedDateDetails = emptyList(),
            settings = settings,
            dateRangeStart = first,
            dateRangeEnd = first,
            exportedAt = fixedInstant,
            calendarTimeZone = "UTC",
        )
        val runner = APIEndpointExportRunner(
            captureSource = RecordingCapture(mapOf(first to data)),
            envelopeBuilder = builder,
            uploader = uploader,
            credentialStore = RecordingCredentials(),
            policyResolver = APIExportEnginePolicyResolver {
                ResolvedExportEnginePolicy(
                    ExportEngineMode.legacy,
                    AndroidExportProfile.android_frozen_v4,
                    ExportEnginePolicyTarget.API_V1_FROZEN_V4,
                )
            },
            nativePlanner = APIExportNativePlanBuilder { error("legacy invoked native planner") },
            rustPlanner = APIExportRustPlanner { error("legacy invoked Rust planner") },
            idSource = APIExportIdSource { fixedIds },
            clock = { fixedInstant },
            zoneIdProvider = { ZoneId.of("UTC") },
        )

        val result = runner.exportDates(listOf(first), settings)

        assertThat(result.successCount).isEqualTo(1)
        assertThat(uploader.payloads).containsExactly(expected)
    }

    @Test
    fun sparseApiScopeIsWhollyLegacyBeforeCapture() = runTest {
        var nativePlans = 0
        var rustPlans = 0
        val third = first.plusDays(2)
        val capture = RecordingCapture(
            mapOf(
                first to HealthData(first, activity = ActivityData(steps = 1)),
                third to HealthData(third, activity = ActivityData(steps = 3)),
            ),
        )
        val uploader = RecordingUploader()
        val runner = runner(
            mode = ExportEngineMode.rust,
            capture = capture,
            native = APIExportNativePlanBuilder { nativePlans += 1; apiPlan(it, listOf("native")) },
            rust = APIExportRustPlanner {
                rustPlans += 1
                APIExportRustPlan(testPin(ExportEngineMode.rust), apiPlan(it, listOf("rust")))
            },
            uploader = uploader,
        )

        val result = runner.exportDates(listOf(first, third), settings())

        assertThat(result.successCount).isEqualTo(2)
        assertThat(capture.calls).containsExactly(first, third).inOrder()
        assertThat(nativePlans).isEqualTo(0)
        assertThat(rustPlans).isEqualTo(0)
        assertThat(uploader.payloads).hasSize(1)
        assertThat(uploader.payloads.single()).contains("\"start\": \"2026-07-24\"")
        assertThat(uploader.payloads.single()).contains("\"end\": \"2026-07-26\"")
    }

    private fun runner(
        mode: ExportEngineMode,
        capture: APIExportCaptureSource,
        native: APIExportNativePlanBuilder,
        rust: APIExportRustPlanner,
        uploader: APIExportUploader,
        credentials: APIExportCredentialStore = RecordingCredentials(),
        diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
        zone: () -> ZoneId = { ZoneId.of("UTC") },
        clock: () -> Instant = { fixedInstant },
        operationStore: com.healthmd.data.export.APIExportOperationStore? = null,
    ): APIEndpointExportRunner = APIEndpointExportRunner(
        captureSource = capture,
        envelopeBuilder = APIExportEnvelopeBuilder(JsonExporter()),
        uploader = uploader,
        credentialStore = credentials,
        policyResolver = APIExportEnginePolicyResolver {
            ResolvedExportEnginePolicy(
                mode = mode,
                profile = AndroidExportProfile.android_frozen_v4,
                target = ExportEnginePolicyTarget.API_V1_FROZEN_V4,
            )
        },
        nativePlanner = native,
        rustPlanner = rust,
        diagnosticSink = diagnosticSink,
        idSource = APIExportIdSource { fixedIds },
        clock = clock,
        zoneIdProvider = zone,
        operationStore = operationStore,
    )

    private fun settings(): ExportSettings = ExportSettings(
        exportTarget = ExportTarget.API_ENDPOINT,
        apiEndpointUrl = "https://api.example.com/private",
    )

    private fun previewBody(start: LocalDate, end: LocalDate, marker: String): String =
        """{"date_range":{"start":"$start","end":"$end"},"marker":"$marker"}"""

    private fun apiPlan(
        request: FrozenAPIExportRequest,
        bodies: List<String>,
    ): ExportArtifactPlan = rawApiPlan(
        request,
        bodies.mapIndexed { index, value ->
            val descriptor = runCatching { Json.parseToJsonElement(value).jsonObject }.getOrNull()
            val range = descriptor?.get("date_range")?.jsonObject
            val start = range?.get("start")?.jsonPrimitive?.content?.let(LocalDate::parse)
                ?: if (bodies.size == request.requestedDates.size) request.requestedDates[index]
                else request.requestedDates.first()
            val end = range?.get("end")?.jsonPrimitive?.content?.let(LocalDate::parse)
                ?: if (bodies.size == request.requestedDates.size) request.requestedDates[index]
                else request.requestedDates.last()
            val marker = descriptor?.get("marker")?.jsonPrimitive?.content ?: value
            validEnvelope(request, start, end, marker).encodeToByteArray()
        },
    )

    private fun validEnvelope(
        request: FrozenAPIExportRequest,
        start: LocalDate,
        end: LocalDate,
        marker: String,
    ): String {
        val scopedDates = request.requestedDates.filter { it in start..end }
        val envelope = APIExportEnvelopeBuilder(JsonExporter()).build(
            records = request.records.filter { it.date in scopedDates },
            failedDateDetails = request.failedDateDetails.filter { it.date in scopedDates },
            settings = request.settings,
            dateRangeStart = start,
            dateRangeEnd = end,
            exportedAt = request.exportedAt,
            calendarTimeZone = request.calendarTimeZone,
        )
        val root = Json.parseToJsonElement(envelope).jsonObject
        return Json.encodeToString(
            JsonObject.serializer(),
            JsonObject(root + ("marker" to JsonPrimitive(marker))),
        )
    }

    private fun mutateEnvelope(
        body: String,
        key: String,
        value: kotlinx.serialization.json.JsonElement,
    ): ByteArray {
        val root = Json.parseToJsonElement(body).jsonObject
        return Json.encodeToString(
            JsonObject.serializer(),
            JsonObject(root + (key to value)),
        ).encodeToByteArray()
    }

    private fun rawApiPlan(
        request: FrozenAPIExportRequest,
        bodies: List<ByteArray>,
    ): ExportArtifactPlan {
        val items = bodies.mapIndexed { index, content ->
            val path = apiArtifactPath(request.ids.requestId, index)
            val sha = sha256Hex(content)
            ExportArtifactPlanItem(
                artifactId = artifactIdHex(
                    requestId = request.ids.requestId,
                    sessionId = request.ids.sessionId,
                    profile = AndroidExportProfile.android_frozen_v4,
                    relativePath = path,
                    mediaType = API_MEDIA_TYPE,
                    writeMode = ExportArtifactWriteMode.api_post,
                    contentSha256 = sha,
                ),
                relativePath = path,
                mediaType = API_MEDIA_TYPE,
                writeMode = ExportArtifactWriteMode.api_post,
                content = content,
            )
        }
        return ExportArtifactPlan(
            schema = ExportArtifactPlan.SCHEMA,
            artifactPlanVersion = ExportArtifactPlan.VERSION,
            requestId = request.ids.requestId,
            sessionId = request.ids.sessionId,
            profile = AndroidExportProfile.android_frozen_v4,
            items = items,
        )
    }

    private class RecordingCapture(
        private val data: Map<LocalDate, HealthData>,
        private val events: MutableList<String>? = null,
    ) : APIExportCaptureSource {
        val calls = mutableListOf<LocalDate>()

        override fun isBeforeFirstUnlock(): Boolean = false

        override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData {
            calls += date
            events?.add("capture:$date")
            return data.getValue(date)
        }
    }

    private class RecordingUploader(
        private val events: MutableList<String>? = null,
        private val failOnCall: Int? = null,
        private val retryableFailureOnFirstCall: Boolean = false,
    ) : APIExportUploader {
        val payloads = mutableListOf<String>()

        override suspend fun upload(
            endpointUrl: String,
            payload: String,
            authorizationHeader: String?,
            requestHeaders: List<APIExportRequestHeader>,
        ): APIExportUploadResult {
            payloads += payload
            events?.add("upload")
            if (retryableFailureOnFirstCall && payloads.size == 1) {
                throw APIExportClientException(
                    failureReason = ExportFailureReason.NETWORK_ERROR,
                    retryable = true,
                    message = "fixed network failure",
                )
            }
            if (failOnCall == payloads.size) error("fixed upload failure")
            return APIExportUploadResult(202)
        }
    }

    private class MemoryAPIExportOperationStore : APIExportOperationStore {
        private val operations = mutableMapOf<String, DurableAPIExportOperation>()

        override suspend fun load(operationId: String): DurableAPIExportOperation? =
            operations[operationId]

        override suspend fun create(operation: DurableAPIExportOperation) {
            val existing = operations[operation.operationId]
            require(existing == null || existing.immutableContentEquals(operation))
            if (existing == null) operations[operation.operationId] = operation
        }

        override suspend fun acknowledge(operationId: String, expectedFrontier: Int) {
            val operation = requireNotNull(operations[operationId])
            require(operation.acknowledgedBatchCount == expectedFrontier)
            operations[operationId] = operation.copy(
                acknowledgedBatchCount = expectedFrontier + 1,
            )
        }

        override suspend fun delete(operationId: String) {
            operations.remove(operationId)
        }
    }

    private class RecordingCredentials(
        private val authorization: String? = "Bearer test-token",
        private val headers: List<APIExportRequestHeader> = emptyList(),
        private val destinationFingerprint: String = "frozen-fingerprint",
    ) : APIExportCredentialStore {
        var requestConfigurationCalls = 0

        override suspend fun authorizationHeader(): String? = authorization
        override suspend fun hasAuthorization(): Boolean = authorization != null
        override suspend fun saveAuthorization(value: String) = Unit
        override suspend fun clearAuthorization() = Unit
        override suspend fun requestHeaders(): List<APIExportRequestHeader> = headers

        override suspend fun requestConfiguration(endpointUrl: String): APIExportRequestConfiguration {
            requestConfigurationCalls += 1
            return APIExportRequestConfiguration(
                endpointUrl = endpointUrl,
                authorizationHeader = authorization,
                requestHeaders = headers,
                destinationFingerprint = destinationFingerprint,
            )
        }
    }
}

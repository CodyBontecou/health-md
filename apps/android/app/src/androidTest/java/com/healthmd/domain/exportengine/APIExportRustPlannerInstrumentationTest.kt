package com.healthmd.domain.exportengine

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCaptureSource
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.APIExportRequestConfiguration
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.export.APIExportUploadResult
import com.healthmd.data.export.APIExportUploader
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.storage.ScheduledFolderExportJournal
import com.healthmd.data.storage.ScheduledFolderExportJournalStore
import com.healthmd.data.storage.ScheduledFolderJournalLoad
import com.healthmd.data.storage.ScheduledFolderJournalPhase
import com.healthmd.data.storage.sha256Hex
import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthData
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class APIExportRustPlannerInstrumentationTest {
    @Test
    fun productionFolderJournalFsyncsAndReloadsCapturingHeader() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val core = HealthMdCoreService()
        val readiness = core.checkReadiness()
        val profile = AndroidExportProfile.android_frozen_v4
        val pin = ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = profile,
            ianaTimeZone = "UTC",
            readiness = readiness,
            registry = core.getMetricRegistry(profile.coreProfile),
        )
        val operationId = "instrumented-folder-journal"
        val journal = ScheduledFolderExportJournal(
            operationId = operationId,
            folderUri = "content://instrumented/tree/root",
            settingsSnapshotSha256 = sha256Hex("settings".encodeToByteArray()),
            enginePinJson = ExportEnginePinCodec.encodeCanonical(pin),
            ownerDates = listOf("2026-07-24"),
            phase = ScheduledFolderJournalPhase.CAPTURING,
        )
        val store = ScheduledFolderExportJournalStore(context)
        store.discard(operationId)

        assertTrue(store.save(journal))
        assertEquals(ScheduledFolderJournalLoad.Found(journal), store.load(operationId))
        store.discard(operationId)
    }

    @Test
    fun productionShadowRecorderPersistsHealthFreeAggregateOffCaller() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val recorder = AndroidShadowExportEvidenceRecorder(context)
        recorder.reset()
        recorder.emit(
            ShadowComparisonDiagnostic(
                profile = AndroidExportProfile.android_frozen_v4,
                semanticProfileRevision = 1u,
                renderProfileRevision = 1u,
                comparison = ExportArtifactPlanComparison(emptyList()),
            ),
        )

        val snapshot = withTimeout(5_000) {
            while (recorder.snapshot().profiles.isEmpty()) delay(10)
            recorder.snapshot()
        }

        assertEquals(1, snapshot.profiles.single().comparisonCount)
        assertEquals(1, snapshot.profiles.single().exactMatchCount)
        assertTrue(
            context.noBackupFilesDir.resolve("shared-core-shadow-evidence-v1.json").isFile,
        )
        recorder.reset()
    }

    @Test
    fun packagedRustPlanPassesTheSameEnvelopeGateUsedBeforePost() = runBlocking {
        val first = LocalDate.of(2026, 7, 24)
        val second = first.plusDays(1)
        val payloads = mutableListOf<String>()
        val capture = object : APIExportCaptureSource {
            override fun isBeforeFirstUnlock(): Boolean = false

            override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData =
                HealthData(date, activity = ActivityData(steps = if (date == first) 10 else 20))
        }
        val uploader = object : APIExportUploader {
            override suspend fun upload(
                endpointUrl: String,
                payload: String,
                authorizationHeader: String?,
                requestHeaders: List<APIExportRequestHeader>,
            ): APIExportUploadResult {
                payloads += payload
                return APIExportUploadResult(202)
            }
        }
        val credentials = object : APIExportCredentialStore {
            override suspend fun authorizationHeader(): String? = null
            override suspend fun hasAuthorization(): Boolean = false
            override suspend fun saveAuthorization(value: String) = Unit
            override suspend fun clearAuthorization() = Unit
            override suspend fun requestHeaders(): List<APIExportRequestHeader> = emptyList()
            override suspend fun requestConfiguration(endpointUrl: String) =
                APIExportRequestConfiguration(
                    endpointUrl = endpointUrl,
                    authorizationHeader = null,
                    requestHeaders = emptyList(),
                    destinationFingerprint = "a".repeat(64),
                )
        }
        val runner = APIEndpointExportRunner(
            captureSource = capture,
            envelopeBuilder = APIExportEnvelopeBuilder(JsonExporter()),
            uploader = uploader,
            credentialStore = credentials,
            policyResolver = APIExportEnginePolicyResolver {
                ResolvedExportEnginePolicy(
                    mode = ExportEngineMode.rust,
                    profile = AndroidExportProfile.android_frozen_v4,
                    target = ExportEnginePolicyTarget.API_V1_FROZEN_V4,
                )
            },
            nativePlanner = APIExportNativePlanBuilder {
                error("Rust API authority must not invoke native rendering")
            },
            rustPlanner = HealthMdRustAPIExportPlanner(),
            idSource = APIExportIdSource {
                APIExportIds("instrumented-api-request", "instrumented-api-session")
            },
            clock = { Instant.parse("2026-07-26T12:00:00Z") },
            zoneIdProvider = { ZoneId.of("UTC") },
        )

        val result = runner.exportDates(
            dates = listOf(second, first),
            settings = ExportSettings(
                exportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = "https://api.example.com/health",
            ),
        )

        assertEquals(2, result.successCount)
        assertEquals(1, payloads.size)
        val root = Json.parseToJsonElement(payloads.single()).jsonObject
        assertEquals(APIExportEnvelopeBuilder.API_EXPORT_SCHEMA, root.getValue("schema").jsonPrimitive.content)
        assertEquals("2026-07-24", root.getValue("date_range").jsonObject.getValue("start").jsonPrimitive.content)
        assertEquals("2026-07-25", root.getValue("date_range").jsonObject.getValue("end").jsonPrimitive.content)
        assertEquals(2, root.getValue("records").jsonArray.size)
    }
}

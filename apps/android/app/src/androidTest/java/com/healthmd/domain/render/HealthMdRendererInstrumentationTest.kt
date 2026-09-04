package com.healthmd.domain.render

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.CoreArtifactWriteMode
import com.healthmd.core.CoreStreamArtifactConfig
import com.healthmd.core.CoreStreamMode
import com.healthmd.core.HealthMdCoreService
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HealthMdRendererInstrumentationTest {
    @Test
    fun bothProfilesRenderPackagedPlansAndBoundedStreams() {
        val service = HealthMdCoreService()
        for ((profile, profileId, version) in listOf(
            Triple(CoreMetricRegistryProfile.ANDROID_FROZEN_V4, "android_frozen_v4", 4),
            Triple(CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5, "android_analytical_v5", 5),
        )) {
            val registry = service.getMetricRegistry(profile)
            val semantic = semanticResult(profileId)
            val customization = if (version == 4) {
                FormatCustomization()
            } else {
                FormatCustomization.analyticalDefault()
            }
            val presentation = HealthData(
                date = LocalDate.of(2026, 7, 25),
                activity = ActivityData(steps = 1234),
            )
            val encoded = HealthMdRenderInputAdapter.encode(
                semanticResult = semantic,
                registry = registry,
                calendarTimeZone = "UTC",
                options = HealthMdRenderInputAdapter.Options(
                    requestId = "android-render-$version",
                    formats = listOf("markdown", "obsidian_bases", "json", "csv"),
                    writeMode = "update",
                ),
                presentationByOwnerDate = mapOf("2026-07-25" to presentation),
                presentationCustomization = customization,
            )
            service.createRenderSession(encoded.configuration, semantic).use { session ->
                encoded.batches.forEach(session::processBatch)
                val plan = session.finish()
                assertEquals(4, plan.items.size)
                assertEquals(
                    listOf(
                        "health/2026-07-25.md",
                        "health/2026-07-25-bases.md",
                        "health/2026-07-25.json",
                        "health/2026-07-25.csv",
                    ),
                    plan.items.map { it.relativePath },
                )
                assertTrue(plan.items.all { it.byteCount == it.content.size.toULong() && it.sha256.length == 64 })
                val bases = plan.items.single { it.relativePath.endsWith("-bases.md") }.content.decodeToString()
                assertEquals(ObsidianBasesExporter().export(presentation, customization), bases)
                val publicJson = plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()
                if (version == 4) {
                    assertFalse(publicJson.contains("schemaProfile"))
                } else {
                    assertTrue(publicJson.contains("\"schemaProfile\": \"android-analytical-v5\""))
                    assertTrue(publicJson.contains("\"schemaVersion\": 5"))
                }
            }
        }

        service.createPlannedLosslessArtifactStream(
            CoreStreamMode.JSON_ARRAY,
            CoreStreamArtifactConfig(
                requestId = "android-lossless-test",
                sessionId = "android-lossless-session",
                profile = CoreMetricRegistryProfile.ANDROID_FROZEN_V4,
                relativePath = "health/raw/archive.json",
                mediaType = "application/json",
                writeMode = CoreArtifactWriteMode.OVERWRITE,
            ),
        ).use { stream ->
            val chunks = listOf(
                stream.pushJsonItem("{\"id\":1}".encodeToByteArray()),
                stream.pushJsonItem("{\"id\":2}".encodeToByteArray()),
            )
            val finish = stream.finish()
            assertEquals(
                "[{\"id\":1},{\"id\":2}]",
                (chunks + finish.chunk).fold(ByteArray(0)) { result, bytes -> result + bytes }.decodeToString(),
            )
            assertEquals(2uL, finish.descriptor.itemCount)
            assertEquals("health/raw/archive.json", finish.descriptor.artifact?.relativePath)
            assertEquals(finish.descriptor.byteCount, finish.descriptor.artifact?.byteCount)
            assertEquals(finish.descriptor.sha256, finish.descriptor.artifact?.sha256)
            assertEquals(64, finish.descriptor.artifact?.artifactId?.length)
        }
        val existing = "---\nuser: keep\ndate: old\n---\nUser intro\n\n## Sleep\nold\n\n## Notes\nkeep\n"
        val generated = "---\ndate: new\n---\nGenerated intro\n\n## Sleep\nnew\n\n## Activity\nsteps\n"
        val merged = service.mergeMarkdown(
            CoreMetricRegistryProfile.ANDROID_FROZEN_V4,
            existing,
            generated,
        )
        assertEquals(MarkdownMerger().merge(existing, generated), merged)
    }

    @Test
    fun frozenV4ApiEnvelopeMatchesNativeBytesIncludingFailures() {
        val service = HealthMdCoreService()
        val first = LocalDate.of(2026, 7, 25)
        val second = LocalDate.of(2026, 7, 26)
        val exportedAt = Instant.parse("2026-07-27T12:00:00Z")
        val presentation = HealthData(
            date = first,
            activity = ActivityData(steps = 1234),
        )
        val failure = FailedDateDetail(second, ExportFailureReason.NO_HEALTH_DATA)
        val native = APIExportEnvelopeBuilder(JsonExporter()).build(
            records = listOf(presentation),
            failedDateDetails = listOf(failure),
            settings = ExportSettings(),
            dateRangeStart = first,
            dateRangeEnd = second,
            exportedAt = exportedAt,
        )
        val failureTimestamp = second.atStartOfDay(ZoneId.systemDefault()).toInstant().toString()
        val semantic = semanticResult("android_frozen_v4")
        val encoded = HealthMdRenderInputAdapter.encode(
            semanticResult = semantic,
            registry = service.getMetricRegistry(CoreMetricRegistryProfile.ANDROID_FROZEN_V4),
            calendarTimeZone = ZoneId.systemDefault().id,
            options = HealthMdRenderInputAdapter.Options(
                requestId = "android-api-parity",
                formats = listOf("json"),
                writeMode = "overwrite",
                api = HealthMdRenderInputAdapter.ApiOptions(
                    envelopeVersion = 1,
                    exportedAt = exportedAt.toString(),
                    source = "android",
                    dateRangeStart = first.toString(),
                    dateRangeEnd = second.toString(),
                    failedDateDetails = listOf(
                        HealthMdRenderInputAdapter.ApiFailureOptions(
                            ownerDate = second.toString(),
                            timestamp = failureTimestamp,
                            reason = "no_health_data",
                        ),
                    ),
                ),
            ),
            presentationByOwnerDate = mapOf(first.toString() to presentation),
            presentationCustomization = FormatCustomization(),
        )
        service.createRenderSession(encoded.configuration, semantic).use { session ->
            encoded.batches.forEach(session::processBatch)
            val api = session.finish().items.single { it.relativePath.startsWith("api/") }
            assertEquals(native, api.content.decodeToString())
        }
    }

    private fun semanticResult(profile: String): ByteArray = """
        {"schema":"healthmd.semantic_result","semantic_input_version":1,"canonical_model_version":1,"core_api_version":3,"registry_sha256":"4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2","profile_revision":1,"session_id":"android-render-session","profile":"$profile","state":"completed","next_batch_index":1,"records_accepted":1,"records_filtered":0,"days":[{"owner_date":"2026-07-25","values":[{"output_key":"steps","semantic_id":"steps","aggregation":"sum","value":{"value_type":"number","number":{"representation":"unsigned_integer","decimal":"1234"},"unit":{"id":"count"}},"source_record_ids":["record-1"]}]}],"rollups":[],"retained_extensions":[]}
    """.trimIndent().encodeToByteArray()
}

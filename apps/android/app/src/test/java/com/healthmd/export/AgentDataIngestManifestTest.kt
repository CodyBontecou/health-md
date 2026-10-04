package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.AgentDataCompleteness
import com.healthmd.data.export.AgentDataIngestManifest
import com.healthmd.data.export.AgentDataIngestManifestBuilder
import com.healthmd.data.export.ArtifactKind
import java.time.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

/**
 * Field-for-field manifest builder tests against the frozen `healthmd.agent_data_ingest` v1
 * schema and the registered contract fixtures
 * (`packages/contracts/agent-data/v1/fixtures/ingest-*.json`).
 */
class AgentDataIngestManifestTest {

    private val day = LocalDate.of(2026, 3, 15)

    @Test
    fun dailyManifestMatchesTheFixtureFieldSetMinusTheOmittedRecordCount() {
        val artifact = """
            {"schema":"healthmd.health_data","schema_version":4,"date":"2026-03-15"}
        """.trimIndent().encodeToByteArray()

        val manifest = AgentDataIngestManifestBuilder.dailyHealthData(
            ownerDate = day,
            artifactBytes = artifact,
        )

        assertThat(manifest.schema).isEqualTo("healthmd.agent_data_ingest")
        assertThat(manifest.schemaVersion).isEqualTo(1)
        assertThat(manifest.artifactKind).isEqualTo("health_data_daily")
        assertThat(manifest.platform).isEqualTo("android")
        assertThat(manifest.artifactSchema).isEqualTo("healthmd.health_data")
        assertThat(manifest.artifactSchemaVersion).isEqualTo(4)
        assertThat(manifest.ownerDate).isEqualTo("2026-03-15")
        assertThat(manifest.physicalFormat).isEqualTo("json")
        assertThat(manifest.mediaType).isEqualTo("application/json")
        assertThat(manifest.byteCount).isEqualTo(artifact.size.toLong())
        assertThat(manifest.sha256).isEqualTo(AgentDataIngestManifestBuilder.sha256Hex(artifact))
        assertThat(manifest.completeness.type).isEqualTo("complete")

        // The registered fixture ingest-request-complete.json carries exactly these fields
        // plus the informational record_count, which the Android client omits.
        val encoded = Json.parseToJsonElement(manifest.encodeJsonLine()).jsonObject
        assertThat(encoded.keys).containsExactly(
            "schema",
            "schema_version",
            "artifact_kind",
            "platform",
            "artifact_schema",
            "artifact_schema_version",
            "owner_date",
            "physical_format",
            "media_type",
            "byte_count",
            "sha256",
            "completeness",
        )
    }

    @Test
    fun analyticalArtifactCarriesItsOwnSchemaIdentityFromTheDocumentRoot() {
        val artifact = """
            {"date":"2026-07-25","schemaProfile":"android-analytical-v5","schemaVersion":5}
        """.trimIndent().encodeToByteArray()

        val manifest = AgentDataIngestManifestBuilder.dailyHealthData(day, artifact)

        assertThat(manifest.artifactSchema).isEqualTo("healthmd.health_data")
        assertThat(manifest.artifactSchemaVersion).isEqualTo(5)
    }

    @Test
    fun legacyCompatibilityArtifactDefaultsToTheFrozenV4DailyIdentity() {
        val artifact = """{"date":"2026-07-25","type":"health-data","units":"metric"}"""
            .encodeToByteArray()

        val manifest = AgentDataIngestManifestBuilder.dailyHealthData(day, artifact)

        assertThat(manifest.artifactSchema).isEqualTo("healthmd.health_data")
        assertThat(manifest.artifactSchemaVersion).isEqualTo(4)
    }

    @Test
    fun rawSnapshotManifestMirrorsTheRawFixtureShape() {
        val bytes = ("{\"wire\":\"steps\"}\n" + "{\"wire\":\"hr\"}\n").encodeToByteArray()

        val manifest = AgentDataIngestManifestBuilder.rawSnapshot(
            captureDay = LocalDate.of(2026, 3, 18),
            physicalFormat = AgentDataIngestManifest.PHYSICAL_FORMAT_NDJSON,
            bytes = bytes,
            mediaType = AgentDataIngestManifestBuilder.MEDIA_TYPE_NDJSON,
        )

        // Mirrors ingest-request-raw-complete.json (platform android, minus record_count).
        assertThat(manifest.artifactKind).isEqualTo("raw_snapshot")
        assertThat(manifest.artifactSchema).isEqualTo("healthmd.raw-snapshot")
        assertThat(manifest.artifactSchemaVersion).isEqualTo(1)
        assertThat(manifest.ownerDate).isEqualTo("2026-03-18")
        assertThat(manifest.physicalFormat).isEqualTo("ndjson")
        assertThat(manifest.mediaType).isEqualTo("application/x-ndjson")
        assertThat(manifest.byteCount).isEqualTo(bytes.size.toLong())
        assertThat(manifest.sha256).isEqualTo(AgentDataIngestManifestBuilder.sha256Hex(bytes))
        assertThat(manifest.completeness.type).isEqualTo("complete")
    }

    @Test
    fun encodedManifestLineIsSingleLineJsonWithoutRecordCount() {
        val artifact = """{"schema":"healthmd.health_data","schema_version":4}""".encodeToByteArray()
        val line = AgentDataIngestManifestBuilder.dailyHealthData(day, artifact).encodeJsonLine()

        assertThat(line).doesNotContain("\n")
        assertThat(line).doesNotContain("record_count")
        val root = Json.parseToJsonElement(line).jsonObject
        assertThat(root.getValue("platform").jsonPrimitive.content).isEqualTo("android")
        assertThat(root.getValue("completeness").jsonObject.toString())
            .isEqualTo("{\"type\":\"complete\"}")
    }

    @Test
    fun finalizedPartialGrammarMirrorsThePartialFixture() {
        val completeness = AgentDataCompleteness.finalizedPartial(
            listOf(LocalDate.of(2026, 3, 16), LocalDate.of(2026, 3, 15)),
        )
        val encoded = Json.encodeToJsonElement(
            AgentDataCompleteness.serializer(),
            completeness,
        ).toString()

        assertThat(encoded).isEqualTo(
            "{\"type\":\"partial\",\"finalized\":true," +
                "\"covered_owner_dates\":[\"2026-03-15\",\"2026-03-16\"]}",
        )
    }

    @Test
    fun rawKindsMustBeCompleteAndUnfinalizedPartialsAreRejected() {
        val bytes = "{}".encodeToByteArray()
        val raw = AgentDataIngestManifestBuilder.rawSnapshot(
            captureDay = day,
            physicalFormat = AgentDataIngestManifest.PHYSICAL_FORMAT_JSON,
            bytes = bytes,
        )
        assertThat(raw.completeness.type).isEqualTo("complete")

        val unfinalized = runCatching {
            AgentDataCompleteness(type = "partial", finalized = false, coveredOwnerDates = listOf("2026-03-16"))
        }.exceptionOrNull()
        assertThat(unfinalized).isInstanceOf(IllegalArgumentException::class.java)

        val rawWithPartial = runCatching {
            AgentDataIngestManifest(
                artifactKind = ArtifactKind.RAW_SNAPSHOT,
                artifactSchema = "healthmd.raw-snapshot",
                artifactSchemaVersion = 1,
                ownerDate = "2026-03-18",
                physicalFormat = "json",
                mediaType = "application/json",
                byteCount = bytes.size.toLong(),
                sha256 = AgentDataIngestManifestBuilder.sha256Hex(bytes),
                completeness = AgentDataCompleteness.finalizedPartial(listOf(day)),
            )
        }.exceptionOrNull()
        assertThat(rawWithPartial).isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test
    fun rejectsStructurallyInvalidManifests() {
        val good = "{}".encodeToByteArray()
        val goodSha = AgentDataIngestManifestBuilder.sha256Hex(good)

        fun manifest(
            kind: String = "health_data_daily",
            schema: String = "healthmd.health_data",
            version: Int = 4,
            sha: String = goodSha,
            byteCount: Long = good.size.toLong(),
            completeness: AgentDataCompleteness = AgentDataCompleteness.complete(),
        ) = AgentDataIngestManifest(
            artifactKind = kind,
            artifactSchema = schema,
            artifactSchemaVersion = version,
            ownerDate = "2026-03-15",
            physicalFormat = "json",
            mediaType = "application/json",
            byteCount = byteCount,
            sha256 = sha,
            completeness = completeness,
        )

        assertThat(runCatching { manifest(kind = "unknown_kind") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { manifest(schema = "") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { manifest(version = 0) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { manifest(sha = "XYZ") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { manifest(byteCount = 0) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { manifest(byteCount = AgentDataIngestManifest.MAX_ARTIFACT_BYTES + 1) }
            .exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching {
            AgentDataIngestManifestBuilder.dailyHealthData(day, "not json".encodeToByteArray())
        }.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
    }
}

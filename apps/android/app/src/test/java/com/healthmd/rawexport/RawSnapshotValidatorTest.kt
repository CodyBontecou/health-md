package com.healthmd.rawexport

import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata
import com.google.common.truth.Truth.assertThat
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RawSnapshotValidatorTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun validatesJsonAndNdjsonIncludingExactArtifactAndSidecarChecksums() = runTest {
        for (format in RawExportFormat.entries) {
            val result = export(format, 2)
            val file = File(result.finalLocation)
            var callbacks = 0
            val validation = file.inputStream().use {
                RawSnapshotValidator().validate(
                    it,
                    format,
                    RawValidationOptions(result.artifactChecksumSha256, "${result.artifactChecksumSha256}  ${file.name}\n", file.name),
                ) { decoded ->
                    callbacks++
                    assertThat(decoded.fields).isInstanceOf(DecodedFields.Steps::class.java)
                    assertThat(decoded.nonRestorableMetadata).isNotNull()
                }
            }
            assertThat(validation.issues).isEmpty()
            assertThat(validation.valid).isTrue()
            assertThat(validation.schema).isEqualTo("healthmd.raw-snapshot")
            assertThat(validation.majorVersion).isEqualTo(1)
            assertThat(validation.recordCount).isEqualTo(2)
            assertThat(validation.artifactChecksumVerified).isTrue()
            assertThat(validation.sidecarChecksumVerified).isTrue()
            assertThat(callbacks).isEqualTo(2)
        }
    }

    @Test fun reportsEveryManifestCountChecksumTruncationTrailingAndVersionCorruptionWithoutHealthValues() = runTest {
        val jsonResult = export(RawExportFormat.JSON, 1)
        val json = File(jsonResult.finalLocation).readText()
        val ndjsonResult = export(RawExportFormat.NDJSON, 1)
        val ndjson = File(ndjsonResult.finalLocation).readText()
        val cases = listOf(
            Triple(json.replaceFirst("\"recordCount\":1", "\"recordCount\":2"), RawExportFormat.JSON, "record_count"),
            Triple(json.replaceFirst("\"issueCount\":0", "\"issueCount\":1"), RawExportFormat.JSON, "issue_count"),
            Triple(json.replaceFirst("\"count\":1,\"wireType\":\"steps\"", "\"count\":2,\"wireType\":\"steps\""), RawExportFormat.JSON, "type_counts"),
            Triple(json.replaceFirst("\"hash\":\"", "\"hash\":\"0"), RawExportFormat.JSON, "record_sha256"),
            Triple(json.replaceFirst("\"logicalChecksumSha256\":\"", "\"logicalChecksumSha256\":\"0"), RawExportFormat.JSON, "logical_checksum"),
            Triple(json.replaceFirst("\"manifestChecksumSha256\":\"", "\"manifestChecksumSha256\":\"0"), RawExportFormat.JSON, "manifest_checksum"),
            Triple(json.dropLast(2), RawExportFormat.JSON, "invalid_stream_shape"),
            Triple(ndjson.substringBeforeLast("{\"kind\":\"manifest\""), RawExportFormat.NDJSON, "manifest_missing"),
            Triple(ndjson + "{}\n", RawExportFormat.NDJSON, "content_after_manifest"),
            Triple(ndjson.replaceFirst("\"version\":1", "\"version\":2"), RawExportFormat.NDJSON, "unsupported_major_version"),
        )
        cases.forEach { (artifact, format, expectedCode) ->
            val result = RawSnapshotValidator().validate(ByteArrayInputStream(artifact.toByteArray()), format)
            assertThat(result.valid).isFalse()
            assertThat(result.issues.map { it.code }).contains(expectedCode)
            assertThat(result.issues.joinToString { it.message }).doesNotContain("source.package")
            assertThat(result.issues.joinToString { it.message }).doesNotContain("hc:")
        }
        val badArtifact = RawSnapshotValidator().validate(
            File(jsonResult.finalLocation).inputStream(),
            RawExportFormat.JSON,
            RawValidationOptions("0".repeat(64)),
        )
        assertThat(badArtifact.issues.map { it.code }).contains("artifact_checksum")
    }

    @Test fun enforcesPerRecordHashRawInstantQuantityEnumAndNestedOrderSemantics() {
        val mapped = RawHealthConnectMapper.map(
            StepsRecord(
                startTime = Instant.ofEpochSecond(1, 123),
                startZoneOffset = null,
                endTime = Instant.ofEpochSecond(2, 456),
                endZoneOffset = null,
                count = 9,
                metadata = Metadata.manualEntry(clientRecordId = "fixture", clientRecordVersion = 7),
            ),
            "steps",
        )
        val objectValue = RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(mapped)).jsonObject
        val decoded = RawRecordDecoder.decode(objectValue)
        assertThat((decoded.fields as DecodedFields.Steps).count).isEqualTo(9)
        assertThat(decoded.startTime).isEqualTo(DecodedInstant(1, 123))
        assertThat(decoded.startZoneOffset).isNull()
        assertThat(decoded.metadata!!.restorable.clientRecordVersion).isEqualTo(7)
        assertThat(decoded.metadata.nonRestorable.serverAssignedId).isEmpty()

        fun corrupt(path: String, transform: (JsonObject) -> JsonObject): String = runCatching { RawRecordDecoder.decode(transform(objectValue)); "accepted" }
            .exceptionOrNull().let { failure -> (failure as RawDecodeException).code + path }
        assertThat(corrupt("exact") { root -> root.mutateObject("startTime") { it + ("epochSecondExact" to JsonPrimitive("01")) } }).startsWith("exact_integer")
        assertThat(corrupt("enum") { root -> root.mutateObject("metadata") { metadata -> metadata.mutateObject("recordingMethod") { it - "label" } } }).startsWith("missing")
    }

    @Test fun additiveUnknownFieldsSurviveAtEveryDecodedBoundaryAndStillParticipateInHash() {
        val mapped = RawHealthConnectMapper.map(
            StepsRecord(
                startTime = Instant.ofEpochSecond(1), startZoneOffset = null,
                endTime = Instant.ofEpochSecond(2), endZoneOffset = null,
                count = 4, metadata = Metadata.manualEntry(clientRecordId = "unknown"),
            ),
            "steps",
        )
        var objectValue = RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(mapped)).jsonObject
        objectValue = JsonObject(objectValue + ("futureEnvelope" to JsonPrimitive("retained")))
            .mutateObject("fields") { it + ("futureField" to JsonPrimitive(17)) }
            .mutateObject("metadata") { it + ("futureMetadata" to JsonPrimitive(true)) }
        val hash = RawJson.sha256(RawJson.canonical(JsonObject(objectValue.filterKeys { it != "hash" })))
        objectValue = JsonObject(objectValue + ("hash" to JsonPrimitive(hash)))

        val decoded = RawRecordDecoder.decode(objectValue)
        assertThat(decoded.additiveUnknownFields.keys).containsAtLeast("/futureEnvelope", "/fields/futureField", "/metadata/futureMetadata")
        assertThat(decoded.additiveUnknownFields["/fields/futureField"]).isEqualTo(JsonPrimitive(17))
    }

    @Test fun largeNdjsonIsDecodedIncrementallyWithoutRecordAggregation() = runTest {
        val count = 8_000
        val result = export(RawExportFormat.NDJSON, count)
        var seen = 0
        val validation = File(result.finalLocation).inputStream().use { input ->
            RawSnapshotValidator().validate(input, RawExportFormat.NDJSON) {
                seen++
                if (seen % 1_000 == 0) assertThat((it.fields as DecodedFields.Steps).count).isAtLeast(0)
            }
        }
        assertThat(validation.valid).isTrue()
        assertThat(validation.recordCount).isEqualTo(count.toLong())
        assertThat(seen).isEqualTo(count)
    }

    @Test fun restartCleanupDeletesAbandonedPrivatePartialButProtectsLiveRun() {
        val root = temporary.newFolder("partial-restart")
        val stale = File(root, "old.json.partial").apply { writeText("crash debris") }
        val active = File(root, "live.ndjson.partial").apply { writeText("live") }
        val final = File(root, "complete.json").apply { writeText("final") }

        cleanupAbandonedFilePartials(root, setOf(active.absolutePath))

        assertThat(stale.exists()).isFalse()
        assertThat(active.exists()).isTrue()
        assertThat(final.exists()).isTrue()
    }

    @Test fun restartDeletesAbandonedSpoolBeforeStartingFromScratch() = runTest {
        val root = temporary.newFolder("restart")
        val spoolRoot = File(root, "spools").apply { mkdirs() }
        val abandoned = File(spoolRoot, "spool-abandoned").apply { mkdirs() }
        File(abandoned, "health-data.ndjson").writeText("sensitive partial")
        val storage = DirectoryStorage(File(root, "out"))
        orchestrator(storage, spoolRoot, RawExportFormat.JSON, 1).export(request(RawExportFormat.JSON))
        assertThat(abandoned.exists()).isFalse()
        assertThat(spoolRoot.listFiles().orEmpty()).isEmpty()
        assertThat(File(root, "out").listFiles().orEmpty().none { it.name.endsWith(".partial") }).isTrue()
    }

    private suspend fun export(format: RawExportFormat, count: Int): RawExportResult {
        val root = temporary.newFolder("export-${format.name}-$count-${System.nanoTime()}")
        return orchestrator(DirectoryStorage(File(root, "out")), File(root, "spool"), format, count).export(request(format))
    }

    private fun orchestrator(storage: RawExportStorage, spoolRoot: File, format: RawExportFormat, count: Int): RawSnapshotExportOrchestrator {
        val records = (0 until count).map { index ->
            RawHealthConnectMapper.map(
                StepsRecord(
                    startTime = Instant.ofEpochSecond(index.toLong() + 1), startZoneOffset = null,
                    endTime = Instant.ofEpochSecond(index.toLong() + 2), endZoneOffset = null,
                    count = index.toLong() + 1, metadata = Metadata.manualEntry(clientRecordId = "record-${index.toString().padStart(8, '0')}", clientRecordVersion = 1),
                ),
                "steps",
            )
        }
        return RawSnapshotExportOrchestrator(
            repository = object : RawHealthRepository {
                override suspend fun capabilities() = RawProviderCapabilities(available = true)
                override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
                    emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
                    records.forEach { emit(RawExportItem.Record(it)) }
                    RawExportTypeCatalog.definitions.forEach { definition ->
                        emit(RawExportItem.TypeReport(RawTypeReport(
                            typeKey = definition.typeKey,
                            wireType = definition.wireType,
                            status = if (definition.typeKey == "steps") RawTypeStatus.EXPORTED else RawTypeStatus.NOT_SELECTED,
                            permission = definition.permission,
                            feature = definition.feature,
                            rangeBehavior = definition.rangeBehavior,
                        )))
                    }
                    emit(RawExportItem.Status(RawSnapshotStatus.COMPLETE))
                }
            },
            storage = storage,
            spoolRoot = spoolRoot,
            clock = { Instant.ofEpochSecond(10_000, 123) },
            maxRecordsInMemory = 16,
        )
    }

    private fun request(format: RawExportFormat) = RawSnapshotRequest(
        format,
        RawSnapshotScope.SELECTED_RECORD_TYPES,
        RawInstant(0, 0),
        RawInstant(20_000, 0),
        selectedMetricIds = setOf("steps"),
    )

    private class DirectoryStorage(private val directory: File) : RawExportStorage {
        override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
            directory.mkdirs()
            val partial = File(directory, "$snapshotId.partial")
            val final = File(directory, "$snapshotId.${format.name.lowercase()}")
            return object : RawAtomicExportSink {
                override val output = partial.outputStream()
                override val partialLocation = partial.path
                private var closed = false
                override fun close() { if (!closed) { output.close(); closed = true } }
                override fun promote(): String { close(); check(partial.renameTo(final)); return final.path }
                override fun abort() { close(); partial.delete() }
            }
        }
    }

    private fun JsonObject.mutateObject(key: String, update: (JsonObject) -> Map<String, kotlinx.serialization.json.JsonElement>): JsonObject =
        JsonObject(this + (key to JsonObject(update(getValue(key).jsonObject))))
}

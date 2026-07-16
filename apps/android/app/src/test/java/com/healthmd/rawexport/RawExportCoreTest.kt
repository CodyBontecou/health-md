package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import java.io.File
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RawExportCoreTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun canonicalJsonSortsObjectKeysAndRecordHashExcludesItself() {
        val record = record("b", "native-1", 2).withCanonicalIdentityAndHash()
        val changedHashField = record.copy(hash = "not-the-hash")
        assertThat(RawJson.recordHash(changedHashField)).isEqualTo(record.hash)
        assertThat(RawJson.canonical(record.fields)).isEqualTo("{\"a\":1,\"z\":2}")
    }

    @Test fun spoolOrdersAndDeduplicatesByNativeIdentityDeterministically() {
        val directory = temporary.newFolder("spool")
        DiskBackedCanonicalSpool(directory, maxRecordsInMemory = 1).use { spool ->
            spool.append(record("z", "same", 3, version = 1))
            spool.append(record("a", "other", 1))
            spool.append(record("z", "same", 2, version = 2))
            val output = mutableListOf<RawRecord>()
            spool.forEachRecord(output::add)
            assertThat(output.map { it.wireType }).containsExactly("a", "z").inOrder()
            assertThat(output.last().metadata!!.clientRecordVersion).isEqualTo(2)
            assertThat(spool.duplicateCount).isEqualTo(1)
        }
    }

    @Test fun jsonAndNdjsonContainEquivalentOrderedRecordsAndIssues() = runTest {
        val root = temporary.newFolder("equivalence")
        val clock = { Instant.ofEpochSecond(1_700_000_000, 123) }
        val source = listOf(record("z", "z", 2), record("a", "a", 1))
        fun orchestrator(formatRoot: String) = RawSnapshotExportOrchestrator(
            repository = FakeRepository(flowOf(
                RawExportItem.Status(RawSnapshotStatus.RUNNING),
                RawExportItem.Record(source[0]),
                RawExportItem.Issue(RawIssue("notice", "test")),
                RawExportItem.Record(source[1]),
                RawExportItem.Status(RawSnapshotStatus.COMPLETE),
            )),
            storage = DirectoryStorage(File(root, formatRoot)),
            spoolRoot = File(root, "spool-$formatRoot"),
            clock = clock,
            maxRecordsInMemory = 1,
        )
        val json = orchestrator("json").export(request(RawExportFormat.JSON))
        val ndjson = orchestrator("ndjson").export(request(RawExportFormat.NDJSON))
        val jsonRoot = RawJson.codec.parseToJsonElement(File(json.finalLocation).readText()).jsonObject
        val jsonHashes = jsonRoot.getValue("records").jsonArray.map { it.jsonObject.getValue("hash").toString() }
        val lines = File(ndjson.finalLocation).readLines().map(RawJson.codec::parseToJsonElement)
        val ndjsonHashes = lines.filter { it.jsonObject["kind"].toString() == "\"record\"" }
            .map { it.jsonObject.getValue("record").jsonObject.getValue("hash").toString() }
        assertThat(ndjsonHashes).containsExactlyElementsIn(jsonHashes).inOrder()
        assertThat(json.manifest.recordCount).isEqualTo(ndjson.manifest.recordCount)
        assertThat(json.manifest.issueCount).isEqualTo(ndjson.manifest.issueCount)
        assertThat(json.manifest.logicalChecksumSha256).isEqualTo(ndjson.manifest.logicalChecksumSha256)
        assertThat(json.manifest.manifestChecksumSha256).isEqualTo(ndjson.manifest.manifestChecksumSha256)
        assertThat(json.artifactChecksumSha256).hasLength(64)
        assertThat(ndjson.artifactChecksumSha256).hasLength(64)
    }

    @Test fun cancellationNeverPromotesPartialArtifact() = runTest {
        val destination = temporary.newFolder("cancel")
        val repository = FakeRepository(flow {
            emit(RawExportItem.Record(record("steps", "one", 1)))
            throw CancellationException("stop")
        })
        val orchestrator = RawSnapshotExportOrchestrator(
            repository, DirectoryStorage(destination), temporary.newFolder("cancel-spool"),
            clock = { Instant.EPOCH }, maxRecordsInMemory = 1,
        )
        var cancelled = false
        try {
            orchestrator.export(request(RawExportFormat.JSON))
        } catch (_: CancellationException) {
            cancelled = true
        }
        assertThat(cancelled).isTrue()
        assertThat(destination.listFiles().orEmpty()).isEmpty()
    }

    @Test fun nullableOffsetsAndNanosecondsSurviveSerialization() {
        val value = record("heart_rate", "id", 10).copy(
            startTime = RawInstant(10, 999_999_999),
            startZoneOffsetSeconds = null,
            endZoneOffsetSeconds = null,
        ).withCanonicalIdentityAndHash()
        val roundTrip = RawJson.codec.decodeFromString(RawRecord.serializer(), RawJson.canonicalRecord(value))
        assertThat(roundTrip.startTime!!.nano).isEqualTo(999_999_999)
        assertThat(roundTrip.startZoneOffsetSeconds).isNull()
        assertThat(roundTrip.endZoneOffsetSeconds).isNull()
    }

    private fun request(format: RawExportFormat) = RawSnapshotRequest(
        format = format,
        scope = RawSnapshotScope.SELECTED_RECORD_TYPES,
        startTime = RawInstant(0, 0),
        endTime = RawInstant(100, 0),
        selectedMetricIds = setOf("steps"),
    )

    private fun record(type: String, identity: String, second: Long, version: Long = 0): RawRecord {
        val metadata = RawMetadata(
            id = identity,
            clientRecordVersion = version,
            lastModifiedTime = RawInstant(second, 7),
            dataOriginPackageName = "example.health",
            recordingMethod = RawEnumValue(2, "automatically_recorded"),
        )
        return RawRecord(
            wireType = type,
            nativeIdentity = "hc:$identity",
            startTime = RawInstant(second, 1),
            metadata = metadata,
            fields = kotlinx.serialization.json.buildJsonObject {
                put("z", kotlinx.serialization.json.JsonPrimitive(2))
                put("a", kotlinx.serialization.json.JsonPrimitive(1))
            },
            hash = "",
        ).withCanonicalIdentityAndHash()
    }

    private class FakeRepository(private val items: Flow<RawExportItem>) : RawHealthRepository {
        override suspend fun capabilities() = RawProviderCapabilities(available = true)
        override fun stream(request: RawSnapshotRequest) = items
    }

    private class DirectoryStorage(private val directory: File) : RawExportStorage {
        override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
            directory.mkdirs()
            val partial = File(directory, "$snapshotId.partial")
            val final = File(directory, snapshotId)
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
}

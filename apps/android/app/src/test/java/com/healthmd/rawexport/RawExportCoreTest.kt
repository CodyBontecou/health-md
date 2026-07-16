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
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RawExportCoreTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun everyV1TypeStatusHasItsExactWireValue() {
        val values = RawTypeStatus.entries.map {
            RawJson.codec.encodeToJsonElement(RawTypeStatus.serializer(), it).jsonPrimitive.content
        }
        assertThat(values).containsExactly(
            "exported", "not_selected", "permission_not_granted", "feature_unavailable",
            "history_permission_missing", "read_error", "unsupported_by_provider",
        ).inOrder()
    }

    @Test fun canonicalJsonSortsObjectKeysAndRecordHashExcludesItself() {
        val record = record("b", "native-1", 2).withCanonicalIdentityAndHash()
        val changedHashField = record.copy(hash = "not-the-hash")
        assertThat(RawJson.recordHash(changedHashField)).isEqualTo(record.hash)
        assertThat(RawJson.canonical(record.fields)).isEqualTo("{\"a\":1,\"z\":2}")
    }

    @Test fun canonicalJsonRejectsNonFiniteNumbersAndQuantityPairsMustAgree() {
        assertThat(runCatching { RawJson.canonical(kotlinx.serialization.json.JsonPrimitive(Double.NaN)) }.isFailure).isTrue()
        assertThat(runCatching { RawQuantity(1.0, "2.0", "Length", "m") }.isFailure).isTrue()
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
            assertThat(spool.identityCollisionCount).isEqualTo(1)
            val issues = mutableListOf<RawIssue>()
            spool.forEachIssue(issues::add)
            assertThat(issues.map { it.code }).containsExactly("identity_collision")
        }
    }

    @Test fun issuesStreamInDeterministicOccurrenceOrderWithoutTypeRegrouping() {
        DiskBackedCanonicalSpool(temporary.newFolder("issue-order-spool"), 1).use { spool ->
            spool.append(RawIssue("global-first", "first", recordType = null))
            spool.append(RawIssue("steps-second", "second", recordType = "steps"))
            val codes = mutableListOf<String>()

            spool.forEachIssue { codes += it.code }

            assertThat(codes).containsExactly("global-first", "steps-second").inOrder()
        }
    }

    @Test fun identicalNativeIdentityAndPayloadDeduplicatesWithoutCollisionIssue() {
        DiskBackedCanonicalSpool(temporary.newFolder("identical-spool"), 1).use { spool ->
            val same = record("steps", "same", 1)
            spool.append(same)
            spool.append(same)
            val output = mutableListOf<RawRecord>()
            val issues = mutableListOf<RawIssue>()
            spool.forEachRecord(output::add)
            spool.forEachIssue(issues::add)
            assertThat(output).containsExactly(same)
            assertThat(spool.duplicateCount).isEqualTo(1)
            assertThat(spool.identityCollisionCount).isEqualTo(0)
            assertThat(issues).isEmpty()
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
        assertThat(json.manifest.typeReports).isEqualTo(ndjson.manifest.typeReports)
        assertThat(json.manifest.typeReports).hasSize(54)
        assertThat(json.artifactChecksumSha256).hasLength(64)
        assertThat(ndjson.artifactChecksumSha256).hasLength(64)
    }

    @Test fun manifestCarriesEveryV1TypeStatusWithMatchingIssues() = runTest {
        val request = RawSnapshotRequest(
            RawExportFormat.JSON,
            RawSnapshotScope.SELECTED_RECORD_TYPES,
            RawInstant(0, 0),
            RawInstant(100, 0),
            selectedMetricIds = HealthConnectRecordCatalog.records.flatMap { it.metricIds }.toSet(),
        )
        val statuses = listOf(
            RawTypeStatus.EXPORTED,
            RawTypeStatus.PERMISSION_NOT_GRANTED,
            RawTypeStatus.FEATURE_UNAVAILABLE,
            RawTypeStatus.HISTORY_PERMISSION_MISSING,
            RawTypeStatus.READ_ERROR,
            RawTypeStatus.UNSUPPORTED_BY_PROVIDER,
        )
        val items: Flow<RawExportItem> = flow {
            emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
            RawExportTypeCatalog.definitions.forEachIndexed { index, definition ->
                val selected = RawExportTypeCatalog.isSelected(definition, request)
                val status = if (selected) statuses[index % statuses.size] else RawTypeStatus.NOT_SELECTED
                if (status != RawTypeStatus.EXPORTED && status != RawTypeStatus.NOT_SELECTED) {
                    emit(RawExportItem.Issue(RawIssue(status.name.lowercase(), "status", recordType = definition.typeKey)))
                }
                emit(RawExportItem.TypeReport(RawTypeReport(
                    definition.typeKey, definition.wireType, status,
                    permission = definition.permission, feature = definition.feature,
                    rangeBehavior = definition.rangeBehavior,
                )))
            }
            emit(RawExportItem.Status(RawSnapshotStatus.PARTIAL))
        }
        val result = RawSnapshotExportOrchestrator(
            FakeRepository(items), DirectoryStorage(temporary.newFolder("all-statuses")),
            temporary.newFolder("all-statuses-spool"), clock = { Instant.EPOCH },
        ).export(request)
        assertThat(result.manifest.typeReports.map { it.status }.toSet())
            .containsExactlyElementsIn(RawTypeStatus.entries)
        result.manifest.typeReports.filter { it.status != RawTypeStatus.EXPORTED && it.status != RawTypeStatus.NOT_SELECTED }
            .forEach { assertThat(it.issueCount).isAtLeast(1) }
    }

    @Test fun selectedOmissionIsPartialButAllAuthorizedTruthfulOmissionIsComplete() = runTest {
        suspend fun run(scope: RawSnapshotScope, directoryName: String): RawExportResult {
            val request = RawSnapshotRequest(
                RawExportFormat.JSON,
                scope,
                RawInstant(0, 0),
                RawInstant(100, 0),
                selectedMetricIds = setOf("steps"),
            )
            val items: Flow<RawExportItem> = flow {
                emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
                RawExportTypeCatalog.definitions.forEach { definition ->
                    val selected = RawExportTypeCatalog.isSelected(definition, request)
                    val status = when {
                        !selected -> RawTypeStatus.NOT_SELECTED
                        definition.typeKey == "steps" -> RawTypeStatus.PERMISSION_NOT_GRANTED
                        else -> RawTypeStatus.EXPORTED
                    }
                    if (status == RawTypeStatus.PERMISSION_NOT_GRANTED) {
                        emit(RawExportItem.Issue(RawIssue("permission_not_granted", "missing", recordType = definition.typeKey)))
                    }
                    emit(RawExportItem.TypeReport(RawTypeReport(
                        definition.typeKey, definition.wireType, status,
                        permission = definition.permission, feature = definition.feature,
                        rangeBehavior = definition.rangeBehavior,
                    )))
                }
                emit(RawExportItem.Status(RawSnapshotStatus.COMPLETE))
            }
            return RawSnapshotExportOrchestrator(
                FakeRepository(items),
                DirectoryStorage(temporary.newFolder(directoryName)),
                temporary.newFolder("$directoryName-spool"),
                clock = { Instant.EPOCH },
            ).export(request)
        }

        assertThat(run(RawSnapshotScope.SELECTED_RECORD_TYPES, "selected-status").manifest.status)
            .isEqualTo(RawSnapshotStatus.PARTIAL)
        assertThat(run(RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA, "all-status").manifest.status)
            .isEqualTo(RawSnapshotStatus.COMPLETE)
    }

    @Test fun halfOpenFilteringUsesPointContainmentAndIntervalOverlapWithoutClippingFields() {
        val request = RawSnapshotRequest(RawExportFormat.JSON, RawSnapshotScope.SELECTED_RECORD_TYPES, RawInstant(10, 5), RawInstant(20, 5))
        fun point(time: RawInstant) = record("weight", "p-${time.epochSecond}-${time.nano}", 1).copy(startTime = time, endTime = null)
        fun interval(start: RawInstant, end: RawInstant) = record("steps", "i-${start.epochSecond}-${end.epochSecond}", 1).copy(startTime = start, endTime = end)
        assertThat(point(RawInstant(10, 5)).isInHalfOpenRange(request, RawRangeBehavior.INSTANT)).isTrue()
        assertThat(point(RawInstant(20, 5)).isInHalfOpenRange(request, RawRangeBehavior.INSTANT)).isFalse()
        assertThat(interval(RawInstant(0, 0), RawInstant(10, 5)).isInHalfOpenRange(request, RawRangeBehavior.OVERLAP)).isFalse()
        assertThat(interval(RawInstant(20, 5), RawInstant(30, 0)).isInHalfOpenRange(request, RawRangeBehavior.OVERLAP)).isFalse()
        assertThat(interval(RawInstant(0, 0), RawInstant(10, 6)).isInHalfOpenRange(request, RawRangeBehavior.OVERLAP)).isTrue()
        assertThat(interval(RawInstant(20, 4), RawInstant(30, 0)).isInHalfOpenRange(request, RawRangeBehavior.OVERLAP)).isTrue()
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

    @Test fun normalEndWithoutTerminalStatusDoesNotPromote() = runTest {
        val destination = temporary.newFolder("missing-status")
        val orchestrator = RawSnapshotExportOrchestrator(
            FakeRepository(flowOf(RawExportItem.Status(RawSnapshotStatus.RUNNING))),
            DirectoryStorage(destination),
            temporary.newFolder("missing-status-spool"),
            clock = { Instant.EPOCH },
        )
        val failed = runCatching { orchestrator.export(request(RawExportFormat.JSON)) }.isFailure
        assertThat(failed).isTrue()
        assertThat(destination.listFiles().orEmpty()).isEmpty()
    }

    @Test fun headerSetsAndTypeReportsAreLexicallySorted() = runTest {
        val root = temporary.newFolder("sorts")
        val request = RawSnapshotRequest(
            RawExportFormat.JSON, RawSnapshotScope.SELECTED_RECORD_TYPES,
            RawInstant(0, 0), RawInstant(100, 0), selectedMetricIds = linkedSetOf("z", "steps", "a"),
        )
        val result = RawSnapshotExportOrchestrator(
            FakeRepository(
                flowOf(RawExportItem.Status(RawSnapshotStatus.COMPLETE)),
                RawProviderCapabilities(available = true, grantedPermissions = linkedSetOf("z", "a"), availableFeatures = linkedSetOf("z", "a")),
            ),
            DirectoryStorage(root), temporary.newFolder("sorts-spool"), clock = { Instant.EPOCH },
        ).export(request)
        val rootJson = RawJson.codec.parseToJsonElement(File(result.finalLocation).readText()).jsonObject
        val header = rootJson.getValue("header").jsonObject
        assertThat(header.getValue("request").jsonObject.getValue("selectedMetricIds").jsonArray.map { it.jsonPrimitive.content })
            .containsExactly("a", "steps", "z").inOrder()
        assertThat(header.getValue("capabilities").jsonObject.getValue("grantedPermissions").jsonArray.map { it.jsonPrimitive.content })
            .containsExactly("a", "z").inOrder()
        assertThat(result.manifest.typeReports.map { it.typeKey })
            .isEqualTo(result.manifest.typeReports.map { it.typeKey }.sorted())
    }

    @Test fun exactInt64StringsAndNanosecondsSurviveSerialization() {
        val value = record("heart_rate", "id", 10).copy(
            startTime = RawInstant(10, 999_999_999),
            startZoneOffsetSeconds = null,
            endZoneOffsetSeconds = null,
        ).withCanonicalIdentityAndHash()
        val roundTrip = RawJson.codec.decodeFromString(RawRecord.serializer(), RawJson.canonicalRecord(value))
        assertThat(roundTrip.startTime!!.nano).isEqualTo(999_999_999)
        assertThat(roundTrip.startTime!!.epochSecondExact).isEqualTo("10")
        assertThat(roundTrip.metadata!!.clientRecordVersionExact).isEqualTo("0")
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

    private class FakeRepository(
        private val items: Flow<RawExportItem>,
        private val providerCapabilities: RawProviderCapabilities = RawProviderCapabilities(available = true),
    ) : RawHealthRepository {
        override suspend fun capabilities() = providerCapabilities
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

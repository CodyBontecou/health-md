package com.healthmd.rawexport

import android.content.Context
import java.io.File
import java.io.FilterOutputStream
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.collect
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

class RawSnapshotExportOrchestrator(
    private val repository: RawHealthRepository,
    private val storage: RawExportStorage,
    private val spoolRoot: File,
    private val clock: () -> Instant = Instant::now,
    private val maxRecordsInMemory: Int = 512,
) {
    constructor(
        context: Context,
        repository: RawHealthRepository,
        storage: RawExportStorage = NoBackupRawExportStorage(context),
        clock: () -> Instant = Instant::now,
    ) : this(repository, storage, File(context.noBackupFilesDir, "raw-export"), clock)

    suspend fun export(inputRequest: RawSnapshotRequest): RawExportResult {
        val request = inputRequest.copy(selectedMetricIds = inputRequest.selectedMetricIds.toSortedSet())
        val definitions = repository.typeDefinitions()
            .map { it.copy(metricIds = it.metricIds.toSortedSet()) }
            .sortedBy { it.typeKey }
        require(definitions.isNotEmpty()) { "Raw provider type inventory is empty" }
        require(definitions.map { it.typeKey }.distinct().size == definitions.size) { "Raw provider type keys must be unique" }
        val definitionsByKey = definitions.associateBy { it.typeKey }
        val created = clock()
        val capabilities = repository.capabilities().let {
            it.copy(
                grantedPermissions = it.grantedPermissions.toSortedSet(),
                availableFeatures = it.availableFeatures.toSortedSet(),
            )
        }
        val snapshotId = createSnapshotId(request, created, capabilities.providerId)
        val spoolDirectory = File(spoolRoot, "spool-$snapshotId")
        // Native pages may be as large as the bounded HTTP page limit. Flush each immediately;
        // retaining the Health Connect batch size here could multiply page-sized byte/text copies.
        val spoolBatchSize = if (capabilities.fidelityLevel == RawProviderFidelity.NATIVE_API_PAYLOAD) 1 else maxRecordsInMemory
        val spool = DiskBackedCanonicalSpool(spoolDirectory, spoolBatchSize)
        val reports = linkedMapOf<String, RawTypeReport>()
        val observedIssueCounts = mutableMapOf<String, Long>()
        var providerFinalStatus: RawSnapshotStatus? = null
        var sink: RawAtomicExportSink? = null
        try {
            try {
                repository.stream(request).collect { item ->
                    when (item) {
                        is RawExportItem.Record -> spool.append(item.record)
                        is RawExportItem.Issue -> {
                            spool.append(item.issue)
                            item.issue.recordType?.let { type ->
                                observedIssueCounts[type] = (observedIssueCounts[type] ?: 0) + 1
                            }
                        }
                        is RawExportItem.TypeReport -> {
                            val prior = reports.put(item.report.typeKey, item.report)
                            if (prior != null) {
                                spool.append(RawIssue("duplicate_type_report", "The provider emitted more than one report for a type.", RawIssueSeverity.ERROR, item.report.typeKey))
                                observedIssueCounts[item.report.typeKey] = (observedIssueCounts[item.report.typeKey] ?: 0) + 1
                            }
                        }
                        is RawExportItem.Status -> when (item.status) {
                            RawSnapshotStatus.PENDING, RawSnapshotStatus.RUNNING -> Unit
                            RawSnapshotStatus.CANCELLED -> throw CancellationException(item.message ?: "Raw export cancelled")
                            RawSnapshotStatus.COMPLETE, RawSnapshotStatus.PARTIAL, RawSnapshotStatus.FAILED -> providerFinalStatus = item.status
                        }
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                spool.append(
                    RawIssue(
                        code = "provider_stream_failed",
                        message = "Raw provider stream failed.",
                        severity = RawIssueSeverity.ERROR,
                        retryable = true,
                    ),
                )
                providerFinalStatus = RawSnapshotStatus.FAILED
            }

            // A normal end without a terminal provider status is an incomplete run, not a partial artifact.
            val terminalStatus = providerFinalStatus ?: error("Provider ended without a terminal raw export status")
            for (definition in definitions) {
                val supplied = reports[definition.typeKey]
                if (supplied == null) {
                    if (isSelected(definition, request)) {
                        val message = "The provider did not emit the required type report."
                        spool.append(RawIssue("type_report_missing", message, RawIssueSeverity.ERROR, definition.typeKey))
                        observedIssueCounts[definition.typeKey] = (observedIssueCounts[definition.typeKey] ?: 0) + 1
                        reports[definition.typeKey] = definition.report(RawTypeStatus.READ_ERROR, message)
                    } else {
                        reports[definition.typeKey] = definition.report(RawTypeStatus.NOT_SELECTED)
                    }
                } else {
                    val selected = isSelected(definition, request)
                    val resolvedStatus = if (selected && supplied.status == RawTypeStatus.NOT_SELECTED) {
                        val message = "The provider marked a scope-selected type as not selected."
                        spool.append(RawIssue("invalid_type_status", message, RawIssueSeverity.ERROR, definition.typeKey))
                        observedIssueCounts[definition.typeKey] = (observedIssueCounts[definition.typeKey] ?: 0) + 1
                        RawTypeStatus.READ_ERROR
                    } else {
                        supplied.status
                    }
                    reports[definition.typeKey] = supplied.copy(
                        typeKey = definition.typeKey,
                        wireType = definition.wireType,
                        providerId = definition.providerId,
                        status = resolvedStatus,
                        permission = definition.permission,
                        feature = definition.feature,
                        rangeBehavior = definition.rangeBehavior,
                        pagination = definition.pagination,
                        serverAggregation = definition.serverAggregation,
                    )
                }
            }
            val unknownReportKeys = reports.keys - definitionsByKey.keys
            unknownReportKeys.sorted().forEach { key ->
                reports.remove(key)
                spool.append(RawIssue("unknown_type_report", "The provider emitted a report outside its declared capability inventory.", RawIssueSeverity.ERROR, key))
            }
            reports.values.forEach { report ->
                if (report.status != RawTypeStatus.EXPORTED && report.status != RawTypeStatus.NOT_SELECTED &&
                    (observedIssueCounts[report.typeKey] ?: 0L) == 0L
                ) {
                    spool.append(
                        RawIssue(
                            code = "type_status_issue_missing",
                            message = "A non-exported type status did not include its required structured issue.",
                            severity = RawIssueSeverity.ERROR,
                            recordType = report.typeKey,
                        ),
                    )
                    observedIssueCounts[report.typeKey] = 1
                }
            }

            val finalStatus = resolveFinalStatus(terminalStatus, request, reports.values, definitions, definitionsByKey)
            check(finalStatus in FINAL_ARTIFACT_STATUSES) { "Transient status cannot be promoted: $finalStatus" }
            spool.prepare()

            val header = RawSnapshotHeader(
                snapshotId = snapshotId,
                createdAt = RawInstant(created.epochSecond, created.nano),
                request = request,
                capabilities = capabilities,
            )
            sink = storage.openPartial(snapshotId, request.format)
            val artifactDigest = MessageDigest.getInstance("SHA-256")
            val counting = CountingOutputStream(DigestOutputStream(sink.output, artifactDigest))
            val logicalDigest = MessageDigest.getInstance("SHA-256")
            val typeCounts = linkedMapOf<String, Long>()
            val reportRecordCounts = mutableMapOf<String, Long>()
            val reportIssueCounts = mutableMapOf<String, Long>()

            fun logical(kind: String, canonical: String) {
                logicalDigest.update(kind.toByteArray(Charsets.UTF_8))
                logicalDigest.update(0)
                logicalDigest.update(canonical.toByteArray(Charsets.UTF_8))
                logicalDigest.update('\n'.code.toByte())
            }
            fun account(record: RawRecord) {
                typeCounts[record.wireType] = (typeCounts[record.wireType] ?: 0L) + 1
                val typeKey = record.reportTypeKey(definitionsByKey)
                reportRecordCounts[typeKey] = (reportRecordCounts[typeKey] ?: 0L) + 1
            }
            fun account(issue: RawIssue) {
                issue.recordType?.let { typeKey ->
                    reportIssueCounts[typeKey] = (reportIssueCounts[typeKey] ?: 0L) + 1
                }
            }

            val headerJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawSnapshotHeader.serializer(), header))
            val logicalHeaderJson = RawJson.canonical(
                RawJson.codec.encodeToJsonElement(
                    RawSnapshotHeader.serializer(),
                    header.copy(request = header.request.copy(format = RawExportFormat.JSON)),
                ),
            )
            logical("header", logicalHeaderJson)
            when (request.format) {
                RawExportFormat.JSON -> {
                    counting.utf8("{\"header\":$headerJson,\"records\":[")
                    var first = true
                    spool.forEachRecord { record ->
                        val canonical = RawJson.canonicalRecord(record)
                        if (!first) counting.utf8(",")
                        first = false
                        counting.utf8(canonical)
                        logical("record", canonical)
                        account(record)
                    }
                    counting.utf8("],\"issues\":[")
                    first = true
                    spool.forEachIssue { issue ->
                        val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
                        if (!first) counting.utf8(",")
                        first = false
                        counting.utf8(canonical)
                        logical("issue", canonical)
                        account(issue)
                    }
                    counting.utf8("],\"manifest\":")
                }
                RawExportFormat.NDJSON -> {
                    counting.utf8(envelope("header", "header", headerJson) + "\n")
                    spool.forEachRecord { record ->
                        val canonical = RawJson.canonicalRecord(record)
                        counting.utf8(envelope("record", "record", canonical) + "\n")
                        logical("record", canonical)
                        account(record)
                    }
                    spool.forEachIssue { issue ->
                        val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
                        counting.utf8(envelope("issue", "issue", canonical) + "\n")
                        logical("issue", canonical)
                        account(issue)
                    }
                }
            }

            val resolvedReports = reports.values.map { report ->
                report.copy(
                    recordCount = reportRecordCounts[report.typeKey] ?: 0,
                    issueCount = reportIssueCounts[report.typeKey] ?: 0,
                )
            }.sortedBy { it.typeKey }
            val logicalChecksum = logicalDigest.digest().hex()
            val completed = clock()
            val unsigned = RawSnapshotManifest(
                snapshotId = snapshotId,
                status = finalStatus,
                completedAt = RawInstant(completed.epochSecond, completed.nano),
                recordCount = spool.recordCount,
                issueCount = spool.issueCount,
                duplicateCount = spool.duplicateCount,
                identityCollisionCount = spool.identityCollisionCount,
                typeCounts = typeCounts.entries.sortedBy { it.key }.map { RawTypeCount(it.key, it.value) },
                typeReports = resolvedReports,
                logicalChecksumSha256 = logicalChecksum,
                manifestChecksumSha256 = "",
            )
            val manifest = unsigned.copy(manifestChecksumSha256 = RawJson.manifestHash(unsigned))
            val manifestJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawSnapshotManifest.serializer(), manifest))
            if (request.format == RawExportFormat.JSON) {
                counting.utf8(manifestJson + "}")
            } else {
                counting.utf8(envelope("manifest", "manifest", manifestJson) + "\n")
            }
            counting.flush()
            sink.close()
            val bytes = counting.count
            val artifactChecksum = artifactDigest.digest().hex()
            val finalLocation = sink.promote()
            return RawExportResult(
                snapshotId = snapshotId,
                finalLocation = finalLocation,
                format = request.format,
                manifest = manifest.copy(artifactChecksumSha256 = artifactChecksum),
                artifactChecksumSha256 = artifactChecksum,
                bytesWritten = bytes,
            )
        } catch (cancelled: CancellationException) {
            sink?.abort()
            throw cancelled
        } catch (error: Throwable) {
            sink?.abort()
            throw error
        } finally {
            spool.close()
        }
    }

    private fun resolveFinalStatus(
        providerStatus: RawSnapshotStatus,
        request: RawSnapshotRequest,
        reports: Collection<RawTypeReport>,
        definitions: List<RawProviderTypeDefinition>,
        definitionsByKey: Map<String, RawProviderTypeDefinition>,
    ): RawSnapshotStatus {
        if (providerStatus == RawSnapshotStatus.FAILED) return RawSnapshotStatus.FAILED
        val knownMetrics = definitions.flatMap { it.metricIds }.toSet()
        val unknownSelection = request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES &&
            request.selectedMetricIds.any { it !in knownMetrics }
        val incompleteReport = reports.any { report ->
            when (request.scope) {
                RawSnapshotScope.SELECTED_RECORD_TYPES -> {
                    val selected = definitionsByKey[report.typeKey]?.let { isSelected(it, request) } == true
                    selected && report.status != RawTypeStatus.EXPORTED
                }
                RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ->
                    report.status == RawTypeStatus.READ_ERROR || report.status == RawTypeStatus.HISTORY_PERMISSION_MISSING
            }
        }
        return if (providerStatus == RawSnapshotStatus.PARTIAL || unknownSelection || incompleteReport) {
            RawSnapshotStatus.PARTIAL
        } else {
            RawSnapshotStatus.COMPLETE
        }
    }

    private fun isSelected(definition: RawProviderTypeDefinition, request: RawSnapshotRequest): Boolean =
        request.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ||
            definition.metricIds.any(request.selectedMetricIds::contains)

    private fun RawProviderTypeDefinition.report(status: RawTypeStatus, message: String? = null) = RawTypeReport(
        typeKey = typeKey,
        wireType = wireType,
        providerId = providerId,
        status = status,
        permission = permission,
        feature = feature,
        rangeBehavior = rangeBehavior,
        pagination = pagination,
        serverAggregation = serverAggregation,
        message = message,
    )

    private fun RawRecord.reportTypeKey(definitionsByKey: Map<String, RawProviderTypeDefinition>): String {
        providerPayload?.endpointKey?.let { return it }
        if (wireType != "medical_resource") return wireType
        val label = fields["medicalResourceType"]?.jsonObject?.get("label")?.jsonPrimitive?.content
        return label?.let { "medical_resource/$it" }?.takeIf(definitionsByKey::containsKey) ?: wireType
    }

    private fun createSnapshotId(request: RawSnapshotRequest, created: Instant, providerId: String): String {
        val logicalRequest = request.copy(format = RawExportFormat.JSON)
        val requestJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawSnapshotRequest.serializer(), logicalRequest))
        val providerLine = if (providerId == "health_connect") "" else "provider:$providerId\n"
        return RawJson.sha256("v1\n$providerLine${created.epochSecond}:${created.nano}\n$requestJson").take(32)
    }

    private fun envelope(kind: String, field: String, canonicalValue: String): String =
        RawJson.canonical(JsonObject(mapOf("kind" to JsonPrimitive(kind), field to RawJson.codec.parseToJsonElement(canonicalValue))))

    private class CountingOutputStream(output: OutputStream) : FilterOutputStream(output) {
        var count: Long = 0; private set
        override fun write(value: Int) { out.write(value); count++ }
        override fun write(buffer: ByteArray, offset: Int, length: Int) { out.write(buffer, offset, length); count += length }
        fun utf8(value: String) = write(value.toByteArray(Charsets.UTF_8))
    }

    private fun ByteArray.hex(): String = joinToString("") { "%02x".format(it) }

    companion object {
        private val FINAL_ARTIFACT_STATUSES = setOf(RawSnapshotStatus.COMPLETE, RawSnapshotStatus.PARTIAL, RawSnapshotStatus.FAILED)
    }
}

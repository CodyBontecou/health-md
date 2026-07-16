package com.healthmd.rawexport

import android.content.Context
import java.io.File
import java.io.FilterOutputStream
import java.io.OutputStream
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.collect
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private class ProviderProtocolException(message: String) : IllegalStateException(message)

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
        val exportContext = currentCoroutineContext()
        val checkCancellation = { exportContext.ensureActive() }
        checkCancellation()
        val request = inputRequest.copy(selectedMetricIds = inputRequest.selectedMetricIds.toSortedSet(RawJson.codePointComparator))
        val definitions = repository.typeDefinitions()
            .map { it.copy(metricIds = it.metricIds.toSortedSet(RawJson.codePointComparator)) }
            .sortedWith { left, right -> RawJson.codePointComparator.compare(left.typeKey, right.typeKey) }
        require(definitions.isNotEmpty()) { "Raw provider type inventory is empty" }
        require(definitions.map { it.typeKey }.distinct().size == definitions.size) { "Raw provider type keys must be unique" }
        val definitionsByKey = definitions.associateBy { it.typeKey }
        val created = clock()
        val capabilities = repository.capabilities().let {
            it.copy(
                grantedPermissions = it.grantedPermissions.toSortedSet(RawJson.codePointComparator),
                availableFeatures = it.availableFeatures.toSortedSet(RawJson.codePointComparator),
            )
        }
        val snapshotId = createSnapshotId(request, created, capabilities.providerId)
        val spoolDirectory = File(spoolRoot, "spool-$snapshotId")
        claimSpool(spoolDirectory)
        // Native pages may be as large as the bounded HTTP page limit. Flush each immediately;
        // retaining the Health Connect batch size here could multiply page-sized byte/text copies.
        val spoolBatchSize = if (capabilities.fidelityLevel == RawProviderFidelity.NATIVE_API_PAYLOAD) 1 else maxRecordsInMemory
        val spool = try {
            DiskBackedCanonicalSpool(spoolDirectory, spoolBatchSize)
        } catch (error: Throwable) {
            releaseSpool(spoolDirectory)
            throw error
        }
        val reports = linkedMapOf<String, RawTypeReport>()
        val observedIssueCounts = mutableMapOf<String, Long>()
        var providerFinalStatus: RawSnapshotStatus? = null
        var providerContractIncomplete = false
        var sink: RawAtomicExportSink? = null
        try {
            try {
                repository.stream(request).collect { item ->
                    checkCancellation()
                    if (providerFinalStatus != null) {
                        throw ProviderProtocolException("Provider emitted output after its terminal status")
                    }
                    when (item) {
                        is RawExportItem.Record -> spool.append(item.record, checkCancellation)
                        is RawExportItem.Issue -> {
                            spool.append(item.issue, checkCancellation)
                            item.issue.recordType?.let { type ->
                                observedIssueCounts[type] = (observedIssueCounts[type] ?: 0) + 1
                            }
                        }
                        is RawExportItem.TypeReport -> {
                            val prior = reports[item.report.typeKey]
                            reports[item.report.typeKey] = if (prior == null) item.report else retainHigherSeverity(prior, item.report)
                            if (prior != null) {
                                providerContractIncomplete = true
                                spool.append(RawIssue("duplicate_type_report", "The provider emitted more than one report for a type.", RawIssueSeverity.ERROR, recordType = null), checkCancellation)
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
            } catch (protocol: ProviderProtocolException) {
                throw protocol
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

            checkCancellation()
            // A normal end without exactly one terminal provider status is incomplete, not partial.
            val terminalStatus = providerFinalStatus ?: error("Provider ended without a terminal raw export status")
            for (definition in definitions) {
                checkCancellation()
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
            if (unknownReportKeys.isNotEmpty()) providerContractIncomplete = true
            unknownReportKeys.sortedWith(RawJson.codePointComparator).forEach { key ->
                reports.remove(key)
                // There can be no matching retained report, so this is a global issue by contract.
                spool.append(RawIssue("unknown_type_report", "The provider emitted a report outside its declared capability inventory.", RawIssueSeverity.ERROR, recordType = null), checkCancellation)
            }
            reports.values.forEach { report ->
                checkCancellation()
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
                        checkCancellation,
                    )
                    observedIssueCounts[report.typeKey] = 1
                }
            }

            if (terminalStatus == RawSnapshotStatus.PARTIAL) {
                spool.append(
                    RawIssue(
                        code = "provider_partial_status",
                        message = "The provider completed with an explicit partial status.",
                        severity = RawIssueSeverity.ERROR,
                        recordType = null,
                    ),
                    checkCancellation,
                )
            }
            val effectiveTerminalStatus = if (providerContractIncomplete && terminalStatus != RawSnapshotStatus.FAILED) {
                RawSnapshotStatus.PARTIAL
            } else {
                terminalStatus
            }
            val finalStatus = resolveFinalStatus(effectiveTerminalStatus, request, reports.values, definitions, definitionsByKey)
            check(finalStatus in FINAL_ARTIFACT_STATUSES) { "Transient status cannot be promoted: $finalStatus" }
            spool.prepare(checkCancellation)

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
                    spool.forEachRecord(checkCancellation) { record ->
                        checkCancellation()
                        val canonical = RawJson.canonicalRecord(record)
                        if (!first) counting.utf8(",")
                        first = false
                        counting.utf8(canonical)
                        logical("record", canonical)
                        account(record)
                        checkCancellation()
                    }
                    counting.utf8("],\"issues\":[")
                    first = true
                    spool.forEachIssue(checkCancellation) { issue ->
                        checkCancellation()
                        val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
                        if (!first) counting.utf8(",")
                        first = false
                        counting.utf8(canonical)
                        logical("issue", canonical)
                        account(issue)
                        checkCancellation()
                    }
                    counting.utf8("],\"manifest\":")
                }
                RawExportFormat.NDJSON -> {
                    counting.utf8(envelope("header", "header", headerJson) + "\n")
                    spool.forEachRecord(checkCancellation) { record ->
                        checkCancellation()
                        val canonical = RawJson.canonicalRecord(record)
                        counting.utf8(envelope("record", "record", canonical) + "\n")
                        logical("record", canonical)
                        account(record)
                        checkCancellation()
                    }
                    spool.forEachIssue(checkCancellation) { issue ->
                        checkCancellation()
                        val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
                        counting.utf8(envelope("issue", "issue", canonical) + "\n")
                        logical("issue", canonical)
                        account(issue)
                        checkCancellation()
                    }
                }
            }

            val resolvedReports = reports.values.map { report ->
                checkCancellation()
                report.copy(
                    recordCount = reportRecordCounts[report.typeKey] ?: 0,
                    issueCount = reportIssueCounts[report.typeKey] ?: 0,
                )
            }.sortedWith { left, right -> RawJson.codePointComparator.compare(left.typeKey, right.typeKey) }
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
                typeCounts = typeCounts.entries.sortedWith { left, right -> RawJson.codePointComparator.compare(left.key, right.key) }
                    .map { RawTypeCount(it.key, it.value) },
                typeReports = resolvedReports,
                logicalChecksumSha256 = logicalChecksum,
                manifestChecksumSha256 = "",
            )
            checkCancellation()
            val manifest = unsigned.copy(manifestChecksumSha256 = RawJson.manifestHash(unsigned))
            val manifestJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawSnapshotManifest.serializer(), manifest))
            checkCancellation()
            if (request.format == RawExportFormat.JSON) {
                counting.utf8(manifestJson + "}")
            } else {
                counting.utf8(envelope("manifest", "manifest", manifestJson) + "\n")
            }
            checkCancellation()
            counting.flush()
            sink.close()
            checkCancellation()
            val bytes = counting.count
            val artifactChecksum = artifactDigest.digest().hex()
            val expectation = RawPromotionExpectation(bytes, artifactChecksum)
            checkCancellation() // The last check before storage enters cancellation-aware promotion.
            val receipt = sink.promote(expectation, checkCancellation)
            check(receipt.byteCount == bytes && receipt.checksumSha256 == artifactChecksum) {
                "Storage promotion receipt does not identify the completed partial."
            }
            checkCancellation()
            return RawExportResult(
                snapshotId = snapshotId,
                finalLocation = receipt.location,
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
            releaseSpool(spoolDirectory)
        }
    }

    private fun retainHigherSeverity(first: RawTypeReport, second: RawTypeReport): RawTypeReport {
        val firstRank = TYPE_STATUS_PRECEDENCE.getValue(first.status)
        val secondRank = TYPE_STATUS_PRECEDENCE.getValue(second.status)
        return if (secondRank > firstRank) second else first
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
        private val TYPE_STATUS_PRECEDENCE = mapOf(
            RawTypeStatus.EXPORTED to 0,
            RawTypeStatus.HISTORY_PERMISSION_MISSING to 1,
            RawTypeStatus.READ_ERROR to 2,
            RawTypeStatus.PERMISSION_NOT_GRANTED to 3,
            RawTypeStatus.FEATURE_UNAVAILABLE to 4,
            RawTypeStatus.UNSUPPORTED_BY_PROVIDER to 5,
            RawTypeStatus.NOT_SELECTED to 6,
        )
        private val spoolLock = Any()
        private val activeSpools = mutableSetOf<String>()

        /** New-process runs remove abandoned installation-private spools; concurrent live runs are retained. */
        private fun claimSpool(directory: File) = synchronized(spoolLock) {
            val path = directory.absolutePath
            directory.parentFile?.listFiles()
                ?.filter { it.isDirectory && it.name.startsWith("spool-") && it.absolutePath !in activeSpools }
                ?.forEach { check(it.deleteRecursively()) { "Unable to clean an abandoned raw export spool." } }
            activeSpools += path
        }

        private fun releaseSpool(directory: File) = synchronized(spoolLock) {
            activeSpools -= directory.absolutePath
        }
    }
}

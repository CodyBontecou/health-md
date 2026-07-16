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

    suspend fun export(request: RawSnapshotRequest): RawExportResult {
        val created = clock()
        val capabilities = repository.capabilities()
        val snapshotId = createSnapshotId(request, created)
        val spoolDirectory = File(spoolRoot, "spool-$snapshotId")
        val spool = DiskBackedCanonicalSpool(spoolDirectory, maxRecordsInMemory)
        var finalStatus = RawSnapshotStatus.PENDING
        var sink: RawAtomicExportSink? = null
        try {
            try {
                repository.stream(request).collect { item ->
                    when (item) {
                        is RawExportItem.Record -> spool.append(item.record)
                        is RawExportItem.Issue -> spool.append(item.issue)
                        is RawExportItem.Status -> finalStatus = item.status
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                spool.append(
                    RawIssue(
                        code = "provider_stream_failed",
                        message = error.message?.take(240) ?: "Raw provider stream failed.",
                        severity = RawIssueSeverity.ERROR,
                        retryable = true,
                    ),
                )
                finalStatus = RawSnapshotStatus.FAILED
            }
            if (finalStatus !in setOf(RawSnapshotStatus.COMPLETE, RawSnapshotStatus.PARTIAL, RawSnapshotStatus.FAILED)) {
                finalStatus = RawSnapshotStatus.PARTIAL
                spool.append(RawIssue("completion_status_missing", "Provider ended without a final completion status."))
            }
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

            fun logical(kind: String, canonical: String) {
                logicalDigest.update(kind.toByteArray(Charsets.UTF_8))
                logicalDigest.update(0)
                logicalDigest.update(canonical.toByteArray(Charsets.UTF_8))
                logicalDigest.update('\n'.code.toByte())
            }

            val headerJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawSnapshotHeader.serializer(), header))
            // Format is an artifact concern, not part of the logical snapshot identity/checksum.
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
                        typeCounts[record.wireType] = (typeCounts[record.wireType] ?: 0L) + 1
                    }
                    counting.utf8("],\"issues\":[")
                    first = true
                    spool.forEachIssue { issue ->
                        val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
                        if (!first) counting.utf8(",")
                        first = false
                        counting.utf8(canonical)
                        logical("issue", canonical)
                    }
                    counting.utf8("],\"manifest\":")
                }
                RawExportFormat.NDJSON -> {
                    counting.utf8(envelope("header", "header", headerJson) + "\n")
                    spool.forEachRecord { record ->
                        val canonical = RawJson.canonicalRecord(record)
                        counting.utf8(envelope("record", "record", canonical) + "\n")
                        logical("record", canonical)
                        typeCounts[record.wireType] = (typeCounts[record.wireType] ?: 0L) + 1
                    }
                    spool.forEachIssue { issue ->
                        val canonical = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue))
                        counting.utf8(envelope("issue", "issue", canonical) + "\n")
                        logical("issue", canonical)
                    }
                }
            }

            val logicalChecksum = logicalDigest.digest().hex()
            val unsigned = RawSnapshotManifest(
                snapshotId = snapshotId,
                status = finalStatus,
                recordCount = spool.recordCount,
                issueCount = spool.issueCount,
                duplicateCount = spool.duplicateCount,
                typeCounts = typeCounts.entries.sortedBy { it.key }.map { RawTypeCount(it.key, it.value) },
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

    private fun createSnapshotId(request: RawSnapshotRequest, created: Instant): String {
        val logicalRequest = request.copy(format = RawExportFormat.JSON)
        val requestJson = RawJson.canonical(RawJson.codec.encodeToJsonElement(RawSnapshotRequest.serializer(), logicalRequest))
        return RawJson.sha256("v1\n${created.epochSecond}:${created.nano}\n$requestJson").take(32)
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
}

package com.healthmd.rawexport

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.Closeable
import java.io.File
import java.util.PriorityQueue

/** Bounded-memory external sort and native-identity de-duplication spool. */
class DiskBackedCanonicalSpool(
    private val directory: File,
    private val maxRecordsInMemory: Int = 512,
) : Closeable {
    private val identityBuffer = ArrayList<RawRecord>(maxRecordsInMemory)
    private val identityChunks = mutableListOf<File>()
    private val orderedBuffer = ArrayList<RawRecord>(maxRecordsInMemory)
    private val orderedChunks = mutableListOf<File>()
    private val issuesFile: File
    private val issuesWriter: BufferedWriter
    private var prepared = false

    var inputRecordCount: Long = 0; private set
    var recordCount: Long = 0; private set
    var duplicateCount: Long = 0; private set
    var identityCollisionCount: Long = 0; private set
    var issueCount: Long = 0; private set

    init {
        require(maxRecordsInMemory > 0)
        directory.mkdirs()
        issuesFile = File(directory, "issues.ndjson")
        issuesWriter = issuesFile.bufferedWriter()
    }

    fun append(record: RawRecord) {
        check(!prepared)
        identityBuffer += record
        inputRecordCount++
        if (identityBuffer.size >= maxRecordsInMemory) flushIdentityChunk()
    }

    fun append(issue: RawIssue) {
        check(!prepared)
        issuesWriter.append(RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue)))
        issuesWriter.newLine()
        issueCount++
    }

    fun prepare() {
        if (prepared) return
        issuesWriter.flush()
        flushIdentityChunk()
        mergeIdentityAndBuildOrderedChunks()
        issuesWriter.flush()
        flushOrderedChunk()
        identityChunks.forEach(File::delete)
        identityChunks.clear()
        prepared = true
    }

    fun forEachRecord(block: (RawRecord) -> Unit) {
        prepare()
        mergeFiles(orderedChunks, ORDER_COMPARATOR, block)
    }

    fun forEachIssue(block: (RawIssue) -> Unit) {
        prepare()
        val ordered = issuesFile.bufferedReader().useLines { lines ->
            lines.filter(String::isNotBlank)
                .mapIndexed { index, line -> index to RawJson.codec.decodeFromString(RawIssue.serializer(), line) }
                .toList()
        }.sortedWith(compareBy<Pair<Int, RawIssue>>({ RawExportTypeCatalog.issueRank(it.second.recordType) }, { it.first }))
        ordered.forEach { block(it.second) }
    }

    private fun flushIdentityChunk() {
        if (identityBuffer.isEmpty()) return
        identityBuffer.sortWith(IDENTITY_COMPARATOR)
        identityChunks += writeChunk("identity", identityBuffer)
        identityBuffer.clear()
    }

    private fun flushOrderedChunk() {
        if (orderedBuffer.isEmpty()) return
        orderedBuffer.sortWith(ORDER_COMPARATOR)
        orderedChunks += writeChunk("ordered", orderedBuffer)
        orderedBuffer.clear()
    }

    private fun mergeIdentityAndBuildOrderedChunks() {
        var current: RawRecord? = null
        var collision = false
        fun finishGroup(record: RawRecord) {
            if (collision) {
                identityCollisionCount++
                append(
                    RawIssue(
                        code = "identity_collision",
                        message = "Records with one native identity had differing payloads or versions; the deterministic preferred record was retained.",
                        severity = RawIssueSeverity.WARNING,
                        recordType = record.reportTypeKey(),
                    ),
                )
            }
            addOrdered(record)
        }
        mergeFiles(identityChunks, IDENTITY_COMPARATOR) { record ->
            val prior = current
            if (prior == null) {
                current = record
            } else if (prior.nativeIdentity == record.nativeIdentity) {
                duplicateCount++
                if (prior.hash != record.hash) collision = true
                current = preferred(prior, record)
            } else {
                finishGroup(prior)
                current = record
                collision = false
            }
        }
        current?.let(::finishGroup)
    }

    private fun addOrdered(record: RawRecord) {
        orderedBuffer += record
        recordCount++
        if (orderedBuffer.size >= maxRecordsInMemory) flushOrderedChunk()
    }

    private fun preferred(a: RawRecord, b: RawRecord): RawRecord {
        val av = a.metadata?.clientRecordVersion ?: Long.MIN_VALUE
        val bv = b.metadata?.clientRecordVersion ?: Long.MIN_VALUE
        if (av != bv) return if (av > bv) a else b
        val at = a.metadata?.lastModifiedTime
        val bt = b.metadata?.lastModifiedTime
        val timeComparison = compareValuesBy(at, bt, { it?.epochSecond ?: Long.MIN_VALUE }, { it?.nano ?: Int.MIN_VALUE })
        if (timeComparison != 0) return if (timeComparison > 0) a else b
        return if (a.hash <= b.hash) a else b
    }

    private fun writeChunk(prefix: String, records: List<RawRecord>): File {
        val file = File(directory, "$prefix-${System.nanoTime()}-${records.hashCode()}.ndjson")
        file.bufferedWriter().use { writer ->
            records.forEach {
                writer.append(RawJson.canonicalRecord(it))
                writer.newLine()
            }
        }
        return file
    }

    private fun mergeFiles(files: List<File>, comparator: Comparator<RawRecord>, block: (RawRecord) -> Unit) {
        if (files.isEmpty()) return
        data class Cursor(val reader: BufferedReader, var record: RawRecord, val ordinal: Int)
        val queue = PriorityQueue<Cursor> { a, b ->
            comparator.compare(a.record, b.record).takeIf { it != 0 } ?: a.ordinal.compareTo(b.ordinal)
        }
        val readers = files.map(File::bufferedReader)
        try {
            readers.forEachIndexed { index, reader -> readRecord(reader)?.let { queue += Cursor(reader, it, index) } }
            while (queue.isNotEmpty()) {
                val cursor = queue.remove()
                block(cursor.record)
                readRecord(cursor.reader)?.let { next -> cursor.record = next; queue += cursor }
            }
        } finally {
            readers.forEach { runCatching { it.close() } }
        }
    }

    private fun readRecord(reader: BufferedReader): RawRecord? {
        val line = reader.readLine() ?: return null
        return RawJson.codec.decodeFromString(RawRecord.serializer(), line)
    }

    override fun close() {
        runCatching { issuesWriter.close() }
        directory.deleteRecursively()
    }

    private fun RawRecord.reportTypeKey(): String {
        if (wireType != "medical_resource") return wireType
        val label = fields["medicalResourceType"]
            ?.let { it as? kotlinx.serialization.json.JsonObject }
            ?.get("label")
            ?.let { it as? kotlinx.serialization.json.JsonPrimitive }
            ?.content
        return label?.let { "medical_resource/$it" }?.takeIf(RawExportTypeCatalog.byKey::containsKey)
            ?: wireType
    }

    companion object {
        private val IDENTITY_COMPARATOR = compareBy<RawRecord>({ it.nativeIdentity }, { it.hash })
        private val ORDER_COMPARATOR = compareBy<RawRecord>(
            { it.wireType }, { it.startTime?.epochSecond ?: Long.MIN_VALUE },
            { it.startTime?.nano ?: Int.MIN_VALUE }, { it.endTime?.epochSecond ?: Long.MIN_VALUE },
            { it.endTime?.nano ?: Int.MIN_VALUE }, { it.nativeIdentity }, { it.hash },
        )
    }
}

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
    private val maxMergeFanIn: Int = 32,
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
    /** Test/audit visibility: the merge implementation never exceeds [maxMergeFanIn]. */
    var maximumSimultaneouslyOpenChunks: Int = 0; private set

    init {
        require(maxRecordsInMemory > 0)
        require(maxMergeFanIn >= 2)
        directory.mkdirs()
        issuesFile = File(directory, "issues.ndjson")
        issuesWriter = issuesFile.bufferedWriter()
    }

    fun append(record: RawRecord) = append(record) {}

    fun append(record: RawRecord, checkCancellation: () -> Unit) {
        check(!prepared)
        checkCancellation()
        identityBuffer += record
        inputRecordCount++
        if (identityBuffer.size >= maxRecordsInMemory) flushIdentityChunk(checkCancellation)
    }

    fun append(issue: RawIssue) = append(issue) {}

    fun append(issue: RawIssue, checkCancellation: () -> Unit) {
        check(!prepared)
        checkCancellation()
        issuesWriter.append(RawJson.canonical(RawJson.codec.encodeToJsonElement(RawIssue.serializer(), issue)))
        issuesWriter.newLine()
        issueCount++
    }

    fun prepare() = prepare {}

    fun prepare(checkCancellation: () -> Unit) {
        if (prepared) return
        checkCancellation()
        issuesWriter.flush()
        flushIdentityChunk(checkCancellation)
        compactChunks(identityChunks, IDENTITY_COMPARATOR, "identity-merge", checkCancellation)
        mergeIdentityAndBuildOrderedChunks(checkCancellation)
        issuesWriter.flush()
        flushOrderedChunk(checkCancellation)
        compactChunks(orderedChunks, ORDER_COMPARATOR, "ordered-merge", checkCancellation)
        identityChunks.forEach(File::delete)
        identityChunks.clear()
        checkCancellation()
        prepared = true
    }

    fun forEachRecord(block: (RawRecord) -> Unit) = forEachRecord({}, block)

    fun forEachRecord(checkCancellation: () -> Unit, block: (RawRecord) -> Unit) {
        prepare(checkCancellation)
        mergeFiles(orderedChunks, ORDER_COMPARATOR, checkCancellation, block)
    }

    fun forEachIssue(block: (RawIssue) -> Unit) = forEachIssue({}, block)

    fun forEachIssue(checkCancellation: () -> Unit, block: (RawIssue) -> Unit) {
        prepare(checkCancellation)
        // Provider traversal and spool-generated collision issues have deterministic occurrence order.
        issuesFile.bufferedReader().use { reader ->
            while (true) {
                checkCancellation()
                val line = reader.readLine() ?: break
                if (line.isNotBlank()) block(RawJson.codec.decodeFromString(RawIssue.serializer(), line))
            }
        }
    }

    private fun flushIdentityChunk(checkCancellation: () -> Unit) {
        if (identityBuffer.isEmpty()) return
        sort(identityBuffer, IDENTITY_COMPARATOR, checkCancellation)
        identityChunks += writeChunk("identity", identityBuffer, checkCancellation)
        identityBuffer.clear()
    }

    private fun flushOrderedChunk(checkCancellation: () -> Unit) {
        if (orderedBuffer.isEmpty()) return
        sort(orderedBuffer, ORDER_COMPARATOR, checkCancellation)
        orderedChunks += writeChunk("ordered", orderedBuffer, checkCancellation)
        orderedBuffer.clear()
    }

    private fun sort(records: MutableList<RawRecord>, comparator: Comparator<RawRecord>, checkCancellation: () -> Unit) {
        var comparisons = 0
        checkCancellation()
        records.sortWith { left, right ->
            if (++comparisons and 0xff == 0) checkCancellation()
            comparator.compare(left, right)
        }
        checkCancellation()
    }

    /** Repeatedly merge groups so the final merge opens at most [maxMergeFanIn] descriptors. */
    private fun compactChunks(
        chunks: MutableList<File>,
        comparator: Comparator<RawRecord>,
        prefix: String,
        checkCancellation: () -> Unit,
    ) {
        var pass = 0
        while (chunks.size > maxMergeFanIn) {
            checkCancellation()
            val next = mutableListOf<File>()
            chunks.chunked(maxMergeFanIn).forEachIndexed { groupIndex, group ->
                checkCancellation()
                if (group.size == 1) {
                    next += group.single()
                } else {
                    val merged = File(directory, "$prefix-$pass-$groupIndex-${System.nanoTime()}.ndjson")
                    try {
                        merged.bufferedWriter().use { writer ->
                            mergeFiles(group, comparator, checkCancellation) { record ->
                                writer.append(RawJson.canonicalRecord(record))
                                writer.newLine()
                            }
                        }
                    } catch (error: Throwable) {
                        merged.delete()
                        throw error
                    }
                    group.forEach { check(it.delete()) { "Unable to delete an intermediate raw snapshot chunk." } }
                    next += merged
                }
            }
            chunks.clear()
            chunks += next
            pass++
        }
    }

    private fun mergeIdentityAndBuildOrderedChunks(checkCancellation: () -> Unit) {
        var current: RawRecord? = null
        var collision = false
        fun finishGroup(record: RawRecord) {
            checkCancellation()
            if (collision) {
                identityCollisionCount++
                append(
                    RawIssue(
                        code = "identity_collision",
                        message = "Records with one native identity had differing payloads or versions; the deterministic preferred record was retained.",
                        severity = RawIssueSeverity.WARNING,
                        recordType = record.reportTypeKey(),
                    ),
                    checkCancellation,
                )
            }
            addOrdered(record, checkCancellation)
        }
        mergeFiles(identityChunks, IDENTITY_COMPARATOR, checkCancellation) { record ->
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

    private fun addOrdered(record: RawRecord, checkCancellation: () -> Unit) {
        orderedBuffer += record
        recordCount++
        if (orderedBuffer.size >= maxRecordsInMemory) flushOrderedChunk(checkCancellation)
    }

    private fun preferred(a: RawRecord, b: RawRecord): RawRecord {
        val av = a.metadata?.clientRecordVersion ?: Long.MIN_VALUE
        val bv = b.metadata?.clientRecordVersion ?: Long.MIN_VALUE
        if (av != bv) return if (av > bv) a else b
        val at = a.metadata?.lastModifiedTime
        val bt = b.metadata?.lastModifiedTime
        val timeComparison = compareValuesBy(at, bt, { it?.epochSecond ?: Long.MIN_VALUE }, { it?.nano ?: Int.MIN_VALUE })
        if (timeComparison != 0) return if (timeComparison > 0) a else b
        return if (RawJson.codePointComparator.compare(a.hash, b.hash) <= 0) a else b
    }

    private fun writeChunk(prefix: String, records: List<RawRecord>, checkCancellation: () -> Unit): File {
        val file = File(directory, "$prefix-${System.nanoTime()}-${records.hashCode()}.ndjson")
        try {
            file.bufferedWriter().use { writer ->
                records.forEach {
                    checkCancellation()
                    writer.append(RawJson.canonicalRecord(it))
                    writer.newLine()
                }
            }
        } catch (error: Throwable) {
            file.delete()
            throw error
        }
        return file
    }

    private fun mergeFiles(
        files: List<File>,
        comparator: Comparator<RawRecord>,
        checkCancellation: () -> Unit,
        block: (RawRecord) -> Unit,
    ) {
        if (files.isEmpty()) return
        check(files.size <= maxMergeFanIn) { "Raw snapshot merge exceeded bounded fan-in." }
        data class Cursor(val reader: BufferedReader, var record: RawRecord, val ordinal: Int)
        val queue = PriorityQueue<Cursor> { a, b ->
            comparator.compare(a.record, b.record).takeIf { it != 0 } ?: a.ordinal.compareTo(b.ordinal)
        }
        val readers = mutableListOf<BufferedReader>()
        try {
            files.forEachIndexed { index, file ->
                checkCancellation()
                val reader = file.bufferedReader()
                readers += reader
                maximumSimultaneouslyOpenChunks = maxOf(maximumSimultaneouslyOpenChunks, readers.size)
                readRecord(reader)?.let { queue += Cursor(reader, it, index) }
            }
            while (queue.isNotEmpty()) {
                checkCancellation()
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
        providerPayload?.endpointKey?.let { return it }
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
        private fun compareStrings(selector: (RawRecord) -> String): Comparator<RawRecord> =
            Comparator { left, right -> RawJson.codePointComparator.compare(selector(left), selector(right)) }

        private val IDENTITY_COMPARATOR = compareStrings(RawRecord::nativeIdentity)
            .thenComparing(compareStrings(RawRecord::hash))
        private val ORDER_COMPARATOR = compareStrings(RawRecord::wireType)
            .thenComparingLong { it.startTime?.epochSecond ?: Long.MIN_VALUE }
            .thenComparingInt { it.startTime?.nano ?: Int.MIN_VALUE }
            .thenComparingLong { it.endTime?.epochSecond ?: Long.MIN_VALUE }
            .thenComparingInt { it.endTime?.nano ?: Int.MIN_VALUE }
            .thenComparing(compareStrings(RawRecord::nativeIdentity))
            .thenComparing(compareStrings(RawRecord::hash))
    }
}

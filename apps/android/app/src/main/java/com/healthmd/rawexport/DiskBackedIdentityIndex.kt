package com.healthmd.rawexport

import java.io.BufferedReader
import java.io.Closeable
import java.io.File
import java.nio.file.Files
import java.util.Base64
import java.util.PriorityQueue

/** Bounded-memory exact identity uniqueness check used by streaming validation. */
internal class DiskBackedIdentityIndex(
    private val directory: File = Files.createTempDirectory("healthmd-raw-validator-").toFile(),
    private val maxInMemory: Int = 4096,
    private val maxFanIn: Int = 32,
) : Closeable {
    private data class Entry(val encodedIdentity: String, val recordIndex: Long) {
        fun line(): String = "$encodedIdentity\t$recordIndex"
    }

    private val buffer = ArrayList<Entry>(maxInMemory)
    private val chunks = mutableListOf<File>()

    init {
        require(maxInMemory > 0)
        require(maxFanIn >= 2)
        directory.mkdirs()
    }

    fun append(identity: String, recordIndex: Long) {
        val encoded = Base64.getEncoder().encodeToString(identity.toByteArray(Charsets.UTF_8))
        buffer += Entry(encoded, recordIndex)
        if (buffer.size >= maxInMemory) flush()
    }

    fun forEachDuplicate(block: (recordIndex: Long) -> Unit) {
        flush()
        compact()
        var previousIdentity: String? = null
        merge(chunks) { entry ->
            if (entry.encodedIdentity == previousIdentity) block(entry.recordIndex)
            previousIdentity = entry.encodedIdentity
        }
    }

    private fun flush() {
        if (buffer.isEmpty()) return
        buffer.sortWith(ENTRY_COMPARATOR)
        val chunk = File(directory, "identity-${System.nanoTime()}-${chunks.size}.txt")
        chunk.bufferedWriter().use { writer ->
            buffer.forEach { writer.append(it.line()).append('\n') }
        }
        chunks += chunk
        buffer.clear()
    }

    private fun compact() {
        var pass = 0
        while (chunks.size > maxFanIn) {
            val next = mutableListOf<File>()
            chunks.chunked(maxFanIn).forEachIndexed { index, group ->
                if (group.size == 1) {
                    next += group.single()
                } else {
                    val output = File(directory, "merge-$pass-$index-${System.nanoTime()}.txt")
                    try {
                        output.bufferedWriter().use { writer ->
                            merge(group) { writer.append(it.line()).append('\n') }
                        }
                    } catch (error: Throwable) {
                        output.delete()
                        throw error
                    }
                    group.forEach { check(it.delete()) { "Unable to delete validator identity chunk." } }
                    next += output
                }
            }
            chunks.clear()
            chunks += next
            pass++
        }
    }

    private fun merge(files: List<File>, block: (Entry) -> Unit) {
        if (files.isEmpty()) return
        check(files.size <= maxFanIn)
        data class Cursor(val reader: BufferedReader, var entry: Entry, val ordinal: Int)
        val queue = PriorityQueue<Cursor> { left, right ->
            ENTRY_COMPARATOR.compare(left.entry, right.entry).takeIf { it != 0 }
                ?: left.ordinal.compareTo(right.ordinal)
        }
        val readers = mutableListOf<BufferedReader>()
        try {
            files.forEachIndexed { index, file ->
                val reader = file.bufferedReader()
                readers += reader
                readEntry(reader)?.let { queue += Cursor(reader, it, index) }
            }
            while (queue.isNotEmpty()) {
                val cursor = queue.remove()
                block(cursor.entry)
                readEntry(cursor.reader)?.let { cursor.entry = it; queue += cursor }
            }
        } finally {
            readers.forEach { runCatching { it.close() } }
        }
    }

    private fun readEntry(reader: BufferedReader): Entry? {
        val line = reader.readLine() ?: return null
        val separator = line.lastIndexOf('\t')
        check(separator > 0)
        return Entry(line.substring(0, separator), line.substring(separator + 1).toLong())
    }

    override fun close() {
        directory.deleteRecursively()
    }

    companion object {
        private val ENTRY_COMPARATOR = compareBy<Entry>({ it.encodedIdentity }, { it.recordIndex })
    }
}

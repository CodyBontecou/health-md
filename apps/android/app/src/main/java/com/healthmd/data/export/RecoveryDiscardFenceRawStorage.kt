package com.healthmd.data.export

import com.healthmd.rawexport.RawAtomicExportSink
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawExportStorage
import com.healthmd.rawexport.RawPromotionExpectation
import com.healthmd.rawexport.RawPromotionReceipt
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest

/** Scheduled-only staging. Never owns a SAF/external output or an unrelated raw capture. */
internal class RecoveryDiscardFenceRawStorage(
    private val fence: RecoveryDiscardFence,
    private val operationId: String,
    private val directory: File,
    private val index: Int,
) : RawExportStorage {
    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink = fence.withOperation(operationId) {
        require(index in 0..31 && snapshotId.matches(Regex("[0-9a-f]{32}"))) { "raw_api_staging_invalid" }
        check(directory.isDirectory) { "raw_api_staging_unavailable" }
        val partial = File(directory, "capture-$index.partial")
        val final = File(directory, "capture-$index.bin")
        check(!partial.exists() && !final.exists()) { "raw_api_capture_cannot_repeat" }
        check(!Files.isSymbolicLink(partial.toPath()) && !Files.isSymbolicLink(final.toPath())) { "raw_api_staging_invalid" }
        Sink(partial, final)
    }

    private inner class Sink(private val partial: File, private val final: File) : RawAtomicExportSink {
        private val stream = FileOutputStream(partial)
        private var closed = false
        private var count = 0L
        private var promoted = false
        override val partialLocation: String get() = partial.absolutePath
        override val output: OutputStream = object : OutputStream() {
            override fun write(value: Int) = write(byteArrayOf(value.toByte()), 0, 1)
            override fun write(bytes: ByteArray, offset: Int, length: Int) = fence.withOperation(operationId) {
                check(!closed && count + length <= MAX_STAGING_BYTES) { "raw_api_staging_unavailable" }
                stream.write(bytes, offset, length)
                count += length
            }
            override fun flush() { if (!closed) stream.flush() }
            override fun close() = closeOutput()
        }

        override fun promote(expectation: RawPromotionExpectation, checkCancellation: () -> Unit): RawPromotionReceipt =
            fence.withOperation(operationId) {
                check(!promoted) { "raw_api_staging_invalid" }
                if (!closed) { stream.flush(); stream.fd.sync() }
                closeOutput()
                checkCancellation()
                check(partial.isFile && partial.length() == expectation.byteCount && expectation.byteCount == count) {
                    "raw_api_staging_invalid"
                }
                val digest = MessageDigest.getInstance("SHA-256")
                partial.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        checkCancellation()
                        val read = input.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                    }
                }
                check(digest.digest().joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') } == expectation.checksumSha256) {
                    "raw_api_staging_invalid"
                }
                checkCancellation()
                Files.move(partial.toPath(), final.toPath(), StandardCopyOption.ATOMIC_MOVE)
                RecoveryDiscardFence.syncDirectory(directory)
                promoted = true
                checkCancellation()
                RawPromotionReceipt(final.absolutePath, final.name, count, expectation.checksumSha256)
            }

        override fun abort() {
            closeOutput()
            // Unlink only: never reopen an abandoned path after its parent has been discarded.
            runCatching {
                fence.withOperation(operationId) {
                    Files.deleteIfExists(partial.toPath())
                    if (promoted) Files.deleteIfExists(final.toPath())
                }
            }
        }

        override fun close() = closeOutput()
        private fun closeOutput() {
            if (!closed) {
                try { stream.flush(); stream.fd.sync() } finally { stream.close(); closed = true }
            }
        }
    }

    private companion object { const val MAX_STAGING_BYTES = 536_870_912L }
}

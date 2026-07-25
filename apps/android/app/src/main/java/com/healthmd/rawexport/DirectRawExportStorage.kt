package com.healthmd.rawexport

import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

/** Durable no-backup storage owned by one direct CLI job. */
class DirectRawExportStorage(
    private val root: File,
) : RawExportStorage {
    init {
        check(root.mkdirs() || root.isDirectory) { "Unable to create direct raw export storage." }
    }

    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
        require(snapshotId.matches(Regex("[0-9a-f]{32}")))
        val extension = if (format == RawExportFormat.JSON) "json" else "ndjson"
        val partial = File(root, "$snapshotId.$extension.partial")
        val final = File(root, "$snapshotId.$extension")
        check(!final.exists()) { "The immutable direct snapshot already exists." }
        check(!partial.exists() || partial.delete()) { "Unable to remove an abandoned direct partial." }
        return Sink(partial, final)
    }

    private class Sink(
        private val partial: File,
        private val final: File,
    ) : RawAtomicExportSink {
        private var closed = false
        private var promoted = false
        private val fileOutput = FileOutputStream(partial, false)
        override val output: OutputStream = fileOutput
        override val partialLocation: String get() = partial.absolutePath

        override fun promote(
            expectation: RawPromotionExpectation,
            checkCancellation: () -> Unit,
        ): RawPromotionReceipt {
            closeOutput()
            checkCancellation()
            verifyRawPromotionFile(partial, expectation, checkCancellation)
            check(!final.exists()) { "The immutable direct snapshot already exists." }
            check(partial.renameTo(final)) { "Unable to promote the direct snapshot atomically." }
            try {
                verifyRawPromotionFile(final, expectation, checkCancellation)
                checkCancellation()
            } catch (error: Throwable) {
                final.delete()
                throw error
            }
            promoted = true
            return RawPromotionReceipt(
                location = final.absolutePath,
                displayName = final.name,
                byteCount = expectation.byteCount,
                checksumSha256 = expectation.checksumSha256,
            )
        }

        override fun abort() {
            closeOutput()
            partial.delete()
            if (promoted) final.delete()
        }

        override fun close() = closeOutput()

        private fun closeOutput() {
            if (!closed) {
                fileOutput.flush()
                fileOutput.fd.sync()
                fileOutput.close()
                closed = true
            }
        }
    }
}

package com.healthmd.rawexport

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream

interface RawAtomicExportSink : AutoCloseable {
    val output: OutputStream
    val partialLocation: String
    fun promote(): String
    fun abort()
}

interface RawExportStorage {
    fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink
}

/** Internal storage rooted exactly at noBackupFilesDir/raw-export. */
class NoBackupRawExportStorage(context: Context) : RawExportStorage {
    private val root = File(context.noBackupFilesDir, "raw-export").apply { mkdirs() }

    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
        val extension = if (format == RawExportFormat.JSON) "json" else "ndjson"
        val partial = File(root, "$snapshotId.$extension.partial")
        val final = File(root, "$snapshotId.$extension")
        return FileAtomicSink(partial, final)
    }

    private class FileAtomicSink(
        private val partial: File,
        private val final: File,
    ) : RawAtomicExportSink {
        private var closed = false
        private var promoted = false
        override val output: OutputStream = FileOutputStream(partial, false)
        override val partialLocation: String get() = partial.absolutePath

        override fun promote(): String {
            closeOutput()
            check(partial.exists()) { "Partial artifact is missing" }
            if (final.exists() && !final.delete()) error("Unable to replace final artifact")
            check(partial.renameTo(final)) { "Unable to atomically promote raw snapshot" }
            promoted = true
            return final.absolutePath
        }

        override fun abort() {
            closeOutput()
            if (!promoted) partial.delete()
        }

        override fun close() = closeOutput()
        private fun closeOutput() {
            if (!closed) {
                output.flush(); output.close(); closed = true
            }
        }
    }
}

/**
 * SAF tree adapter. The final document is created only after the completed partial has been closed,
 * then copied and the partial deleted. Providers do not offer a cross-provider atomic rename.
 */
class SafRawExportStorage(
    private val context: Context,
    private val treeUri: Uri,
) : RawExportStorage {
    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
        val extension = if (format == RawExportFormat.JSON) "json" else "ndjson"
        val mime = if (format == RawExportFormat.JSON) "application/vnd.healthmd.raw-snapshot+json" else "application/x-ndjson"
        val resolver = context.contentResolver
        val parent = DocumentsContract.buildDocumentUriUsingTree(treeUri, DocumentsContract.getTreeDocumentId(treeUri))
        val partial = requireNotNull(
            DocumentsContract.createDocument(resolver, parent, mime, "$snapshotId.$extension.partial"),
        ) { "Unable to create SAF partial document" }
        return SafSink(resolver, parent, partial, "$snapshotId.$extension", mime)
    }

    private class SafSink(
        private val resolver: ContentResolver,
        private val parent: Uri,
        private val partial: Uri,
        private val finalName: String,
        private val mime: String,
    ) : RawAtomicExportSink {
        private var closed = false
        private var promoted = false
        override val output: OutputStream = requireNotNull(resolver.openOutputStream(partial, "wt"))
        override val partialLocation: String get() = partial.toString()

        override fun promote(): String {
            closeOutput()
            val final = requireNotNull(DocumentsContract.createDocument(resolver, parent, mime, finalName)) {
                "Unable to create final SAF document"
            }
            try {
                requireNotNull(resolver.openInputStream(partial)).use { input ->
                    requireNotNull(resolver.openOutputStream(final, "wt")).use { destination -> input.copyTo(destination) }
                }
            } catch (error: Throwable) {
                DocumentsContract.deleteDocument(resolver, final)
                throw error
            }
            check(DocumentsContract.deleteDocument(resolver, partial)) {
                "Final artifact copied but SAF partial could not be removed"
            }
            promoted = true
            return final.toString()
        }

        override fun abort() {
            closeOutput()
            if (!promoted) runCatching { DocumentsContract.deleteDocument(resolver, partial) }
        }

        override fun close() = closeOutput()
        private fun closeOutput() {
            if (!closed) { output.flush(); output.close(); closed = true }
        }
    }
}

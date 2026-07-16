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

/** Storage capable of publishing a checksum only after the snapshot itself was promoted. */
interface RawIntegrityStorage {
    fun writeIntegrityArtifact(snapshotId: String, format: RawExportFormat, checksumSha256: String): String
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
    relativeDirectory: String = "",
    stableNamePrefix: String? = null,
) : RawExportStorage, RawIntegrityStorage {
    private val resolver = context.contentResolver
    private val directorySegments = relativeDirectory.split('/').map(String::trim).filter(String::isNotEmpty)
    private val namePrefix = stableNamePrefix?.trim()?.takeIf(String::isNotEmpty)

    override fun openPartial(snapshotId: String, format: RawExportFormat): RawAtomicExportSink {
        val mime = if (format == RawExportFormat.JSON) "application/vnd.healthmd.raw-snapshot+json" else "application/x-ndjson"
        val parent = resolveDirectory()
        val finalName = finalName(snapshotId, format)
        check(findChild(parent, finalName) == null) { "Raw snapshot already exists and is immutable." }
        val partialName = "$finalName.partial"
        findChild(parent, partialName)?.let { stale -> DocumentsContract.deleteDocument(resolver, stale) }
        val partial = requireNotNull(
            DocumentsContract.createDocument(resolver, parent, mime, partialName),
        ) { "Unable to create SAF partial document" }
        return SafSink(resolver, parent, partial, finalName, mime)
    }

    override fun writeIntegrityArtifact(
        snapshotId: String,
        format: RawExportFormat,
        checksumSha256: String,
    ): String {
        require(checksumSha256.matches(Regex("[0-9a-f]{64}"))) { "Invalid SHA-256 checksum" }
        val parent = resolveDirectory()
        val artifactName = finalName(snapshotId, format)
        check(findChild(parent, artifactName) != null) { "Cannot publish integrity metadata before snapshot promotion." }
        val sidecarName = "$artifactName.sha256"
        check(findChild(parent, sidecarName) == null) { "Raw snapshot checksum already exists and is immutable." }
        val sidecar = requireNotNull(
            DocumentsContract.createDocument(resolver, parent, "text/plain", sidecarName),
        ) { "Unable to create raw snapshot checksum" }
        try {
            requireNotNull(resolver.openOutputStream(sidecar, "wt")).bufferedWriter(Charsets.UTF_8).use {
                it.write("$checksumSha256  $artifactName\n")
            }
        } catch (error: Throwable) {
            runCatching { DocumentsContract.deleteDocument(resolver, sidecar) }
            throw error
        }
        return sidecar.toString()
    }

    fun finalName(snapshotId: String, format: RawExportFormat): String =
        stableFileName(namePrefix, snapshotId, format)

    private fun resolveDirectory(): Uri {
        var current = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        directorySegments.forEach { segment ->
            require(segment != "." && segment != ".." && !segment.contains('\\')) {
                "Invalid raw snapshot directory"
            }
            current = findChild(current, segment) ?: requireNotNull(
                DocumentsContract.createDocument(
                    resolver,
                    current,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    segment,
                ),
            ) { "Unable to create raw snapshot directory" }
        }
        return current
    }

    private fun findChild(parent: Uri, displayName: String): Uri? {
        val parentId = DocumentsContract.getDocumentId(parent)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentId)
        resolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val idIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameIndex = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameIndex) == displayName) {
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(idIndex))
                }
            }
        }
        return null
    }

    companion object {
        fun stableFileName(prefix: String?, snapshotId: String, format: RawExportFormat): String {
            val extension = if (format == RawExportFormat.JSON) "json" else "ndjson"
            return listOfNotNull(prefix?.trim()?.takeIf(String::isNotEmpty), snapshotId)
                .joinToString("-") + ".$extension"
        }
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
            if (!DocumentsContract.deleteDocument(resolver, partial)) {
                runCatching { DocumentsContract.deleteDocument(resolver, final) }
                error("Raw snapshot promotion failed because the SAF partial could not be removed")
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

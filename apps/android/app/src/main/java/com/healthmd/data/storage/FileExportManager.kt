package com.healthmd.data.storage

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import com.healthmd.data.export.MarkdownMerger
import java.io.ByteArrayOutputStream
import java.io.IOException

class FileExportManager(private val context: Context) {

    /**
     * Persist access to the user-selected folder across app restarts.
     */
    fun takePersistablePermission(uri: Uri) {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        context.contentResolver.takePersistableUriPermission(uri, flags)
    }

    /**
     * Get the display name for a folder URI.
     */
    fun getFolderDisplayName(uriString: String): String? {
        return try {
            val uri = Uri.parse(uriString)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(
                uri, DocumentsContract.getTreeDocumentId(uri)
            )
            context.contentResolver.query(docUri, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Write content to a file within the export folder.
     *
     * @param folderUriString The persisted tree URI of the root export folder
     * @param subfolder Optional subfolder path (e.g., "2026/03")
     * @param fileName File name without extension
     * @param extension File extension (e.g., "md", "json", "csv")
     * @param content The file content to write
     * @param writeMode How to handle existing files
     * @return true if write succeeded
     */
    fun writeFile(
        folderUriString: String,
        subfolder: String?,
        fileName: String,
        extension: String,
        content: String,
        writeMode: WriteMode = WriteMode.OVERWRITE,
    ): Boolean {
        return try {
            val treeUri = Uri.parse(folderUriString)
            val targetFolderUri = if (subfolder != null) {
                ensureSubfolders(treeUri, subfolder)
            } else {
                DocumentsContract.buildDocumentUriUsingTree(
                    treeUri, DocumentsContract.getTreeDocumentId(treeUri)
                )
            }

            val fullFileName = "$fileName.$extension"
            val mimeType = mimeTypeForExtension(extension)

            // Check if file already exists
            val existingFileUri = findExistingFile(treeUri, targetFolderUri, fullFileName)

            when {
                existingFileUri != null && writeMode == WriteMode.OVERWRITE -> {
                    writeContent(existingFileUri, content)
                }
                existingFileUri != null && writeMode == WriteMode.APPEND -> {
                    val existing = readContent(existingFileUri) ?: ""
                    writeContent(existingFileUri, existing + "\n" + content)
                }
                existingFileUri != null && writeMode == WriteMode.UPDATE -> {
                    val existing = readContent(existingFileUri).orEmpty()
                    val merged = if (extension.equals("md", ignoreCase = true)) {
                        MarkdownMerger().merge(existing, content)
                    } else {
                        // UPDATE is Markdown-specific. Structured formats are regenerated atomically.
                        content
                    }
                    writeContent(existingFileUri, merged)
                }
                existingFileUri == null -> {
                    val newFileUri = DocumentsContract.createDocument(
                        context.contentResolver,
                        targetFolderUri,
                        mimeType,
                        fullFileName,
                    ) ?: return false
                    writeContent(newFileUri, content)
                }
                else -> false
            }
        } catch (_: Exception) {
            false
        }
    }

    fun writeFileAtRelativePath(
        folderUriString: String,
        relativePath: String,
        content: String,
        writeMode: WriteMode = WriteMode.OVERWRITE,
    ): Boolean {
        val normalized = normalizePath(relativePath)
        val parent = normalized.substringBeforeLast('/', missingDelimiterValue = "")
        val fileNameWithExtension = normalized.substringAfterLast('/')
        val extension = fileNameWithExtension.substringAfterLast('.', missingDelimiterValue = "txt")
        val fileName = fileNameWithExtension.substringBeforeLast('.', missingDelimiterValue = fileNameWithExtension)
        return writeFile(
            folderUriString = folderUriString,
            subfolder = parent.ifBlank { null },
            fileName = fileName,
            extension = extension,
            content = content,
            writeMode = writeMode,
        )
    }

    fun readFileAtRelativePath(folderUriString: String, relativePath: String): String? {
        return try {
            val treeUri = Uri.parse(folderUriString)
            val normalized = normalizePath(relativePath)
            val parent = normalized.substringBeforeLast('/', missingDelimiterValue = "")
            val fileName = normalized.substringAfterLast('/')
            val folderUri = findFolder(treeUri, parent) ?: return null
            val fileUri = findExistingFile(treeUri, folderUri, fileName) ?: return null
            readContent(fileUri)
        } catch (_: Exception) {
            null
        }
    }

    fun fileExistsAtRelativePath(folderUriString: String, relativePath: String): Boolean {
        return try {
            val treeUri = Uri.parse(folderUriString)
            val normalized = normalizePath(relativePath)
            val parent = normalized.substringBeforeLast('/', missingDelimiterValue = "")
            val fileName = normalized.substringAfterLast('/')
            val folderUri = findFolder(treeUri, parent) ?: return false
            findExistingFile(treeUri, folderUri, fileName) != null
        } catch (_: Exception) {
            false
        }
    }

    /** Strict SAF lookup used only by durable overwrite journals. */
    fun inspectDurableFile(
        folderUriString: String,
        relativePath: String,
    ): DurableFileInspection = try {
        val normalized = normalizeDurablePath(relativePath)
            ?: return DurableFileInspection.Unavailable
        val treeUri = Uri.parse(folderUriString)
        val parentPath = normalized.substringBeforeLast('/', missingDelimiterValue = "")
        val fileName = normalized.substringAfterLast('/')
        when (val parent = findStrictFolder(treeUri, parentPath)) {
            StrictFolderLookup.Missing -> DurableFileInspection.Missing
            StrictFolderLookup.Ambiguous -> DurableFileInspection.Ambiguous
            StrictFolderLookup.Unavailable -> DurableFileInspection.Unavailable
            is StrictFolderLookup.Found -> when (
                val child = findStrictFile(treeUri, parent.uri, fileName)
            ) {
                StrictFileLookup.Missing -> DurableFileInspection.Missing
                StrictFileLookup.Ambiguous -> DurableFileInspection.Ambiguous
                StrictFileLookup.Unavailable -> DurableFileInspection.Unavailable
                is StrictFileLookup.Found -> {
                    val bytes = readContentBytes(child.uri)
                        ?: return DurableFileInspection.Unavailable
                    DurableFileInspection.Found(child.documentId, bytes)
                }
            }
        }
    } catch (_: Exception) {
        DurableFileInspection.Unavailable
    }

    /**
     * Resolves one unique target document, creating missing folders/file but writing no content.
     * The returned document ID is persisted before the first byte write.
     */
    fun bindDurableFile(
        folderUriString: String,
        relativePath: String,
        mediaType: String,
        expectedDocumentId: String? = null,
        requireMissing: Boolean = false,
    ): DurableBoundFile? {
        return try {
            val normalized = normalizeDurablePath(relativePath) ?: return null
            val treeUri = Uri.parse(folderUriString)
            val parentPath = normalized.substringBeforeLast('/', missingDelimiterValue = "")
            val fileName = normalized.substringAfterLast('/')
            val parent = ensureStrictFolders(treeUri, parentPath) ?: return null
            if (expectedDocumentId != null && requireMissing) return null
            when (val existing = findStrictFile(treeUri, parent, fileName)) {
                StrictFileLookup.Ambiguous,
                StrictFileLookup.Unavailable -> null
                is StrictFileLookup.Found -> when {
                    requireMissing -> null
                    expectedDocumentId != null && existing.documentId != expectedDocumentId -> null
                    else -> DurableBoundFile(existing.documentId)
                }
                StrictFileLookup.Missing -> {
                    if (expectedDocumentId != null) return null
                    val created = DocumentsContract.createDocument(
                        context.contentResolver,
                        parent,
                        mediaType,
                        fileName,
                    ) ?: return null
                    val createdId = DocumentsContract.getDocumentId(created)
                    when (val resolved = findStrictFile(treeUri, parent, fileName)) {
                        is StrictFileLookup.Found -> if (resolved.documentId == createdId) {
                            DurableBoundFile(createdId)
                        } else null
                        else -> null
                    }
                }
            }
        } catch (_: Exception) {
            null
        }
    }

    /** Revalidates path-to-document identity and overwrites the bound document with exact bytes. */
    fun overwriteDurableBoundFile(
        folderUriString: String,
        relativePath: String,
        expectedDocumentId: String,
        content: ByteArray,
    ): Boolean {
        return try {
            if (content.size > MAX_DURABLE_FILE_BYTES) return false
            val normalized = normalizeDurablePath(relativePath) ?: return false
            val treeUri = Uri.parse(folderUriString)
            val parentPath = normalized.substringBeforeLast('/', missingDelimiterValue = "")
            val fileName = normalized.substringAfterLast('/')
            val parent = when (val lookup = findStrictFolder(treeUri, parentPath)) {
                is StrictFolderLookup.Found -> lookup.uri
                else -> return false
            }
            val target = when (val lookup = findStrictFile(treeUri, parent, fileName)) {
                is StrictFileLookup.Found -> lookup
                else -> return false
            }
            if (target.documentId != expectedDocumentId) return false
            val stream = context.contentResolver.openOutputStream(target.uri, "wt") ?: return false
            stream.use {
                it.write(content)
                it.flush()
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    /** Renames one exact staging document to an absent final name in the same strict folder. */
    fun renameDurableBoundFile(
        folderUriString: String,
        stagingRelativePath: String,
        finalRelativePath: String,
        expectedDocumentId: String,
    ): DurableBoundFile? {
        return try {
            val staging = normalizeDurablePath(stagingRelativePath) ?: return null
            val final = normalizeDurablePath(finalRelativePath) ?: return null
            val stagingParent = staging.substringBeforeLast('/', missingDelimiterValue = "")
            val finalParent = final.substringBeforeLast('/', missingDelimiterValue = "")
            if (stagingParent != finalParent) return null
            val treeUri = Uri.parse(folderUriString)
            val parent = when (val lookup = findStrictFolder(treeUri, stagingParent)) {
                is StrictFolderLookup.Found -> lookup.uri
                else -> return null
            }
            val stagingFile = when (val lookup = findStrictFile(
                treeUri,
                parent,
                staging.substringAfterLast('/'),
            )) {
                is StrictFileLookup.Found -> lookup
                else -> return null
            }
            if (stagingFile.documentId != expectedDocumentId) return null
            if (findStrictFile(treeUri, parent, final.substringAfterLast('/')) !=
                StrictFileLookup.Missing
            ) return null
            val renamed = DocumentsContract.renameDocument(
                context.contentResolver,
                stagingFile.uri,
                final.substringAfterLast('/'),
            ) ?: return null
            val renamedId = DocumentsContract.getDocumentId(renamed)
            val resolvedFinal = when (val lookup = findStrictFile(
                treeUri,
                parent,
                final.substringAfterLast('/'),
            )) {
                is StrictFileLookup.Found -> lookup
                else -> return null
            }
            if (resolvedFinal.documentId != renamedId) return null
            if (findStrictFile(treeUri, parent, staging.substringAfterLast('/')) !=
                StrictFileLookup.Missing
            ) return null
            DurableBoundFile(renamedId)
        } catch (_: Exception) {
            null
        }
    }

    private fun mimeTypeForExtension(extension: String): String = when (extension.lowercase()) {
        "md" -> "text/markdown"
        "json" -> "application/json"
        "csv" -> "text/csv"
        else -> "text/plain"
    }

    private fun normalizePath(path: String): String =
        path.split('/').filter { it.isNotBlank() }.joinToString("/")

    private fun normalizeDurablePath(path: String): String? {
        if (path.isBlank() || path.length > 1_024 || '\\' in path || path.startsWith('/')) return null
        val segments = path.split('/')
        if (segments.any { it.isBlank() || it == "." || it == ".." }) return null
        val normalized = segments.joinToString("/")
        return normalized.takeIf { it == path }
    }

    private fun ensureSubfolders(treeUri: Uri, path: String): Uri {
        var currentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri, DocumentsContract.getTreeDocumentId(treeUri)
        )

        for (segment in path.split("/").filter { it.isNotEmpty() }) {
            val existingChild = findChildFolder(treeUri, currentUri, segment)
            currentUri = existingChild ?: DocumentsContract.createDocument(
                context.contentResolver,
                currentUri,
                DocumentsContract.Document.MIME_TYPE_DIR,
                segment,
            ) ?: throw IOException("Failed to create subfolder: $segment")
        }

        return currentUri
    }

    private fun findFolder(treeUri: Uri, path: String): Uri? {
        var currentUri = DocumentsContract.buildDocumentUriUsingTree(
            treeUri, DocumentsContract.getTreeDocumentId(treeUri)
        )
        if (path.isBlank()) return currentUri

        for (segment in path.split("/").filter { it.isNotEmpty() }) {
            currentUri = findChildFolder(treeUri, currentUri, segment) ?: return null
        }
        return currentUri
    }

    private fun findChildFolder(treeUri: Uri, parentUri: Uri, name: String): Uri? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, DocumentsContract.getDocumentId(parentUri)
        )
        context.contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE),
            null, null, null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val displayName = cursor.getString(1)
                val mimeType = cursor.getString(2)
                if (displayName == name && mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                    val docId = cursor.getString(0)
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                }
            }
        }
        return null
    }

    private fun ensureStrictFolders(treeUri: Uri, path: String): Uri? {
        var current = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        for (segment in path.split('/').filter { it.isNotEmpty() }) {
            current = when (val child = findStrictChildFolder(treeUri, current, segment)) {
                is StrictFolderLookup.Found -> child.uri
                StrictFolderLookup.Missing -> {
                    val created = DocumentsContract.createDocument(
                        context.contentResolver,
                        current,
                        DocumentsContract.Document.MIME_TYPE_DIR,
                        segment,
                    ) ?: return null
                    val createdId = DocumentsContract.getDocumentId(created)
                    when (val resolved = findStrictChildFolder(treeUri, current, segment)) {
                        is StrictFolderLookup.Found -> if (
                            DocumentsContract.getDocumentId(resolved.uri) == createdId
                        ) {
                            resolved.uri
                        } else {
                            return null
                        }
                        else -> return null
                    }
                }
                else -> return null
            }
        }
        return current
    }

    private fun findStrictFolder(treeUri: Uri, path: String): StrictFolderLookup {
        var current = DocumentsContract.buildDocumentUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
        if (path.isBlank()) return StrictFolderLookup.Found(current)
        for (segment in path.split('/')) {
            current = when (val child = findStrictChildFolder(treeUri, current, segment)) {
                is StrictFolderLookup.Found -> child.uri
                StrictFolderLookup.Missing -> return StrictFolderLookup.Missing
                StrictFolderLookup.Ambiguous -> return StrictFolderLookup.Ambiguous
                StrictFolderLookup.Unavailable -> return StrictFolderLookup.Unavailable
            }
        }
        return StrictFolderLookup.Found(current)
    }

    private fun findStrictChildFolder(
        treeUri: Uri,
        parentUri: Uri,
        name: String,
    ): StrictFolderLookup {
        return try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(parentUri),
            )
            val matches = mutableListOf<Uri>()
            context.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getString(1) == name &&
                        cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR
                    ) {
                        matches += DocumentsContract.buildDocumentUriUsingTree(treeUri, cursor.getString(0))
                    }
                }
            } ?: return StrictFolderLookup.Unavailable
            when (matches.size) {
                0 -> StrictFolderLookup.Missing
                1 -> StrictFolderLookup.Found(matches.single())
                else -> StrictFolderLookup.Ambiguous
            }
        } catch (_: Exception) {
            StrictFolderLookup.Unavailable
        }
    }

    private fun findStrictFile(
        treeUri: Uri,
        folderUri: Uri,
        fileName: String,
    ): StrictFileLookup {
        return try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                DocumentsContract.getDocumentId(folderUri),
            )
            val matches = mutableListOf<StrictFileLookup.Found>()
            context.contentResolver.query(
                childrenUri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0)
                    val name = cursor.getString(1)
                    val mimeType = cursor.getString(2)
                    if (name == fileName && mimeType != DocumentsContract.Document.MIME_TYPE_DIR) {
                        matches += StrictFileLookup.Found(
                            documentId = id,
                            uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
                        )
                    }
                }
            } ?: return StrictFileLookup.Unavailable
            when (matches.size) {
                0 -> StrictFileLookup.Missing
                1 -> matches.single()
                else -> StrictFileLookup.Ambiguous
            }
        } catch (_: Exception) {
            StrictFileLookup.Unavailable
        }
    }

    private fun findExistingFile(treeUri: Uri, folderUri: Uri, fileName: String): Uri? {
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri, DocumentsContract.getDocumentId(folderUri)
        )
        context.contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val displayName = cursor.getString(1)
                if (displayName == fileName) {
                    val docId = cursor.getString(0)
                    return DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
                }
            }
        }
        return null
    }

    private fun writeContent(uri: Uri, content: String): Boolean {
        val stream = context.contentResolver.openOutputStream(uri, "wt") ?: return false
        stream.use {
            it.write(content.toByteArray(Charsets.UTF_8))
            it.flush()
        }
        return true
    }

    private fun readContent(uri: Uri): String? {
        return try {
            context.contentResolver.openInputStream(uri)?.use { stream ->
                stream.bufferedReader().readText()
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun readContentBytes(uri: Uri): ByteArray? = try {
        context.contentResolver.openInputStream(uri)?.use { stream ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            var total = 0
            while (true) {
                val count = stream.read(buffer)
                if (count < 0) break
                total += count
                if (total > MAX_DURABLE_FILE_BYTES) return null
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        }
    } catch (_: Exception) {
        null
    }

    data class DurableBoundFile(val documentId: String)

    sealed interface DurableFileInspection {
        data object Missing : DurableFileInspection
        data object Ambiguous : DurableFileInspection
        data object Unavailable : DurableFileInspection
        data class Found(val documentId: String, val content: ByteArray) : DurableFileInspection
    }

    private sealed interface StrictFolderLookup {
        data object Missing : StrictFolderLookup
        data object Ambiguous : StrictFolderLookup
        data object Unavailable : StrictFolderLookup
        data class Found(val uri: Uri) : StrictFolderLookup
    }

    private sealed interface StrictFileLookup {
        data object Missing : StrictFileLookup
        data object Ambiguous : StrictFileLookup
        data object Unavailable : StrictFileLookup
        data class Found(val documentId: String, val uri: Uri) : StrictFileLookup
    }

    enum class WriteMode { OVERWRITE, APPEND, UPDATE }

    companion object {
        private const val MAX_DURABLE_FILE_BYTES = 8_388_608
    }
}

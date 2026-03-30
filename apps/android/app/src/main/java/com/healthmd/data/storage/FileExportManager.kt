package com.healthmd.data.storage

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
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
            val mimeType = when (extension) {
                "md" -> "text/markdown"
                "json" -> "application/json"
                "csv" -> "text/csv"
                else -> "text/plain"
            }

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
                    // For update mode, we replace the file content
                    // A full MarkdownMerger implementation would be used here
                    writeContent(existingFileUri, content)
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

            true
        } catch (_: Exception) {
            false
        }
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

    private fun writeContent(uri: Uri, content: String) {
        context.contentResolver.openOutputStream(uri, "wt")?.use { stream ->
            stream.write(content.toByteArray(Charsets.UTF_8))
        }
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

    enum class WriteMode { OVERWRITE, APPEND, UPDATE }
}

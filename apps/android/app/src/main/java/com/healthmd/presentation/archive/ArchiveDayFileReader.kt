package com.healthmd.presentation.archive

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import com.healthmd.data.storage.FileExportManager
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.ByteArrayOutputStream
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Reads the file an export wrote for one date through the Storage Access Framework. A missing
 * folder, a revoked grant or an unreadable file reads as null: the Archive then shows no tiles.
 */
class ArchiveDayFileReader @Inject constructor(
    @ApplicationContext private val context: Context,
    private val fileExportManager: FileExportManager,
) {
    suspend fun read(ref: ArchiveFileRef): ArchiveDayFile? = withContext(Dispatchers.IO) {
        try {
            val uri = fileExportManager.findDocumentAtRelativePath(ref.folderUri, ref.relativePath)
                ?: return@withContext null
            val resolver = context.contentResolver
            var size = -1L
            var mimeType: String? = null
            resolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE),
                null,
                null,
                null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    if (!cursor.isNull(0)) size = cursor.getLong(0)
                    mimeType = cursor.getString(1)
                }
            }
            val bytes = resolver.openInputStream(uri)?.use { stream ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                val readLimit = ArchiveDayFile.MAXIMUM_BYTES + 1
                while (output.size() < readLimit) {
                    val count = stream.read(buffer, 0, minOf(buffer.size, readLimit - output.size()))
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
                output.toByteArray()
            } ?: return@withContext null
            val previewBytes = bytes.copyOf(minOf(bytes.size, ArchiveDayFile.MAXIMUM_BYTES))
            val source = ArchiveDayFile.decodePreview(
                previewBytes, truncated = size > previewBytes.size || bytes.size > previewBytes.size,
            ) ?: return@withContext null
            ArchiveDayFile(
                documentUri = uri.toString(),
                name = ref.relativePath.substringAfterLast('/'),
                mimeType = mimeType,
                source = source,
                byteCount = maxOf(size, bytes.size.toLong()),
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
    }

    /** Whether this app still holds a persisted grant on the folder tree. */
    fun hasFolderAccess(folderUri: String): Boolean = try {
        val uri = Uri.parse(folderUri)
        context.contentResolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
    } catch (_: Exception) {
        false
    }

    fun folderDisplayName(folderUri: String): String? =
        runCatching { fileExportManager.getFolderDisplayName(folderUri) }.getOrNull()
}

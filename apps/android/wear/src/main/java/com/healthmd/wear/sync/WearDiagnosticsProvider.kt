package com.healthmd.wear.sync

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri

/**
 * Bounded release-safe diagnostics for physical QA.
 *
 * The provider is protected by the platform signature-level DUMP permission in the manifest, so
 * ordinary apps cannot query it. It exposes only cache presence, byte count, and SHA-256—not
 * health values or encoded payload bytes.
 */
class WearDiagnosticsProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        require(uri.path == "/state") { "Unsupported diagnostics path" }
        val context = requireNotNull(context)
        val state = WearSnapshotRepository.diagnosticState(context)
        val columns = arrayOf(
            "uid",
            "cache_file_present",
            "cache_size",
            "cache_sha256",
            "mismatch_marker_present",
            "clear_tombstone_present",
            "ordering_corrupt",
        )
        return MatrixCursor(columns, 1).apply {
            addRow(arrayOf(
                android.os.Process.myUid().toString(),
                state.cacheFilePresent.toString(),
                state.cacheSize?.toString().orEmpty(),
                state.cacheSha256.orEmpty(),
                state.mismatchMarkerPresent.toString(),
                state.clearTombstonePresent.toString(),
                state.orderingCorrupt.toString(),
            ))
        }
    }

    override fun getType(uri: Uri): String = "vnd.android.cursor.item/vnd.healthmd.wear-state"
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int =
        throw UnsupportedOperationException()
}

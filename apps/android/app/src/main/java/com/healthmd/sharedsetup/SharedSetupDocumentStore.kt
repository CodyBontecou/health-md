package com.healthmd.sharedsetup

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Distinct provider class so Android can publish this authority beside clinician reports. */
class SharedSetupFileProvider : FileProvider()

internal const val SHARED_SETUP_SHARE_RETENTION_MILLIS = 60_000L
internal const val SHARED_SETUP_MAX_RETAINED_SHARE_ARTIFACTS = 4

internal fun isSharedSetupProviderMetadata(uri: Uri, mimeType: String?, displayName: String?): Boolean =
    uri.scheme == "content" &&
        mimeType in setOf(SHARED_SETUP_MIME_TYPE, "application/json", "application/octet-stream") &&
        displayName?.lowercase()?.endsWith(".$SHARED_SETUP_EXTENSION") == true

/**
 * Owns and closes one provider stream while reading at most the outer limit plus one byte.
 * The final single-byte read at exactly 4 MiB is the overflow probe; no provider-controlled
 * stream is ever consumed with an unbounded read helper.
 */
internal fun readBoundedSharedSetupDocument(openInputStream: () -> InputStream?): ByteArray {
    val input = openInputStream() ?: error("The shared setup document could not be opened.")
    return input.use { stream ->
        val output = ByteArrayOutputStream(minOf(8_192, SHARED_SETUP_V2_MAX_BYTES))
        val buffer = ByteArray(8_192)
        var total = 0
        while (total <= SHARED_SETUP_V2_MAX_BYTES) {
            val remainingWithProbe = SHARED_SETUP_V2_MAX_BYTES + 1 - total
            val count = stream.read(buffer, 0, minOf(buffer.size, remainingWithProbe))
            if (count < 0) return@use output.toByteArray()
            if (count == 0) {
                // InputStream permits a zero-length progress result. Force one bounded byte of
                // progress so a hostile provider cannot spin this loop forever.
                val byte = stream.read()
                if (byte < 0) return@use output.toByteArray()
                output.write(byte)
                total += 1
            } else {
                output.write(buffer, 0, count)
                total += count
            }
        }
        error("Shared setup exceeds 4 MiB.")
    }
}

data class SharedSetupShare(val intent: Intent, val artifactID: String)

@Singleton
class SharedSetupDocumentStore private constructor(
    private val context: Context,
    versionedCodecFactory: () -> SharedSetupV2Codec,
) {
    @Inject
    constructor(@ApplicationContext context: Context) : this(context, { SharedSetupV2Codec() })

    internal constructor(context: Context, versionedCodec: SharedSetupV2Codec) :
        this(context, { versionedCodec })

    private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val versionedCodec by lazy(LazyThreadSafetyMode.SYNCHRONIZED, versionedCodecFactory)

    fun isSharedSetupDocument(uri: Uri): Boolean {
        val mimeType = runCatching { context.contentResolver.getType(uri) }.getOrNull()
        val displayName = runCatching {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor ->
                if (!cursor.moveToFirst()) return@use null
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            }
        }.getOrNull()
        return isSharedSetupProviderMetadata(uri, mimeType, displayName)
    }

    fun read(uri: Uri): ByteArray = readBoundedSharedSetupDocument {
        context.contentResolver.openInputStream(uri)
    }

    fun copyTo(bytes: ByteArray, destination: Uri) {
        val validated = validatedVersionedBytes(bytes)
        context.contentResolver.openOutputStream(destination, "w")?.use { it.write(validated) }
            ?: error("The selected document could not be opened.")
    }

    @Synchronized
    fun shareIntent(
        bytes: ByteArray,
        artifactID: String = UUID.randomUUID().toString(),
    ): SharedSetupShare {
        val validated = validatedVersionedBytes(bytes)
        require(runCatching { UUID.fromString(artifactID) }.isSuccess)
        pruneExpiredShareArtifacts()
        val root = File(context.cacheDir, "shared-setup")
        check((root.listFiles()?.size ?: 0) < SHARED_SETUP_MAX_RETAINED_SHARE_ARTIFACTS) {
            "Please wait for an earlier setup share to finish before sharing again."
        }
        val directory = File(root, artifactID)
        check(!directory.exists()) { "The setup share artifact ID is already in use." }
        return try {
            check(directory.mkdirs()) { "The setup share artifact could not be created." }
            directory.setLastModified(System.currentTimeMillis())
            val file = File(directory, "HealthMd-Shared-Setup.$SHARED_SETUP_EXTENSION").apply {
                writeBytes(validated)
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.shared-setup", file)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = SHARED_SETUP_MIME_TYPE
                putExtra(Intent.EXTRA_STREAM, uri)
                clipData = ClipData.newUri(context.contentResolver, file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            SharedSetupShare(intent, artifactID)
        } catch (error: Throwable) {
            runCatching { directory.deleteRecursively() }
            if (root.listFiles()?.isEmpty() == true) runCatching { root.delete() }
            throw error
        }
    }

    suspend fun scheduleShareArtifactCleanup(artifactID: String): Boolean {
        val handoffMillis = System.currentTimeMillis()
        val marked = withContext(Dispatchers.IO) { markShareHandoff(artifactID, handoffMillis) }
        if (!marked) return false
        cleanupScope.launch {
            while (true) {
                val remaining = synchronized(this@SharedSetupDocumentStore) {
                    val directory = shareArtifactDirectory(artifactID)
                    if (directory?.exists() != true) return@launch
                    SHARED_SETUP_SHARE_RETENTION_MILLIS -
                        (System.currentTimeMillis() - directory.lastModified())
                }
                if (remaining <= 0) {
                    deleteShareArtifact(artifactID)
                    return@launch
                }
                delay(remaining)
            }
        }
        return true
    }

    @Synchronized
    internal fun markShareHandoff(artifactID: String, handoffMillis: Long): Boolean {
        val directory = shareArtifactDirectory(artifactID) ?: return false
        return directory.exists() && directory.setLastModified(handoffMillis)
    }

    suspend fun discardShareArtifact(artifactID: String) {
        withContext(Dispatchers.IO) { deleteShareArtifact(artifactID) }
    }

    private fun validatedVersionedBytes(bytes: ByteArray): ByteArray {
        require(bytes.size <= SHARED_SETUP_V2_MAX_BYTES) { "Shared setup exceeds 4 MiB." }
        // Freeze the mutable caller buffer so the bytes written or shared are exactly the bytes
        // that passed complete strict v1/v2 dispatch and validation.
        val stable = bytes.copyOf()
        when (val decoded = versionedCodec.decode(stable)) {
            is SharedSetupVersionedDecodeResult.Valid -> Unit
            is SharedSetupVersionedDecodeResult.Invalid -> throw IllegalArgumentException(decoded.message)
        }
        return stable
    }

    @Synchronized
    fun clearShareArtifacts() {
        val directory = File(context.cacheDir, "shared-setup")
        runCatching { directory.deleteRecursively() }
    }

    @Synchronized
    internal fun pruneExpiredShareArtifacts(nowMillis: Long = System.currentTimeMillis()) {
        val root = File(context.cacheDir, "shared-setup")
        root.listFiles()?.forEach { artifactDirectory ->
            if (nowMillis - artifactDirectory.lastModified() >= SHARED_SETUP_SHARE_RETENTION_MILLIS) {
                runCatching { artifactDirectory.deleteRecursively() }
            }
        }
        if (root.listFiles()?.isEmpty() == true) runCatching { root.delete() }
    }

    @Synchronized
    private fun deleteShareArtifact(artifactID: String) {
        shareArtifactDirectory(artifactID)?.let { runCatching { it.deleteRecursively() } }
        val root = File(context.cacheDir, "shared-setup")
        if (root.listFiles()?.isEmpty() == true) runCatching { root.delete() }
    }

    private fun shareArtifactDirectory(artifactID: String): File? {
        if (runCatching { UUID.fromString(artifactID) }.isFailure) return null
        return File(File(context.cacheDir, "shared-setup"), artifactID)
    }
}

data class PendingSharedSetupImport(
    val id: Long,
    val bytes: ByteArray? = null,
    val errorMessage: String? = null,
) {
    init {
        require((bytes == null) != (errorMessage == null))
        require(bytes == null || bytes.size <= SHARED_SETUP_V2_MAX_BYTES) {
            "Shared setup exceeds 4 MiB."
        }
    }
}

enum class SharedSetupIntentRestoreAction { ACCEPT_SYSTEM_URI, RESTORE_BYTES, SKIP }

/** Cold/warm intent helper; callers copy content immediately. */
object SharedSetupIntentExtractor {
    fun uri(intent: Intent?): Uri? = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.data

    /**
     * Determines whether a retained system intent is new, already backed by saved bytes, still
     * owned by process-level IO, or explicitly finished. The original intent remains intact so a
     * new process can retry an interrupted transient provider read.
     */
    fun restorationAction(
        wasHandled: Boolean,
        wasFinished: Boolean,
        hasRestorableBytes: Boolean,
        sameProcess: Boolean,
    ): SharedSetupIntentRestoreAction = when {
        !wasHandled -> SharedSetupIntentRestoreAction.ACCEPT_SYSTEM_URI
        wasFinished -> SharedSetupIntentRestoreAction.SKIP
        hasRestorableBytes -> SharedSetupIntentRestoreAction.RESTORE_BYTES
        sameProcess -> SharedSetupIntentRestoreAction.SKIP
        else -> SharedSetupIntentRestoreAction.ACCEPT_SYSTEM_URI
    }
}

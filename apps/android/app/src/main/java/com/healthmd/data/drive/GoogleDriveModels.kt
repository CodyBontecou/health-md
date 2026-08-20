package com.healthmd.data.drive

import com.healthmd.BuildConfig
import com.healthmd.domain.exportengine.sha256Hex
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.nio.charset.StandardCharsets
import java.time.LocalDate

const val GOOGLE_DRIVE_SCOPE: String = "https://www.googleapis.com/auth/drive.file"
const val GOOGLE_DRIVE_FOLDER_MIME_TYPE: String = "application/vnd.google-apps.folder"

object GoogleDriveConfiguration {
    fun isConfigured(clientId: String = BuildConfig.GOOGLE_DRIVE_ANDROID_CLIENT_ID): Boolean =
        clientId.isNotBlank()
}

/** Stable privacy-safe identifiers shared with the Apple implementation contract. */
@Serializable
enum class GoogleDriveErrorId {
    @SerialName("configuration_missing") CONFIGURATION_MISSING,
    @SerialName("reauthorization_required") REAUTHORIZATION_REQUIRED,
    @SerialName("account_mismatch") ACCOUNT_MISMATCH,
    @SerialName("folder_unavailable") FOLDER_UNAVAILABLE,
    @SerialName("permission_denied") PERMISSION_DENIED,
    @SerialName("remote_conflict") REMOTE_CONFLICT,
    @SerialName("ambiguous_commit") AMBIGUOUS_COMMIT,
    @SerialName("quota_exceeded") QUOTA_EXCEEDED,
    @SerialName("rate_limited") RATE_LIMITED,
    @SerialName("checksum_mismatch") CHECKSUM_MISMATCH,
    @SerialName("partial_completion") PARTIAL_COMPLETION,
}

@Serializable
data class GoogleDriveFolderCapabilities(
    val canAddChildren: Boolean = false,
    val canEdit: Boolean = false,
)

/** Non-secret binding. The Android Account name is referenced from encrypted storage. */
@Serializable
data class GoogleDriveDestination(
    val version: Int = CURRENT_VERSION,
    val kind: String = KIND,
    val id: String,
    val accountReferenceId: String,
    val permissionId: String,
    val folderId: String,
    val sharedDriveId: String? = null,
    val resourceKey: String? = null,
    val accountLabel: String,
    val folderLabel: String,
    val capabilities: GoogleDriveFolderCapabilities,
    val lastValidatedAtEpochMillis: Long,
) {
    init {
        require(version in 1..CURRENT_VERSION)
        require(kind == KIND)
        require(id.isSafeOpaqueId() && accountReferenceId.isSafeOpaqueId())
        require(permissionId.isNotBlank() && folderId.isNotBlank())
        require(accountLabel.length <= 128 && folderLabel.length <= 256)
    }

    val fingerprint: String
        get() = sha256Hex(
            listOf(id, permissionId, folderId, sharedDriveId.orEmpty(), resourceKey.orEmpty())
                .joinToString("\u0000")
                .toByteArray(StandardCharsets.UTF_8),
        )

    companion object {
        const val CURRENT_VERSION = 1
        const val KIND = "google_drive"
    }
}

@Serializable
data class GoogleDriveRemoteMetadata(
    val id: String,
    val name: String,
    val mimeType: String,
    val parents: List<String> = emptyList(),
    val driveId: String? = null,
    val resourceKey: String? = null,
    val permissionId: String? = null,
    val version: String? = null,
    val size: Long? = null,
    val md5Checksum: String? = null,
    val sha256Checksum: String? = null,
    val trashed: Boolean = false,
    val capabilities: GoogleDriveFolderCapabilities = GoogleDriveFolderCapabilities(),
)

@Serializable
data class GoogleDriveManagedObject(
    val version: Int = 1,
    val destinationId: String,
    val relativePathHash: String,
    val objectId: String,
    val parentId: String,
    val expectedName: String,
    val mimeType: String,
    val resourceKey: String? = null,
    val remoteVersion: String? = null,
    val byteCount: Long? = null,
    val md5Checksum: String? = null,
    val sha256Checksum: String? = null,
)

@Serializable
enum class GeneratedArtifactWriteIntent {
    OVERWRITE,
    APPEND,
    MARKDOWN_UPDATE,
    DAILY_NOTE_MERGE,
}

/** Immutable destination-neutral bytes. Public renderer bytes are copied without normalization. */
class GeneratedExportArtifact(
    val artifactId: String,
    val relativePath: String,
    val mediaType: String,
    val writeIntent: GeneratedArtifactWriteIntent,
    bytes: ByteArray,
    missingRemotePrefix: ByteArray? = null,
    val createIfMissing: Boolean = true,
) {
    private val immutableBytes = bytes.copyOf()
    private val immutableMissingPrefix = missingRemotePrefix?.copyOf()
    val bytes: ByteArray get() = immutableBytes.copyOf()
    val missingPrefix: ByteArray? get() = immutableMissingPrefix?.copyOf()
    val byteCount: Long = immutableBytes.size.toLong()
    val sha256: String = sha256Hex(immutableBytes)

    init {
        require(artifactId.isSafeOpaqueId())
        require(normalizeDriveRelativePath(relativePath) == relativePath)
        require(mediaType.length in 3..128 && '/' in mediaType)
    }
}

class GeneratedExportBundle(
    val operationId: String,
    val profileId: String?,
    val source: String,
    val dates: List<LocalDate>,
    val settingsSnapshotSha256: String,
    val rendererPin: String,
    artifacts: List<GeneratedExportArtifact>,
) {
    val artifacts: List<GeneratedExportArtifact> = artifacts.sortedBy { it.relativePath }
    val digest: String

    init {
        require(operationId.isSafeOpaqueId())
        require(source in setOf("manual", "scheduled", "retry", "raw"))
        require(dates == dates.distinct().sorted())
        require(settingsSnapshotSha256.matches(Regex("[0-9a-f]{64}")))
        require(this.artifacts.isNotEmpty())
        require(this.artifacts.map { collisionKey(it.relativePath) }.distinct().size == this.artifacts.size)
        digest = sha256Hex(buildString {
            append("healthmd.drive.bundle.v1\u0000")
            append(operationId).append('\u0000').append(settingsSnapshotSha256).append('\u0000')
            this@GeneratedExportBundle.artifacts.forEach {
                append(it.artifactId).append('\u0000').append(it.relativePath).append('\u0000')
                append(it.mediaType).append('\u0000').append(it.writeIntent.name).append('\u0000')
                append(it.byteCount).append('\u0000').append(it.sha256).append('\u0000')
            }
        }.encodeToByteArray())
    }
}

sealed interface GoogleDriveReadiness {
    data object Ready : GoogleDriveReadiness
    data class Unavailable(val error: GoogleDriveErrorId) : GoogleDriveReadiness
}

sealed interface GoogleDriveRunResult {
    data class Complete(val artifactCount: Int) : GoogleDriveRunResult
    data class Stopped(
        /** The actionable cause remains available even when earlier artifacts completed. */
        val error: GoogleDriveErrorId,
        val completedArtifactCount: Int = 0,
        val retryable: Boolean = false,
        val partialCompletion: Boolean = false,
    ) : GoogleDriveRunResult
}

internal fun normalizeDriveRelativePath(path: String): String? {
    if (path.isBlank() || path.length > 4096 || path.startsWith('/') || '\\' in path || '\u0000' in path) return null
    val parts = path.split('/')
    if (parts.any { it.isBlank() || it == "." || it == ".." || it.any(Char::isISOControl) }) return null
    return parts.joinToString("/")
}

internal fun relativePathHash(destinationId: String, path: String): String =
    sha256Hex("healthmd.drive.path.v1\u0000$destinationId\u0000$path".encodeToByteArray())

private fun collisionKey(path: String): String = path.lowercase()

internal fun String.isSafeOpaqueId(): Boolean = matches(Regex("[A-Za-z0-9._-]{1,128}"))

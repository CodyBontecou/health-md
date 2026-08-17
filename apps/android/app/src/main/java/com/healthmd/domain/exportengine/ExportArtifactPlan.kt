package com.healthmd.domain.exportengine

import com.healthmd.core.CoreArtifactPlan
import com.healthmd.core.CoreArtifactWriteMode
import com.healthmd.core.CoreMetricRegistryProfile
import java.security.MessageDigest
import java.text.Normalizer
import java.util.Collections
import java.util.Locale

/** Exact destination-neutral write operation; no destination handle or credential is represented. */
enum class ExportArtifactWriteMode {
    overwrite,
    append,
    markdown_merge,
    api_post,
}

enum class ExportArtifactPlanValidationIssue {
    SCHEMA,
    VERSION,
    REQUEST_ID,
    SESSION_ID,
    PROFILE,
    ARTIFACT_COUNT,
    ARTIFACT_ID,
    DUPLICATE_ARTIFACT_ID,
    RELATIVE_PATH,
    PATH_COLLISION,
    MEDIA_TYPE,
    WRITE_MODE,
    BYTE_COUNT,
    SHA256,
    TOTAL_BYTE_COUNT,
}

/** Validation errors carry a fixed reason only and never echo paths or content. */
class ExportArtifactPlanValidationException(
    val issue: ExportArtifactPlanValidationIssue,
) : IllegalArgumentException("artifact plan is invalid: ${issue.name.lowercase()}")

/** One immutable artifact. Content is copied on ingress and every public read. */
class ExportArtifactPlanItem(
    val artifactId: String,
    val relativePath: String,
    val mediaType: String,
    val writeMode: ExportArtifactWriteMode,
    content: ByteArray,
    val byteCount: ULong = content.size.toULong(),
    val sha256: String = sha256Hex(content),
) {
    private val storedContent: ByteArray = content.copyOf()

    /** A defensive copy; callers cannot mutate a materialized plan in place. */
    val content: ByteArray get() = storedContent.copyOf()

    init {
        validateArtifactId(artifactId)
        validateRelativePath(relativePath)
        validateMediaType(mediaType)
        val maximumBytes = if (writeMode == ExportArtifactWriteMode.api_post) {
            MAX_INLINE_ARTIFACT_BYTES
        } else {
            MAX_ORDINARY_ARTIFACT_BYTES
        }
        if (byteCount != storedContent.size.toULong() || byteCount > maximumBytes) {
            invalid(ExportArtifactPlanValidationIssue.BYTE_COUNT)
        }
        if (!sha256.isLowercaseSha256() || sha256Hex(storedContent) != sha256) {
            invalid(ExportArtifactPlanValidationIssue.SHA256)
        }
        if (
            writeMode == ExportArtifactWriteMode.markdown_merge &&
            (!relativePath.endsWith(".md") || !mediaType.startsWith("text/markdown"))
        ) {
            invalid(ExportArtifactPlanValidationIssue.WRITE_MODE)
        }
    }

    fun copy(
        artifactId: String = this.artifactId,
        relativePath: String = this.relativePath,
        mediaType: String = this.mediaType,
        writeMode: ExportArtifactWriteMode = this.writeMode,
        content: ByteArray = storedContent,
        byteCount: ULong = content.size.toULong(),
        sha256: String = sha256Hex(content),
    ): ExportArtifactPlanItem = ExportArtifactPlanItem(
        artifactId = artifactId,
        relativePath = relativePath,
        mediaType = mediaType,
        writeMode = writeMode,
        content = content,
        byteCount = byteCount,
        sha256 = sha256,
    )

    internal fun contentEquals(other: ExportArtifactPlanItem): Boolean =
        storedContent.contentEquals(other.storedContent)

    internal fun firstDifferingByteOffset(other: ExportArtifactPlanItem): ULong? {
        val sharedLength = minOf(storedContent.size, other.storedContent.size)
        for (index in 0 until sharedLength) {
            if (storedContent[index] != other.storedContent[index]) return index.toULong()
        }
        return sharedLength.toULong().takeIf { storedContent.size != other.storedContent.size }
    }

    override fun equals(other: Any?): Boolean =
        other is ExportArtifactPlanItem &&
            artifactId == other.artifactId &&
            relativePath == other.relativePath &&
            mediaType == other.mediaType &&
            writeMode == other.writeMode &&
            byteCount == other.byteCount &&
            sha256 == other.sha256 &&
            storedContent.contentEquals(other.storedContent)

    override fun hashCode(): Int {
        var result = artifactId.hashCode()
        result = 31 * result + relativePath.hashCode()
        result = 31 * result + mediaType.hashCode()
        result = 31 * result + writeMode.hashCode()
        result = 31 * result + byteCount.hashCode()
        result = 31 * result + sha256.hashCode()
        result = 31 * result + storedContent.contentHashCode()
        return result
    }

    override fun toString(): String =
        "ExportArtifactPlanItem(artifactId=$artifactId, relativePath=<redacted>, " +
            "mediaType=$mediaType, writeMode=$writeMode, byteCount=$byteCount, " +
            "sha256=$sha256, content=<redacted>)"

    companion object {
        const val MAX_ORDINARY_ARTIFACT_BYTES: ULong = 8_388_608uL
        const val MAX_INLINE_ARTIFACT_BYTES: ULong = 33_554_432uL
    }
}

/** Ordered immutable plan matching the UniFFI artifact-plan v1 boundary. */
class ExportArtifactPlan(
    val schema: String,
    val artifactPlanVersion: UInt,
    val requestId: String,
    val sessionId: String,
    val profile: AndroidExportProfile,
    items: List<ExportArtifactPlanItem>,
    val totalByteCount: ULong = items.fold(0uL) { total, item -> total + item.byteCount },
) {
    val items: List<ExportArtifactPlanItem> =
        Collections.unmodifiableList(items.toList())

    init {
        if (schema != SCHEMA) invalid(ExportArtifactPlanValidationIssue.SCHEMA)
        if (artifactPlanVersion != VERSION) invalid(ExportArtifactPlanValidationIssue.VERSION)
        validateOpaqueId(requestId, ExportArtifactPlanValidationIssue.REQUEST_ID)
        validateOpaqueId(sessionId, ExportArtifactPlanValidationIssue.SESSION_ID)
        if (this.items.size > MAX_ARTIFACTS) {
            invalid(ExportArtifactPlanValidationIssue.ARTIFACT_COUNT)
        }
        val hasInvalidIdentity = this.items.any { item ->
            item.artifactId != artifactIdHex(
                requestId = requestId,
                sessionId = sessionId,
                profile = profile,
                relativePath = item.relativePath,
                mediaType = item.mediaType,
                writeMode = item.writeMode,
                contentSha256 = item.sha256,
            )
        }
        if (hasInvalidIdentity) invalid(ExportArtifactPlanValidationIssue.ARTIFACT_ID)
        if (this.items.map { it.artifactId }.distinct().size != this.items.size) {
            invalid(ExportArtifactPlanValidationIssue.DUPLICATE_ARTIFACT_ID)
        }
        val pathKeys = this.items.map { collisionKey(it.relativePath) }
        if (pathKeys.distinct().size != pathKeys.size) {
            invalid(ExportArtifactPlanValidationIssue.PATH_COLLISION)
        }
        val computedTotal = this.items.fold(0uL) { total, item ->
            val next = total + item.byteCount
            if (next < total) invalid(ExportArtifactPlanValidationIssue.TOTAL_BYTE_COUNT)
            next
        }
        if (totalByteCount != computedTotal || totalByteCount > MAX_TOTAL_BYTES) {
            invalid(ExportArtifactPlanValidationIssue.TOTAL_BYTE_COUNT)
        }
    }

    fun copy(
        schema: String = this.schema,
        artifactPlanVersion: UInt = this.artifactPlanVersion,
        requestId: String = this.requestId,
        sessionId: String = this.sessionId,
        profile: AndroidExportProfile = this.profile,
        items: List<ExportArtifactPlanItem> = this.items,
        totalByteCount: ULong = items.fold(0uL) { total, item -> total + item.byteCount },
    ): ExportArtifactPlan = ExportArtifactPlan(
        schema = schema,
        artifactPlanVersion = artifactPlanVersion,
        requestId = requestId,
        sessionId = sessionId,
        profile = profile,
        items = items,
        totalByteCount = totalByteCount,
    )

    override fun equals(other: Any?): Boolean =
        other is ExportArtifactPlan &&
            schema == other.schema &&
            artifactPlanVersion == other.artifactPlanVersion &&
            requestId == other.requestId &&
            sessionId == other.sessionId &&
            profile == other.profile &&
            items == other.items &&
            totalByteCount == other.totalByteCount

    override fun hashCode(): Int {
        var result = schema.hashCode()
        result = 31 * result + artifactPlanVersion.hashCode()
        result = 31 * result + requestId.hashCode()
        result = 31 * result + sessionId.hashCode()
        result = 31 * result + profile.hashCode()
        result = 31 * result + items.hashCode()
        result = 31 * result + totalByteCount.hashCode()
        return result
    }

    override fun toString(): String =
        "ExportArtifactPlan(schema=$schema, artifactPlanVersion=$artifactPlanVersion, " +
            "requestId=<redacted>, sessionId=<redacted>, profile=$profile, " +
            "itemCount=${items.size}, totalByteCount=$totalByteCount)"

    companion object {
        const val SCHEMA = "healthmd.artifact_plan"
        const val VERSION: UInt = 1u
        const val MAX_ARTIFACTS = 4_096
        const val MAX_TOTAL_BYTES: ULong = 33_554_432uL

        fun fromCore(plan: CoreArtifactPlan): ExportArtifactPlan =
            CoreArtifactPlanConverter.convert(plan)
    }
}

/** Converts mutable generated UniFFI records into validated, defensively copied app records. */
object CoreArtifactPlanConverter {
    fun convert(plan: CoreArtifactPlan): ExportArtifactPlan = ExportArtifactPlan(
        schema = plan.schema,
        artifactPlanVersion = plan.artifactPlanVersion,
        requestId = plan.requestId,
        sessionId = plan.sessionId,
        profile = when (plan.profile) {
            CoreMetricRegistryProfile.ANDROID_FROZEN_V4 ->
                AndroidExportProfile.android_frozen_v4
            CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5 ->
                AndroidExportProfile.android_analytical_v5
            CoreMetricRegistryProfile.APPLE_HEALTH_DATA_V8 ->
                invalid(ExportArtifactPlanValidationIssue.PROFILE)
        },
        items = plan.items.map { item ->
            ExportArtifactPlanItem(
                artifactId = item.artifactId,
                relativePath = item.relativePath,
                mediaType = item.mediaType,
                writeMode = when (item.writeMode) {
                    CoreArtifactWriteMode.OVERWRITE -> ExportArtifactWriteMode.overwrite
                    CoreArtifactWriteMode.APPEND -> ExportArtifactWriteMode.append
                    CoreArtifactWriteMode.MARKDOWN_MERGE -> ExportArtifactWriteMode.markdown_merge
                    CoreArtifactWriteMode.API_POST -> ExportArtifactWriteMode.api_post
                },
                content = item.content.copyOf(),
                byteCount = item.byteCount,
                sha256 = item.sha256,
            )
        },
        totalByteCount = plan.totalByteCount,
    )
}

private fun validateArtifactId(value: String) {
    if (!value.isLowercaseSha256()) invalid(ExportArtifactPlanValidationIssue.ARTIFACT_ID)
}

private fun validateRelativePath(value: String) {
    val windowsAbsolute = value.length >= 2 && value[0].isLetter() && value[1] == ':'
    if (
        value.isEmpty() ||
        value.encodeToByteArray().size > 4_096 ||
        value.startsWith('/') ||
        windowsAbsolute ||
        '\\' in value ||
        '\u0000' in value ||
        value.any(Char::isISOControl) ||
        '{' in value ||
        '}' in value
    ) {
        invalid(ExportArtifactPlanValidationIssue.RELATIVE_PATH)
    }
    val components = value.split('/')
    if (components.any { it.isEmpty() || it == "." || it == ".." }) {
        invalid(ExportArtifactPlanValidationIssue.RELATIVE_PATH)
    }
}

private fun validateMediaType(value: String) {
    if (
        value.isEmpty() ||
        value.length > 128 ||
        '/' !in value ||
        value.any { character ->
            !character.isLetterOrDigit() &&
                character !in setOf('/', '+', '-', '.', ';', '=', ' ')
        } ||
        value.any { it.code > 0x7f }
    ) {
        invalid(ExportArtifactPlanValidationIssue.MEDIA_TYPE)
    }
}

private fun validateOpaqueId(value: String, issue: ExportArtifactPlanValidationIssue) {
    if (value.isEmpty() || value.length > 128 || value.any(Char::isISOControl)) invalid(issue)
}

private fun collisionKey(path: String): String {
    val compatible = Normalizer.normalize(path, Normalizer.Form.NFKC)
    // Root uppercase before lowercase covers multi-code-point folds such as ß -> ss.
    val folded = compatible.uppercase(Locale.ROOT).lowercase(Locale.ROOT)
    return Normalizer.normalize(folded, Normalizer.Form.NFKC)
}

internal fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).toLowercaseHex()

internal fun artifactIdHex(
    requestId: String,
    sessionId: String,
    profile: AndroidExportProfile,
    relativePath: String,
    mediaType: String,
    writeMode: ExportArtifactWriteMode,
    contentSha256: String,
): String {
    val digest = MessageDigest.getInstance("SHA-256")
    digest.update("healthmd.artifact_id.v1\u0000".encodeToByteArray())
    listOf(
        requestId,
        sessionId,
        profile.name,
        relativePath,
        mediaType,
        writeMode.name,
        contentSha256,
    ).forEach { value ->
        val bytes = value.encodeToByteArray()
        var length = bytes.size.toLong()
        val encodedLength = ByteArray(Long.SIZE_BYTES)
        for (index in encodedLength.indices.reversed()) {
            encodedLength[index] = (length and 0xff).toByte()
            length = length ushr 8
        }
        digest.update(encodedLength)
        digest.update(bytes)
    }
    return digest.digest().toLowercaseHex()
}

private fun ByteArray.toLowercaseHex(): String {
    val alphabet = "0123456789abcdef"
    return buildString(size * 2) {
        this@toLowercaseHex.forEach { byte ->
            val value = byte.toInt() and 0xff
            append(alphabet[value ushr 4])
            append(alphabet[value and 0x0f])
        }
    }
}

private fun invalid(issue: ExportArtifactPlanValidationIssue): Nothing =
    throw ExportArtifactPlanValidationException(issue)

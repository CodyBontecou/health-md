package com.healthmd.domain.exportengine

import com.healthmd.BuildConfig
import java.util.Collections

enum class ExportArtifactMismatchDimension {
    ORDER,
    COUNT,
    ARTIFACT_ID,
    RELATIVE_PATH,
    MEDIA_TYPE,
    WRITE_MODE,
    BYTE_LENGTH,
    SHA256,
    BYTES,
}

/** First-byte offsets require both an internal/debug context and an explicit request. */
data class ExportArtifactComparisonOptions(
    val isInternalOrDebug: Boolean = false,
    val includeFirstByteOffset: Boolean = false,
) {
    init {
        require(!includeFirstByteOffset || isInternalOrDebug) {
            "first-byte offsets require internal/debug diagnostics"
        }
    }
}

/**
 * Health-free evidence for one mismatch.
 *
 * Artifact bytes, field values, dates, credentials, request IDs, and relative paths are never
 * represented. Lengths and one-way hashes are allowed comparison evidence.
 */
data class ExportArtifactMismatch(
    val dimension: ExportArtifactMismatchDimension,
    val artifactIndex: Int? = null,
    val expectedCount: Int? = null,
    val actualCount: Int? = null,
    val expectedLength: ULong? = null,
    val actualLength: ULong? = null,
    val expectedSha256: String? = null,
    val actualSha256: String? = null,
    val firstByteOffset: ULong? = null,
)

class ExportArtifactPlanComparison internal constructor(
    mismatches: List<ExportArtifactMismatch>,
) {
    val mismatches: List<ExportArtifactMismatch> =
        Collections.unmodifiableList(mismatches.toList())
    val matches: Boolean get() = mismatches.isEmpty()
    val dimensions: Set<ExportArtifactMismatchDimension> get() =
        mismatches.mapTo(linkedSetOf()) { it.dimension }

    override fun toString(): String =
        "ExportArtifactPlanComparison(matches=$matches, mismatches=$mismatches)"
}

/** Byte-exact ordered comparator. It never parses, trims, normalizes, or re-encodes content. */
class ExportArtifactPlanComparator {
    fun compare(
        expected: ExportArtifactPlan,
        actual: ExportArtifactPlan,
        options: ExportArtifactComparisonOptions = ExportArtifactComparisonOptions(),
    ): ExportArtifactPlanComparison {
        val mismatches = mutableListOf<ExportArtifactMismatch>()
        if (expected.items.size != actual.items.size) {
            mismatches += ExportArtifactMismatch(
                dimension = ExportArtifactMismatchDimension.COUNT,
                expectedCount = expected.items.size,
                actualCount = actual.items.size,
            )
        }
        if (expected.totalByteCount != actual.totalByteCount) {
            mismatches += ExportArtifactMismatch(
                dimension = ExportArtifactMismatchDimension.BYTE_LENGTH,
                expectedLength = expected.totalByteCount,
                actualLength = actual.totalByteCount,
            )
        }

        val expectedOrder = expected.items.map { it.artifactId }
        val actualOrder = actual.items.map { it.artifactId }
        if (
            expectedOrder != actualOrder &&
            expectedOrder.size == actualOrder.size &&
            expectedOrder.toSet() == actualOrder.toSet()
        ) {
            mismatches += ExportArtifactMismatch(
                dimension = ExportArtifactMismatchDimension.ORDER,
            )
        }

        val sharedCount = minOf(expected.items.size, actual.items.size)
        for (index in 0 until sharedCount) {
            val left = expected.items[index]
            val right = actual.items[index]
            if (left.artifactId != right.artifactId) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.ARTIFACT_ID,
                    artifactIndex = index,
                )
            }
            if (left.relativePath != right.relativePath) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.RELATIVE_PATH,
                    artifactIndex = index,
                )
            }
            if (left.mediaType != right.mediaType) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.MEDIA_TYPE,
                    artifactIndex = index,
                )
            }
            if (left.writeMode != right.writeMode) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.WRITE_MODE,
                    artifactIndex = index,
                )
            }
            if (left.byteCount != right.byteCount) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.BYTE_LENGTH,
                    artifactIndex = index,
                    expectedLength = left.byteCount,
                    actualLength = right.byteCount,
                )
            }
            if (left.sha256 != right.sha256) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.SHA256,
                    artifactIndex = index,
                    expectedLength = left.byteCount,
                    actualLength = right.byteCount,
                    expectedSha256 = left.sha256,
                    actualSha256 = right.sha256,
                )
            }
            if (!left.contentEquals(right)) {
                mismatches += ExportArtifactMismatch(
                    dimension = ExportArtifactMismatchDimension.BYTES,
                    artifactIndex = index,
                    expectedLength = left.byteCount,
                    actualLength = right.byteCount,
                    expectedSha256 = left.sha256,
                    actualSha256 = right.sha256,
                    firstByteOffset = if (
                        BuildConfig.DEBUG &&
                            options.isInternalOrDebug && options.includeFirstByteOffset
                    ) {
                        left.firstDifferingByteOffset(right)
                    } else {
                        null
                    },
                )
            }
        }
        return ExportArtifactPlanComparison(mismatches)
    }
}

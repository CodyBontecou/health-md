package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class ExportArtifactPlanComparatorTest {
    private val comparator = ExportArtifactPlanComparator()
    private val first = testArtifact(
        path = "private/2026-07-25/user-secret.json",
        content = "abc".encodeToByteArray(),
    )
    private val second = testArtifact(
        path = "private/second.csv",
        mediaType = "text/csv; charset=utf-8",
        content = "x,y\n".encodeToByteArray(),
    )
    private val expected = testPlan(listOf(first, second))

    @Test
    fun comparatorDetectsEveryExactMismatchDimension() {
        assertThat(
            comparator.compare(expected, expected.copy(items = listOf(second, first))).dimensions,
        ).contains(ExportArtifactMismatchDimension.ORDER)
        assertThat(
            comparator.compare(expected, expected.copy(items = listOf(first))).dimensions,
        ).contains(ExportArtifactMismatchDimension.COUNT)

        val otherRequestId = "other-request"
        val otherRequest = testPlan(
            requestId = otherRequestId,
            items = listOf(
                testArtifact(
                    path = "private/2026-07-25/user-secret.json",
                    content = "abc".encodeToByteArray(),
                    requestId = otherRequestId,
                ),
                testArtifact(
                    path = "private/second.csv",
                    mediaType = "text/csv; charset=utf-8",
                    content = "x,y\n".encodeToByteArray(),
                    requestId = otherRequestId,
                ),
            ),
        )
        assertThat(comparator.compare(expected, otherRequest).dimensions)
            .contains(ExportArtifactMismatchDimension.ARTIFACT_ID)
        assertThat(
            comparator.compare(
                expected,
                changedFirst(path = "private/other.json"),
            ).dimensions,
        ).contains(ExportArtifactMismatchDimension.RELATIVE_PATH)
        assertThat(
            comparator.compare(
                expected,
                changedFirst(mediaType = "application/octet-stream"),
            ).dimensions,
        ).contains(ExportArtifactMismatchDimension.MEDIA_TYPE)
        assertThat(
            comparator.compare(
                expected,
                changedFirst(writeMode = ExportArtifactWriteMode.append),
            ).dimensions,
        ).contains(ExportArtifactMismatchDimension.WRITE_MODE)

        val contentMismatch = comparator.compare(
            expected,
            changedFirst(content = "abz".encodeToByteArray()),
        )
        assertThat(contentMismatch.dimensions).containsAtLeast(
            ExportArtifactMismatchDimension.SHA256,
            ExportArtifactMismatchDimension.BYTES,
        )
        val lengthMismatch = comparator.compare(
            expected,
            changedFirst(content = "longer".encodeToByteArray()),
        )
        assertThat(lengthMismatch.dimensions).contains(ExportArtifactMismatchDimension.BYTE_LENGTH)
    }

    @Test
    fun productionDiagnosticsAreRedactedAndOffsetRequiresExplicitInternalMode() {
        val actual = changedFirst(content = "abz".encodeToByteArray())

        val production = comparator.compare(expected, actual)
        val productionBytes = production.mismatches.single {
            it.dimension == ExportArtifactMismatchDimension.BYTES
        }
        assertThat(productionBytes.firstByteOffset).isNull()
        assertThat(production.toString()).doesNotContain("private/2026-07-25")
        assertThat(production.toString()).doesNotContain("abc")
        assertThat(production.toString()).doesNotContain("abz")

        val internal = comparator.compare(
            expected,
            actual,
            ExportArtifactComparisonOptions(
                isInternalOrDebug = true,
                includeFirstByteOffset = true,
            ),
        )
        assertThat(
            internal.mismatches.single {
                it.dimension == ExportArtifactMismatchDimension.BYTES
            }.firstByteOffset,
        ).isEqualTo(2uL)
    }

    private fun changedFirst(
        path: String = "private/2026-07-25/user-secret.json",
        mediaType: String = "application/json",
        writeMode: ExportArtifactWriteMode = ExportArtifactWriteMode.overwrite,
        content: ByteArray = "abc".encodeToByteArray(),
    ): ExportArtifactPlan = testPlan(
        listOf(
            testArtifact(
                path = path,
                mediaType = mediaType,
                writeMode = writeMode,
                content = content,
            ),
            second,
        ),
    )
}

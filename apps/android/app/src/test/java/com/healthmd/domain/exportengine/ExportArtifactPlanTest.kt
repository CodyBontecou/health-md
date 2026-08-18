package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreArtifactPlan
import com.healthmd.core.CoreArtifactPlanItem
import com.healthmd.core.CoreArtifactWriteMode
import com.healthmd.core.CoreMetricRegistryProfile
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ExportArtifactPlanTest {
    @Test
    fun corePlanConversionPreservesEveryDescriptorAndDefensivelyCopiesContent() {
        val bytes = "{\"ok\":true}".encodeToByteArray()
        val core = CoreArtifactPlan(
            schema = ExportArtifactPlan.SCHEMA,
            artifactPlanVersion = 1u,
            requestId = TEST_REQUEST_ID,
            sessionId = TEST_SESSION_ID,
            profile = CoreMetricRegistryProfile.ANDROID_FROZEN_V4,
            items = listOf(
                CoreArtifactPlanItem(
                    artifactId = artifactIdHex(
                        requestId = TEST_REQUEST_ID,
                        sessionId = TEST_SESSION_ID,
                        profile = AndroidExportProfile.android_frozen_v4,
                        relativePath = "health/result.json",
                        mediaType = "application/json",
                        writeMode = ExportArtifactWriteMode.overwrite,
                        contentSha256 = sha256Hex(bytes),
                    ),
                    relativePath = "health/result.json",
                    mediaType = "application/json",
                    writeMode = CoreArtifactWriteMode.OVERWRITE,
                    content = bytes,
                    byteCount = bytes.size.toULong(),
                    sha256 = sha256Hex(bytes),
                ),
            ),
            totalByteCount = bytes.size.toULong(),
        )

        val converted = ExportArtifactPlan.fromCore(core)
        bytes[0] = 'X'.code.toByte()
        val exposed = converted.items.single().content
        exposed[0] = 'Y'.code.toByte()

        assertThat(converted.schema).isEqualTo("healthmd.artifact_plan")
        assertThat(converted.artifactPlanVersion).isEqualTo(1u)
        assertThat(converted.profile).isEqualTo(AndroidExportProfile.android_frozen_v4)
        assertThat(converted.items.single().artifactId).isEqualTo(core.items.single().artifactId)
        assertThat(converted.items.single().relativePath).isEqualTo("health/result.json")
        assertThat(converted.items.single().mediaType).isEqualTo("application/json")
        assertThat(converted.items.single().writeMode)
            .isEqualTo(ExportArtifactWriteMode.overwrite)
        assertThat(converted.items.single().byteCount).isEqualTo(11uL)
        assertThat(converted.items.single().sha256)
            .isEqualTo(sha256Hex("{\"ok\":true}".encodeToByteArray()))
        assertArrayEquals(
            "{\"ok\":true}".encodeToByteArray(),
            converted.items.single().content,
        )
    }

    @Test
    fun strictValidationRejectsTraversalLengthsHashesAndCaseFoldedCollisions() {
        fun invalidItem(
            path: String = "health/result.json",
            byteCount: ULong = 2uL,
            hash: String = sha256Hex("{}".encodeToByteArray()),
        ): ExportArtifactPlanValidationException = assertThrows(
            ExportArtifactPlanValidationException::class.java,
        ) {
            ExportArtifactPlanItem(
                artifactId = "1".repeat(64),
                relativePath = path,
                mediaType = "application/json",
                writeMode = ExportArtifactWriteMode.overwrite,
                content = "{}".encodeToByteArray(),
                byteCount = byteCount,
                sha256 = hash,
            )
        }

        assertThat(invalidItem(path = "health/../secret.json").issue)
            .isEqualTo(ExportArtifactPlanValidationIssue.RELATIVE_PATH)
        assertThat(invalidItem(byteCount = 3uL).issue)
            .isEqualTo(ExportArtifactPlanValidationIssue.BYTE_COUNT)
        assertThat(invalidItem(hash = "0".repeat(64)).issue)
            .isEqualTo(ExportArtifactPlanValidationIssue.SHA256)

        val collision = assertThrows(ExportArtifactPlanValidationException::class.java) {
            testPlan(
                listOf(
                    testArtifact(path = "Health/Result.json"),
                    testArtifact(path = "health/result.json"),
                ),
            )
        }
        assertThat(collision.issue).isEqualTo(ExportArtifactPlanValidationIssue.PATH_COLLISION)
        val unicodeCollision = assertThrows(ExportArtifactPlanValidationException::class.java) {
            testPlan(
                listOf(
                    testArtifact(path = "Straße/result.json"),
                    testArtifact(path = "STRASSE/result.json"),
                ),
            )
        }
        assertThat(unicodeCollision.issue)
            .isEqualTo(ExportArtifactPlanValidationIssue.PATH_COLLISION)
    }

    @Test
    fun converterRejectsNonAndroidPlans() {
        val core = CoreArtifactPlan(
            schema = ExportArtifactPlan.SCHEMA,
            artifactPlanVersion = 1u,
            requestId = TEST_REQUEST_ID,
            sessionId = TEST_SESSION_ID,
            profile = CoreMetricRegistryProfile.APPLE_HEALTH_DATA_V8,
            items = emptyList(),
            totalByteCount = 0uL,
        )

        val error = assertThrows(ExportArtifactPlanValidationException::class.java) {
            ExportArtifactPlan.fromCore(core)
        }
        assertThat(error.issue).isEqualTo(ExportArtifactPlanValidationIssue.PROFILE)
    }
}

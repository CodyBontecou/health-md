package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreArtifactPlan
import com.healthmd.core.CoreArtifactPlanItem
import com.healthmd.core.CoreArtifactWriteMode
import com.healthmd.core.CoreMetricRegistryProfile
import java.io.File
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
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
    fun successorCorePlanRequiresV2AndNeverWidenHistoricalPlanV1() {
        val core = CoreArtifactPlan(
            schema = "healthmd.artifact_plan",
            artifactPlanVersion = 2u,
            requestId = TEST_REQUEST_ID,
            sessionId = TEST_SESSION_ID,
            profile = CoreMetricRegistryProfile.ANDROID_SLEEP_V6,
            items = emptyList(),
            totalByteCount = 0uL,
        )
        val converted = ExportArtifactPlan.fromCore(core)
        assertThat(converted.profile).isEqualTo(AndroidExportProfile.android_sleep_v6)
        assertThat(converted.artifactPlanVersion).isEqualTo(2u)
        assertThat(converted.items).isEmpty()

        val draft = assertThrows(ExportArtifactPlanValidationException::class.java) {
            ExportArtifactPlan.fromCore(core.copy(artifactPlanVersion = 1u))
        }
        assertThat(draft.issue).isEqualTo(ExportArtifactPlanValidationIssue.VERSION)
        for (historical in listOf(
            CoreMetricRegistryProfile.ANDROID_FROZEN_V4,
            CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5,
        )) {
            val widened = assertThrows(ExportArtifactPlanValidationException::class.java) {
                ExportArtifactPlan.fromCore(core.copy(profile = historical))
            }
            assertThat(widened.issue).isEqualTo(ExportArtifactPlanValidationIssue.VERSION)
        }
        val otherPlatform = assertThrows(ExportArtifactPlanValidationException::class.java) {
            ExportArtifactPlan.fromCore(core.copy(profile = CoreMetricRegistryProfile.APPLE_HEALTH_DATA_V10))
        }
        assertThat(otherPlatform.issue).isEqualTo(ExportArtifactPlanValidationIssue.PROFILE)
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
    fun realCoreSuccessorPlanFixtureVerifiesIdentitiesHashesAndDefensiveCopies() {
        val file = generateSequence(File(System.getProperty("user.dir") ?: ".")) { it.parentFile }
            .map { File(it, "packages/contracts/render-input/v2/fixtures/core-android-v6-artifact-plan.json") }
            .first(File::isFile)
        val root = Json.parseToJsonElement(file.readText()).jsonObject
        assertThat(root.getValue("profile").jsonPrimitive.content).isEqualTo("android_sleep_v6")
        val core = CoreArtifactPlan(
            schema = root.getValue("schema").jsonPrimitive.content,
            artifactPlanVersion = root.getValue("artifact_plan_version").jsonPrimitive.content.toUInt(),
            requestId = root.getValue("request_id").jsonPrimitive.content,
            sessionId = root.getValue("session_id").jsonPrimitive.content,
            profile = CoreMetricRegistryProfile.ANDROID_SLEEP_V6,
            items = root.getValue("items").jsonArray.map { value ->
                val item = value.jsonObject
                CoreArtifactPlanItem(
                    artifactId = item.getValue("artifact_id").jsonPrimitive.content,
                    relativePath = item.getValue("relative_path").jsonPrimitive.content,
                    mediaType = item.getValue("media_type").jsonPrimitive.content,
                    writeMode = CoreArtifactWriteMode.valueOf(item.getValue("write_mode").jsonPrimitive.content.uppercase()),
                    content = Base64.getDecoder().decode(item.getValue("content_base64").jsonPrimitive.content),
                    byteCount = item.getValue("byte_count").jsonPrimitive.content.toULong(),
                    sha256 = item.getValue("sha256").jsonPrimitive.content,
                )
            },
            totalByteCount = root.getValue("total_byte_count").jsonPrimitive.content.toULong(),
        )
        val plan = ExportArtifactPlan.fromCore(core)
        assertThat(plan.artifactPlanVersion).isEqualTo(2u)
        assertThat(plan.items).hasSize(4)
        plan.items.forEach { item ->
            assertThat(item.content.decodeToString()).contains("morning_ends")
            assertThat(item.content.decodeToString()).doesNotContain("sleep_core_hours")
        }
        val original = plan.items.first().content
        core.items.first().content[0] = 'X'.code.toByte()
        assertArrayEquals(original, plan.items.first().content)
        val error = assertThrows(ExportArtifactPlanValidationException::class.java) {
            ExportArtifactPlan.fromCore(core)
        }
        assertThat(error.issue).isEqualTo(ExportArtifactPlanValidationIssue.SHA256)
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

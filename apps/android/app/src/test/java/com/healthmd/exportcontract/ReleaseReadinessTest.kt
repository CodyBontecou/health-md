package com.healthmd.exportcontract

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ReleaseReadinessTest {

    private fun repoRoot(): File {
        val startDir = requireNotNull(System.getProperty("user.dir"))
        var dir: File? = File(startDir).absoluteFile
        while (dir != null) {
            if (File(dir, "app/build.gradle.kts").exists()) return dir
            dir = dir.parentFile
        }
        throw AssertionError("Could not locate repo root from $startDir")
    }

    private fun readRepoFile(relativePath: String): String =
        File(repoRoot(), relativePath).also { file ->
            assertTrue("Expected $relativePath to exist", file.exists())
        }.readText()

    @Test
    fun appVersion_isBumpedForParityRelease() {
        val buildGradle = readRepoFile("app/build.gradle.kts")

        assertTrue(buildGradle.contains("versionCode = 11"))
        assertTrue(buildGradle.contains("versionName = \"1.3.0\""))
    }

    @Test
    fun playStoreReleaseNotes_describePhase4ParityRollout() {
        val releaseNotes = readRepoFile("play-console/listing/en-US/release-notes/en-US/default.txt")

        assertTrue(releaseNotes.contains("v1.3.0"))
        assertTrue(releaseNotes.contains("Android/iOS Export Parity"))
        assertTrue(releaseNotes.contains("Obsidian Health.md plugin"))
        assertTrue(releaseNotes.contains("re-export recent history"))
        assertTrue(releaseNotes.contains("canonical iOS-compatible names"))
        assertTrue("Play Store release notes should stay within the 500-character limit", releaseNotes.trim().length <= 500)
    }

    @Test
    fun exportContractDocs_referencePhase4ReleaseReadiness() {
        val migrationPlan = readRepoFile("docs/export-contract/migration-plan.md")
        val compatibilityReport = readRepoFile("docs/export-contract/compatibility-report.md")
        val gapMatrix = readRepoFile("docs/export-contract/android-ios-gap-matrix.md")

        assertTrue(migrationPlan.contains("Phase 4 release-readiness"))
        assertTrue(migrationPlan.contains("versionCode = 11"))
        assertTrue(migrationPlan.contains("completed P0-P3 implementation"))

        assertTrue(compatibilityReport.contains("Phase 4 rollout prep"))
        assertTrue(compatibilityReport.contains("versionCode 11"))
        assertTrue(compatibilityReport.contains("HealthMetrics.unavailableMetrics"))

        assertTrue(gapMatrix.contains("Phase 4 Android status"))
        assertTrue(gapMatrix.contains("versionName = \"1.3.0\""))
        assertTrue(gapMatrix.contains("versionCode = 11"))
    }
}

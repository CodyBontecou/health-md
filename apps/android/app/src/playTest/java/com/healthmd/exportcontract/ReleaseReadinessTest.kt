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
    fun appVersion_isPreparedForDependableSchedulingRelease() {
        val buildGradle = readRepoFile("app/build.gradle.kts")

        assertTrue(buildGradle.contains("versionCode = 39"))
        assertTrue(buildGradle.contains("versionName = \"1.9.1\""))
    }

    @Test
    fun playStoreReleaseNotes_describeDependableSchedulingRelease() {
        val releaseNotePaths = listOf(
            "play-console/listing/en-US/release-notes/en-US/default.txt",
            "app/src/main/play/release-notes/en-US/default.txt",
        )

        val releaseNotesByPath = releaseNotePaths.associateWith(::readRepoFile)
        val canonicalReleaseNotes = releaseNotesByPath.getValue(releaseNotePaths.first())

        releaseNotesByPath.forEach { (path, releaseNotes) ->
            assertTrue("Expected $path to match the canonical Play release notes", releaseNotes == canonicalReleaseNotes)
            assertTrue(releaseNotes.contains("v1.9.1"))
            assertTrue(releaseNotes.contains("Share My Setup"))
            assertTrue(releaseNotes.contains("no health data or credentials"))
            assertTrue(releaseNotes.contains("full lookback"))
            assertTrue(releaseNotes.contains("Today Refresh"))
            assertTrue(releaseNotes.contains("TalkBack"))
            assertTrue("Play Store release notes should stay within the 500-character limit", releaseNotes.trim().length <= 500)
        }
    }

    @Test
    fun googlePlayRelease_isPhoneOnlyWhileWearPublicationIsDeferred() {
        val releaseScope = readRepoFile("release-scope.json")
        val uploadScript = readRepoFile("scripts/upload-google-play-phone-release.sh")
        val releaseWorkflow = readRepoFile("../../.github/workflows/android-release.yml")
        val promotionWorkflow = readRepoFile("../../.github/workflows/android-promote-production.yml")
        val phoneManifest = readRepoFile("app/src/play/AndroidManifest.xml")
        val wearManifest = readRepoFile("wear/src/main/AndroidManifest.xml")
        val wearCapabilities = readRepoFile("wear/src/main/res/values/wear.xml")

        assertTrue(releaseScope.contains("\"releaseVersionName\": \"1.9.1\""))
        assertTrue(releaseScope.contains("\"versionCode\": 39"))
        assertTrue(releaseScope.contains("\"status\": \"deferred\""))
        assertTrue(releaseScope.contains("\"published\": false"))
        assertTrue(releaseScope.contains("\"runtimeAdvertisedByPhone\": false"))
        assertTrue(uploadScript.contains("PHONE_PLAY_TRACK:-internal"))
        assertTrue(uploadScript.contains("app-play-release.aab"))
        assertTrue(!uploadScript.contains("wear-release.aab"))
        assertTrue(uploadScript.contains("CONFIRM_PLAY_PHONE_UPLOAD"))
        assertTrue(uploadScript.contains("play_phone_release_payload"))
        assertTrue(releaseWorkflow.contains("./scripts/upload-google-play-phone-release.sh"))
        assertTrue(releaseWorkflow.contains("RELEASE_TAG^{commit}"))
        assertTrue(releaseWorkflow.contains("release_sha: \${{ needs.resolve.outputs.release_sha }}"))
        assertTrue(releaseWorkflow.contains("pull-requests: read"))
        assertTrue(releaseWorkflow.contains("wearIncluded:false"))
        assertTrue(!releaseWorkflow.contains(":wear:bundleRelease"))
        assertTrue(!releaseWorkflow.contains("wear:internal"))
        assertTrue(promotionWorkflow.contains("sourceTrack:\"internal\""))
        assertTrue(promotionWorkflow.contains("destinationTrack:\"production\""))
        assertTrue(promotionWorkflow.contains("wearIncluded:false"))
        assertTrue(!promotionWorkflow.contains("wear_version_code"))
        assertTrue(!phoneManifest.contains("WearPhoneDataLayerService"))
        assertTrue(!phoneManifest.contains("com.google.android.gms.wearable"))
        assertTrue(wearCapabilities.contains("android_wear_capabilities"))
        assertTrue(wearCapabilities.contains("healthmd_watch_sync"))
        assertTrue(wearManifest.contains("com.google.android.gms.wearable.DATA_CHANGED"))
    }

    @Test
    fun wearEmulatorEvidence_derivesIdentityFromTheInspectedApk() {
        val smoke = readRepoFile("scripts/run-wear-emulator-smoke.sh")

        assertTrue(smoke.contains("dump badging"))
        assertTrue(smoke.contains("wear_version_code"))
        assertTrue(smoke.contains("wear_version_name"))
        assertTrue(smoke.contains("installed identity differs from inspected APK"))
        assertTrue(smoke.contains("--argjson wearVersionCode"))
        assertTrue(smoke.contains("mismatch marker stores the rejected Data Layer sequence"))
        assertTrue("A Data Layer sequence must not be derived from an app version code", !smoke.contains("mismatch_version_code"))
        assertTrue("Evidence tooling must not silently pin the current Wear code", !smoke.contains("1000029"))
        assertTrue("Evidence tooling must not silently pin the current semantic version", !smoke.contains("1.8.0"))
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

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
    fun appVersion_isPreparedForScheduledExportReliabilityRelease() {
        val buildGradle = readRepoFile("app/build.gradle.kts")

        assertTrue(buildGradle.contains("versionCode = 30"))
        assertTrue(buildGradle.contains("versionName = \"1.8.1\""))
    }

    @Test
    fun playStoreReleaseNotes_describeScheduledExportReliabilityRelease() {
        val releaseNotePaths = listOf(
            "play-console/listing/en-US/release-notes/en-US/default.txt",
            "app/src/main/play/release-notes/en-US/default.txt",
        )

        val releaseNotesByPath = releaseNotePaths.associateWith(::readRepoFile)
        val canonicalReleaseNotes = releaseNotesByPath.getValue(releaseNotePaths.first())

        releaseNotesByPath.forEach { (path, releaseNotes) ->
            assertTrue("Expected $path to match the canonical Play release notes", releaseNotes == canonicalReleaseNotes)
            assertTrue(releaseNotes.contains("v1.8.1"))
            assertTrue(releaseNotes.contains("scheduled export"))
            assertTrue(releaseNotes.contains("retry"))
            assertTrue(releaseNotes.contains("Health Connect"))
            assertTrue(releaseNotes.contains("Play Billing"))
            assertTrue(releaseNotes.contains("Wear OS"))
            assertTrue("Play Store release notes should stay within the 500-character limit", releaseNotes.trim().length <= 500)
        }
    }

    @Test
    fun wearReleaseUploadsExactPairThenSeparatelyVerifiesExactReleaseScreenshots() {
        val uploadScript = readRepoFile("scripts/upload-google-play-paired-release.sh")
        val screenshotScript = readRepoFile("scripts/sync-google-play-wear-screenshots.sh")
        val signerCapture = readRepoFile("scripts/capture-google-play-generated-apk-evidence.sh")
        val releaseWorkflow = readRepoFile("../../.github/workflows/android-release.yml")
        val screenshotWorkflow = readRepoFile("../../.github/workflows/android-wear-screenshots.yml")
        val evidenceWorkflow = readRepoFile("../../.github/workflows/android-wear-evidence.yml")
        val blockerReport = readRepoFile("scripts/report-wear-release-blockers.sh")

        assertTrue(uploadScript.contains("PHONE_PLAY_TRACK:-qa"))
        assertTrue(uploadScript.contains("WEAR_PLAY_TRACK:-wear:qa"))
        assertTrue(uploadScript.contains("app-play-release.aab"))
        assertTrue(uploadScript.contains("wear-release.aab"))
        assertTrue(!uploadScript.contains("wear-app.png"))
        assertTrue(!uploadScript.contains("wear-tile.png"))
        assertTrue(uploadScript.contains("CONFIRM_PLAY_PAIRED_UPLOAD"))
        assertTrue(screenshotScript.contains("wear-app.png"))
        assertTrue(screenshotScript.contains("wear-tile.png"))
        assertTrue(screenshotScript.contains("verify-wear-play-screenshot-evidence.py"))
        assertTrue(screenshotScript.contains("EXPECTED_WEAR_APK_SHA256"))
        assertTrue(screenshotScript.contains("EXPECTED_PLAY_APP_SIGNING_CERT_SHA256"))
        assertTrue(screenshotScript.contains("EXPECTED_SCREENSHOT_REVIEWER"))
        assertTrue(screenshotScript.contains("play_wear_apk"))
        assertTrue(screenshotScript.contains("verify-wear-play-screenshot-upload-evidence.py"))
        assertTrue(signerCapture.contains("\$api/\$code/downloads/\$download:download"))
        assertTrue(signerCapture.contains("apksigner"))
        assertTrue(signerCapture.contains("EXPECTED_PHONE_VERSION_CODE"))
        assertTrue(signerCapture.contains("EXPECTED_WEAR_VERSION_CODE"))
        assertTrue(signerCapture.contains("refusing to overwrite"))
        assertTrue(signerCapture.contains("verify-google-play-generated-apk-evidence.sh"))
        assertTrue(releaseWorkflow.contains("./scripts/upload-google-play-paired-release.sh"))
        assertTrue(releaseWorkflow.contains("wear:qa"))
        assertTrue(releaseWorkflow.contains("GITHUB_REF_NAME^{commit}"))
        assertTrue(releaseWorkflow.contains("qa-upload-receipt.json"))
        assertTrue(screenshotWorkflow.contains("environment: google-play-qa"))
        assertTrue(screenshotWorkflow.contains("./scripts/sync-google-play-wear-screenshots.sh"))
        assertTrue(screenshotWorkflow.contains("submission_run_attempt"))
        assertTrue(screenshotWorkflow.contains("Upload protected screenshot mutation evidence"))
        assertTrue(evidenceWorkflow.contains("submission_run_attempt"))
        assertTrue(evidenceWorkflow.contains("screenshot_upload_run_id"))
        assertTrue(evidenceWorkflow.contains("screenshotUploadRunAttempt"))
        assertTrue(evidenceWorkflow.contains("screenshotSubmissionRunAttempt"))
        assertTrue(blockerReport.contains("expectedPairAlreadyProduction"))
        assertTrue(blockerReport.contains("Play-generated APK signer identity receipt missing or invalid"))
        assertTrue(blockerReport.contains("verify-google-play-generated-apk-evidence.sh"))
        assertTrue(blockerReport.contains("verify-wear-play-screenshot-evidence.py"))
        assertTrue(blockerReport.contains("verify-wear-battery-evidence.py"))
        assertTrue(blockerReport.contains("verify-wear-paired-qa-evidence.py"))
        assertTrue(blockerReport.contains("check-wear-adb-pair-readiness.sh"))
        assertTrue(blockerReport.contains("check-github-wear-release-environments.sh"))
        assertTrue(blockerReport.contains("required protected GitHub Wear release environments"))
        assertTrue(blockerReport.contains("EXPECTED_PAIRED_REVIEWER"))
        assertTrue(blockerReport.contains("EXPECTED_SCREENSHOT_REVIEWER"))
        assertTrue(blockerReport.contains("git ls-remote --tags origin"))
        assertTrue(blockerReport.contains("retained protected paired-QA evidence, not current ADB presence, is the completion gate"))
        assertTrue(blockerReport.contains("verified remote x86_64 Wear CI receipt missing or invalid"))
    }

    @Test
    fun wearDataLayerCapabilities_areStaticallyAdvertisedAndCapabilityChangesAreDelivered() {
        val phoneManifest = readRepoFile("app/src/play/AndroidManifest.xml")
        val phoneCapabilities = readRepoFile("app/src/play/res/values/wear.xml")
        val wearManifest = readRepoFile("wear/src/main/AndroidManifest.xml")
        val wearCapabilities = readRepoFile("wear/src/main/res/values/wear.xml")

        assertTrue(phoneCapabilities.contains("android_wear_capabilities"))
        assertTrue(phoneCapabilities.contains("healthmd_phone_sync"))
        assertTrue(wearCapabilities.contains("android_wear_capabilities"))
        assertTrue(wearCapabilities.contains("healthmd_watch_sync"))
        assertTrue(phoneManifest.contains("com.google.android.gms.wearable.CAPABILITY_CHANGED"))
        assertTrue(phoneManifest.contains("android:scheme=\"wear\" android:host=\"*\""))
        assertTrue(wearManifest.contains("com.google.android.gms.wearable.DATA_CHANGED"))
        assertTrue(wearManifest.contains("com.google.android.gms.wearable.MESSAGE_RECEIVED"))
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

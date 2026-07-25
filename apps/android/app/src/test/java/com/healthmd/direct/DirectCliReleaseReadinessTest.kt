package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import java.io.File
import org.junit.Test

class DirectCliReleaseReadinessTest {
    private fun repoRoot(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            if (File(directory, "settings.gradle.kts").isFile) return directory
            directory = directory.parentFile
        }
        error("Could not locate the Android repository root.")
    }

    private fun read(path: String): String = File(repoRoot(), path).readText()

    @Test
    fun directProtocolModuleAndForegroundServiceAreRegistered() {
        assertThat(read("settings.gradle.kts")).contains("include(\":direct-protocol\")")
        val manifest = read("app/src/main/AndroidManifest.xml")
        assertThat(manifest).contains("android.permission.FOREGROUND_SERVICE_DATA_SYNC")
        assertThat(manifest).contains(".direct.DirectCliForegroundService")
        assertThat(manifest).contains("android:foregroundServiceType=\"dataSync\"")
        assertThat(manifest).contains("android:exported=\"false\"")
    }

    @Test
    fun directCliRemainsManualAndSeparateFromScheduledExportTargets() {
        val targets = read("app/src/main/java/com/healthmd/domain/model/ExportTarget.kt")
        assertThat(targets).doesNotContain("DIRECT_CLI")
        val strategy = read("docs/android-desktop-destination.md")
        assertThat(strategy).contains("not a WorkManager destination")
        assertThat(strategy).contains("manual export path")
    }

    @Test
    fun keystoreGeneratesItsOwnGcmIvAndPairingRefreshesTheScreen() {
        val trustStore = read(
            "app/src/main/java/com/healthmd/direct/DirectCliTrustStore.kt",
        )
        assertThat(trustStore).contains("cipher.init(Cipher.ENCRYPT_MODE, key())")
        assertThat(trustStore).doesNotContain(
            "cipher.init(Cipher.ENCRYPT_MODE, key(), GCMParameterSpec",
        )
        assertThat(trustStore).contains("val nonce = requireNotNull(cipher.iv)")

        val viewModel = read(
            "app/src/main/java/com/healthmd/presentation/directcli/DirectCliViewModel.kt",
        )
        assertThat(viewModel).contains(
            "if (state is DirectCliConnectionState.Completed) refreshTrust()",
        )
    }

    @Test
    fun rustInteropFixtureIsCommittedToTheKotlinModule() {
        val fixture = File(
            repoRoot(),
            "direct-protocol/src/test/resources/rust-direct-v2.json",
        )
        assertThat(fixture.isFile).isTrue()
        assertThat(fixture.readText()).contains("request_fingerprint")
        assertThat(read("direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/InteroperabilityTest.kt"))
            .contains("cryptoMatchesRustVectors")
    }
}

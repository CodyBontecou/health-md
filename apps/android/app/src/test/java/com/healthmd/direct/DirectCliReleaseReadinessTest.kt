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
    fun directCliSessionReconnectsAfterNonTerminalCloses() {
        val coordinator = read(
            "app/src/main/java/com/healthmd/direct/DirectCliCoordinator.kt",
        )
        assertThat(coordinator).contains("RECONNECT_INITIAL_BACKOFF_MILLIS = 250L")
        assertThat(coordinator).contains("RECONNECT_MAXIMUM_BACKOFF_MILLIS = 2_000L")
        assertThat(coordinator).contains("MAXIMUM_CONSECUTIVE_RECONNECT_FAILURES = 6")
        assertThat(coordinator).contains("DirectCliCompletion.SessionFinished")
        assertThat(coordinator).contains("currentCoroutineContext().ensureActive()")
        assertThat(coordinator).contains("wake preflight")
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
    fun directCliUiStateUsesTypedOutcomesInsteadOfArbitraryProse() {
        val paired = DirectCliConnectionState.Completed(
            DirectCliCompletion.Paired("Test listener"),
        )
        val failed = DirectCliConnectionState.Failed(DirectCliFailure.EXPORT_FAILED)

        assertThat(paired.outcome).isEqualTo(DirectCliCompletion.Paired("Test listener"))
        assertThat(failed.reason).isEqualTo(DirectCliFailure.EXPORT_FAILED)

        val screen = read(
            "app/src/main/java/com/healthmd/presentation/directcli/DirectCliScreen.kt",
        )
        assertThat(screen).contains("Formatter.formatFileSize")
        assertThat(screen).doesNotContain("state.message")

        val service = read(
            "app/src/main/java/com/healthmd/direct/DirectCliForegroundService.kt",
        )
        assertThat(service).contains("getString(R.string.direct_cli_notification_title)")
        assertThat(service).doesNotContain("error.message")
    }

    @Test
    fun qrPairingUsesOptionalOpenSourceCameraPathWithoutExternalDeepLinkAuthority() {
        val manifest = read("app/src/main/AndroidManifest.xml")
        assertThat(manifest).contains("android.permission.CAMERA")
        assertThat(manifest).contains("android.hardware.camera.any")
        assertThat(manifest).contains("android:required=\"false\"")
        assertThat(manifest).doesNotContain("android:scheme=\"healthmd\"")

        val build = read("app/build.gradle.kts")
        assertThat(build).contains("libs.androidx.camera.camera2")
        assertThat(build).contains("libs.zxing.core")
        val scanner = read(
            "app/src/main/java/com/healthmd/presentation/directcli/DirectCliPairingScanner.kt",
        )
        assertThat(scanner).contains("ProcessCameraProvider")
        assertThat(scanner).contains("MultiFormatReader")
    }

    @Test
    fun legacyPairingFallbackRequiresTypedRejectionAndChecksCancellation() {
        val coordinator = read(
            "app/src/main/java/com/healthmd/direct/DirectCliCoordinator.kt",
        )
        val pairingFlow = coordinator
            .substringAfter("suspend fun pair(")
            .substringBefore("suspend fun connectAndServe(")
        assertThat(pairingFlow).contains("catch (sharedPairingError: PairingRejectedException)")
        assertThat(pairingFlow).contains("currentCoroutineContext().ensureActive()")
        assertThat(pairingFlow).doesNotContain(": Exception)")
        assertThat(pairingFlow).doesNotContain(": IllegalStateException)")
        assertThat(pairingFlow).doesNotContain(": Throwable)")
    }

    @Test
    fun sharedPairingFixtureIsConsumedByRustSwiftAndKotlin() {
        val fixture = File(
            repoRoot(),
            "../../packages/contracts/direct-protocol/pairing-v3/fixtures/shared-pairing-v3.json",
        ).canonicalFile
        assertThat(fixture.isFile).isTrue()
        assertThat(fixture.readText()).contains("\"pairing_protocol_version\": 3")
        assertThat(read("direct-protocol/build.gradle.kts"))
            .contains("../../packages/contracts/direct-protocol/pairing-v3/fixtures")
        assertThat(read(
            "direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/SharedPairingV3InteropTest.kt",
        )).contains("getResource(\"/shared-pairing-v3.json\")")
    }

    @Test
    fun sharedInteropFixtureIsConsumedByTheKotlinModule() {
        val fixture = File(
            repoRoot(),
            "../../packages/contracts/direct-protocol/v2/fixtures/interop.json",
        ).canonicalFile
        assertThat(fixture.isFile).isTrue()
        assertThat(fixture.readText()).contains("request_fingerprint")
        assertThat(read("direct-protocol/build.gradle.kts"))
            .contains("../../packages/contracts/direct-protocol/v2/fixtures")
        assertThat(read("direct-protocol/src/test/kotlin/com/healthmd/direct/protocol/InteroperabilityTest.kt"))
            .contains("getResource(\"/interop.json\")")
    }
}

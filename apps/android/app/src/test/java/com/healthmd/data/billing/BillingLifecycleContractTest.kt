package com.healthmd.data.billing

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.io.File

class BillingLifecycleContractTest {

    @Test
    fun featureViewModelsCannotCloseTheApplicationScopedBillingClient() {
        val module = readSource("di/BillingModule.kt")
        val contract = readSource("domain/repository/BillingRepository.kt")
        val implementation = readSource("data/billing/BillingRepositoryImpl.kt")
        val paywallViewModel = readSource("presentation/paywall/PaywallViewModel.kt")
        val scheduleViewModel = readSource("presentation/schedule/ScheduleViewModel.kt")

        assertThat(module).contains("@Singleton")
        assertThat(contract).doesNotContain("fun endConnection(")
        assertThat(implementation).doesNotContain("billingClient.endConnection()")
        assertThat(implementation).contains(".enableAutoServiceReconnection()")
        assertThat(paywallViewModel).doesNotContain("billingRepository.endConnection()")
        assertThat(scheduleViewModel).doesNotContain("billingRepository.endConnection()")
    }

    @Test
    fun playBillingDependencyMeetsGooglePlayMinimum() {
        val catalog = File(androidProjectRoot(), "gradle/libs.versions.toml").readText()
        val version = Regex("""(?m)^billing = \"(\d+)\.(\d+)\.(\d+)\"$""")
            .find(catalog)
            ?.groupValues
            ?.drop(1)
            ?.map(String::toInt)

        assertThat(version).isNotNull()
        val (major, minor, patch) = requireNotNull(version)
        assertThat(major > 8 || (major == 8 && (minor > 0 || (minor == 0 && patch >= 0)))).isTrue()
    }

    private fun readSource(relativePath: String): String =
        File(androidProjectRoot(), "app/src/main/java/com/healthmd/$relativePath").readText()

    private fun androidProjectRoot(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            if (File(directory, "app/build.gradle.kts").exists()) return directory
            directory = directory.parentFile
        }
        error("Could not locate Android project root")
    }
}

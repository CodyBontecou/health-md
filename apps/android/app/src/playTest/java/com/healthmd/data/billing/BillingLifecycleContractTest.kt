package com.healthmd.data.billing

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.io.File

class BillingLifecycleContractTest {

    @Test
    fun applicationScopedClientUsesBillingManagedReconnection() {
        val module = readSource("di/BillingModule.kt")
        val contract = readSource("domain/repository/EntitlementRepository.kt") +
            readSource("domain/repository/PurchaseRepository.kt")
        val implementation = readSource("data/billing/BillingRepositoryImpl.kt")
        val paywallViewModel = readSource("presentation/paywall/PaywallViewModel.kt")
        val scheduleViewModel = readSource("presentation/schedule/ScheduleViewModel.kt")
        val disconnectedCallback = implementation
            .substringAfter("override fun onBillingServiceDisconnected()")
            .substringBefore("        })")

        assertThat(module).contains("@Singleton")
        assertThat(contract).doesNotContain("fun endConnection(")
        assertThat(implementation).doesNotContain("billingClient.endConnection()")
        assertThat(implementation).contains(".enableAutoServiceReconnection()")
        assertThat(implementation).doesNotContain("if (!billingClient.isReady)")
        assertThat(disconnectedCallback).doesNotContain("startConnection()")
        assertThat(implementation).contains("_productDetails.value = null")
        assertThat(paywallViewModel).doesNotContain("billingRepository.endConnection()")
        assertThat(scheduleViewModel).doesNotContain("billingRepository.endConnection()")
    }

    @Test
    fun playBillingDependencyIsAtLeastVersionEight() {
        val catalog = File(androidProjectRoot(), "gradle/libs.versions.toml").readText()
        val version = Regex("""(?m)^billing = "(\d+)\.(\d+)\.(\d+)"$""")
            .find(catalog)
            ?.groupValues
            ?.drop(1)
            ?.map(String::toInt)

        assertThat(version).isNotNull()
        assertThat(requireNotNull(version).first()).isAtLeast(8)
    }

    private fun readSource(relativePath: String): String {
        val root = androidProjectRoot()
        return listOf(
            File(root, "app/src/main/java/com/healthmd/$relativePath"),
            File(root, "app/src/play/java/com/healthmd/$relativePath"),
        ).firstOrNull(File::isFile)?.readText()
            ?: error("Missing production source: $relativePath")
    }

    private fun androidProjectRoot(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            if (File(directory, "app/build.gradle.kts").exists()) return directory
            directory = directory.parentFile
        }
        error("Could not locate Android project root")
    }
}

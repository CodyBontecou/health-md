package com.healthmd.distribution

import android.app.Activity
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.access.FdroidAccessRepository
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.data.health.providers.HealthProviderId
import com.healthmd.domain.distribution.DistributionChannel
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.export.ExportAccountingPolicy
import com.healthmd.domain.model.ExportResult
import com.healthmd.presentation.onboarding.OnboardingPage
import com.healthmd.presentation.onboarding.onboardingPages
import io.mockk.mockk
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Test

class FdroidDistributionPolicyTest {
    private val policy = DistributionPolicy.fdroid()

    @Test
    fun channelIncludesFullAccessAndNoPlayIntegrations() {
        assertThat(policy.channel).isEqualTo(DistributionChannel.FDROID)
        assertThat(policy.fullAccessIncluded).isTrue()
        assertThat(policy.purchasesAvailable).isFalse()
        assertThat(policy.reviewPromptAvailable).isFalse()
        assertThat(policy.campaignAttributionEnabled).isFalse()
        assertThat(policy.onboardingAnalyticsEnabled).isFalse()
        assertThat(policy.wearSyncAvailable).isFalse()
        assertThat(policy.directCloudProvidersAvailable).isFalse()
    }

    @Test
    fun entitlementIsStableAndPurchaseActionsAreUnavailable() = runTest {
        val repository = FdroidAccessRepository()

        repeat(11) {
            assertThat(repository.isUnlocked.value).isTrue()
            assertThat(
                ExportAccountingPolicy.shouldConsumeFreeExport(
                    ExportResult(successCount = 1, totalCount = 1),
                    isPurchased = repository.isUnlocked.value,
                ),
            ).isFalse()
        }
        assertThat(repository.isAvailable).isFalse()
        assertThat(repository.offer.value).isNull()
        assertThat(repository.launchPurchase(mockk<Activity>(relaxed = true))).isFalse()
        assertThat(repository.restorePurchase()).isFalse()
    }

    @Test
    fun onboardingUsesIncludedAccessStepInsteadOfPaywall() {
        val pages = onboardingPages(policy)

        assertThat(pages).contains(OnboardingPage.INCLUDED_ACCESS)
        assertThat(pages).doesNotContain(OnboardingPage.PLAY_ACCESS)
    }

    @Test
    fun providerCatalogContainsOnlyHealthConnect() {
        val catalog = HealthProviderCatalog(
            context = mockk(relaxed = true),
            definitions = listOf(HealthProviderCatalog.healthConnectDefinition()),
        )

        assertThat(catalog.definitions.map { it.id })
            .containsExactly(HealthProviderId.HEALTH_CONNECT)
    }

    @Test
    fun commonProductionSourceDoesNotImportChannelSpecificIntegrations() {
        val appRoot = locateAppRoot()
        val commonSource = File(appRoot, "src/main/java")
            .walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .joinToString("\n") { it.readText() }

        listOf(
            "com.android.billingclient",
            "com.android.installreferrer",
            "com.google.android.play",
            "com.google.android.gms.wearable",
            "com.healthmd.data.health.oauth",
            "com.healthmd.data.health.providers.cloud",
            "com.healthmd.data.health.providers.direct",
            "com.healthmd.rawexport.CloudRawHealthDataProvider",
            "com.healthmd.data.attribution",
            "com.healthmd.data.onboardinganalytics",
            "com.healthmd.wear",
        ).forEach { forbidden ->
            assertThat(commonSource).doesNotContain(forbidden)
        }

        val directCoordinator = File(
            appRoot,
            "src/main/java/com/healthmd/direct/DirectCliCoordinator.kt",
        ).readText()
        assertThat(directCoordinator).doesNotContain("\"fitbit\"")
        assertThat(directCoordinator).doesNotContain("Fitbit raw export")
    }

    @Test
    fun commonBackupRulesContainNoPlayOnlyStateNames() {
        val appRoot = locateAppRoot()
        val commonBackupRules = listOf(
            "src/main/res/xml/backup_rules.xml",
            "src/main/res/xml/data_extraction_rules.xml",
        ).joinToString("\n") { relativePath -> File(appRoot, relativePath).readText() }

        listOf(
            "health_md_oauth_tokens",
            "wear-sync-private",
            "campaign_attribution",
            "onboarding_analytics",
        ).forEach { forbidden ->
            assertThat(commonBackupRules).doesNotContain(forbidden)
        }
    }

    private fun locateAppRoot(): File {
        var current: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (current != null) {
            val candidate = File(current, "app/src/main")
            if (candidate.isDirectory) return File(current, "app")
            current = current.parentFile
        }
        error("Could not locate Android app module")
    }
}

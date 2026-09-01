package com.healthmd.data.health.providers

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import io.mockk.mockk
import org.junit.Test

class HealthProviderCatalogTest {

    @Test
    fun providerCatalog_includesSupportedProvidersAndExcludesGoogleFit() {
        val catalog = HealthProviderCatalog(
            context = mockk<Context>(relaxed = true),
            definitions = PlayHealthProviderDefinitions.all(),
        )
        val definitions = catalog.definitions

        val displayNames = definitions.map { it.displayName }
        assertThat(displayNames).containsAtLeast(
            "Samsung Health",
            "Huawei Health",
            "Fitbit",
            "Garmin Connect",
            "Withings",
            "Oura",
            "Polar Flow",
            "WHOOP",
        )
        assertThat(displayNames).doesNotContain("Google Fit")

        val knownPackageNames = definitions.flatMap { definition ->
            definition.packageNames + listOfNotNull(definition.setupPackageName)
        }
        assertThat(knownPackageNames).doesNotContain("com.google.android.apps.fitness")
        assertThat(knownPackageNames).doesNotContain("com.google.android.gms")
    }

    @Test
    fun providerCatalog_usesResourceBackedPresentationMetadata() {
        val definitions = HealthProviderCatalog(
            context = mockk<Context>(relaxed = true),
            definitions = PlayHealthProviderDefinitions.all(),
        ).definitions

        assertThat(definitions.map { it.summaryRes }).doesNotContain(0)
        assertThat(definitions.map { it.setupDescriptionRes }).doesNotContain(0)
        assertThat(definitions.map { it.integrationKind.labelRes }).doesNotContain(0)
        assertThat(definitions.map { it.directExportStatus.labelRes }).doesNotContain(0)
    }

    @Test
    fun providerState_actionLabelDependsOnlyOnInstalledState() {
        val definition = HealthProviderCatalog(
            context = mockk<Context>(relaxed = true),
            definitions = PlayHealthProviderDefinitions.all(),
        ).definitions
            .first()

        assertThat(
            HealthProviderState(
                definition = definition,
                installedPackageName = definition.setupPackageName,
                isInstalled = true,
                setupIntent = null,
            ).actionLabelRes
        ).isEqualTo(R.string.health_provider_action_open)
        assertThat(
            HealthProviderState(
                definition = definition,
                installedPackageName = null,
                isInstalled = false,
                setupIntent = null,
            ).actionLabelRes
        ).isEqualTo(R.string.health_provider_action_install_setup)
    }
}

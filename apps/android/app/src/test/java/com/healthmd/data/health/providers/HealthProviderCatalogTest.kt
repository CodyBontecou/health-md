package com.healthmd.data.health.providers

import android.content.Context
import com.google.common.truth.Truth.assertThat
import io.mockk.mockk
import org.junit.Test

class HealthProviderCatalogTest {

    @Test
    fun providerCatalog_includesSupportedProvidersAndExcludesGoogleFit() {
        val catalog = HealthProviderCatalog(context = mockk<Context>(relaxed = true))
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
}

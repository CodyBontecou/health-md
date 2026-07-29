package com.healthmd.domain.registry

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.healthmd.core.CoreMetricRegistryProfile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HealthMdCoreRegistryAdapterInstrumentationTest {
    @Test
    fun packagedRustProfilesMatchGeneratedNativeCatalogExactly() {
        val frozen = HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_FROZEN_V4)
        val analytical = HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5)

        assertTrue(HealthMdCoreRegistryAdapter.shadowDifferences(frozen).isEmpty())
        assertTrue(HealthMdCoreRegistryAdapter.shadowDifferences(analytical).isEmpty())
        assertEquals(frozen.metrics.map { it.selectionId }, analytical.metrics.map { it.selectionId })
        assertEquals(132, frozen.outputs.count { it.enabledByDefault })
        assertEquals(148, analytical.outputs.count { it.enabledByDefault })
        assertEquals(13, frozen.outputs.count { it.aliasKind == "legacy_android" })
    }

    @Test
    fun adapterRejectsCrossPairedProfileMetadata() {
        val frozen = HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_FROZEN_V4)
        val rejected = runCatching {
            HealthMdCoreRegistryAdapter.definitions(
                frozen.copy(
                    publicProfileId = "android-analytical-v5",
                    publicSchemaVersion = 5u,
                ),
            )
        }

        assertTrue(rejected.isFailure)
    }
}

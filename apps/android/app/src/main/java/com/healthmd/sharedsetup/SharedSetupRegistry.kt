package com.healthmd.sharedsetup

import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.domain.registry.HealthMdCoreRegistryAdapter

/** Registry-backed metric translation. Labels and categories are never translation authority. */
data class SharedSetupRegistryBinding(
    val semanticId: String,
    val appleSelectionId: String?,
    val androidSelectionId: String?,
    val equivalence: String,
)

interface SharedSetupMetricRegistry {
    val version: Int
    val sha256: String
    val bySemanticId: Map<String, SharedSetupRegistryBinding>
    val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding>
}

class AndroidSharedSetupMetricRegistry : SharedSetupMetricRegistry {
    private val android = HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5)
    private val apple = HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.APPLE_HEALTH_DATA_V8)

    init {
        require(android.registryVersion == apple.registryVersion && android.registrySha256 == apple.registrySha256) {
            "Apple and Android metric registry snapshots must share one pinned identity"
        }
    }

    override val version: Int = android.registryVersion.toInt()
    override val sha256: String = android.registrySha256
    override val bySemanticId: Map<String, SharedSetupRegistryBinding> = buildMap {
        val androidBySemantic = android.metrics.associateBy { it.semanticId }
        apple.metrics.forEach { appleMetric ->
            val androidMetric = androidBySemantic[appleMetric.semanticId]
            val canonical = androidMetric?.let {
                requireNotNull(ANDROID_SHARED_SETUP_ALIASES[appleMetric.semanticId]) {
                    "Canonical alias missing for ${appleMetric.semanticId}"
                }
            }
            if (canonical != null) {
                require(canonical.appleSelectionId == appleMetric.selectionId && canonical.androidSelectionId == androidMetric?.selectionId) {
                    "Generated alias disagrees with the shared-core registry for ${appleMetric.semanticId}"
                }
            }
            put(
                appleMetric.semanticId,
                SharedSetupRegistryBinding(
                    semanticId = appleMetric.semanticId,
                    appleSelectionId = appleMetric.selectionId,
                    androidSelectionId = androidMetric?.selectionId,
                    equivalence = canonical?.equivalence ?: "platform_exact_or_unavailable",
                ),
            )
        }
        android.metrics.filterNot { containsKey(it.semanticId) }.forEach { androidMetric ->
            val canonical = requireNotNull(ANDROID_SHARED_SETUP_ALIASES[androidMetric.semanticId]) {
                "Canonical alias missing for ${androidMetric.semanticId}"
            }
            require(canonical.appleSelectionId == null && canonical.androidSelectionId == androidMetric.selectionId) {
                "Generated alias disagrees with the shared-core registry for ${androidMetric.semanticId}"
            }
            put(
                androidMetric.semanticId,
                SharedSetupRegistryBinding(
                    semanticId = androidMetric.semanticId,
                    appleSelectionId = null,
                    androidSelectionId = androidMetric.selectionId,
                    equivalence = canonical.equivalence,
                ),
            )
        }
    }
    override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> =
        bySemanticId.values.mapNotNull { binding ->
            binding.androidSelectionId?.let { it to binding }
        }.toMap()
}

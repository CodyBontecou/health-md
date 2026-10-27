// HOST ONLY replacement for core-backed registry wiring. No success validator stub:
// compile/run the unchanged real SharedSetupV2Codec + real serializable v2 DTOs.
package com.healthmd.sharedsetup

data class SharedSetupRegistryBinding(val semanticId: String, val appleSelectionId: String?, val androidSelectionId: String?, val equivalence: String)
interface SharedSetupMetricRegistry {
    val version: Int
    val sha256: String
    val bySemanticId: Map<String, SharedSetupRegistryBinding>
    val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding>
}
class AndroidSharedSetupMetricRegistry : SharedSetupMetricRegistry {
    init { error("Host must inject byte-pinned registry evidence; real UniFFI adapter is unqualified here") }
    override val version: Int get() = error("not available")
    override val sha256: String get() = error("not available")
    override val bySemanticId: Map<String, SharedSetupRegistryBinding> get() = error("not available")
    override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> get() = error("not available")
}

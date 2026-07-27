package com.healthmd.domain.registry

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.rawexport.HealthConnectRecordCatalog
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.io.File

class SharedMetricRegistryContractTest {
    private val registry by lazy {
        Json.parseToJsonElement(registryFile().readText()).jsonObject
    }

    @Test
    fun generatedNativeCatalogMatchesRustOrderIdsCategoriesUnitsAndDefaults() {
        val androidBindings = registry.getValue("metrics").jsonArray
            .map { it.jsonObject }
            .map { semantic -> semantic to semantic.getValue("android").jsonObject }
            .filter { (_, binding) -> binding.getValue("status").jsonPrimitive.content == "backed" }
            .sortedBy { (_, binding) -> binding.getValue("ordinal").jsonPrimitive.content.toInt() }

        assertThat(androidBindings).hasSize(106)
        androidBindings.zip(HealthMetrics.allMetrics).forEach { (registryRow, native) ->
            val binding = registryRow.second
            assertThat(binding.getValue("selection_id").jsonPrimitive.content).isEqualTo(native.id)
            assertThat(binding.getValue("category_id").jsonPrimitive.content.uppercase())
                .isEqualTo(native.category.name)
            assertThat(binding.getValue("unit").jsonPrimitive.content).isEqualTo(native.unit)
            assertThat(binding.getValue("default_enabled").jsonPrimitive.content).isEqualTo("true")
        }
    }

    @Test
    fun clinicallyDistinctHrvAndNativeAggregationsAreExplicit() {
        val semanticRows = registry.getValue("metrics").jsonArray
            .map { it.jsonObject }
            .associateBy { it.getValue("semantic_id").jsonPrimitive.content }
        val appleHrv = semanticRows.getValue("hrv")
        val androidHrv = semanticRows.getValue("android.hrv_rmssd")

        assertThat(appleHrv.getValue("apple").jsonObject.getValue("source_selector").jsonPrimitive.content)
            .isEqualTo("HKQuantityTypeIdentifierHeartRateVariabilitySDNN")
        assertThat(appleHrv.getValue("android").jsonObject.getValue("status").jsonPrimitive.content)
            .isEqualTo("unavailable")
        assertThat(androidHrv.getValue("android").jsonObject.getValue("selection_id").jsonPrimitive.content)
            .isEqualTo("hrv")
        assertThat(androidHrv.getValue("android").jsonObject.getValue("related_semantic_ids").jsonArray
            .map { it.jsonPrimitive.content }).containsExactly("hrv")

        val aggregations = semanticRows.values
            .map { it.getValue("android").jsonObject }
            .filter { it.getValue("status").jsonPrimitive.content == "backed" }
            .associate {
                it.getValue("selection_id").jsonPrimitive.content to
                    it.getValue("source_aggregation").jsonPrimitive.content
            }
        assertThat(aggregations).containsAtLeast(
            "walking_hr", "average",
            "hrv", "latest",
            "body_temp", "average",
            "skin_temperature", "average",
        )
    }

    @Test
    fun nativeCapabilitySelectorsMatchOpaqueRegistryAvailabilityKeys() {
        val nativeAvailability = buildMap {
            HealthConnectRecordCatalog.records.forEach { descriptor ->
                descriptor.metricIds.forEach { metricId ->
                    put(metricId, descriptor.featureName ?: "baseline")
                }
            }
            put("medical_resources", "personal_health_records")
        }
        val registryAvailability = registry.getValue("metrics").jsonArray
            .map { it.jsonObject.getValue("android").jsonObject }
            .filter { it.getValue("status").jsonPrimitive.content == "backed" }
            .associate {
                it.getValue("selection_id").jsonPrimitive.content to
                    it.getValue("availability_key").jsonPrimitive.content
            }

        assertThat(nativeAvailability.keys).containsAtLeastElementsIn(registryAvailability.keys)
        assertThat(registryAvailability).isEqualTo(nativeAvailability.filterKeys(registryAvailability::containsKey))
    }

    @Test
    fun profileOutputsAndUnavailableIdentitiesMatchNativePresentationAdapters() {
        val profiles = registry.getValue("profiles").jsonArray.map { it.jsonObject }
        val frozen = profiles.single { it.getValue("id").jsonPrimitive.content == "android_frozen_v4" }
        val analytical = profiles.single { it.getValue("id").jsonPrimitive.content == "android_analytical_v5" }
        val frozenOutputs = frozen.getValue("outputs").jsonArray.map { it.jsonObject }
        val analyticalOutputs = analytical.getValue("outputs").jsonArray.map { it.jsonObject }

        assertThat(frozenOutputs.map { it.getValue("key").jsonPrimitive.content })
            .isEqualTo(HealthDataFields.allKeys)
        assertThat(analyticalOutputs.map { it.getValue("key").jsonPrimitive.content })
            .isEqualTo(HealthDataFields.allKeys)
        assertThat(frozenOutputs.count { it.getValue("enabled_by_default").jsonPrimitive.content == "true" })
            .isEqualTo(132)
        assertThat(analyticalOutputs.count { it.getValue("enabled_by_default").jsonPrimitive.content == "true" })
            .isEqualTo(148)
        assertThat(frozenOutputs.count { it.getValue("alias_kind").jsonPrimitive.content == "legacy_android" })
            .isEqualTo(13)

        val unavailable = registry.getValue("legacy_unavailable").jsonObject
            .getValue("android").jsonArray
            .map { it.jsonObject }
        assertThat(unavailable).hasSize(HealthMetrics.unavailableMetrics.size)
        unavailable.zip(HealthMetrics.unavailableMetrics).forEach { (registryRow, native) ->
            assertThat(registryRow.getValue("selection_id").jsonPrimitive.content).isEqualTo(native.id)
            assertThat(registryRow.getValue("category_id").jsonPrimitive.content.uppercase())
                .isEqualTo(native.category.name)
            assertThat(registryRow.getValue("label_key").jsonPrimitive.content).isEqualTo(native.id)
            assertThat(registryRow.getValue("reference_name").jsonPrimitive.content).isEqualTo(native.displayName)
            assertThat(registryRow.getValue("reason").jsonPrimitive.content).isEqualTo(native.reason)
            assertThat(registryRow.getValue("reason_key").jsonPrimitive.content)
                .isEqualTo("metric_unavailable_${native.id}")
        }
    }

    private fun registryFile(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val candidate = File(
                directory,
                "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json",
            )
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }
        error("Could not locate shared Rust metric registry")
    }
}

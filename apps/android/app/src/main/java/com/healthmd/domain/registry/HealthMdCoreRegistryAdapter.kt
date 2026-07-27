package com.healthmd.domain.registry

import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.domain.model.HealthMetricDefinition
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.HEALTHMD_CORE_REGISTRY_SHA256

/**
 * Native presentation/capability adapter for the shared Rust registry.
 *
 * Health Connect record classes, feature detection, permissions, persistence, and localized
 * resources remain Kotlin-owned. One coarse immutable snapshot is loaded and cached by callers.
 */
object HealthMdCoreRegistryAdapter {
    fun snapshot(
        profile: CoreMetricRegistryProfile,
        service: HealthMdCoreService = HealthMdCoreService(),
    ): CoreMetricRegistrySnapshot = service.getMetricRegistry(profile)

    fun definitions(snapshot: CoreMetricRegistrySnapshot): List<HealthMetricDefinition> {
        when (snapshot.profileId) {
            "android_frozen_v4" -> {
                require(snapshot.publicProfileId == "android-frozen-v4")
                require(snapshot.publicSchemaVersion == 4u)
            }
            "android_analytical_v5" -> {
                require(snapshot.publicProfileId == "android-analytical-v5")
                require(snapshot.publicSchemaVersion == 5u)
            }
            else -> error("Unsupported shared-core registry profile")
        }
        require(snapshot.publicSchema == "healthmd.health_data")
        require(snapshot.registryVersion == 1u)
        require(snapshot.profileRevision == 1u)
        require(snapshot.registrySha256 == HEALTHMD_CORE_REGISTRY_SHA256)
        require(snapshot.metrics.size == 106)
        return snapshot.metrics.mapIndexed { index, metric ->
            require(metric.ordinal == index.toUInt())
            HealthMetricDefinition(
                id = metric.selectionId,
                category = category(metric.categoryId),
                unit = metric.unit,
            )
        }
    }

    /** Health-free JSON-pointer-style differences for shadow rollout diagnostics. */
    fun shadowDifferences(
        snapshot: CoreMetricRegistrySnapshot,
        nativeDefinitions: List<HealthMetricDefinition> = HealthMetrics.allMetrics,
    ): List<String> = buildList {
        val rustDefinitions = runCatching { definitions(snapshot) }.getOrElse {
            add("/registry/invalid_metadata")
            return@buildList
        }
        if (rustDefinitions.size != nativeDefinitions.size) add("/metrics/count")
        rustDefinitions.zip(nativeDefinitions).forEachIndexed { index, (rust, native) ->
            val prefix = "/metrics/$index"
            if (rust.id != native.id) add("$prefix/selection_id")
            if (rust.category != native.category) add("$prefix/category_id")
            if (rust.unit != native.unit) add("$prefix/unit")
        }
        val nativeUnavailable = HealthMetrics.unavailableMetrics
        if (snapshot.unavailableMetrics.size != nativeUnavailable.size) {
            add("/unavailable_metrics/count")
        }
        snapshot.unavailableMetrics.zip(nativeUnavailable).forEachIndexed { index, (rust, native) ->
            val prefix = "/unavailable_metrics/$index"
            if (rust.selectionId != native.id) add("$prefix/selection_id")
            if (category(rust.categoryId) != native.category) add("$prefix/category_id")
            if (rust.labelKey != native.id) add("$prefix/label_key")
            if (rust.reasonKey != "metric_unavailable_${native.id}") add("$prefix/reason_key")
        }
        if (snapshot.outputs.map { it.key } != HealthDataFields.allKeys) add("/outputs/flat")
        if (snapshot.outputs.map { it.ordinal } != snapshot.outputs.indices.map { it.toUInt() }) {
            add("/outputs/order")
        }
    }

    private fun category(value: String): HealthMetricCategory = when (value) {
        "Sleep" -> HealthMetricCategory.SLEEP
        "Activity" -> HealthMetricCategory.ACTIVITY
        "Heart" -> HealthMetricCategory.HEART
        "Respiratory" -> HealthMetricCategory.RESPIRATORY
        "Vitals" -> HealthMetricCategory.VITALS
        "Body" -> HealthMetricCategory.BODY
        "Nutrition" -> HealthMetricCategory.NUTRITION
        "Mobility" -> HealthMetricCategory.MOBILITY
        "Cycling" -> HealthMetricCategory.CYCLING
        "Hearing" -> HealthMetricCategory.HEARING
        "Mindfulness" -> HealthMetricCategory.MINDFULNESS
        "Reproductive" -> HealthMetricCategory.REPRODUCTIVE
        "Symptoms" -> HealthMetricCategory.SYMPTOMS
        "Medications" -> HealthMetricCategory.MEDICATIONS
        "Other" -> HealthMetricCategory.OTHER
        "Workouts" -> HealthMetricCategory.WORKOUTS
        else -> error("Invalid shared-core category metadata")
    }
}

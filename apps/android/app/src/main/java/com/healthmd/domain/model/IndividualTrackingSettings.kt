package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.time.LocalDate

@Serializable
data class MetricTrackingConfig(
    val trackIndividually: Boolean = false,
    val customFolder: String? = null,
)

@Serializable
data class IndividualTrackingSettings(
    val globalEnabled: Boolean = false,
    /**
     * Legacy Android v1 list. Kept so saved settings that only contain `enabledMetrics` decode
     * cleanly; new mutations keep it in sync with [metricConfigs].
     */
    val enabledMetrics: Set<String> = emptySet(),
    val metricConfigs: Map<String, MetricTrackingConfig> = emptyMap(),
    val entriesFolder: String = "entries",
    val organizeByCategory: Boolean = true,
    val filenameTemplate: String = "{metric}-{date}-{time}",
) {
    val trackedMetricIds: Set<String>
        get() = migratedMetricIds(rawTrackedMetricIds)

    val trackedMetricCount: Int
        get() = trackedMetricIds.count { it in HealthMetrics.allMetrics.map { metric -> metric.id }.toSet() }

    val requiresGranularData: Boolean
        get() = globalEnabled && trackedMetricIds.any { it in GRANULAR_TRACKING_METRICS }

    fun isMetricEnabled(metricId: String): Boolean = metricId in trackedMetricIds

    fun shouldTrackIndividually(metricId: String): Boolean = globalEnabled && isMetricEnabled(metricId)

    fun shouldTrackAny(vararg metricIds: String): Boolean = globalEnabled && metricIds.any { isMetricEnabled(it) }

    fun configFor(metricId: String): MetricTrackingConfig {
        val direct = metricConfigs[metricId]
        if (direct != null) return direct
        val legacyKey = when (metricId) {
            "bp_systolic", "bp_diastolic" -> "blood_pressure"
            else -> metricId
        }
        return if (legacyKey in enabledMetrics) MetricTrackingConfig(trackIndividually = true) else MetricTrackingConfig()
    }

    fun enableAll(allMetrics: List<String> = HealthMetrics.allMetrics.map { it.id }): IndividualTrackingSettings =
        withTrackedMetricIds(allMetrics.toSet())

    fun disableAll(): IndividualTrackingSettings = copy(enabledMetrics = emptySet(), metricConfigs = emptyMap())

    fun enableSuggested(): IndividualTrackingSettings = withTrackedMetricIds(suggestedMetrics)

    fun toggleMetric(metric: String): IndividualTrackingSettings {
        val normalized = migratedMetricIds(setOf(metric))
        val currentlyEnabled = normalized.any { it in trackedMetricIds }
        val next = if (currentlyEnabled) trackedMetricIds - normalized else trackedMetricIds + normalized
        return withTrackedMetricIds(next)
    }

    fun enableCategory(category: HealthMetricCategory): IndividualTrackingSettings {
        val metricIds = HealthMetrics.metricsForCategory(category).map { it.id }.toSet()
        return withTrackedMetricIds(trackedMetricIds + metricIds)
    }

    fun disableCategory(category: HealthMetricCategory): IndividualTrackingSettings {
        val metricIds = HealthMetrics.metricsForCategory(category).map { it.id }.toSet()
        return withTrackedMetricIds(trackedMetricIds - metricIds)
    }

    fun toggleCategory(category: HealthMetricCategory): IndividualTrackingSettings =
        if (isCategoryFullyEnabled(category)) disableCategory(category) else enableCategory(category)

    fun enabledCountForCategory(category: HealthMetricCategory): Int =
        HealthMetrics.metricsForCategory(category).count { it.id in trackedMetricIds }

    fun totalMetricCount(category: HealthMetricCategory): Int =
        HealthMetrics.metricsForCategory(category).size

    fun isCategoryFullyEnabled(category: HealthMetricCategory): Boolean {
        val total = totalMetricCount(category)
        return total > 0 && enabledCountForCategory(category) == total
    }

    fun isCategoryPartiallyEnabled(category: HealthMetricCategory): Boolean {
        val total = totalMetricCount(category)
        val enabled = enabledCountForCategory(category)
        return total > 0 && enabled in 1 until total
    }

    fun relativePathFor(
        metricId: String,
        metricSlug: String,
        category: HealthMetricCategory,
        date: LocalDate,
        time: String,
    ): String {
        val categoryFolder = category.folderName()
        val safeMetric = metricSlug.toPathSegment()
        val filename = filenameTemplate
            .replace("{metric}", safeMetric)
            .replace("{date}", date.toString())
            .replace("{time}", time)
            .replace("{category}", categoryFolder)
            .let { if (it.endsWith(".md", ignoreCase = true)) it else "$it.md" }
            .toPathSegment(allowDot = true)

        val customFolder = configFor(metricId).customFolder?.trim('/')?.takeIf { it.isNotBlank() }
        val folder = customFolder ?: categoryFolder.takeIf { organizeByCategory }
        return joinRelativePath(entriesFolder.trim('/'), folder, filename)
    }

    private fun withTrackedMetricIds(metricIds: Set<String>): IndividualTrackingSettings {
        val migrated = migratedMetricIds(metricIds)
        val nextConfigs = migrated.associateWith { metricId ->
            configFor(metricId).copy(trackIndividually = true)
        }
        return copy(enabledMetrics = migrated, metricConfigs = nextConfigs)
    }

    private val rawTrackedMetricIds: Set<String>
        get() = buildSet {
            addAll(enabledMetrics)
            metricConfigs.forEach { (metricId, config) ->
                if (config.trackIndividually) add(metricId)
            }
        }

    companion object {
        val suggestedMetrics = setOf(
            "workouts",
            "bp_systolic",
            "bp_diastolic",
            "blood_glucose",
            "weight",
            "steps",
            "avg_hr",
            "hrv",
            "blood_oxygen",
            "respiratory_rate",
            "body_temp",
            "sleep_total",
            "mindful_sessions",
        )

        fun isSuggested(metricId: String): Boolean = metricId in suggestedMetrics

        private val GRANULAR_TRACKING_METRICS = setOf(
            "steps",
            "avg_hr",
            "min_hr",
            "max_hr",
            "walking_hr",
            "hrv",
            "blood_oxygen",
            "respiratory_rate",
            "body_temp",
            "bp_systolic",
            "bp_diastolic",
            "blood_glucose",
            "sleep_total",
            "sleep_deep",
            "sleep_rem",
            "sleep_light",
            "sleep_awake",
            "sleep_in_bed",
            "mindful_minutes",
            "mindful_sessions",
            "workouts",
        )

        private fun migratedMetricIds(metricIds: Set<String>): Set<String> = buildSet {
            metricIds.forEach { metricId ->
                when (metricId) {
                    "blood_pressure" -> {
                        add("bp_systolic")
                        add("bp_diastolic")
                    }
                    "blood_pressure_systolic" -> add("bp_systolic")
                    "blood_pressure_diastolic" -> add("bp_diastolic")
                    "mindful_minutes" -> add("mindful_minutes")
                    else -> add(metricId)
                }
            }
        }
    }
}

fun HealthMetricCategory.folderName(): String = when (this) {
    HealthMetricCategory.SLEEP -> "sleep"
    HealthMetricCategory.ACTIVITY -> "activity"
    HealthMetricCategory.HEART -> "heart"
    HealthMetricCategory.RESPIRATORY -> "respiratory"
    HealthMetricCategory.VITALS -> "vitals"
    HealthMetricCategory.BODY -> "body"
    HealthMetricCategory.NUTRITION -> "nutrition"
    HealthMetricCategory.MOBILITY -> "mobility"
    HealthMetricCategory.HEARING -> "hearing"
    HealthMetricCategory.MINDFULNESS -> "mindfulness"
    HealthMetricCategory.REPRODUCTIVE -> "reproductive"
    HealthMetricCategory.SYMPTOMS -> "symptoms"
    HealthMetricCategory.WORKOUTS -> "workouts"
}

private fun String.toPathSegment(allowDot: Boolean = false): String {
    val allowed = map { char ->
        when {
            char.isLetterOrDigit() -> char
            char == '-' || char == '_' || (allowDot && char == '.') -> char
            else -> '-'
        }
    }.joinToString("")
        .trim('-', '_', '.')
        .replace(Regex("-+"), "-")
    return allowed.ifBlank { "entry" }
}

private fun joinRelativePath(vararg parts: String?): String {
    val cleaned = mutableListOf<String>()
    for (part in parts) {
        val normalized = part?.trim('/')?.takeIf { it.isNotBlank() } ?: continue
        if (cleaned.isNotEmpty()) {
            val current = cleaned.joinToString("/")
            if (normalized == current || normalized.startsWith("$current/")) {
                cleaned.clear()
                cleaned.addAll(normalized.split('/').filter { it.isNotBlank() })
                continue
            }
        }
        cleaned.addAll(normalized.split('/').filter { it.isNotBlank() })
    }
    return cleaned.joinToString("/")
}

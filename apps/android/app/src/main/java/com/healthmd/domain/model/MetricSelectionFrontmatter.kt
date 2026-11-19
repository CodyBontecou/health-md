package com.healthmd.domain.model

// Metric selection and Format → Custom frontmatter fields (iOS `ExportSettingsSnapshot`
// `setMetricSelection`, `enableFrontmatterFields` and `writesFrontmatter`).

/**
 * Replaces the metric selection. A metric turned on also turns on its frontmatter fields: a note
 * writes a field only when its metric is selected *and* the field is on in Format → Custom, so a
 * field switched off there earlier silently dropped a metric the user had just picked. Fields of
 * metrics that stay on, or are turned off, are unchanged, so Format → Custom still trims a
 * metric's fields (for example Workouts').
 */
fun ExportSettings.withMetricSelection(selection: MetricSelectionState): ExportSettings {
    val newlyEnabled = selection.enabledMetrics - metricSelection.enabledMetrics
    return copy(metricSelection = selection).withFrontmatterFieldsEnabled(newlyEnabled)
}

/** Turns on every Format → Custom field of the given metrics. */
fun ExportSettings.withFrontmatterFieldsEnabled(metricIds: Iterable<String>): ExportSettings {
    val keys = metricIds.flatMapTo(mutableSetOf()) { HealthDataFields.frontmatterKeys(it) }
    val config = formatCustomization.frontmatterConfig
    if (config.fields.none { !it.isEnabled && it.originalKey in keys }) return this
    val fields = config.fields.map { if (it.originalKey in keys) it.copy(isEnabled = true) else it }
    return copy(formatCustomization = formatCustomization.copy(frontmatterConfig = config.copy(fields = fields)))
}

/**
 * Whether [metricId] reaches a daily note's frontmatter: it is selected and at least one of its
 * fields is on in Format → Custom (a field missing from the list counts as on, as in export).
 */
fun ExportSettings.writesFrontmatter(metricId: String): Boolean {
    if (!metricSelection.isEnabled(metricId)) return false
    val keys = HealthDataFields.frontmatterKeys(metricId)
    if (keys.isEmpty()) return true
    val config = formatCustomization.frontmatterConfig
    return keys.any { config.isFieldEnabled(it) }
}

package com.healthmd.data.export

import com.healthmd.domain.model.*

class ObsidianBasesExporter {

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter
        val fmConfig = customization.frontmatterConfig

        return buildString {
            append("---\n")
            if (customization.compatibilitySchemaProfile == CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5) {
                append("healthmd_schema_profile: android-analytical-v5\n")
            }
            if (fmConfig.includeDate) {
                append("${fmConfig.customDateKey}: $dateString\n")
            }
            if (fmConfig.includeType) {
                append("${fmConfig.customTypeKey}: ${fmConfig.customTypeValue}\n")
            }

            // Custom static fields
            for ((key, value) in fmConfig.customFields.toSortedMap()) {
                append("$key: $value\n")
            }

            // Placeholder fields
            for (key in fmConfig.placeholderFields.sorted()) {
                append("$key: \n")
            }

            // All-connected-only audit fields. Ordinary export frontmatter remains byte-for-byte unchanged.
            data.compatibilityProvenance?.let { provenance ->
                fun yamlList(values: List<String>): String = values.joinToString(prefix = "[", postfix = "]") {
                    "\"${it.replace("\\", "\\\\").replace("\"", "\\\"")}\""
                }
                append("healthmd_all_connected_merge_policy: ${provenance.mergePolicyId}\n")
                append("healthmd_all_connected_providers_attempted: ${yamlList(provenance.providerIdsAttempted)}\n")
                append("healthmd_all_connected_providers_succeeded: ${yamlList(provenance.providerIdsSucceeded)}\n")
                append("healthmd_all_connected_providers_failed: ${yamlList(provenance.providerFailures.map { "${it.providerId}:${it.errorType}" })}\n")
                append("healthmd_all_connected_category_selections: ${yamlList(provenance.categorySelections.map {
                    "${it.category}=${it.chosenProviderId ?: "none"};omitted=${it.omittedOverlappingProviderIds.joinToString("|")}"
                })}\n")
                append("healthmd_all_connected_workout_sources: ${yamlList(provenance.workoutSources.map {
                    "${it.workoutId}=${it.providerId}:${it.providerWorkoutId}"
                })}\n")
                append("healthmd_all_connected_workout_detail_sources: ${yamlList(provenance.workoutDetailSources.flatMap { workout ->
                    workout.sourceIdsByDetail.toSortedMap().map { (detail, ids) ->
                        "${workout.workoutId}:$detail=${ids.joinToString("|")}"
                    }
                })}\n")
                append("healthmd_all_connected_workout_dedupe_decisions: ${yamlList(provenance.workoutDedupeDecisions.map {
                    "keep=${it.keptProviderId}:${it.keptWorkoutId};omit=${it.omittedProviderId}:${it.omittedWorkoutId};reason=${it.reason}"
                })}\n")
            }

            // Health data as frontmatter properties — driven by HealthDataFields (single source of truth)
            for (field in HealthDataFields.extract(
                data,
                converter,
                customization.timeFormat,
                customization.includeLegacyAndroidAliases,
                customization.includeAndroidNativeFields,
            )) {
                if (field.value == null) continue
                val outputKey = fmConfig.outputKey(field.key) ?: continue
                append("$outputKey: ${field.value}\n")
            }

            append("---\n")
        }
    }

}

package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class MarkdownTemplateStyle {
    STANDARD,
    COMPACT,
    DETAILED,
    CUSTOM,
}

@Serializable
enum class BulletStyle(val symbol: String) {
    DASH("-"),
    ASTERISK("*"),
    PLUS("+"),
}

@Serializable
data class MarkdownTemplateConfig(
    val style: MarkdownTemplateStyle = MarkdownTemplateStyle.STANDARD,
    val customTemplate: String = DEFAULT_TEMPLATE,
    val sectionHeaderLevel: Int = 2, // 1 = #, 2 = ##, 3 = ###
    val useEmoji: Boolean = false,
    val includeSummary: Boolean = true,
    val bulletStyle: BulletStyle = BulletStyle.DASH,
) {
    companion object {
        const val DEFAULT_TEMPLATE = """# Health Data — {{date}}

{{#sleep}}
## Sleep
{{sleep_metrics}}
{{/sleep}}

{{#activity}}
## Activity
{{activity_metrics}}
{{/activity}}

{{#heart}}
## Heart
{{heart_metrics}}
{{/heart}}

{{#vitals}}
## Vitals
{{vitals_metrics}}
{{/vitals}}

{{#body}}
## Body
{{body_metrics}}
{{/body}}

{{#nutrition}}
## Nutrition
{{nutrition_metrics}}
{{/nutrition}}

{{#mobility}}
## Mobility
{{mobility_metrics}}
{{/mobility}}

{{#workouts}}
## Workouts
{{workout_list}}
{{/workouts}}"""
    }
}

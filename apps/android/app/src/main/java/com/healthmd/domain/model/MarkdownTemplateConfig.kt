package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class MarkdownTemplateStyle(val displayName: String, val description: String) {
    STANDARD("Standard", "Balanced format with sections and bullet points"),
    COMPACT("Compact", "Condensed single-line metrics, minimal whitespace"),
    DETAILED("Detailed", "Expanded format with descriptions and context"),
    CUSTOM("Custom", "Your own template with placeholders"),
}

@Serializable
enum class BulletStyle(val symbol: String, val displayName: String) {
    DASH("-", "Dash (-)"),
    ASTERISK("*", "Asterisk (*)"),
    PLUS("+", "Plus (+)"),
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

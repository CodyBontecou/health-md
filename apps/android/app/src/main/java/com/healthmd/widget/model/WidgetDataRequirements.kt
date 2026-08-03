package com.healthmd.widget.model

import kotlinx.serialization.Serializable

/** The four independently discoverable Android widget providers. */
@Serializable
enum class HealthWidgetKind {
    SUMMARY,
    ACTIVITY,
    HEART_RANGE,
    SLEEP,
}

/**
 * Data categories needed by the widget instances currently installed.
 *
 * This is deliberately narrower than export selection. Phone widgets do not display blood oxygen,
 * so v1 does not query the broad vitals category merely because Apple caches that unused value.
 */
data class WidgetDataRequirements(
    val activity: Boolean = false,
    val sleep: Boolean = false,
    val heart: Boolean = false,
) {
    val hasAny: Boolean get() = activity || sleep || heart

    operator fun plus(other: WidgetDataRequirements): WidgetDataRequirements =
        WidgetDataRequirements(
            activity = activity || other.activity,
            sleep = sleep || other.sleep,
            heart = heart || other.heart,
        )

    companion object {
        fun forKind(kind: HealthWidgetKind): WidgetDataRequirements = when (kind) {
            HealthWidgetKind.SUMMARY -> WidgetDataRequirements(activity = true, sleep = true, heart = true)
            HealthWidgetKind.ACTIVITY -> WidgetDataRequirements(activity = true)
            HealthWidgetKind.HEART_RANGE -> WidgetDataRequirements(heart = true)
            HealthWidgetKind.SLEEP -> WidgetDataRequirements(sleep = true)
        }

        fun forKinds(kinds: Iterable<HealthWidgetKind>): WidgetDataRequirements =
            kinds.fold(WidgetDataRequirements()) { accumulated, kind -> accumulated + forKind(kind) }
    }
}

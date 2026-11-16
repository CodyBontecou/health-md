package com.healthmd.domain.model

/**
 * Export data categories whose read access a health provider can report separately.
 *
 * Health Connect grants each record type independently, so "some access" does not mean the
 * selected categories are readable. Planned workouts and medical records have their own
 * permission flows and are not reported here.
 */
enum class HealthAccessCategory {
    SLEEP,
    ACTIVITY,
    HEART,
    VITALS,
    BODY,
    NUTRITION,
    MOBILITY,
    REPRODUCTIVE_HEALTH,
    MINDFULNESS,
    WORKOUTS,
}

/** The access categories an export with this selection reads, in display order. */
fun DataTypeSelection.accessCategories(): Set<HealthAccessCategory> = buildSet {
    if (sleep) add(HealthAccessCategory.SLEEP)
    if (activity) add(HealthAccessCategory.ACTIVITY)
    if (heart) add(HealthAccessCategory.HEART)
    if (vitals) add(HealthAccessCategory.VITALS)
    if (body) add(HealthAccessCategory.BODY)
    if (nutrition) add(HealthAccessCategory.NUTRITION)
    if (mobility) add(HealthAccessCategory.MOBILITY)
    if (reproductiveHealth) add(HealthAccessCategory.REPRODUCTIVE_HEALTH)
    if (mindfulness) add(HealthAccessCategory.MINDFULNESS)
    if (workouts) add(HealthAccessCategory.WORKOUTS)
}

package com.healthmd.domain.model

/**
 * Which daily note owns a sleep session (issue #104).
 *
 * Planned cross-platform mode switch. Apple and Android persist the same [wireValue]
 * strings and default to [NIGHT_BEGINS].
 *
 * @property NIGHT_BEGINS shipped noon-to-noon journaling behavior. Summary
 *   intervals are clipped at the window boundaries; this remains the default
 *   so existing exports never change silently.
 * @property MORNING_ENDS proposed wake-up-date ownership of the whole session,
 *   unavailable until successor profiles and consumers are approved.
 */
enum class SleepDayAttribution(val wireValue: String) {
    NIGHT_BEGINS("night_begins"),
    MORNING_ENDS("morning_ends");

    val isAvailableForShippedProfiles: Boolean
        get() = this == NIGHT_BEGINS

    companion object {
        val DEFAULT: SleepDayAttribution = NIGHT_BEGINS

        /** Unknown persisted values fail closed to the shipped default. */
        fun fromWireValue(raw: String?): SleepDayAttribution =
            entries.firstOrNull { it.wireValue == raw } ?: DEFAULT
    }
}

/**
 * Capture-entry choice for sleep attribution.
 *
 * This shape keeps an explicit NIGHT_BEGINS override distinct from "read the
 * stored preference"; the shipped default enum value is never used as a sentinel.
 */
sealed interface SleepDayAttributionOverride {
    data object StoredPreference : SleepDayAttributionOverride
    data class Value(val attribution: SleepDayAttribution) : SleepDayAttributionOverride
}

class SleepAttributionUnavailableException : IllegalStateException(
    "Morning ends is unavailable for current export profiles. Choose Night begins for a new export.",
)

/** Immutable timezone and sleep-owner policy for one Android capture operation. */
data class AndroidCaptureContext(
    val zoneId: java.time.ZoneId,
    val sleepDayAttribution: SleepDayAttribution,
) {
    fun requireShippedProfile() {
        if (!sleepDayAttribution.isAvailableForShippedProfiles) throw SleepAttributionUnavailableException()
    }

    val explicitSleepDayAttributionOverride: SleepDayAttributionOverride
        get() {
            requireShippedProfile()
            return SleepDayAttributionOverride.Value(sleepDayAttribution)
        }
}

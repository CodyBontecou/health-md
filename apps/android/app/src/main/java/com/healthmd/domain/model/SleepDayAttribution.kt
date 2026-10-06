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

enum class SleepCaptureAuthorityError {
    PROFILE_UNAVAILABLE,
    UNVERSIONED_ATTRIBUTION,
    MISSING_DURABLE_ATTRIBUTION,
}

class SleepAttributionUnavailableException(
    val reason: SleepCaptureAuthorityError = SleepCaptureAuthorityError.PROFILE_UNAVAILABLE,
) : IllegalStateException(
    when (reason) {
        SleepCaptureAuthorityError.PROFILE_UNAVAILABLE ->
            "Morning ends is unavailable for current export profiles. Choose Night begins for a new export."
        SleepCaptureAuthorityError.UNVERSIONED_ATTRIBUTION ->
            "This saved sleep attribution has no supported export profile. It cannot resume; start a new export without changing the saved job."
        SleepCaptureAuthorityError.MISSING_DURABLE_ATTRIBUTION ->
            "This pending export has no immutable sleep attribution context. It cannot resume; start a new export without changing the saved job."
    },
)

/** Immutable timezone and sleep-owner policy for one Android capture operation. */
@kotlinx.serialization.Serializable(with = AndroidCaptureContextSerializer::class)
data class AndroidCaptureContext(
    val zoneId: java.time.ZoneId,
    val sleepDayAttribution: SleepDayAttribution,
    /** Fresh successor authority only. The durable decoder must preserve an absent draft marker. */
    val exportProfileID: String? = if (sleepDayAttribution == SleepDayAttribution.MORNING_ENDS) "android-sleep-v6" else null,
) {
    init {
        require(exportProfileID == null || when (sleepDayAttribution) {
            SleepDayAttribution.MORNING_ENDS -> exportProfileID == "android-sleep-v6"
            SleepDayAttribution.NIGHT_BEGINS -> exportProfileID in setOf("android-frozen-v4", "android-analytical-v5")
        }) { "Invalid capture export profile" }
    }

    fun requireShippedProfile() {
        if (sleepDayAttribution == SleepDayAttribution.MORNING_ENDS && exportProfileID != "android-sleep-v6") {
            throw SleepAttributionUnavailableException(SleepCaptureAuthorityError.UNVERSIONED_ATTRIBUTION)
        }
        if (!sleepDayAttribution.isAvailableForShippedProfiles) throw SleepAttributionUnavailableException()
    }

    companion object {
        fun recovered(context: AndroidCaptureContext?): AndroidCaptureContext =
            (context ?: throw SleepAttributionUnavailableException(SleepCaptureAuthorityError.MISSING_DURABLE_ATTRIBUTION))
                .also { it.requireShippedProfile() }
    }

    val explicitSleepDayAttributionOverride: SleepDayAttributionOverride
        get() {
            requireShippedProfile()
            return SleepDayAttributionOverride.Value(sleepDayAttribution)
        }
}

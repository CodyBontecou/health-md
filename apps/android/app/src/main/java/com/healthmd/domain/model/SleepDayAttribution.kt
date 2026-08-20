package com.healthmd.domain.model

/**
 * Which daily note owns a sleep session (issue #104).
 *
 * Shared cross-platform setting. Apple and Android persist the same [wireValue]
 * strings, default to [NIGHT_BEGINS], and keep the whole session in a single
 * note; only the owning calendar date differs.
 *
 * @property NIGHT_BEGINS the note for the calendar date the session starts owns
 *   it. Shipped noon-to-noon journaling behavior; the default so existing
 *   exports never change silently.
 * @property MORNING_ENDS the note for the wake-up date (the calendar date of
 *   the session end) owns the whole session, matching the Health Connect UI.
 */
enum class SleepDayAttribution(val wireValue: String) {
    NIGHT_BEGINS("night_begins"),
    MORNING_ENDS("morning_ends");

    companion object {
        val DEFAULT: SleepDayAttribution = NIGHT_BEGINS

        /** Unknown persisted values fail closed to the shipped default. */
        fun fromWireValue(raw: String?): SleepDayAttribution =
            entries.firstOrNull { it.wireValue == raw } ?: DEFAULT
    }
}

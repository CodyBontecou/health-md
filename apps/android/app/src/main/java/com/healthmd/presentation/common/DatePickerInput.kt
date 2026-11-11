package com.healthmd.presentation.common

import java.time.LocalDate
import java.time.format.DateTimeParseException

/** ISO input is strict: an impossible day must never resolve to another calendar date. */
internal fun parseDatePickerInput(input: String, yearRange: IntRange): LocalDate? {
    if (!input.matches(Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}"))) return null
    return try {
        LocalDate.parse(input).takeIf { it.year in yearRange }
    } catch (_: DateTimeParseException) {
        null
    }
}

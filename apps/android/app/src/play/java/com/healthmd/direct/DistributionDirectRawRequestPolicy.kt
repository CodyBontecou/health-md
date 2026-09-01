package com.healthmd.direct

import java.time.LocalDate
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** Play-only request limits for direct cloud providers. */
class DistributionDirectRawRequestPolicy @Inject constructor() {
    fun validationError(providerId: String, selection: JsonObject): String? = when {
        providerId == FITBIT_PROVIDER_ID && !isBoundedFitbitRange(selection) ->
            "Fitbit raw export requires an explicit range of at most 366 days."
        else -> null
    }

    private fun isBoundedFitbitRange(selection: JsonObject): Boolean {
        if (selection["type"]?.jsonPrimitive?.content != "exact") return false
        val start = selection["start_date"]?.jsonPrimitive?.contentOrNull
            ?.let(LocalDate::parse) ?: return false
        val end = selection["end_date"]?.jsonPrimitive?.contentOrNull
            ?.let(LocalDate::parse) ?: return false
        return !end.isBefore(start) && ChronoUnit.DAYS.between(start, end) < MAXIMUM_FITBIT_RAW_DAYS
    }

    private companion object {
        const val FITBIT_PROVIDER_ID = "fitbit"
        const val MAXIMUM_FITBIT_RAW_DAYS = 366L
    }
}

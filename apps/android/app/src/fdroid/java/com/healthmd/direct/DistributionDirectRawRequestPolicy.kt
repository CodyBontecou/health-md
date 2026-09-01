package com.healthmd.direct

import javax.inject.Inject
import kotlinx.serialization.json.JsonObject

/** F-Droid has no direct cloud providers and therefore no provider-specific request limits. */
class DistributionDirectRawRequestPolicy @Inject constructor() {
    fun validationError(providerId: String, selection: JsonObject): String? = null
}

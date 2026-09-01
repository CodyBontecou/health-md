package com.healthmd.data.health.providers.direct

import com.healthmd.data.health.HealthDataProvider
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

open class UnavailableHealthDataProvider(
    final override val providerId: String,
    private val reason: String,
) : HealthDataProvider {
    override suspend fun fetchHealthData(date: LocalDate): HealthData =
        throw UnsupportedOperationException(reason)

    override suspend fun isAvailable(): Boolean = false
    override suspend fun hasPermissions(): Boolean = false
    override suspend fun hasHistoricalReadPermission(): Boolean = false
    override suspend fun hasBackgroundReadPermission(): Boolean = false
    override suspend fun getEarliestDataDate(): LocalDate? = null
    override fun isBeforeFirstUnlock(): Boolean = false
}

class SamsungHealthDirectDataProvider : UnavailableHealthDataProvider(
    providerId = "samsung_health",
    reason = "Samsung Health direct export requires Samsung Health Data SDK approval; use Samsung Health Health Connect sharing for now.",
)

class HuaweiHealthDirectDataProvider : UnavailableHealthDataProvider(
    providerId = "huawei_health",
    reason = "Huawei Health direct export requires an HMS Health Kit build and AppGallery Connect configuration.",
)

class GarminDirectDataProvider : UnavailableHealthDataProvider(
    providerId = "garmin",
    reason = "Garmin direct export requires Garmin Health API partner approval and backend/webhook sync.",
)

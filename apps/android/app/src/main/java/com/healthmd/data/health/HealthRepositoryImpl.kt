package com.healthmd.data.health

import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.HealthRepository
import java.time.LocalDate

class HealthRepositoryImpl(
    private val healthConnectManager: HealthConnectManager,
) : HealthRepository {

    override suspend fun fetchHealthData(date: LocalDate): HealthData =
        healthConnectManager.fetchHealthData(date)

    override suspend fun isAvailable(): Boolean =
        healthConnectManager.isAvailable()

    override suspend fun hasPermissions(): Boolean =
        healthConnectManager.hasAllPermissions()
}

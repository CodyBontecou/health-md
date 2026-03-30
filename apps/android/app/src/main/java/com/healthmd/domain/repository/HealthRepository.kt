package com.healthmd.domain.repository

import com.healthmd.domain.model.HealthData
import java.time.LocalDate

interface HealthRepository {
    suspend fun fetchHealthData(date: LocalDate): HealthData
    suspend fun isAvailable(): Boolean
    suspend fun hasPermissions(): Boolean
}

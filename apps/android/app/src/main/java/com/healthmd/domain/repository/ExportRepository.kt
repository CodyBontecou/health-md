package com.healthmd.domain.repository

import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData

interface ExportRepository {
    suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean
    suspend fun hasExportFolder(): Boolean
    fun getExportFolderName(): String?
}

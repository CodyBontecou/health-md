package com.healthmd.domain.repository

import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

sealed interface DurableScheduledFolderOperationStart {
    data object New : DurableScheduledFolderOperationStart
    data class Resumed(val result: ExportResult) : DurableScheduledFolderOperationStart
    data object Failed : DurableScheduledFolderOperationStart
}

interface ExportRepository {
    suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean
    suspend fun beginDurableScheduledFolderOperation(
        operationId: String,
        dates: List<LocalDate>,
        settings: ExportSettings,
        settingsSnapshotJson: String,
        requireExistingJournal: Boolean,
    ): DurableScheduledFolderOperationStart = DurableScheduledFolderOperationStart.Failed
    suspend fun stageDurableScheduledFolderDay(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): Boolean = false
    suspend fun finishDurableScheduledFolderOperation(
        operationId: String,
        dates: List<LocalDate>,
        failedDateDetails: List<FailedDateDetail>,
        wasCancelled: Boolean,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = failedDateDetails,
        wasCancelled = wasCancelled,
    )
    suspend fun hasResumableDurableScheduledFolderOperation(
        operationId: String,
        dates: List<LocalDate>,
        settings: ExportSettings,
        settingsSnapshotJson: String,
    ): Boolean = false
    suspend fun discardDurableScheduledFolderOperation(operationId: String) = Unit
    suspend fun previewHealthData(data: HealthData, settings: ExportSettings): ExportPreviewDay =
        ExportPreviewDay(date = data.date)
    suspend fun hasExportFolder(): Boolean
    fun getExportFolderName(): String?
}

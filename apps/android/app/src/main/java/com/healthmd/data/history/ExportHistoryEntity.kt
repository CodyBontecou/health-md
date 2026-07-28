package com.healthmd.data.history

import androidx.room.Entity
import androidx.room.PrimaryKey
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.rawexport.ExportMode
import kotlinx.serialization.json.Json
import java.time.LocalDate

@Entity(tableName = "export_history")
data class ExportHistoryEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val timestamp: Long,
    val source: String,
    val dateRangeStart: String, // ISO date
    val dateRangeEnd: String,   // ISO date
    val successCount: Int,
    val totalCount: Int,
    val failureReason: String? = null,
    val failedDateDetailsJson: String? = null,
    val targetType: String = ExportTarget.DEVICE_FOLDER.name,
    val targetLabel: String? = null,
    val fileCount: Int = 0,
    val warningSummary: String? = null,
    val exportMode: String = ExportMode.COMPATIBILITY.name,
) {
    fun toDomain(): ExportHistoryEntry {
        val json = Json { ignoreUnknownKeys = true }
        return ExportHistoryEntry(
            id = id,
            timestamp = timestamp,
            source = ExportSource.valueOf(source),
            dateRangeStart = LocalDate.parse(dateRangeStart),
            dateRangeEnd = LocalDate.parse(dateRangeEnd),
            successCount = successCount,
            totalCount = totalCount,
            failureReason = failureReason?.let { ExportFailureReason.valueOf(it) },
            failedDateDetails = failedDateDetailsJson?.let {
                try {
                    json.decodeFromString<List<FailedDateDetail>>(it)
                } catch (_: Exception) {
                    emptyList()
                }
            } ?: emptyList(),
            target = runCatching { ExportTarget.valueOf(targetType) }.getOrDefault(ExportTarget.DEVICE_FOLDER),
            targetLabel = targetLabel,
            fileCount = fileCount,
            warningSummary = warningSummary,
            exportMode = runCatching { ExportMode.valueOf(exportMode) }.getOrDefault(ExportMode.COMPATIBILITY),
        )
    }

    companion object {
        fun fromDomain(entry: ExportHistoryEntry): ExportHistoryEntity {
            val json = Json { ignoreUnknownKeys = true }
            return ExportHistoryEntity(
                id = entry.id,
                timestamp = entry.timestamp,
                source = entry.source.name,
                dateRangeStart = entry.dateRangeStart.toString(),
                dateRangeEnd = entry.dateRangeEnd.toString(),
                successCount = entry.successCount,
                totalCount = entry.totalCount,
                failureReason = entry.failureReason?.name,
                failedDateDetailsJson = if (entry.failedDateDetails.isNotEmpty()) {
                    json.encodeToString(
                        kotlinx.serialization.builtins.ListSerializer(FailedDateDetail.serializer()),
                        entry.failedDateDetails,
                    )
                } else null,
                targetType = entry.target.name,
                targetLabel = entry.targetLabel,
                fileCount = entry.fileCount,
                warningSummary = entry.warningSummary,
                exportMode = entry.exportMode.name,
            )
        }
    }
}

package com.healthmd.domain.repository

import com.healthmd.domain.model.ExportHistoryEntry
import kotlinx.coroutines.flow.Flow

interface ExportHistoryRepository {
    fun getAllEntries(): Flow<List<ExportHistoryEntry>>
    suspend fun insertEntry(entry: ExportHistoryEntry)
    suspend fun deleteEntry(id: Long)
    suspend fun clearAll()
}

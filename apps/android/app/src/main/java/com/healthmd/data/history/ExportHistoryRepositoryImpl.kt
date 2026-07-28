package com.healthmd.data.history

import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.repository.ExportHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class ExportHistoryRepositoryImpl(
    private val dao: ExportHistoryDao,
) : ExportHistoryRepository {

    override fun getAllEntries(): Flow<List<ExportHistoryEntry>> =
        dao.getAllEntries().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insertEntry(entry: ExportHistoryEntry) {
        dao.insertEntry(ExportHistoryEntity.fromDomain(entry))
    }

    override suspend fun deleteEntry(id: Long) {
        dao.deleteEntry(id)
    }

    override suspend fun clearAll() {
        dao.clearAll()
    }
}

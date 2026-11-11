package com.healthmd.data.history

import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.repository.ExportHistoryRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class ExportHistoryRepositoryImpl(
    private val dao: ExportHistoryDao,
    /** Runs after history changes, e.g. to refresh the Archive widget. Failures are ignored. */
    private val onChanged: suspend () -> Unit = {},
) : ExportHistoryRepository {

    override fun getAllEntries(): Flow<List<ExportHistoryEntry>> =
        dao.getAllEntries().map { entities -> entities.map { it.toDomain() } }

    override suspend fun insertEntry(entry: ExportHistoryEntry) {
        dao.insertEntry(ExportHistoryEntity.fromDomain(entry))
        notifyChanged()
    }

    override suspend fun deleteEntry(id: Long) {
        dao.deleteEntry(id)
        notifyChanged()
    }

    override suspend fun clearAll() {
        dao.clearAll()
        notifyChanged()
    }

    private suspend fun notifyChanged() {
        runCatching { onChanged() }
    }
}

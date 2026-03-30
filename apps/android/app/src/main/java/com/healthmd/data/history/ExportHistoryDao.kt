package com.healthmd.data.history

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface ExportHistoryDao {

    @Query("SELECT * FROM export_history ORDER BY timestamp DESC")
    fun getAllEntries(): Flow<List<ExportHistoryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertEntry(entry: ExportHistoryEntity)

    @Query("DELETE FROM export_history WHERE id = :id")
    suspend fun deleteEntry(id: Long)

    @Query("DELETE FROM export_history")
    suspend fun clearAll()
}

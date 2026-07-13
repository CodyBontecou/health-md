package com.healthmd.data.history

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(entities = [ExportHistoryEntity::class], version = 3, exportSchema = false)
abstract class ExportHistoryDatabase : RoomDatabase() {
    abstract fun exportHistoryDao(): ExportHistoryDao
}

package com.healthmd.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase
import com.healthmd.data.history.ExportHistoryDao
import com.healthmd.data.history.ExportHistoryDatabase
import com.healthmd.data.history.ExportHistoryRepositoryImpl
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {

    private val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE export_history ADD COLUMN targetLabel TEXT")
            db.execSQL("ALTER TABLE export_history ADD COLUMN fileCount INTEGER NOT NULL DEFAULT 0")
            db.execSQL("ALTER TABLE export_history ADD COLUMN warningSummary TEXT")
        }
    }

    private val MIGRATION_2_3 = object : Migration(2, 3) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE export_history ADD COLUMN targetType TEXT NOT NULL DEFAULT 'DEVICE_FOLDER'")
        }
    }

    @Provides
    @Singleton
    fun provideExportHistoryDatabase(@ApplicationContext context: Context): ExportHistoryDatabase =
        Room.databaseBuilder(
            context,
            ExportHistoryDatabase::class.java,
            "export_history.db",
        )
            .addMigrations(MIGRATION_1_2, MIGRATION_2_3)
            .build()

    @Provides
    fun provideExportHistoryDao(database: ExportHistoryDatabase): ExportHistoryDao =
        database.exportHistoryDao()

    @Provides
    @Singleton
    fun provideExportHistoryRepository(dao: ExportHistoryDao): ExportHistoryRepository =
        ExportHistoryRepositoryImpl(dao)

    @Provides
    @Singleton
    fun provideSettingsRepository(
        dataStore: DataStore<Preferences>,
        @ApplicationContext context: Context,
    ): SettingsRepository =
        SettingsRepositoryImpl(dataStore, context)
}

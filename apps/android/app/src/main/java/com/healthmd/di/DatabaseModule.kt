package com.healthmd.di

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.room.Room
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

    @Provides
    @Singleton
    fun provideExportHistoryDatabase(@ApplicationContext context: Context): ExportHistoryDatabase =
        Room.databaseBuilder(
            context,
            ExportHistoryDatabase::class.java,
            "export_history.db",
        ).build()

    @Provides
    fun provideExportHistoryDao(database: ExportHistoryDatabase): ExportHistoryDao =
        database.exportHistoryDao()

    @Provides
    @Singleton
    fun provideExportHistoryRepository(dao: ExportHistoryDao): ExportHistoryRepository =
        ExportHistoryRepositoryImpl(dao)

    @Provides
    @Singleton
    fun provideSettingsRepository(dataStore: DataStore<Preferences>): SettingsRepository =
        SettingsRepositoryImpl(dataStore)
}

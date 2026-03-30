package com.healthmd.di

import android.content.Context
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.storage.ExportRepositoryImpl
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ExportModule {

    @Provides
    @Singleton
    fun provideMarkdownExporter(): MarkdownExporter = MarkdownExporter()

    @Provides
    @Singleton
    fun provideJsonExporter(): JsonExporter = JsonExporter()

    @Provides
    @Singleton
    fun provideCsvExporter(): CsvExporter = CsvExporter()

    @Provides
    @Singleton
    fun provideFileExportManager(@ApplicationContext context: Context): FileExportManager =
        FileExportManager(context)

    @Provides
    @Singleton
    fun provideExportRepository(
        fileExportManager: FileExportManager,
        markdownExporter: MarkdownExporter,
        jsonExporter: JsonExporter,
        csvExporter: CsvExporter,
        settingsRepository: SettingsRepository,
    ): ExportRepository = ExportRepositoryImpl(
        fileExportManager = fileExportManager,
        markdownExporter = markdownExporter,
        jsonExporter = jsonExporter,
        csvExporter = csvExporter,
        settingsRepository = settingsRepository,
    )
}

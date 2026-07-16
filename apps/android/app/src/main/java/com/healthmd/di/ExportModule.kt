package com.healthmd.di

import android.content.Context
import com.healthmd.data.export.APIExportClient
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportUploader
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.EncryptedAPIExportCredentialStore
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.export.RawSnapshotExportRunner
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.data.storage.ExportRepositoryImpl
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.RawSnapshotApiClient
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import java.util.concurrent.TimeUnit
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
    fun provideObsidianBasesExporter(): ObsidianBasesExporter = ObsidianBasesExporter()

    @Provides
    @Singleton
    fun provideFileExportManager(@ApplicationContext context: Context): FileExportManager =
        FileExportManager(context)

    @Provides
    @Singleton
    fun provideAPIExportHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .callTimeout(90, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    @Provides
    @Singleton
    fun provideAPIExportUploader(client: APIExportClient): APIExportUploader = client

    @Provides
    @Singleton
    fun provideRawSnapshotApiClient(client: OkHttpClient): RawSnapshotApiClient =
        RawSnapshotApiClient(client)

    @Provides
    @Singleton
    fun provideRawSnapshotService(runner: RawSnapshotExportRunner): RawSnapshotService = runner

    @Provides
    @Singleton
    fun provideAPIExportCredentialStore(
        store: EncryptedAPIExportCredentialStore,
    ): APIExportCredentialStore = store

    @Provides
    @Singleton
    fun provideExportRepository(
        fileExportManager: FileExportManager,
        markdownExporter: MarkdownExporter,
        jsonExporter: JsonExporter,
        csvExporter: CsvExporter,
        obsidianBasesExporter: ObsidianBasesExporter,
        settingsRepository: SettingsRepository,
    ): ExportRepository = ExportRepositoryImpl(
        fileExportManager = fileExportManager,
        markdownExporter = markdownExporter,
        jsonExporter = jsonExporter,
        csvExporter = csvExporter,
        obsidianBasesExporter = obsidianBasesExporter,
        settingsRepository = settingsRepository,
    )
}

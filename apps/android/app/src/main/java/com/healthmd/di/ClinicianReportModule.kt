package com.healthmd.di

import com.healthmd.data.clinicianreport.AndroidClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.AndroidClinicianReportVocabularyFactory
import com.healthmd.data.clinicianreport.ClinicianReportDataSource
import com.healthmd.data.clinicianreport.ClinicianReportDateProvider
import com.healthmd.data.clinicianreport.ClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.DefaultClinicianReportDataSource
import com.healthmd.data.clinicianreport.SystemClinicianReportDateProvider
import com.healthmd.domain.clinicianreport.ClinicianReportVocabularyFactory
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class ClinicianReportModule {
    @Binds @Singleton
    abstract fun bindDataSource(source: DefaultClinicianReportDataSource): ClinicianReportDataSource

    @Binds @Singleton
    abstract fun bindDateProvider(provider: SystemClinicianReportDateProvider): ClinicianReportDateProvider

    @Binds @Singleton
    abstract fun bindPdfRenderer(renderer: AndroidClinicianReportPdfRenderer): ClinicianReportPdfRenderer

    @Binds @Singleton
    abstract fun bindVocabularyFactory(factory: AndroidClinicianReportVocabularyFactory): ClinicianReportVocabularyFactory
}

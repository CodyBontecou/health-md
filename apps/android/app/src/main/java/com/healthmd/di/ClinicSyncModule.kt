package com.healthmd.di

import com.healthmd.data.clinicsync.AndroidClinicSyncNotifier
import com.healthmd.data.clinicsync.AutomationClinicSyncExportLauncher
import com.healthmd.data.clinicsync.ClinicSyncExportLauncher
import com.healthmd.data.clinicsync.ClinicSyncNotifier
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
abstract class ClinicSyncModule {
    @Binds
    abstract fun bindExportLauncher(launcher: AutomationClinicSyncExportLauncher): ClinicSyncExportLauncher

    @Binds
    abstract fun bindNotifier(notifier: AndroidClinicSyncNotifier): ClinicSyncNotifier
}

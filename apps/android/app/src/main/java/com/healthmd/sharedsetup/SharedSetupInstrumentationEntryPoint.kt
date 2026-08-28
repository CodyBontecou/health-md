package com.healthmd.sharedsetup

import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

/** Bounded access to real dependencies for on-device lifecycle/regression instrumentation. */
@EntryPoint
@InstallIn(SingletonComponent::class)
interface SharedSetupInstrumentationEntryPoint {
    fun sharedSetupService(): SharedSetupService
    fun sharedSetupDocumentStore(): SharedSetupDocumentStore
    fun sharedSetupCoordinator(): SharedSetupCoordinator
    fun settingsRepository(): SettingsRepository
    fun scheduledProfileEntryStore(): ScheduledProfileEntryStore
    fun scheduledProfileScheduler(): ScheduledProfileScheduler
    fun exportProfileRepository(): ExportProfileRepository
    fun exportProfileCoordinator(): ExportProfileCoordinator
    fun exportScheduler(): ExportScheduler
    fun exportHistoryRepository(): ExportHistoryRepository
    fun profileSnapshotFactory(): ScheduledProfileSnapshotFactory
    fun healthRepository(): HealthRepository
}

package com.healthmd.sharedsetup

import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
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
}

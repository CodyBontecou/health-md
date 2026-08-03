package com.healthmd.widget

import com.healthmd.widget.data.HealthConnectWidgetDataSource
import com.healthmd.widget.data.HealthWidgetSnapshotStore
import com.healthmd.widget.data.NoBackupHealthWidgetSnapshotStore
import com.healthmd.widget.data.WidgetHealthDataSource
import com.healthmd.widget.glance.AndroidHealthWidgetInstanceRegistry
import com.healthmd.widget.glance.GlanceHealthWidgetUpdater
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetUpdater
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class WidgetModule {
    @Binds
    @Singleton
    abstract fun bindWidgetHealthDataSource(
        source: HealthConnectWidgetDataSource,
    ): WidgetHealthDataSource

    @Binds
    @Singleton
    abstract fun bindHealthWidgetSnapshotStore(
        store: NoBackupHealthWidgetSnapshotStore,
    ): HealthWidgetSnapshotStore

    @Binds
    @Singleton
    abstract fun bindHealthWidgetInstanceRegistry(
        registry: AndroidHealthWidgetInstanceRegistry,
    ): HealthWidgetInstanceRegistry

    @Binds
    @Singleton
    abstract fun bindHealthWidgetUpdater(
        updater: GlanceHealthWidgetUpdater,
    ): HealthWidgetUpdater
}

package com.healthmd.data.scheduler

import kotlinx.coroutines.sync.Mutex
import javax.inject.Inject
import javax.inject.Singleton

/** Prevents WorkManager and foreground recovery from uploading the same scheduled dates at once. */
@Singleton
class ScheduledExportRunCoordinator @Inject constructor() {
    val mutex = Mutex()
}

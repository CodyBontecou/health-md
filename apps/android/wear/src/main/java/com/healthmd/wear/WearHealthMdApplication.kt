package com.healthmd.wear

import android.app.Application
import com.healthmd.wear.sync.WearSnapshotRepository

/** Deliberately lightweight: no phone export, analytics, Health Connect, or CLI initialization. */
class WearHealthMdApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        WearSnapshotRepository.initialize(this)
    }
}

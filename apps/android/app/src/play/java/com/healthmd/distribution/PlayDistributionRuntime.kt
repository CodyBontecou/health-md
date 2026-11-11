package com.healthmd.distribution

import android.content.Context
import androidx.work.WorkManager
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import javax.inject.Inject

/** Google Play lifecycle: erase retired telemetry without starting collection or uploads. */
class PlayDistributionRuntime @Inject constructor(
    @ApplicationContext private val context: Context,
) : DistributionRuntime {
    private val cleanupScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun initialize() {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork("campaign-attribution-upload")
        workManager.cancelUniqueWork("onboarding-analytics-upload")
        cleanupScope.launch {
            // The retired DataStore producers are gone; these files have no active writer.
            for (name in listOf("campaign_attribution", "onboarding_analytics")) {
                File(context.filesDir, "datastore/$name.preferences_pb").delete()
                File(context.filesDir, "datastore/$name.preferences_pb.tmp").delete()
            }
        }
    }

    override suspend fun reconcileForeground() = Unit
}

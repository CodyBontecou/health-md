package com.healthmd.wear.surface

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester

class WearSurfaceInvalidationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Tile invalidation may bind to the system Tile service, which is forbidden directly from
        // a manifest receiver context. Hand it off before returning and always finish goAsync().
        val pending = goAsync()
        val applicationContext = context.applicationContext
        Thread {
            try { invalidateAllWearSurfaces(applicationContext) }
            finally { pending.finish() }
        }.start()
    }
}

internal val ALL_TILE_SERVICES = listOf(DailyActivityTileService::class.java, RecoveryTileService::class.java)
internal val ALL_COMPLICATION_SERVICES = listOf(
        DailyActivityComplicationService::class.java, RecoveryComplicationService::class.java,
        StepsComplicationService::class.java, MoveComplicationService::class.java,
        ExerciseComplicationService::class.java, SleepComplicationService::class.java,
        RestingHeartRateComplicationService::class.java, AverageHeartRateComplicationService::class.java,
        HrvComplicationService::class.java, BloodOxygenComplicationService::class.java,
    )

fun invalidateAllWearSurfaces(context: Context) {
    ALL_TILE_SERVICES.forEach { TileService.getUpdater(context).requestUpdate(it) }
    ALL_COMPLICATION_SERVICES.forEach { ComplicationDataSourceUpdateRequester.create(context, android.content.ComponentName(context, it)).requestUpdateAll() }
}

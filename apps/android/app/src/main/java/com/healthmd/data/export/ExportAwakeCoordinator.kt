package com.healthmd.data.export

import android.annotation.SuppressLint
import android.content.Context
import android.os.PowerManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.UUID

/**
 * Coordinates process-wide power assertions for active exports.
 *
 * A partial wake lock keeps export work running if Android would otherwise suspend the CPU.
 * [isExportActive] lets the visible activity also set FLAG_KEEP_SCREEN_ON so the display does
 * not time out. Activity IDs make overlapping exports safe and make begin/end idempotent.
 */
class ExportAwakeCoordinator {
    private val lock = Any()
    private val activeActivityIds = mutableSetOf<UUID>()
    private val _isExportActive = MutableStateFlow(false)
    private var powerManager: PowerManager? = null
    private var wakeLock: PowerManager.WakeLock? = null

    val isExportActive: StateFlow<Boolean> = _isExportActive.asStateFlow()

    fun initialize(context: Context) {
        synchronized(lock) {
            if (powerManager == null) {
                powerManager = context.applicationContext.getSystemService(PowerManager::class.java)
            }
            updateStateLocked()
        }
    }

    fun beginActivity(activityId: UUID = UUID.randomUUID()): UUID {
        synchronized(lock) {
            if (activeActivityIds.add(activityId)) updateStateLocked()
        }
        return activityId
    }

    fun endActivity(activityId: UUID) {
        synchronized(lock) {
            if (activeActivityIds.remove(activityId)) updateStateLocked()
        }
    }

    suspend fun <T> whileExporting(block: suspend () -> T): T {
        val activityId = beginActivity()
        return try {
            block()
        } finally {
            endActivity(activityId)
        }
    }

    @SuppressLint("Wakelock", "WakelockTimeout")
    private fun updateStateLocked() {
        val shouldStayAwake = activeActivityIds.isNotEmpty()
        if (_isExportActive.value != shouldStayAwake) {
            _isExportActive.value = shouldStayAwake
        }

        if (shouldStayAwake) {
            if (wakeLock?.isHeld != true) {
                wakeLock = try {
                    powerManager?.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK,
                        "HealthMd:ActiveExport",
                    )?.apply {
                        setReferenceCounted(false)
                        acquire()
                    }
                } catch (_: SecurityException) {
                    null
                }
            }
        } else {
            val lockToRelease = wakeLock
            wakeLock = null
            try {
                lockToRelease?.takeIf { it.isHeld }?.release()
            } catch (_: SecurityException) {
                // Keep export completion reliable even if an OEM revokes the assertion.
            }
        }
    }

    companion object {
        val shared = ExportAwakeCoordinator()
    }
}

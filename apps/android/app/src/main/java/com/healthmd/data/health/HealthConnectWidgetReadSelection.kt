package com.healthmd.data.health

/** Exact Health Connect record families needed by the current home-screen widget refresh. */
data class HealthConnectWidgetReadSelection(
    val steps: Boolean = false,
    val activeCalories: Boolean = false,
    val exerciseSessions: Boolean = false,
    val sleepSessions: Boolean = false,
    val heartRate: Boolean = false,
    val restingHeartRate: Boolean = false,
    val hrvRmssd: Boolean = false,
    val oxygenSaturation: Boolean = false,
) {
    val hasAny: Boolean
        get() = steps || activeCalories || exerciseSessions || sleepSessions || heartRate ||
            restingHeartRate || hrvRmssd || oxygenSaturation
}

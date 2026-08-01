package com.healthmd.data.health

import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.net.toUri
import androidx.health.connect.client.HealthConnectClient
import timber.log.Timber

private const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"
private const val HEALTH_CONNECT_MARKET_URI = "market://details?id=$HEALTH_CONNECT_PACKAGE"
private const val HEALTH_CONNECT_WEB_URI =
    "https://play.google.com/store/apps/details?id=$HEALTH_CONNECT_PACKAGE"

enum class HealthConnectLaunchResult {
    OPENED,
    FAILED,
}

internal enum class HealthConnectIntentTarget {
    HEALTH_CONNECT_SETTINGS,
    PLAY_STORE_APP,
    PLAY_STORE_WEB,
}

internal fun healthConnectSettingsTargets(sdkInt: Int): List<HealthConnectIntentTarget> =
    listOf(HealthConnectIntentTarget.HEALTH_CONNECT_SETTINGS) +
        if (sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            emptyList()
        } else {
            listOf(
                HealthConnectIntentTarget.PLAY_STORE_APP,
                HealthConnectIntentTarget.PLAY_STORE_WEB,
            )
        }

/** Opens Health Connect through its supported settings action and reports every failed launch. */
class HealthConnectIntentLauncher(private val context: Context) {
    fun openSettings(): HealthConnectLaunchResult {
        return launchFirstAvailable(
            healthConnectSettingsTargets(Build.VERSION.SDK_INT).map(::targetIntent)
        )
    }

    fun openInstallOrUpdate(): HealthConnectLaunchResult = launchFirstAvailable(
        listOf(
            Intent(Intent.ACTION_VIEW, HEALTH_CONNECT_MARKET_URI.toUri()),
            Intent(Intent.ACTION_VIEW, HEALTH_CONNECT_WEB_URI.toUri()),
        )
    )

    private fun targetIntent(target: HealthConnectIntentTarget): Intent = when (target) {
        // This AndroidX action resolves to the standalone APK on Android 13 and to the
        // framework module on Android 14+.
        HealthConnectIntentTarget.HEALTH_CONNECT_SETTINGS ->
            Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
        HealthConnectIntentTarget.PLAY_STORE_APP ->
            Intent(Intent.ACTION_VIEW, HEALTH_CONNECT_MARKET_URI.toUri())
        HealthConnectIntentTarget.PLAY_STORE_WEB ->
            Intent(Intent.ACTION_VIEW, HEALTH_CONNECT_WEB_URI.toUri())
    }

    private fun launchFirstAvailable(candidates: List<Intent>): HealthConnectLaunchResult {
        candidates.forEach { candidate ->
            candidate.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(candidate)
                return HealthConnectLaunchResult.OPENED
            } catch (error: RuntimeException) {
                Timber.w(error, "Unable to launch Health Connect action %s", candidate.action)
            }
        }
        return HealthConnectLaunchResult.FAILED
    }
}

fun grantedAnyRequestedHealthPermission(
    requested: Set<String>,
    granted: Set<String>,
): Boolean = requested.isNotEmpty() && granted.any { it in requested }

fun grantedAllRequestedHealthPermissions(
    requested: Set<String>,
    granted: Set<String>,
): Boolean = requested.isNotEmpty() && granted.containsAll(requested)

/** Converts synchronous Activity Result launch failures into a result the UI can display. */
fun tryLaunchHealthConnectPermissions(
    permissions: Set<String>,
    launch: (Set<String>) -> Unit,
): Boolean {
    if (permissions.isEmpty()) return false
    return runCatching { launch(permissions) }.isSuccess
}

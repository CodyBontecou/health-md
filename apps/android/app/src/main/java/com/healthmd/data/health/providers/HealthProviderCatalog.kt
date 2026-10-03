package com.healthmd.data.health.providers

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.StringRes
import androidx.health.connect.client.HealthConnectClient
import com.healthmd.R

/**
 * First-class catalog of health ecosystems available in the active distribution channel.
 *
 * Health Connect remains the canonical on-device read path. Flavor-owned modules provide any
 * additional provider definitions so unavailable provider setup and copy are not compiled into
 * another channel.
 */
class HealthProviderCatalog(
    private val context: Context,
    val definitions: List<HealthProviderDefinition>,
) {
    fun providerStates(): List<HealthProviderState> = definitions.map { definition ->
        val installedPackage = definition.packageNames.firstOrNull { isPackageInstalled(it) }
        HealthProviderState(
            definition = definition,
            installedPackageName = installedPackage,
            isInstalled = installedPackage != null,
            setupIntent = buildSetupIntent(definition, installedPackage),
        )
    }

    fun setupIntentFor(providerId: HealthProviderId): Intent? =
        providerStates().firstOrNull { it.definition.id == providerId }?.setupIntent

    private fun buildSetupIntent(
        definition: HealthProviderDefinition,
        installedPackageName: String?,
    ): Intent? {
        if (
            definition.id == HealthProviderId.HEALTH_CONNECT &&
            (installedPackageName != null || Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
        ) {
            return Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }

        if (installedPackageName != null) {
            context.packageManager.getLaunchIntentForPackage(installedPackageName)?.let { launchIntent ->
                return launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }

        definition.setupPackageName?.let { packageName ->
            return Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$packageName")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }

        return definition.webSetupUri?.let { uri ->
            Intent(Intent.ACTION_VIEW, Uri.parse(uri)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean = try {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(packageName, 0)
        true
    } catch (_: Exception) {
        false
    }

    companion object {
        fun healthConnectDefinition(): HealthProviderDefinition = HealthProviderDefinition(
            id = HealthProviderId.HEALTH_CONNECT,
            displayName = "Health Connect",
            integrationKind = HealthProviderIntegrationKind.AndroidSystem,
            packageNames = listOf("com.google.android.apps.healthdata"),
            setupPackageName = "com.google.android.apps.healthdata",
            summaryRes = R.string.health_provider_health_connect_summary,
            setupDescriptionRes = R.string.health_provider_health_connect_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.Available,
        )
    }
}

data class HealthProviderDefinition(
    val id: HealthProviderId,
    val displayName: String,
    val integrationKind: HealthProviderIntegrationKind,
    val packageNames: List<String>,
    @StringRes val summaryRes: Int,
    @StringRes val setupDescriptionRes: Int,
    val directExportStatus: HealthProviderDirectExportStatus,
    val setupPackageName: String? = null,
    val webSetupUri: String? = null,
)

data class HealthProviderState(
    val definition: HealthProviderDefinition,
    val installedPackageName: String?,
    val isInstalled: Boolean,
    val setupIntent: Intent?,
) {
    @get:StringRes
    val actionLabelRes: Int
        get() = if (isInstalled) {
            R.string.health_provider_action_open
        } else {
            R.string.health_provider_action_install_setup
        }
}

enum class HealthProviderId(val wireId: String) {
    HEALTH_CONNECT("health_connect"),
    SAMSUNG_HEALTH("samsung_health"),
    HUAWEI_HEALTH("huawei_health"),
    FITBIT("fitbit"),
    GARMIN("garmin"),
    WITHINGS("withings"),
    OURA("oura"),
    POLAR("polar"),
    WHOOP("whoop"),
}

data class HealthProviderIntegrationKind(
    @StringRes val labelRes: Int,
    private val diagnosticLabel: String,
) {
    /** Stable diagnostics value; user-facing presentation must use [labelRes]. */
    val label: String
        get() = diagnosticLabel

    companion object {
        val AndroidSystem = HealthProviderIntegrationKind(
            R.string.health_provider_integration_android_system,
            "Android system",
        )
    }
}

data class HealthProviderDirectExportStatus(
    @StringRes val labelRes: Int,
    private val diagnosticLabel: String,
) {
    /** Stable diagnostics value; user-facing presentation must use [labelRes]. */
    val label: String
        get() = diagnosticLabel

    companion object {
        val Available = HealthProviderDirectExportStatus(
            R.string.health_provider_direct_export_available,
            "Export-ready",
        )
    }
}

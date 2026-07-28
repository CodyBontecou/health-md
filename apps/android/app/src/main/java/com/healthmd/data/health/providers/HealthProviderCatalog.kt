package com.healthmd.data.health.providers

import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * First-class catalog of health ecosystems Health.md can work with.
 *
 * Health Connect remains the canonical on-device read path. The provider metadata
 * below lets the app surface vendor-specific setup paths now, while leaving clear
 * extension points for direct SDK/OAuth adapters where those APIs require app keys,
 * signatures, or partner approval.
 */
class HealthProviderCatalog(
    private val context: Context,
) {
    val definitions: List<HealthProviderDefinition> = listOf(
        HealthProviderDefinition(
            id = HealthProviderId.HEALTH_CONNECT,
            displayName = "Health Connect",
            integrationKind = HealthProviderIntegrationKind.AndroidSystem,
            packageNames = listOf("com.google.android.apps.healthdata"),
            setupPackageName = "com.google.android.apps.healthdata",
            summary = "Default Android health hub used for private on-device exports.",
            setupDescription = "Grant Health Connect permissions from the Export screen. Health.md reads records locally and writes them directly to your folder.",
            directExportStatus = HealthProviderDirectExportStatus.Available,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.SAMSUNG_HEALTH,
            displayName = "Samsung Health",
            integrationKind = HealthProviderIntegrationKind.HealthConnectSource,
            packageNames = listOf("com.sec.android.app.shealth"),
            setupPackageName = "com.sec.android.app.shealth",
            summary = "Samsung phones, Galaxy Watch, sleep, steps, workouts, vitals.",
            setupDescription = "Open Samsung Health and enable sharing with Health Connect. Samsung's direct Health Data SDK can be added later if partner-approved data is needed outside Health Connect.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresVendorApproval,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.HUAWEI_HEALTH,
            displayName = "Huawei Health",
            integrationKind = HealthProviderIntegrationKind.VendorSdk,
            packageNames = listOf("com.huawei.health"),
            setupPackageName = "com.huawei.health",
            webSetupUri = "https://consumer.huawei.com/en/mobileservices/health/",
            summary = "Huawei devices and HMS/AppGallery markets.",
            setupDescription = "Huawei support requires HMS Health Kit app registration and an HMS-enabled build. This catalog keeps Huawei visible without adding HMS dependencies to the Play build.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresAppConfiguration,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.FITBIT,
            displayName = "Fitbit",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.fitbit.FitbitMobile"),
            setupPackageName = "com.fitbit.FitbitMobile",
            webSetupUri = "https://dev.fitbit.com/build/reference/web-api/",
            summary = "Fitbit trackers, Pixel Watch Fitbit data, sleep, activity, heart.",
            setupDescription = "Direct Fitbit import uses the Fitbit Web API with OAuth scopes and refresh tokens. Until app credentials are configured, export Fitbit data through Health Connect where available.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.GARMIN,
            displayName = "Garmin Connect",
            integrationKind = HealthProviderIntegrationKind.PartnerApi,
            packageNames = listOf("com.garmin.android.apps.connectmobile"),
            setupPackageName = "com.garmin.android.apps.connectmobile",
            webSetupUri = "https://developer.garmin.com/health-api/overview/",
            summary = "Garmin watches, training, activity, sleep, body battery-style metrics.",
            setupDescription = "Garmin production imports require Garmin Health API partner approval and usually a backend/webhook sync path. Health.md excludes Google Fit fallbacks by design.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresPartnerApproval,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.WITHINGS,
            displayName = "Withings",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.withings.wiscale2"),
            setupPackageName = "com.withings.wiscale2",
            webSetupUri = "https://developer.withings.com/",
            summary = "Withings scales, watches, blood pressure, sleep mats.",
            setupDescription = "Direct Withings import uses OAuth 2.0 and the Withings public API. Configure client credentials before enabling live cloud reads.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.OURA,
            displayName = "Oura",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.ouraring.oura"),
            setupPackageName = "com.ouraring.oura",
            webSetupUri = "https://cloud.ouraring.com/docs/",
            summary = "Oura Ring sleep, readiness, activity, heart rate, HRV.",
            setupDescription = "Direct Oura import uses the Oura Cloud API with OAuth 2.0. Configure client credentials before enabling live cloud reads.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.POLAR,
            displayName = "Polar Flow",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("fi.polar.polarflow"),
            setupPackageName = "fi.polar.polarflow",
            webSetupUri = "https://www.polar.com/accesslink-api/",
            summary = "Polar training, heart-rate devices, sleep/activity via AccessLink.",
            setupDescription = "Historical Polar import should use Polar AccessLink OAuth. BLE sensor support is a separate future live-session feature, not a replacement for history export.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.WHOOP,
            displayName = "WHOOP",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.whoop.android"),
            setupPackageName = "com.whoop.android",
            webSetupUri = "https://developer.whoop.com/",
            summary = "WHOOP recovery, strain, sleep, workouts, physiology.",
            setupDescription = "Direct WHOOP import uses the WHOOP API with OAuth scopes for cycles, recovery, sleep, workouts, and profile data.",
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
    )

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
}

data class HealthProviderDefinition(
    val id: HealthProviderId,
    val displayName: String,
    val integrationKind: HealthProviderIntegrationKind,
    val packageNames: List<String>,
    val summary: String,
    val setupDescription: String,
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
    val actionLabel: String
        get() = if (isInstalled) "Open" else "Install / setup"
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

enum class HealthProviderIntegrationKind(val label: String) {
    AndroidSystem("Android system"),
    HealthConnectSource("Health Connect source"),
    VendorSdk("Vendor SDK"),
    CloudApi("Cloud API"),
    PartnerApi("Partner API"),
}

enum class HealthProviderDirectExportStatus(val label: String) {
    Available("Export-ready"),
    RequiresOAuthCredentials("Needs OAuth credentials"),
    RequiresVendorApproval("Needs vendor approval"),
    RequiresPartnerApproval("Needs partner approval"),
    RequiresAppConfiguration("Needs app configuration"),
}

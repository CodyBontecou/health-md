package com.healthmd.data.health.providers

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.annotation.StringRes
import androidx.health.connect.client.HealthConnectClient
import com.healthmd.R

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
            summaryRes = R.string.health_provider_health_connect_summary,
            setupDescriptionRes = R.string.health_provider_health_connect_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.Available,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.SAMSUNG_HEALTH,
            displayName = "Samsung Health",
            integrationKind = HealthProviderIntegrationKind.HealthConnectSource,
            packageNames = listOf("com.sec.android.app.shealth"),
            setupPackageName = "com.sec.android.app.shealth",
            summaryRes = R.string.health_provider_samsung_health_summary,
            setupDescriptionRes = R.string.health_provider_samsung_health_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresVendorApproval,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.HUAWEI_HEALTH,
            displayName = "Huawei Health",
            integrationKind = HealthProviderIntegrationKind.VendorSdk,
            packageNames = listOf("com.huawei.health"),
            setupPackageName = "com.huawei.health",
            webSetupUri = "https://consumer.huawei.com/en/mobileservices/health/",
            summaryRes = R.string.health_provider_huawei_health_summary,
            setupDescriptionRes = R.string.health_provider_huawei_health_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresAppConfiguration,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.FITBIT,
            displayName = "Fitbit",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.fitbit.FitbitMobile"),
            setupPackageName = "com.fitbit.FitbitMobile",
            webSetupUri = "https://dev.fitbit.com/build/reference/web-api/",
            summaryRes = R.string.health_provider_fitbit_summary,
            setupDescriptionRes = R.string.health_provider_fitbit_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.GARMIN,
            displayName = "Garmin Connect",
            integrationKind = HealthProviderIntegrationKind.PartnerApi,
            packageNames = listOf("com.garmin.android.apps.connectmobile"),
            setupPackageName = "com.garmin.android.apps.connectmobile",
            webSetupUri = "https://developer.garmin.com/health-api/overview/",
            summaryRes = R.string.health_provider_garmin_summary,
            setupDescriptionRes = R.string.health_provider_garmin_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresPartnerApproval,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.WITHINGS,
            displayName = "Withings",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.withings.wiscale2"),
            setupPackageName = "com.withings.wiscale2",
            webSetupUri = "https://developer.withings.com/",
            summaryRes = R.string.health_provider_withings_summary,
            setupDescriptionRes = R.string.health_provider_withings_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.OURA,
            displayName = "Oura",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.ouraring.oura"),
            setupPackageName = "com.ouraring.oura",
            webSetupUri = "https://cloud.ouraring.com/docs/",
            summaryRes = R.string.health_provider_oura_summary,
            setupDescriptionRes = R.string.health_provider_oura_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.POLAR,
            displayName = "Polar Flow",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("fi.polar.polarflow"),
            setupPackageName = "fi.polar.polarflow",
            webSetupUri = "https://www.polar.com/accesslink-api/",
            summaryRes = R.string.health_provider_polar_summary,
            setupDescriptionRes = R.string.health_provider_polar_setup_description,
            directExportStatus = HealthProviderDirectExportStatus.RequiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.WHOOP,
            displayName = "WHOOP",
            integrationKind = HealthProviderIntegrationKind.CloudApi,
            packageNames = listOf("com.whoop.android"),
            setupPackageName = "com.whoop.android",
            webSetupUri = "https://developer.whoop.com/",
            summaryRes = R.string.health_provider_whoop_summary,
            setupDescriptionRes = R.string.health_provider_whoop_setup_description,
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

enum class HealthProviderIntegrationKind(
    @StringRes val labelRes: Int,
    private val diagnosticLabel: String,
) {
    AndroidSystem(R.string.health_provider_integration_android_system, "Android system"),
    HealthConnectSource(R.string.health_provider_integration_health_connect_source, "Health Connect source"),
    VendorSdk(R.string.health_provider_integration_vendor_sdk, "Vendor SDK"),
    CloudApi(R.string.health_provider_integration_cloud_api, "Cloud API"),
    PartnerApi(R.string.health_provider_integration_partner_api, "Partner API");

    /** Stable diagnostics value; user-facing presentation must use [labelRes]. */
    val label: String
        get() = diagnosticLabel
}

enum class HealthProviderDirectExportStatus(
    @StringRes val labelRes: Int,
    private val diagnosticLabel: String,
) {
    Available(R.string.health_provider_direct_export_available, "Export-ready"),
    RequiresOAuthCredentials(
        R.string.health_provider_direct_export_requires_oauth_credentials,
        "Needs OAuth credentials",
    ),
    RequiresVendorApproval(
        R.string.health_provider_direct_export_requires_vendor_approval,
        "Needs vendor approval",
    ),
    RequiresPartnerApproval(
        R.string.health_provider_direct_export_requires_partner_approval,
        "Needs partner approval",
    ),
    RequiresAppConfiguration(
        R.string.health_provider_direct_export_requires_app_configuration,
        "Needs app configuration",
    );

    /** Stable diagnostics value; user-facing presentation must use [labelRes]. */
    val label: String
        get() = diagnosticLabel
}

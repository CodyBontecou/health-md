package com.healthmd.data.health.providers

import com.healthmd.R

object PlayHealthProviderDefinitions {
    private val healthConnectSource = HealthProviderIntegrationKind(
        R.string.health_provider_integration_health_connect_source,
        "Health Connect source",
    )
    private val vendorSdk = HealthProviderIntegrationKind(
        R.string.health_provider_integration_vendor_sdk,
        "Vendor SDK",
    )
    private val cloudApi = HealthProviderIntegrationKind(
        R.string.health_provider_integration_cloud_api,
        "Cloud API",
    )
    private val partnerApi = HealthProviderIntegrationKind(
        R.string.health_provider_integration_partner_api,
        "Partner API",
    )
    private val requiresOAuthCredentials = HealthProviderDirectExportStatus(
        R.string.health_provider_direct_export_requires_oauth_credentials,
        "Needs OAuth credentials",
    )
    private val requiresVendorApproval = HealthProviderDirectExportStatus(
        R.string.health_provider_direct_export_requires_vendor_approval,
        "Needs vendor approval",
    )
    private val requiresPartnerApproval = HealthProviderDirectExportStatus(
        R.string.health_provider_direct_export_requires_partner_approval,
        "Needs partner approval",
    )
    private val requiresAppConfiguration = HealthProviderDirectExportStatus(
        R.string.health_provider_direct_export_requires_app_configuration,
        "Needs app configuration",
    )

    fun all(): List<HealthProviderDefinition> = listOf(
        HealthProviderCatalog.healthConnectDefinition(),
        HealthProviderDefinition(
            id = HealthProviderId.SAMSUNG_HEALTH,
            displayName = "Samsung Health",
            integrationKind = healthConnectSource,
            packageNames = listOf("com.sec.android.app.shealth"),
            setupPackageName = "com.sec.android.app.shealth",
            summaryRes = R.string.health_provider_samsung_health_summary,
            setupDescriptionRes = R.string.health_provider_samsung_health_setup_description,
            directExportStatus = requiresVendorApproval,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.HUAWEI_HEALTH,
            displayName = "Huawei Health",
            integrationKind = vendorSdk,
            packageNames = listOf("com.huawei.health"),
            setupPackageName = "com.huawei.health",
            webSetupUri = "https://consumer.huawei.com/en/mobileservices/health/",
            summaryRes = R.string.health_provider_huawei_health_summary,
            setupDescriptionRes = R.string.health_provider_huawei_health_setup_description,
            directExportStatus = requiresAppConfiguration,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.FITBIT,
            displayName = "Fitbit",
            integrationKind = cloudApi,
            packageNames = listOf("com.fitbit.FitbitMobile"),
            setupPackageName = "com.fitbit.FitbitMobile",
            webSetupUri = "https://dev.fitbit.com/build/reference/web-api/",
            summaryRes = R.string.health_provider_fitbit_summary,
            setupDescriptionRes = R.string.health_provider_fitbit_setup_description,
            directExportStatus = requiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.GARMIN,
            displayName = "Garmin Connect",
            integrationKind = partnerApi,
            packageNames = listOf("com.garmin.android.apps.connectmobile"),
            setupPackageName = "com.garmin.android.apps.connectmobile",
            webSetupUri = "https://developer.garmin.com/health-api/overview/",
            summaryRes = R.string.health_provider_garmin_summary,
            setupDescriptionRes = R.string.health_provider_garmin_setup_description,
            directExportStatus = requiresPartnerApproval,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.WITHINGS,
            displayName = "Withings",
            integrationKind = cloudApi,
            packageNames = listOf("com.withings.wiscale2"),
            setupPackageName = "com.withings.wiscale2",
            webSetupUri = "https://developer.withings.com/",
            summaryRes = R.string.health_provider_withings_summary,
            setupDescriptionRes = R.string.health_provider_withings_setup_description,
            directExportStatus = requiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.OURA,
            displayName = "Oura",
            integrationKind = cloudApi,
            packageNames = listOf("com.ouraring.oura"),
            setupPackageName = "com.ouraring.oura",
            webSetupUri = "https://cloud.ouraring.com/docs/",
            summaryRes = R.string.health_provider_oura_summary,
            setupDescriptionRes = R.string.health_provider_oura_setup_description,
            directExportStatus = requiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.POLAR,
            displayName = "Polar Flow",
            integrationKind = cloudApi,
            packageNames = listOf("fi.polar.polarflow"),
            setupPackageName = "fi.polar.polarflow",
            webSetupUri = "https://www.polar.com/accesslink-api/",
            summaryRes = R.string.health_provider_polar_summary,
            setupDescriptionRes = R.string.health_provider_polar_setup_description,
            directExportStatus = requiresOAuthCredentials,
        ),
        HealthProviderDefinition(
            id = HealthProviderId.WHOOP,
            displayName = "WHOOP",
            integrationKind = cloudApi,
            packageNames = listOf("com.whoop.android"),
            setupPackageName = "com.whoop.android",
            webSetupUri = "https://developer.whoop.com/",
            summaryRes = R.string.health_provider_whoop_summary,
            setupDescriptionRes = R.string.health_provider_whoop_setup_description,
            directExportStatus = requiresOAuthCredentials,
        ),
    )
}

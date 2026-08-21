import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
}

// Load signing properties from local.properties
val localProperties = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

fun configuredValue(name: String): String =
    providers.gradleProperty(name)
        .orElse(providers.environmentVariable(name))
        .getOrElse("")

fun configuredEngineMode(name: String): String =
    configuredValue(name).takeIf { it == "legacy" || it == "shadow" || it == "rust" }
        ?: "legacy"

fun String.asBuildConfigString(): String = "\"${
    replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}\""

val campaignAttributionEndpointUrl = configuredValue("CAMPAIGN_ATTRIBUTION_ENDPOINT_URL")
val campaignAttributionIngestToken = configuredValue("CAMPAIGN_ATTRIBUTION_INGEST_TOKEN")
val onboardingAnalyticsEndpointUrl = configuredValue("ONBOARDING_ANALYTICS_ENDPOINT_URL")
    .ifBlank { "https://health-md-pricing-analytics.costream.workers.dev" }
val exportEngineAndroidFrozenV4 = configuredEngineMode("EXPORT_ENGINE_ANDROID_FROZEN_V4")
val exportEngineAndroidAnalyticalV5 = configuredEngineMode("EXPORT_ENGINE_ANDROID_ANALYTICAL_V5")
val exportEngineApiV1FrozenV4 = configuredEngineMode("EXPORT_ENGINE_API_V1_FROZEN_V4")
val directProtocolEngine = configuredEngineMode("DIRECT_PROTOCOL_ENGINE")
val practiceCompiledIn = configuredValue("PRACTICE_COMPILED_IN") == "included"
val googleDriveAndroidClientId = configuredValue("GOOGLE_DRIVE_ANDROID_CLIENT_ID")
val instrumentedTestBuildType = providers.gradleProperty("healthmdInstrumentedTestBuildType")
    .getOrElse("debug")
    .also { require(it in setOf("debug", "e2e")) }

android {
    namespace = "com.healthmd"
    compileSdk = 36
    ndkVersion = "27.1.12297006"

    defaultConfig {
        applicationId = "com.healthmd.android"
        minSdk = 28
        targetSdk = 35
        versionCode = 29
        versionName = "1.7.1"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
        }

        buildConfigField("String", "FITBIT_CLIENT_ID", "\"${project.findProperty("FITBIT_CLIENT_ID") as? String ?: ""}\"")
        buildConfigField("String", "FITBIT_TOKEN_BROKER_URL", "\"${project.findProperty("FITBIT_TOKEN_BROKER_URL") as? String ?: ""}\"")
        buildConfigField("String", "WITHINGS_CLIENT_ID", "\"${project.findProperty("WITHINGS_CLIENT_ID") as? String ?: ""}\"")
        buildConfigField("String", "WITHINGS_TOKEN_BROKER_URL", "\"${project.findProperty("WITHINGS_TOKEN_BROKER_URL") as? String ?: ""}\"")
        buildConfigField("String", "OURA_CLIENT_ID", "\"${project.findProperty("OURA_CLIENT_ID") as? String ?: ""}\"")
        buildConfigField("String", "OURA_TOKEN_BROKER_URL", "\"${project.findProperty("OURA_TOKEN_BROKER_URL") as? String ?: ""}\"")
        buildConfigField("String", "POLAR_CLIENT_ID", "\"${project.findProperty("POLAR_CLIENT_ID") as? String ?: ""}\"")
        buildConfigField("String", "POLAR_TOKEN_BROKER_URL", "\"${project.findProperty("POLAR_TOKEN_BROKER_URL") as? String ?: ""}\"")
        buildConfigField("String", "WHOOP_CLIENT_ID", "\"${project.findProperty("WHOOP_CLIENT_ID") as? String ?: ""}\"")
        buildConfigField("String", "WHOOP_TOKEN_BROKER_URL", "\"${project.findProperty("WHOOP_TOKEN_BROKER_URL") as? String ?: ""}\"")
        buildConfigField(
            "String",
            "CAMPAIGN_ATTRIBUTION_ENDPOINT_URL",
            campaignAttributionEndpointUrl.asBuildConfigString(),
        )
        buildConfigField(
            "String",
            "CAMPAIGN_ATTRIBUTION_INGEST_TOKEN",
            campaignAttributionIngestToken.asBuildConfigString(),
        )
        buildConfigField(
            "String",
            "ONBOARDING_ANALYTICS_ENDPOINT_URL",
            onboardingAnalyticsEndpointUrl.asBuildConfigString(),
        )
        buildConfigField(
            "String",
            "EXPORT_ENGINE_ANDROID_FROZEN_V4",
            exportEngineAndroidFrozenV4.asBuildConfigString(),
        )
        buildConfigField(
            "String",
            "EXPORT_ENGINE_ANDROID_ANALYTICAL_V5",
            exportEngineAndroidAnalyticalV5.asBuildConfigString(),
        )
        buildConfigField(
            "String",
            "EXPORT_ENGINE_API_V1_FROZEN_V4",
            exportEngineApiV1FrozenV4.asBuildConfigString(),
        )
        buildConfigField(
            "String",
            "DIRECT_PROTOCOL_ENGINE",
            directProtocolEngine.asBuildConfigString(),
        )
        buildConfigField(
            "boolean",
            "PRACTICE_COMPILED_IN",
            practiceCompiledIn.toString(),
        )
        // Public Android OAuth client identifier only. No client secret is shipped.
        buildConfigField(
            "String",
            "GOOGLE_DRIVE_ANDROID_CLIENT_ID",
            googleDriveAndroidClientId.asBuildConfigString(),
        )
    }

    signingConfigs {
        create("release") {
            storeFile = file(localProperties.getProperty("RELEASE_STORE_FILE", "health-md-release.jks"))
            storePassword = localProperties.getProperty("RELEASE_STORE_PASSWORD")
            keyAlias = localProperties.getProperty("RELEASE_KEY_ALIAS")
            keyPassword = localProperties.getProperty("RELEASE_KEY_PASSWORD")
        }
    }

    buildTypes {
        debug {
            isPseudoLocalesEnabled = true
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
        create("e2e") {
            initWith(getByName("debug"))
            applicationIdSuffix = ".e2e"
            versionNameSuffix = "-e2e"
            matchingFallbacks += listOf("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    androidResources {
        generateLocaleConfig = true
    }

    testBuildType = instrumentedTestBuildType

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    packaging {
        resources.excludes += "META-INF/versions/9/OSGI-INF/MANIFEST.MF"
    }
}

dependencies {
    implementation(project(":direct-protocol"))
    implementation(project(":healthmd-core"))
    implementation(project(":wearable-contract"))

    // Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
    add("e2eImplementation", libs.compose.ui.test.manifest)

    // AndroidX
    implementation(libs.core.ktx)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.navigation.compose)
    implementation(libs.glance)
    implementation(libs.glance.appwidget)
    implementation(libs.play.services.wearable)
    implementation(libs.play.services.auth)

    // Health Connect
    implementation(libs.health.connect)

    // Hilt
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.navigation.compose)
    implementation(libs.hilt.work)
    ksp(libs.hilt.work.compiler)

    // WorkManager
    implementation(libs.work.runtime.ktx)

    // DataStore
    implementation(libs.datastore.preferences)

    // Encrypted OAuth/API credential storage
    implementation(libs.security.crypto)

    // Direct HTTPS API endpoint exports
    implementation(libs.okhttp)

    // Room
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)

    // Billing
    implementation(libs.billing.ktx)

    // Google Play campaign install attribution (no analytics SDK)
    implementation(libs.install.referrer)

    // Play In-App Review
    implementation(libs.play.review)
    implementation(libs.play.review.ktx)

    // Tagged, on-device PDF authoring. The port is Apache-2.0. Its obsolete
    // Bouncy Castle transitives are excluded because direct-protocol already supplies bcprov-jdk18on.
    implementation(libs.pdfbox.android) {
        exclude(group = "org.bouncycastle")
    }

    // Logging
    implementation(libs.timber)

    // Kotlinx
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.kotlinx.coroutines.android)

    // Testing
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    testImplementation(kotlin("reflect"))
    testImplementation(libs.mockk)
    testImplementation(libs.truth)
    testImplementation(libs.okhttp.mockwebserver)
    testImplementation(libs.okhttp.tls)
    testImplementation(libs.glance.testing)
    testImplementation(libs.glance.appwidget.testing)
    testImplementation(libs.androidx.test.core)
    testImplementation(libs.robolectric)
    testImplementation(libs.work.testing)
    testImplementation("com.networknt:json-schema-validator:1.5.9")
    androidTestImplementation(libs.androidx.test.ext)
    androidTestImplementation(libs.androidx.test.core)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.espresso.core)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
}

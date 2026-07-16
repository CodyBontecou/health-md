import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.hilt)
    alias(libs.plugins.ksp)
    alias(libs.plugins.play.publisher)
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

fun String.asBuildConfigString(): String = "\"${
    replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
}\""

val campaignAttributionEndpointUrl = configuredValue("CAMPAIGN_ATTRIBUTION_ENDPOINT_URL")
val campaignAttributionIngestToken = configuredValue("CAMPAIGN_ATTRIBUTION_INGEST_TOKEN")

android {
    namespace = "com.healthmd"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.healthmd.android"
        minSdk = 28
        targetSdk = 35
        versionCode = 20
        versionName = "1.5.2"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"

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
}

dependencies {
    // Compose
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.graphics)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // AndroidX
    implementation(libs.core.ktx)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.navigation.compose)

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
    androidTestImplementation(libs.androidx.test.ext)
    androidTestImplementation(platform(libs.compose.bom))
    androidTestImplementation(libs.compose.ui.test.junit4)
}

// Google Play Publisher Configuration
play {
    val configuredPath =
        System.getenv("PLAY_CONSOLE_KEY_PATH")
            ?: providers.gradleProperty("PLAY_CONSOLE_KEY_PATH").orNull
            ?: "${System.getProperty("user.home")}/.config/play-console/play-publisher-crested-drive-492000-u7.json"

    val serviceKeyFile = file(configuredPath)
    if (serviceKeyFile.exists()) {
        serviceAccountCredentials.set(serviceKeyFile)
    }

    track.set("internal")
    defaultToAppBundles.set(true)
}

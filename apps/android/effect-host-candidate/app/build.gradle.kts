import java.security.MessageDigest
import org.gradle.api.artifacts.component.ProjectComponentIdentifier

plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val auditBuildTools by configurations.creating { isCanBeConsumed = false; isCanBeResolved = true }

android {
    namespace = "com.healthmd.effecthostcandidate"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    defaultConfig {
        applicationId = "com.healthmd.effecthost.androidcandidate"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.0-candidate.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64") }
    }
    flavorDimensions += "distribution"
    productFlavors { create("play") { dimension = "distribution"; applicationIdSuffix = ".play" } }
    signingConfigs {
        create("candidateTest") {
            storeFile = rootProject.file(".test-signing/candidate-test.p12")
            storePassword = "healthmd-private-test-only"
            keyAlias = "candidate-test"
            keyPassword = "healthmd-private-test-only"
            storeType = "PKCS12"
        }
    }
    buildTypes {
        release {
            isDebuggable = false
            isMinifyEnabled = true
            signingConfig = signingConfigs.getByName("candidateTest")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            testProguardFiles("proguard-rules.pro")
        }
    }
    testBuildType = "release"
    sourceSets["main"].assets.srcDir(rootProject.file("dist/assets"))
    // RN's vendored fbjni and the exact transitive fbjni AAR have identical bytes in all four ABIs.
    packaging { jniLibs.pickFirsts += "**/libfbjni.so" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    auditBuildTools("com.android.tools.build:aapt2:9.2.1-15009934:osx")
    implementation("com.facebook.react:react-android:0.87.1")
    implementation("com.facebook.hermes:hermes-android:250829098.0.17")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
    androidTestImplementation("androidx.test:runner:1.7.0")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    // These test-API annotations are referenced by R8 in the non-debuggable test APK.
    androidTestImplementation("com.google.errorprone:error_prone_annotations:2.28.0")
}

dependencyLocking { lockAllConfigurations() }

// Resolve and hash actual artifacts without compiling or executing the candidate.
tasks.register("auditResolvedArtifacts") {
    doLast {
        val rows = mutableListOf<String>()
        for (name in listOf("auditBuildTools", "kotlinCompilerClasspath", "playReleaseRuntimeClasspath", "playReleaseUnitTestRuntimeClasspath", "playReleaseAndroidTestRuntimeClasspath")) {
            for (artifact in configurations.getByName(name).resolvedConfiguration.resolvedArtifacts.sortedBy { it.moduleVersion.id.toString() }) {
                if (artifact.id.componentIdentifier is ProjectComponentIdentifier) continue
                val hash = MessageDigest.getInstance("SHA-256").digest(artifact.file.readBytes()).joinToString("") { "%02x".format(it) }
                rows += "$name\t${artifact.moduleVersion.id}\t${artifact.file.name}\t$hash"
            }
        }
        val output = rootProject.file("dist/audit/resolved-artifacts.tsv")
        output.parentFile.mkdirs(); output.writeText(rows.joinToString("\n", postfix = "\n"))
    }
}

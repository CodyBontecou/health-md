import java.util.Properties
import org.gradle.api.GradleException
import org.gradle.api.tasks.Exec
import org.gradle.api.tasks.testing.Test

plugins {
    alias(libs.plugins.android.library)
    alias(libs.plugins.kotlin.android)
}

val pinnedNdkVersion = "27.1.12297006"
val expectedAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
val rustWorkspace = rootProject.layout.projectDirectory.dir("../../packages/healthmd-core-rust")
val rustBuildScript = rustWorkspace.file("scripts/build-android-cdylibs.sh")
val bindingsScript = rustWorkspace.file("scripts/generate-kotlin-bindings.sh")
val committedBindings = layout.projectDirectory.file(
    "src/main/kotlin/com/healthmd/core/healthmd_core_uniffi.kt",
)
val generatedBindingsDirectory = layout.buildDirectory.dir("generated/bindings/kotlin")
val generatedBindings = generatedBindingsDirectory.map {
    it.file("com/healthmd/core/healthmd_core_uniffi.kt")
}
val debugJniDirectory = layout.buildDirectory.dir("generated/jniLibs/debug")
val releaseJniDirectory = layout.buildDirectory.dir("generated/jniLibs/release")

fun androidSdkDirectory(): File? {
    val environmentPath = System.getenv("ANDROID_SDK_ROOT")
        ?: System.getenv("ANDROID_HOME")
    if (!environmentPath.isNullOrBlank()) return file(environmentPath)

    val localPropertiesFile = rootProject.file("local.properties")
    if (!localPropertiesFile.isFile) return null
    val properties = Properties().apply {
        localPropertiesFile.inputStream().use(::load)
    }
    return properties.getProperty("sdk.dir")?.takeIf(String::isNotBlank)?.let(::file)
}

val rustSourceInputs = fileTree(rustWorkspace) {
    include("Cargo.lock")
    include("Cargo.toml")
    include("rust-toolchain.toml")
    include("crates/**/*.rs")
    include("crates/**/*.toml")
    include("crates/**/*.json")
    include("xtask/**/*.rs")
    include("xtask/**/*.toml")
    exclude("target/**")
}

fun registerRustPreparation(
    taskName: String,
    profile: String,
    outputDirectory: Provider<Directory>,
) = tasks.register<Exec>(taskName) {
    group = "build"
    description = "Builds the $profile Health.md Rust cdylib for every supported Android ABI."
    inputs.files(rustSourceInputs, rustBuildScript)
    inputs.property("androidNdkVersion", pinnedNdkVersion)
    inputs.property("androidAbis", expectedAbis)
    inputs.property("rustProfile", profile)
    outputs.dir(outputDirectory)

    environment(
        "CARGO_TARGET_DIR",
        layout.buildDirectory.dir("rust-target/android-$profile").get().asFile.absolutePath,
    )
    commandLine(rustBuildScript.asFile.absolutePath, profile, outputDirectory.get().asFile.absolutePath)

    doFirst {
        val sdkDirectory = androidSdkDirectory()
            ?: throw GradleException(
                "Android SDK is missing. Set ANDROID_SDK_ROOT or sdk.dir in apps/android/local.properties, " +
                    "then install NDK $pinnedNdkVersion.",
            )
        val ndkDirectory = sdkDirectory.resolve("ndk/$pinnedNdkVersion")
        if (!ndkDirectory.isDirectory) {
            throw GradleException(
                "Android NDK $pinnedNdkVersion is missing at $ndkDirectory. " +
                    "Install it with: sdkmanager 'ndk;$pinnedNdkVersion'",
            )
        }
        environment("ANDROID_NDK_HOME", ndkDirectory.absolutePath)
        environment("ANDROID_NDK_ROOT", ndkDirectory.absolutePath)
    }
}

val prepareRustDebug = registerRustPreparation(
    taskName = "prepareRustDebug",
    profile = "debug",
    outputDirectory = debugJniDirectory,
)
val prepareRustRelease = registerRustPreparation(
    taskName = "prepareRustRelease",
    profile = "release",
    outputDirectory = releaseJniDirectory,
)

val generateKotlinBindings = tasks.register<Exec>("generateHealthMdCoreKotlinBindings") {
    group = "verification"
    description = "Regenerates the pinned UniFFI Kotlin binding into the build directory."
    inputs.files(rustSourceInputs, bindingsScript)
    outputs.dir(generatedBindingsDirectory)
    environment(
        "CARGO_TARGET_DIR",
        layout.buildDirectory.dir("rust-target/bindings-host").get().asFile.absolutePath,
    )
    commandLine(bindingsScript.asFile.absolutePath, generatedBindingsDirectory.get().asFile.absolutePath)
}

val checkKotlinBindings = tasks.register("checkHealthMdCoreKotlinBindings") {
    group = "verification"
    description = "Fails when the committed UniFFI 0.32 Kotlin binding has drifted from Rust source."
    dependsOn(generateKotlinBindings)
    inputs.file(committedBindings)
    inputs.file(generatedBindings)

    doLast {
        val committedFile = committedBindings.asFile
        val generatedFile = generatedBindings.get().asFile
        if (!committedFile.isFile) {
            throw GradleException("Committed UniFFI binding is missing: $committedFile")
        }
        if (!generatedFile.isFile) {
            throw GradleException("Pinned UniFFI generation did not produce: $generatedFile")
        }
        if (!committedFile.readBytes().contentEquals(generatedFile.readBytes())) {
            throw GradleException(
                "Committed UniFFI Kotlin bindings have drifted. Regenerate with " +
                    "packages/healthmd-core-rust/scripts/generate-kotlin-bindings.sh " +
                    "apps/android/healthmd-core/src/main/kotlin",
            )
        }
    }
}

android {
    namespace = "com.healthmd.core"
    compileSdk = 36
    ndkVersion = pinnedNdkVersion

    defaultConfig {
        minSdk = 28
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
        ndk {
            abiFilters += expectedAbis
        }
    }

    buildTypes {
        debug {
            ndk.debugSymbolLevel = "FULL"
        }
        release {
            ndk.debugSymbolLevel = "FULL"
        }
    }

    sourceSets {
        getByName("debug").jniLibs.srcDir(debugJniDirectory)
        getByName("release").jniLibs.srcDir(releaseJniDirectory)
    }

    packaging {
        jniLibs.keepDebugSymbols += "**/libhealthmd_core_uniffi.so"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

tasks.matching { it.name == "preDebugBuild" || it.name == "mergeDebugJniLibFolders" }
    .configureEach {
        dependsOn(prepareRustDebug)
    }
tasks.matching { it.name == "preReleaseBuild" || it.name == "mergeReleaseJniLibFolders" }
    .configureEach {
        dependsOn(prepareRustRelease)
    }
tasks.matching { it.name == "check" }.configureEach {
    dependsOn(checkKotlinBindings)
}
tasks.withType<Test>().configureEach {
    dependsOn(generateKotlinBindings)
    systemProperty("healthmd.core.bindings.committed", committedBindings.asFile.absolutePath)
    systemProperty("healthmd.core.bindings.generated", generatedBindings.get().asFile.absolutePath)
}

dependencies {
    implementation("net.java.dev.jna:jna:${libs.versions.jna.get()}@aar")

    testImplementation(libs.junit)
    testImplementation(libs.truth)
    androidTestImplementation(libs.androidx.test.ext)
    androidTestImplementation(libs.androidx.test.runner)
    androidTestImplementation(libs.truth)
}

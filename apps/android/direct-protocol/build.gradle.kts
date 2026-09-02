plugins {
    id("org.jetbrains.kotlin.jvm")
    alias(libs.plugins.kotlin.serialization)
}

kotlin {
    jvmToolchain(17)
}

sourceSets {
    test {
        resources.srcDirs(
            rootProject.layout.projectDirectory.dir(
                "../../packages/contracts/direct-protocol/v2/fixtures",
            ),
            rootProject.layout.projectDirectory.dir(
                "../../packages/contracts/direct-protocol/pairing-v3/fixtures",
            ),
        )
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)
    implementation(libs.bouncycastle)

    testImplementation(libs.junit)
    testImplementation(libs.truth)
}

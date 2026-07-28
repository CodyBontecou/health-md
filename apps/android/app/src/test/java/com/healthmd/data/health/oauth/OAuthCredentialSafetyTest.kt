package com.healthmd.data.health.oauth

import com.google.common.truth.Truth.assertThat
import com.healthmd.BuildConfig
import org.junit.Test
import java.io.File

class OAuthCredentialSafetyTest {

    @Test
    fun generatedBuildConfig_doesNotExposeProviderClientSecrets() {
        val buildConfigFieldNames = BuildConfig::class.java.fields.map { it.name }

        assertThat(buildConfigFieldNames.filter { it.contains("SECRET", ignoreCase = true) }).isEmpty()
        assertThat(buildConfigFieldNames).containsAtLeast(
            "FITBIT_CLIENT_ID",
            "WITHINGS_CLIENT_ID",
            "OURA_CLIENT_ID",
            "POLAR_CLIENT_ID",
            "WHOOP_CLIENT_ID",
            "FITBIT_TOKEN_BROKER_URL",
            "WITHINGS_TOKEN_BROKER_URL",
            "OURA_TOKEN_BROKER_URL",
            "POLAR_TOKEN_BROKER_URL",
            "WHOOP_TOKEN_BROKER_URL",
        )
    }

    @Test
    fun defaultOAuthRegistry_usesPublicClientOrTokenBrokerOnly() {
        val configs = OAuthConfigRegistry().all()

        assertThat(configs.map { it.providerId }).containsAtLeast(
            "fitbit",
            "withings",
            "oura",
            "polar",
            "whoop",
        )
        assertThat(configs.filter { it.clientSecret.isNotBlank() }).isEmpty()
        assertThat(configs.map { it.clientAuthStyle }).doesNotContain(OAuthClientAuthStyle.Basic)
    }

    @Test
    fun productionSources_doNotWireGradleClientSecretPropertiesIntoTheApk() {
        val buildGradle = repoFile("app/build.gradle.kts").readText()
        val oauthRegistry = repoFile("app/src/main/java/com/healthmd/data/health/oauth/OAuthConfigRegistry.kt").readText()

        assertThat(buildGradle).doesNotContain("CLIENT_SECRET")
        assertThat(buildGradle).doesNotContain("clientSecret")
        assertThat(oauthRegistry).doesNotContain("CLIENT_SECRET")
        assertThat(Regex("BuildConfig\\.[A-Z0-9_]*SECRET").containsMatchIn(oauthRegistry)).isFalse()
        assertThat(oauthRegistry).doesNotContain("clientSecret =")
    }

    private fun repoFile(relativePath: String): File = File(repoRoot(), relativePath).also { file ->
        assertThat(file.exists()).isTrue()
    }

    private fun repoRoot(): File {
        var dir: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (dir != null) {
            if (File(dir, "app/build.gradle.kts").exists()) return dir
            dir = dir.parentFile
        }
        error("Could not locate repo root")
    }
}

package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test
import org.w3c.dom.Element

class HealthConnectManifestContractTest {
    private val androidNamespace = "http://schemas.android.com/apk/res/android"

    @Test
    fun rationaleEntryPointsSupportStandaloneAndPlatformHealthConnect() {
        val document = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
        }.newDocumentBuilder().parse(manifestFile())

        val rationaleActivity = document.getElementsByTagName("activity").asElements()
            .single { it.androidAttribute("name") == ".presentation.HealthPermissionsRationaleActivity" }
        assertThat(rationaleActivity.androidAttribute("exported")).isEqualTo("true")
        assertThat(rationaleActivity.actions())
            .containsExactly("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")

        val platformAlias = document.getElementsByTagName("activity-alias").asElements()
            .single { it.androidAttribute("name") == ".presentation.ViewPermissionUsageActivity" }
        assertThat(platformAlias.androidAttribute("targetActivity"))
            .isEqualTo(".presentation.HealthPermissionsRationaleActivity")
        assertThat(platformAlias.androidAttribute("exported")).isEqualTo("true")
        assertThat(platformAlias.androidAttribute("permission"))
            .isEqualTo("android.permission.START_VIEW_PERMISSION_USAGE")
        assertThat(platformAlias.actions())
            .containsExactly("android.intent.action.VIEW_PERMISSION_USAGE")
        assertThat(platformAlias.categories())
            .containsExactly("android.intent.category.HEALTH_PERMISSIONS")
    }

    @Test
    fun standaloneRationaleQueryDoesNotReplaceTheActivityDeclaration() {
        val document = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
        }.newDocumentBuilder().parse(manifestFile())

        val queryActions = document.getElementsByTagName("queries").asElements()
            .flatMap { queries -> queries.getElementsByTagName("action").asElements() }
            .map { it.androidAttribute("name") }
        assertThat(queryActions).contains("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")

        val activityActions = document.getElementsByTagName("activity").asElements()
            .flatMap { it.actions() }
        assertThat(activityActions).contains("androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE")
    }

    private fun manifestFile(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val manifest = File(directory, "app/src/main/AndroidManifest.xml")
            if (manifest.exists()) return manifest
            directory = directory.parentFile
        }
        error("Could not locate app/src/main/AndroidManifest.xml")
    }

    private fun org.w3c.dom.NodeList.asElements(): List<Element> =
        (0 until length).mapNotNull { item(it) as? Element }

    private fun Element.androidAttribute(name: String): String =
        getAttributeNS(androidNamespace, name)

    private fun Element.actions(): List<String> =
        getElementsByTagName("action").asElements().map { it.androidAttribute("name") }

    private fun Element.categories(): List<String> =
        getElementsByTagName("category").asElements().map { it.androidAttribute("name") }
}

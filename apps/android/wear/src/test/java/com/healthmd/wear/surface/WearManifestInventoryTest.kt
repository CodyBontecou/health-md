package com.healthmd.wear.surface

import com.google.common.truth.Truth.assertThat
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test
import org.w3c.dom.Element

class WearManifestInventoryTest {
    @Test fun `manifest and invalidation inventory expose exactly required surfaces`() {
        val manifest = File("src/main/AndroidManifest.xml")
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(manifest)
        val services = document.getElementsByTagName("service")
        var complications = 0; var tiles = 0
        for (index in 0 until services.length) {
            val node = services.item(index)
            val name = node.attributes.getNamedItem("android:name")?.nodeValue.orEmpty()
            if (name.endsWith("ComplicationService")) complications++
            if (name.endsWith("TileService")) tiles++
        }
        assertThat(complications).isEqualTo(10)
        assertThat(tiles).isEqualTo(2)
        assertThat(ALL_COMPLICATION_SERVICES).hasSize(10)
        assertThat(ALL_TILE_SERVICES).hasSize(2)
    }

    @Test fun `manifest has no autonomous battery work and disables backup`() {
        val application = parsedManifest().getElementsByTagName("application").item(0) as Element
        assertThat(application.getAttribute("android:allowBackup")).isEqualTo("false")
        assertThat(application.getAttribute("android:fullBackupContent")).isEqualTo("false")

        val document = parsedManifest()
        assertThat(document.getElementsByTagName("uses-permission").asElements().map {
            it.getAttribute("android:name")
        }).containsExactly("android.permission.RECEIVE_BOOT_COMPLETED")
        val diagnostics = document.getElementsByTagName("provider").asElements().single()
        assertThat(diagnostics.getAttribute("android:name")).isEqualTo(".sync.WearDiagnosticsProvider")
        assertThat(diagnostics.getAttribute("android:permission")).isEqualTo("android.permission.DUMP")
        assertThat(diagnostics.getAttribute("android:exported")).isEqualTo("true")

        assertThat(document.getElementsByTagName("service").asElements().flatMap {
            it.getElementsByTagName("meta-data").asElements()
        }.filter { it.getAttribute("android:name") == "android.support.wearable.complications.UPDATE_PERIOD_SECONDS" }
            .map { it.getAttribute("android:value") }).containsExactlyElementsIn(List(10) { "0" })
    }

    private fun parsedManifest() = DocumentBuilderFactory.newInstance().newDocumentBuilder()
        .parse(File("src/main/AndroidManifest.xml"))

    private fun org.w3c.dom.NodeList.asElements(): List<Element> =
        (0 until length).map { item(it) as Element }
}

package com.healthmd.localization

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test

/** The Archive, Automations and Export now strings ship in every supported locale. */
class RedesignLocalizationTest {
    @Test
    fun everyLocaleTranslatesEveryRedesignString() {
        val canonical = strings(File(resourceRoot(), "values/redesign.xml"))
        assertThat(canonical).isNotEmpty()
        val locales = resourceRoot().listFiles().orEmpty()
            .filter { it.isDirectory && File(it, "strings.xml").isFile && it.name.startsWith("values-") }
        assertThat(locales).isNotEmpty()
        locales.forEach { folder ->
            val file = File(folder, "redesign.xml")
            assertWithMessage("${folder.name}/redesign.xml exists").that(file.isFile).isTrue()
            val localized = strings(file)
            assertWithMessage("keys in ${folder.name}/redesign.xml")
                .that(localized.keys)
                .containsExactlyElementsIn(canonical.keys)
            canonical.forEach { (name, value) ->
                assertWithMessage("format arguments of $name in ${folder.name}")
                    .that(arguments(localized.getValue(name)))
                    .containsExactlyElementsIn(arguments(value))
            }
        }
    }

    @Test
    fun theCliNameStaysLiteral() {
        resourceRoot().listFiles().orEmpty()
            .map { File(it, "redesign.xml") }
            .filter { it.isFile }
            .forEach { file ->
                assertWithMessage("automations_subtitle in ${file.parentFile.name}")
                    .that(strings(file).getValue("automations_subtitle"))
                    .contains("healthmd")
            }
    }

    private fun arguments(value: String): Set<String> =
        Regex("%\\d+\\$[sd]").findAll(value).map { it.value }.toSet()

    private fun strings(file: File): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = document.getElementsByTagName("string")
        return (0 until nodes.length).associate { index ->
            val node = nodes.item(index)
            node.attributes.getNamedItem("name").nodeValue to node.textContent
        }
    }

    private fun resourceRoot(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val resources = File(directory, "app/src/main/res")
            if (resources.isDirectory) return resources
            directory = directory.parentFile
        }
        error("Could not locate app/src/main/res")
    }
}

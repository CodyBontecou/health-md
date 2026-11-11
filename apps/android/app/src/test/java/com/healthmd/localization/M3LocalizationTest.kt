package com.healthmd.localization

import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test

/** Every Material 3 completion string file (`values/m3_*.xml`) ships translated in every locale. */
class M3LocalizationTest {
    @Test
    fun everyLocaleTranslatesEveryM3String() {
        val root = resourceRoot()
        val canonicalFiles = File(root, "values").listFiles().orEmpty()
            .filter { it.name.startsWith("m3_") && it.name.endsWith(".xml") }
        val locales = root.listFiles().orEmpty()
            .filter { it.isDirectory && File(it, "strings.xml").isFile && it.name.startsWith("values-") }
        canonicalFiles.forEach { canonicalFile ->
            val canonical = strings(canonicalFile)
            locales.forEach { folder ->
                val file = File(folder, canonicalFile.name)
                assertWithMessage("${folder.name}/${canonicalFile.name} exists").that(file.isFile).isTrue()
                val localized = strings(file)
                assertWithMessage("keys in ${folder.name}/${canonicalFile.name}")
                    .that(localized.keys)
                    .containsExactlyElementsIn(canonical.keys)
                canonical.forEach { (name, value) ->
                    assertWithMessage("format arguments of $name in ${folder.name}")
                        .that(arguments(localized.getValue(name)))
                        .containsExactlyElementsIn(arguments(value))
                }
            }
        }
    }

    private fun arguments(value: String): Set<String> =
        Regex("%\\d+\\$[sd]").findAll(value).map { it.value }.toSet()

    private fun strings(file: File): Map<String, String> {
        val document = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val result = mutableMapOf<String, String>()
        listOf("string", "plurals").forEach { tag ->
            val nodes = document.getElementsByTagName(tag)
            for (index in 0 until nodes.length) {
                val node = nodes.item(index)
                result[node.attributes.getNamedItem("name").nodeValue] = node.textContent
            }
        }
        return result
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

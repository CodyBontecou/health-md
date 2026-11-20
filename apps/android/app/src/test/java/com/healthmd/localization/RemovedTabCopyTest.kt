package com.healthmd.localization

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test

/**
 * Android 4.0 replaced the Export / Schedule / History / Sync tabs with Archive, Automations,
 * Settings and the Export now sheet. English copy must not send people to a tab that no longer
 * exists. Only strings shown solely by the debug-only profiles screen are exempt.
 */
class RemovedTabCopyTest {
    @Test
    fun englishStringsDoNotReferenceRemovedTabs() {
        val offenders = File(resourceRoot(), "values").listFiles().orEmpty()
            .filter { it.isFile && it.extension == "xml" }
            .flatMap { file -> strings(file).map { (name, value) -> Triple(file.name, name, value) } }
            .filter { (_, name, value) -> removedTab.containsMatchIn(value) && name !in debugOnlyKeys }
            .map { (file, name, value) -> "$file/$name: $value" }
        assertWithMessage("release-reachable strings that mention a removed tab").that(offenders).isEmpty()
    }

    @Test
    fun exemptStringsStayDebugOnly() {
        val sources = File(resourceRoot().parentFile, "java").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .toList()
        assertThat(sources).isNotEmpty()
        debugOnlyKeys.forEach { key ->
            val users = sources.filter { it.readText().contains("R.string.$key") }.map { it.name }
            assertWithMessage("users of $key").that(users).containsExactly(DEBUG_ONLY_SCREEN)
        }
    }

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

    private companion object {
        val removedTab = Regex("\\b(Export|Schedule|History|Sync)[ -]tab\\b", RegexOption.IGNORE_CASE)

        /** Reachable only through the DEBUG start route `SubRoutes.EXPORT_PROFILES`. */
        const val DEBUG_ONLY_SCREEN = "ExportProfilesScreen.kt"
        val debugOnlyKeys = setOf(
            "m3_profiles_intro",
            "m3_profiles_destination_device_default",
            "m3_profiles_status_active",
        )
    }
}

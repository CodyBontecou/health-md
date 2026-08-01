package com.healthmd.localization

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Test
import org.w3c.dom.Element

class LocalizationContractTest {
    @Test
    fun canonicalUserFacingResourcesDoNotOptOutOfTranslation() {
        val optedOut = parseResources(resourceFile("values")).values
            .filter { it.translatable == false }
            .map { it.name }

        assertThat(optedOut).isEmpty()
    }

    @Test
    fun everySupportedLocaleContainsEveryTranslatableResource() {
        val canonical = parseResources(resourceFile("values"))
        val expectedNames = canonical.values
            .filterNot { it.translatable == false }
            .map { it.name }
            .toSet()

        supportedLocales.forEach { locale ->
            val localized = parseResources(resourceFile("values-$locale"))
            assertWithMessage("resource keys in values-$locale/strings.xml")
                .that(localized.keys)
                .containsAtLeastElementsIn(expectedNames)
        }
    }

    @Test
    fun complexPluralLocalesIncludeRequiredQuantities() {
        val requiredQuantities = mapOf(
            "ar" to setOf("zero", "one", "two", "few", "many", "other"),
            "es" to setOf("one", "many", "other"),
            "fr" to setOf("one", "many", "other"),
            "ro" to setOf("one", "few", "other"),
            "ru" to setOf("one", "few", "many", "other"),
            "uk" to setOf("one", "few", "many", "other"),
        )

        requiredQuantities.forEach { (locale, quantities) ->
            parseResources(resourceFile("values-$locale")).values
                .filter { it.kind == "plurals" }
                .forEach { plural ->
                    assertWithMessage(
                        "plural quantities for ${plural.name} in values-$locale"
                    ).that(plural.values.keys.filterNotNull())
                        .containsAtLeastElementsIn(quantities)
                }
        }
    }

    @Test
    fun technicalIdentifiersAndPathExamplesRemainLiteral() {
        val canonical = parseResources(resourceFile("values"))
        val exactResources = listOf(
            "privacy_category_sleep_permissions",
            "privacy_category_activity_permissions",
            "privacy_category_heart_permissions",
            "privacy_category_vitals_permissions",
            "privacy_category_body_permissions",
            "privacy_category_nutrition_permissions",
            "privacy_category_mobility_permissions",
            "privacy_category_reproductive_permissions",
            "privacy_category_mindfulness_permissions",
            "daily_notes_folder_hint",
            "entries_folder_hint",
        )

        supportedLocales.forEach { locale ->
            val localized = parseResources(resourceFile("values-$locale"))
            exactResources.forEach { name ->
                assertWithMessage("literal value for $name in values-$locale")
                    .that(localized.getValue(name).values.getValue(null))
                    .isEqualTo(canonical.getValue(name).values.getValue(null))
            }

            val folderHelp = localized.getValue("daily_notes_folder_help").values.getValue(null)
            assertWithMessage("folder examples in values-$locale")
                .that(folderHelp)
                .contains("Daily")
            assertWithMessage("nested folder example in values-$locale")
                .that(folderHelp)
                .contains("Journal/Daily")

            val rawDestination = localized.getValue("raw_snapshot_immutable_destination_note")
                .values.getValue(null)
            assertWithMessage("raw snapshot path in values-$locale")
                .that(rawDestination)
                .contains("health/raw")
        }
    }

    @Test
    fun localizedTemplateTokensAndLineBreaksMatchCanonicalResources() {
        val canonical = parseResources(resourceFile("values"))

        supportedLocales.forEach { locale ->
            val localized = parseResources(resourceFile("values-$locale"))
            canonical.forEach { (name, expected) ->
                val actual = localized.getValue(name)
                val expectedText = expected.values["other"]
                    ?: expected.values.values.firstOrNull().orEmpty()
                val expectedTokens = templateTokenRegex.findAll(expectedText)
                    .map { it.value }
                    .sorted()
                    .toList()
                val expectedLineBreaks = literalLineBreakRegex.findAll(expectedText).count()

                actual.values.forEach { (quantity, value) ->
                    val resourceLabel = "$name${quantity?.let { "[$it]" }.orEmpty()}"
                    assertWithMessage("template tokens for $resourceLabel in values-$locale")
                        .that(templateTokenRegex.findAll(value).map { it.value }.sorted().toList())
                        .containsExactlyElementsIn(expectedTokens)
                    assertWithMessage("line breaks for $resourceLabel in values-$locale")
                        .that(literalLineBreakRegex.findAll(value).count())
                        .isEqualTo(expectedLineBreaks)
                }
            }
        }
    }

    @Test
    fun localizedFormatArgumentsMatchCanonicalResources() {
        val canonical = parseResources(resourceFile("values"))
            .filterValues { it.translatable != false }

        supportedLocales.forEach { locale ->
            val localized = parseResources(resourceFile("values-$locale"))
            canonical.forEach { (name, expected) ->
                val actual = localized[name] ?: return@forEach
                assertWithMessage("resource kind for $name in values-$locale")
                    .that(actual.kind)
                    .isEqualTo(expected.kind)

                val expectedArguments = expected.formatArgumentTypes()
                actual.values.forEach { (quantity, value) ->
                    val resourceLabel = "$name${quantity?.let { "[$it]" }.orEmpty()}"
                    assertWithMessage("text for $resourceLabel in values-$locale")
                        .that(value.trim())
                        .isNotEmpty()
                    assertWithMessage("format arguments for $resourceLabel in values-$locale")
                        .that(formatArgumentTypes(value))
                        .containsExactlyElementsIn(expectedArguments)
                }
            }
        }
    }

    private fun parseResources(file: File): Map<String, ResourceValue> {
        val document = DocumentBuilderFactory.newInstance().apply {
            isNamespaceAware = true
        }.newDocumentBuilder().parse(file)
        val resources = buildList {
            document.documentElement.childNodes.asElements().forEach { element ->
                val name = element.getAttribute("name").takeIf { it.isNotBlank() }
                    ?: return@forEach
                when (element.tagName) {
                    "string" -> add(
                        ResourceValue(
                            name = name,
                            kind = "string",
                            translatable = element.getAttribute("translatable")
                                .takeIf { it.isNotBlank() }
                                ?.toBooleanStrict(),
                            values = mapOf(null to element.textContent),
                        )
                    )
                    "plurals" -> add(
                        ResourceValue(
                            name = name,
                            kind = "plurals",
                            translatable = element.getAttribute("translatable")
                                .takeIf { it.isNotBlank() }
                                ?.toBooleanStrict(),
                            values = element.childNodes.asElements()
                                .filter { it.tagName == "item" }
                                .associate { it.getAttribute("quantity") to it.textContent },
                        )
                    )
                }
            }
        }
        assertWithMessage("unique resource names in ${file.path}")
            .that(resources.map { it.name }.toSet().size)
            .isEqualTo(resources.size)
        return resources.associateBy { it.name }
    }

    private fun ResourceValue.formatArgumentTypes(): List<String> {
        val representative = values["other"] ?: values.values.firstOrNull().orEmpty()
        return formatArgumentTypes(representative)
    }

    private fun formatArgumentTypes(value: String): List<String> =
        formatArgumentRegex.findAll(value)
            .map { it.value.lowercase() }
            .sorted()
            .toList()

    private fun resourceFile(directoryName: String): File =
        File(resourceRoot(), "$directoryName/strings.xml").also {
            check(it.isFile) { "Missing localization file: ${it.path}" }
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

    private fun org.w3c.dom.NodeList.asElements(): List<Element> =
        (0 until length).mapNotNull { item(it) as? Element }

    private data class ResourceValue(
        val name: String,
        val kind: String,
        val translatable: Boolean?,
        val values: Map<String?, String>,
    )

    private companion object {
        val supportedLocales = listOf(
            "ar", "bn", "de", "es", "fr", "hi", "ja", "kk",
            "nl", "pa", "pt", "ro", "ru", "uk", "zh",
        )
        val formatArgumentRegex = Regex("%(?:\\d+\\$)?[a-zA-Z]")
        val templateTokenRegex = Regex("\\{\\{[#/]?[a-z_]+}}")
        val literalLineBreakRegex = Regex("\\\\n")
    }
}

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
                .containsExactlyElementsIn(expectedNames)
        }
    }

    @Test
    fun generatedLocaleConfigUsesTheDeclaredSupportedLocales() {
        val resourceRoot = resourceRoot()
        val declaredLocales = resourceRoot.listFiles().orEmpty()
            .filter { it.isDirectory && it.name.startsWith("values-") }
            .filter { File(it, "strings.xml").isFile }
            .map { it.name.removePrefix("values-") }

        assertThat(declaredLocales).containsExactlyElementsIn(supportedLocales)
        assertThat(File(resourceRoot, "resources.properties").readText().trim())
            .isEqualTo("unqualifiedResLocale=en-US")
        val buildConfiguration = File(appModuleRoot(), "build.gradle.kts").readText()
        assertThat(buildConfiguration).contains("generateLocaleConfig = true")
        assertThat(buildConfiguration).contains("isPseudoLocalesEnabled = true")
    }

    @Test
    fun punjabiTranslationUsesAnExplicitGurmukhiQualifier() {
        assertThat(File(resourceRoot(), "values-pa").exists()).isFalse()
        assertThat(File(resourceRoot(), "values-b+pa+Guru/strings.xml").isFile).isTrue()
    }

    @Test
    fun everyLocaleUsesItsRequiredPluralQuantities() {
        val requiredQuantities = mapOf(
            "ar" to setOf("zero", "one", "two", "few", "many", "other"),
            "bn" to setOf("one", "other"),
            "de" to setOf("one", "other"),
            "es" to setOf("one", "many", "other"),
            "fr" to setOf("one", "many", "other"),
            "hi" to setOf("one", "other"),
            "ja" to setOf("other"),
            "kk" to setOf("one", "other"),
            "nl" to setOf("one", "other"),
            "b+pa+Guru" to setOf("one", "other"),
            "pt-rBR" to setOf("one", "many", "other"),
            "ro" to setOf("one", "few", "other"),
            "ru" to setOf("one", "few", "many", "other"),
            "uk" to setOf("one", "few", "many", "other"),
            "b+zh+Hans" to setOf("other"),
        )

        assertThat(requiredQuantities.keys).containsExactlyElementsIn(supportedLocales)
        requiredQuantities.forEach { (locale, quantities) ->
            parseResources(resourceFile("values-$locale")).values
                .filter { it.kind == "plurals" }
                .forEach { plural ->
                    assertWithMessage(
                        "plural quantities for ${plural.name} in values-$locale"
                    ).that(plural.values.keys.filterNotNull())
                        .containsExactlyElementsIn(quantities)
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
            "api_export_endpoint_example",
            "api_export_headers_example",
            "api_export_header_line_syntax",
            "api_export_literal_authorization",
            "api_export_literal_bearer",
            "api_export_literal_basic",
            "api_export_literal_json",
            "api_export_literal_post",
            "api_export_literal_http",
            "api_export_literal_https",
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

    @Test
    fun sharedSetupValuesByteEqualToEnglishAreOnlyDocumentedIntentionalIdenticals() {
        // Allowlist transcribed 1:1 from the table "Documented intentional
        // identical-to-English values" in docs/qa/shared-setup-v2.md (5 cycle-4
        // v2 stragglers + 4 v1 byte-equal terms = 9 pairs). That section's rule:
        // any future byte-equal-to-English value must be re-reviewed deliberately
        // and the QA-doc table updated BEFORE it may be whitelisted here.
        val documentedIntentionalIdenticals = setOf(
            "de" to "shared_setup_v2_destination_cloud", // Standard German term
            "nl" to "shared_setup_v2_destination_cloud", // Standard Dutch term
            "ro" to "shared_setup_v2_destination_cloud", // Standard Romanian term
            "fr" to "shared_setup_v2_destination", // Identical French word
            "fr" to "shared_setup_v2_destination_cloud", // Standard French term
            "es" to "shared_setup_endpoint", // Established es-file term
            "nl" to "shared_setup_endpoint", // Established nl-file term
            "pt-rBR" to "shared_setup_endpoint", // Established pt-file term
            "fr" to "shared_setup_formats", // Identical French word
        )

        val canonical = parseResources(resourceFile("values"))
        val sharedSetupNames = canonical.keys
            .filter { it.startsWith("shared_setup_") }
            .toSet()
        check(sharedSetupNames.isNotEmpty()) { "No shared_setup_* keys found in values/strings.xml" }

        val undocumentedIdenticals = buildList {
            supportedLocales.forEach { locale ->
                val localized = parseResources(resourceFile("values-$locale"))
                sharedSetupNames.forEach { name ->
                    if (locale to name in documentedIntentionalIdenticals) {
                        return@forEach
                    }
                    val englishValues = canonical.getValue(name).values
                    localized.getValue(name).values.forEach { (quantity, value) ->
                        if (quantity in englishValues && value == englishValues.getValue(quantity)) {
                            val resourceLabel = "$name${quantity?.let { "[$it]" }.orEmpty()}"
                            add(
                                "values-$locale/strings.xml: $resourceLabel = \"$value\" " +
                                    "is byte-identical to English"
                            )
                        }
                    }
                }
            }
        }

        assertWithMessage(
            "Shared-setup values byte-identical to English beyond the documented " +
                "intentional identicals in docs/qa/shared-setup-v2.md. Each offender " +
                "is probably an untranslated key: re-review it deliberately and update " +
                "the QA-doc table BEFORE whitelisting the (locale, key) pair here."
        ).that(undocumentedIdenticals).isEmpty()
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

    private fun appModuleRoot(): File =
        File(resourceRoot(), "../../..").canonicalFile

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
            "nl", "b+pa+Guru", "pt-rBR", "ro", "ru", "uk", "b+zh+Hans",
        )
        val formatArgumentRegex = Regex("%(?:\\d+\\$)?[a-zA-Z]")
        val templateTokenRegex = Regex(
            "\\{\\{[#/]?[A-Za-z_]+}}|\\{[A-Za-z][A-Za-z0-9_]*}",
        )
        val literalLineBreakRegex = Regex("\\\\n")
    }
}

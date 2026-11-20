package com.healthmd.data

import com.google.common.truth.Truth.assertWithMessage
import java.io.File
import org.junit.Test

/**
 * Every EncryptedSharedPreferences file depends on this install's Android Keystore key, which is
 * never backed up. A restored copy cannot be decrypted, so each one must be excluded from Auto
 * Backup (`backup_rules.xml`) and from both Android 12+ sections (`data_extraction_rules.xml`).
 *
 * Play builds use the play/ rules, which must cover main + play sources; F-Droid builds use the
 * main/ rules, which must cover main sources.
 */
class BackupRulesEncryptedPreferencesTest {

    @Test
    fun playRulesExcludeEveryEncryptedPreferencesFile() {
        val names = encryptedPreferenceNames("src/main/java") + encryptedPreferenceNames("src/play/java")
        assertExcludedEverywhere(names, rulesDir = "src/play/res/xml")
    }

    @Test
    fun mainRulesExcludeEveryEncryptedPreferencesFileUsedByMainSources() {
        assertExcludedEverywhere(encryptedPreferenceNames("src/main/java"), rulesDir = "src/main/res/xml")
    }

    @Test
    fun scannerFindsTheKnownEncryptedStores() {
        val names = encryptedPreferenceNames("src/main/java") + encryptedPreferenceNames("src/play/java")
        assertWithMessage("encrypted preference names found in source").that(names).containsAtLeast(
            "health_md_api_export_credentials",
            "health_md_google_drive_account_authority",
            "clinic_sponsorship_secure_v1",
            "clinic_sync_doorbell_secure_v1",
            "health_md_oauth_tokens",
        )
    }

    private fun assertExcludedEverywhere(names: Set<String>, rulesDir: String) {
        val appRoot = locateAppRoot()
        val backup = File(appRoot, "$rulesDir/backup_rules.xml").readText()
        val extraction = File(appRoot, "$rulesDir/data_extraction_rules.xml").readText()
        val cloud = section(extraction, "cloud-backup")
        val transfer = section(extraction, "device-transfer")
        names.forEach { name ->
            val exclude = """<exclude domain="sharedpref" path="$name.xml" />"""
            assertWithMessage("$rulesDir/backup_rules.xml excludes $name").that(backup).contains(exclude)
            assertWithMessage("$rulesDir cloud-backup excludes $name").that(cloud).contains(exclude)
            assertWithMessage("$rulesDir device-transfer excludes $name").that(transfer).contains(exclude)
        }
    }

    private fun section(xml: String, tag: String): String =
        Regex("<$tag>(.*?)</$tag>", RegexOption.DOT_MATCHES_ALL).find(xml)?.groupValues?.get(1)
            ?: error("missing <$tag> in data_extraction_rules.xml")

    /** Names passed to EncryptedSharedPreferences.create, as string literals or same-file constants. */
    private fun encryptedPreferenceNames(sourceDir: String): Set<String> {
        val root = File(locateAppRoot(), sourceDir)
        if (!root.isDirectory) return emptySet()
        val create = Regex("""EncryptedSharedPreferences\.create\(\s*\w+\s*,\s*(?:"([^"]+)"|([A-Za-z_][A-Za-z0-9_.]*))""")
        return root.walkTopDown().filter { it.isFile && it.extension == "kt" }.flatMap { file ->
            val text = file.readText()
            create.findAll(text).map { match ->
                match.groupValues[1].ifEmpty {
                    val constant = match.groupValues[2].substringAfterLast('.')
                    Regex("""const val $constant\s*=\s*"([^"]+)"""").find(text)?.groupValues?.get(1)
                        ?: error("${file.name}: cannot resolve EncryptedSharedPreferences name $constant")
                }
            }
        }.toSet()
    }

    private fun locateAppRoot(): File {
        var current: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (current != null) {
            val candidate = File(current, "app/src/main")
            if (candidate.isDirectory) return File(current, "app")
            current = current.parentFile
        }
        error("Could not locate Android app module")
    }
}

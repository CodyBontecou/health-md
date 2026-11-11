package com.healthmd.presentation.settings

import com.healthmd.domain.model.DailyNoteInjectionSettings
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomationOutputPathValidationTest {
    @Test
    fun unsafePathsCannotReplaceSavedAutomationSettings() {
        listOf("../escape", "entries/../escape", "/absolute", "C:\\vault", "a//b", "a%2fb", "a\nb").forEach {
            assertFalse(it, AutomationOutputPathValidation.isValid(listOf(it), "{date}"))
        }
        listOf("", "   ", ".", "..", "../escape", "a/b", "a\\b", "a%2fb", "a\nb").forEach {
            assertFalse(it, AutomationOutputPathValidation.isValid(listOf("entries"), it))
        }
    }

    @Test
    fun vaultRootNestedFoldersAndExistingTokensRemainValid() {
        assertTrue(AutomationOutputPathValidation.isValid(listOf("", "Health/{year}/{month}"), "{date}"))
        assertTrue(AutomationOutputPathValidation.isValid(listOf("entries/健康"), "{date}_{time}_{metric}"))
        assertFalse(AutomationOutputPathValidation.isValid(listOf("Health", "../escape"), "{date}"))
    }

    @Test
    fun dailyNotesRejectTraversalUnknownTokensAndControlCharactersBeforeAutosave() {
        val enabled = DailyNoteInjectionSettings(enabled = true)
        listOf("../{date}", "{unknown}", "{{date}}", "a\u0000b", "a\nb", "a\u007fb", "", "   ").forEach {
            assertFalse(it, AutomationOutputPathValidation.isValidDailyNotes(enabled.copy(filenamePattern = it)))
        }
        listOf("../escape", "/absolute", "Daily/{year}", "Daily\nNotes").forEach {
            assertFalse(it, AutomationOutputPathValidation.isValidDailyNotes(enabled.copy(folderPath = it)))
        }
    }

    @Test
    fun dailyNotesKeepVaultRootNestedUnicodeFoldersAndSupportedDateTokens() {
        listOf("", "Daily", "Journal/健康").forEach { folder ->
            assertTrue(AutomationOutputPathValidation.isValidDailyNotes(DailyNoteInjectionSettings(
                enabled = true, folderPath = folder, filenamePattern = "{year}-{month}-{day}_{weekday}_{monthName}_{quarter}",
            )))
        }
    }

    @Test
    fun brokenDailyNotePathsCanStillBeDisabled() {
        assertTrue(AutomationOutputPathValidation.isValidDailyNotes(DailyNoteInjectionSettings(
            enabled = false, folderPath = "../escape", filenamePattern = "{unknown}",
        )))
    }

}

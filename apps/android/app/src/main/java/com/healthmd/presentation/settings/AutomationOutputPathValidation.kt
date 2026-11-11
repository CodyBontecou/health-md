package com.healthmd.presentation.settings

import com.healthmd.sharedsetup.SharedSetupV2Codec
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.exportengine.validateRelativePath
import java.time.LocalDate

/** Use the portable setup grammar before an editor can persist an output path. */
internal object AutomationOutputPathValidation {
    fun isSafeFolder(value: String): Boolean = SharedSetupV2Codec.isSafeRelative(value, allowSegments = true)

    fun isSafeFilename(value: String): Boolean =
        value.isNotBlank() && SharedSetupV2Codec.isSafeRelative(value, allowSegments = false)

    fun isValid(folders: List<String>, filename: String): Boolean =
        folders.all(::isSafeFolder) && isSafeFilename(filename)

    fun isSafeDailyNoteFolder(value: String): Boolean = isSafeFolder(value) &&
        resolvesToSafePath(DailyNoteInjectionSettings(folderPath = value))

    fun isSafeDailyNoteFilename(value: String): Boolean = isSafeFilename(value) &&
        resolvesToSafePath(DailyNoteInjectionSettings(folderPath = "", filenamePattern = value))

    fun isValidDailyNotes(settings: DailyNoteInjectionSettings): Boolean = !settings.enabled ||
        (isSafeDailyNoteFolder(settings.folderPath) && isSafeDailyNoteFilename(settings.filenamePattern) &&
            resolvesToSafePath(settings))

    // Daily note folders are literal; only filenames expand date tokens. Use the planner's
    // existing grammar as well, so unresolved braces and control characters cannot autosave.
    private fun resolvesToSafePath(settings: DailyNoteInjectionSettings): Boolean = runCatching {
        validateRelativePath(settings.resolvedPath(LocalDate.of(2026, 12, 31)))
    }.isSuccess
}

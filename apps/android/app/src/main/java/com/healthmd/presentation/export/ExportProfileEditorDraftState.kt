package com.healthmd.presentation.export

import androidx.compose.runtime.saveable.Saver
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// Keep the complete unsaved form across Activity recreation without committing a profile.
private val editorDraftJson = Json { ignoreUnknownKeys = true }

internal val ExportProfileEditorDraftSaver = Saver<ExportProfileEditorDraft, String>(
    save = { editorDraftJson.encodeToString(it) },
    restore = { saved ->
        runCatching { editorDraftJson.decodeFromString<ExportProfileEditorDraft>(saved) }.getOrNull()
    },
)

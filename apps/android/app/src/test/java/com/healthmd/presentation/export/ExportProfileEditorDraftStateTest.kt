package com.healthmd.presentation.export

import androidx.compose.runtime.saveable.SaverScope
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.WriteMode
import org.junit.Test

class ExportProfileEditorDraftStateTest {
    private val scope = object : SaverScope {
        override fun canBeSaved(value: Any) = value is String
    }

    @Test
    fun recreationRetainsUnicodeAndUncommittedDestinationAndFormatEdits() {
        val draft = ExportProfileEditorDraft(
            name = "QA 🧪 e\u0301 العربية / \u2066RTL\u2069",
            target = ExportTarget.API_ENDPOINT,
            folderUri = "content://test/tree/unsaved-folder",
            folderDisplayName = "未保存",
            apiEndpointUrl = "https://example.invalid/unfinished draft",
            agentDataGatewayUrl = "https://gateway.invalid/",
            settings = ExportSettings().copy(
                exportFormats = setOf(ExportFormat.MARKDOWN, ExportFormat.JSON),
                writeMode = WriteMode.APPEND,
                filenameFormat = "病歴-{date}",
                detailOverrides = mapOf("sleep" to "daily"),
            ),
        )

        val saved = with(ExportProfileEditorDraftSaver) { scope.save(draft) }

        assertThat(ExportProfileEditorDraftSaver.restore(requireNotNull(saved))).isEqualTo(draft)
    }

    @Test
    fun recreationKeepsEmptyInvalidDraftAndLiveFolderBinding() {
        val draft = ExportProfileEditorDraft(
            name = "",
            target = ExportTarget.DEVICE_FOLDER,
            settings = ExportSettings().copy(exportFormats = emptySet()),
        )
        val saved = with(ExportProfileEditorDraftSaver) { scope.save(draft) }

        assertThat(ExportProfileEditorDraftSaver.restore(requireNotNull(saved))).isEqualTo(draft)
    }

    @Test
    fun unreadableSavedDraftFallsBackToInitialState() {
        assertThat(ExportProfileEditorDraftSaver.restore("{broken")).isNull()
    }
}

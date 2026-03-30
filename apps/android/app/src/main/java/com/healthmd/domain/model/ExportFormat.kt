package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class ExportFormat(val displayName: String, val fileExtension: String) {
    MARKDOWN("Markdown", "md"),
    JSON("JSON", "json"),
    CSV("CSV", "csv"),
}

@Serializable
enum class WriteMode(val displayName: String, val description: String) {
    OVERWRITE(
        "Overwrite",
        "Replace existing files with new health data",
    ),
    APPEND(
        "Append",
        "Add health data to the end of existing files",
    ),
    UPDATE(
        "Update",
        "Update app-managed sections while preserving your custom content",
    ),
}

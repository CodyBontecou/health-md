package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class ExportFormat(val fileExtension: String) {
    MARKDOWN("md"),
    OBSIDIAN_BASES("md"),
    JSON("json"),
    CSV("csv"),
}

@Serializable
enum class WriteMode {
    OVERWRITE,
    APPEND,
    UPDATE,
}

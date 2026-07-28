package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class FrontmatterKeyStyle {
    SNAKE_CASE,
    CAMEL_CASE;

    fun apply(originalKey: String): String = when (this) {
        SNAKE_CASE -> originalKey
        CAMEL_CASE -> toCamelCase(originalKey)
    }

    companion object {
        fun toCamelCase(snakeCase: String): String {
            val parts = snakeCase.split("_")
            if (parts.isEmpty()) return snakeCase
            return parts.first() + parts.drop(1).joinToString("") { part ->
                part.replaceFirstChar { it.uppercaseChar() }
            }
        }

        fun toSnakeCase(camelCase: String): String = buildString {
            for ((i, char) in camelCase.withIndex()) {
                if (char.isUpperCase()) {
                    if (i > 0) append('_')
                    append(char.lowercaseChar())
                } else {
                    append(char)
                }
            }
        }
    }
}

@Serializable
data class CustomFrontmatterField(
    val originalKey: String,
    val customKey: String = originalKey,
    val isEnabled: Boolean = true,
) {
    val outputKey: String
        get() = customKey.ifEmpty { originalKey }
}

@Serializable
data class FrontmatterConfiguration(
    val fields: List<CustomFrontmatterField> = defaultFields,
    val customFields: Map<String, String> = emptyMap(),
    val placeholderFields: List<String> = emptyList(),
    val includeDate: Boolean = true,
    val includeType: Boolean = true,
    val customDateKey: String = "date",
    val customTypeKey: String = "type",
    val customTypeValue: String = "health-data",
    val keyStyle: FrontmatterKeyStyle = FrontmatterKeyStyle.SNAKE_CASE,
) {
    fun outputKey(originalKey: String): String? {
        // Older saved configurations may not contain fields added in newer app versions.
        // Treat missing known fields as enabled defaults so export-contract additions migrate
        // automatically without requiring users to open the customization screen first.
        val field = fields.find { it.originalKey == originalKey }
            ?: return keyStyle.apply(originalKey)
        if (!field.isEnabled) return null
        return field.outputKey
    }

    fun isFieldEnabled(originalKey: String): Boolean =
        fields.find { it.originalKey == originalKey }?.isEnabled ?: true

    fun withKeyStyle(style: FrontmatterKeyStyle): FrontmatterConfiguration = copy(
        keyStyle = style,
        fields = fields.map { it.copy(customKey = style.apply(it.originalKey)) },
    )

    companion object {
        /**
         * Derived from [HealthDataFields.allKeys] — the two cannot drift.
         * To add a new field: add it to [HealthDataFields] only; this list updates automatically.
         */
        val defaultFields: List<CustomFrontmatterField> =
            HealthDataFields.allKeys.map { CustomFrontmatterField(it) }
    }
}

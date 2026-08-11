package com.healthmd.domain.model

/** Applies one Health.md custom-Markdown conditional block with literal, Android-safe tag matching. */
fun applyMarkdownConditionalSection(
    template: String,
    section: String,
    include: Boolean,
): String {
    val openingTag = Regex.escape("{{#$section}}")
    val closingTag = Regex.escape("{{/$section}}")
    val pattern = Regex("$openingTag(.*?)$closingTag", RegexOption.DOT_MATCHES_ALL)
    return if (include) {
        pattern.replace(template) { it.groupValues[1] }
    } else {
        pattern.replace(template, "")
    }
}

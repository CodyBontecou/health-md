package com.healthmd.data.export

/**
 * Merges regenerated Health.md Markdown into an existing note while preserving user-authored
 * content. UPDATE mode is intentionally Markdown-specific: frontmatter keys produced by the app
 * are refreshed, app-managed sections are replaced, and any preamble/custom sections stay intact.
 */
class MarkdownMerger {

    fun merge(existingContent: String, newContent: String): String {
        if (existingContent.isBlank()) return newContent

        val existingParts = splitFrontmatter(existingContent)
        val newParts = splitFrontmatter(newContent)
        val mergedFrontmatter = mergeFrontmatter(existingParts.frontmatter, newParts.frontmatter)
        val mergedBody = mergeBody(existingParts.body, newParts.body)

        return buildString {
            if (mergedFrontmatter.isNotBlank()) {
                append("---\n")
                append(mergedFrontmatter.trimEnd())
                append("\n---\n\n")
            }
            append(mergedBody.trimEnd())
            append("\n")
        }
    }

    private data class MarkdownParts(
        val frontmatter: String,
        val body: String,
    )

    private data class BodySection(
        val heading: String,
        val content: String,
    )

    private data class ParsedBody(
        val preamble: String,
        val sections: List<BodySection>,
    )

    private fun splitFrontmatter(content: String): MarkdownParts {
        if (!content.startsWith("---")) return MarkdownParts(frontmatter = "", body = content)

        val firstLineEnd = content.indexOf('\n')
        if (firstLineEnd == -1) return MarkdownParts(frontmatter = "", body = content)

        val closingIndex = content.indexOf("\n---", startIndex = firstLineEnd + 1)
        if (closingIndex == -1) return MarkdownParts(frontmatter = "", body = content)

        val closingLineEnd = content.indexOf('\n', startIndex = closingIndex + 4)
            .let { if (it == -1) content.length else it + 1 }

        return MarkdownParts(
            frontmatter = content.substring(firstLineEnd + 1, closingIndex),
            body = content.substring(closingLineEnd),
        )
    }

    private fun mergeFrontmatter(existing: String, new: String): String {
        val existingMap = parseFrontmatterToMap(existing)
        val newMap = parseFrontmatterToMap(new)
        val merged = LinkedHashMap<String, String>()
        merged.putAll(existingMap)
        merged.putAll(newMap)
        return merged.entries.joinToString("\n") { (key, value) ->
            if (value.isBlank()) "$key:" else "$key: $value"
        }
    }

    private fun parseFrontmatterToMap(frontmatter: String): LinkedHashMap<String, String> {
        val map = LinkedHashMap<String, String>()
        for (line in frontmatter.lines()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue
            val colonIndex = trimmed.indexOf(':')
            if (colonIndex > 0) {
                val key = trimmed.substring(0, colonIndex).trim()
                val value = trimmed.substring(colonIndex + 1).trim()
                map[key] = value
            }
        }
        return map
    }

    private fun mergeBody(existing: String, new: String): String {
        val existingBody = parseBody(existing)
        val newBody = parseBody(new)
        if (newBody.sections.isEmpty()) return existing
        if (existingBody.sections.isEmpty()) return new

        val newManagedSectionsByKey = newBody.sections
            .filter { isAppManagedHeading(it.heading) }
            .associateBy { appManagedKey(it.heading) }
            .toMutableMap()

        val mergedSections = buildList {
            for (section in existingBody.sections) {
                val key = appManagedKey(section.heading)
                val replacement = if (key != null) newManagedSectionsByKey.remove(key) else null
                add(replacement ?: section)
            }
            addAll(newManagedSectionsByKey.values)
        }

        return buildString {
            if (existingBody.preamble.isNotBlank()) {
                append(existingBody.preamble.trimEnd())
                append("\n\n")
            } else if (newBody.preamble.isNotBlank()) {
                append(newBody.preamble.trimEnd())
                append("\n\n")
            }
            mergedSections.forEachIndexed { index, section ->
                if (index > 0) append("\n")
                append(section.heading.trimEnd())
                append("\n")
                append(section.content.trimEnd())
                append("\n")
            }
        }
    }

    private fun parseBody(body: String): ParsedBody {
        val lines = body.lines()
        val preamble = StringBuilder()
        val sections = mutableListOf<BodySection>()
        var currentHeading: String? = null
        val currentContent = StringBuilder()

        fun flushSection() {
            val heading = currentHeading ?: return
            sections.add(BodySection(heading, currentContent.toString()))
            currentContent.clear()
        }

        for (line in lines) {
            if (line.isMarkdownHeading()) {
                flushSection()
                currentHeading = line
            } else if (currentHeading == null) {
                preamble.append(line).append('\n')
            } else {
                currentContent.append(line).append('\n')
            }
        }
        flushSection()

        return ParsedBody(preamble = preamble.toString(), sections = sections)
    }

    private fun String.isMarkdownHeading(): Boolean = matches(Regex("^#{1,6}\\s+.*"))

    private fun appManagedKey(heading: String): String? {
        val normalized = normalizeHeading(heading)
        if (normalized.startsWith("health data")) return "health data"
        return APP_MANAGED_HEADINGS.firstOrNull { normalized == it }
    }

    private fun isAppManagedHeading(heading: String): Boolean = appManagedKey(heading) != null

    private fun normalizeHeading(heading: String): String = heading.lowercase()
        .replace(Regex("[#*_~`]"), "")
        .replace(Regex("[^a-z0-9 ]"), "")
        .replace(Regex("\\s+"), " ")
        .trim()

    private companion object {
        val APP_MANAGED_HEADINGS = setOf(
            "sleep",
            "activity",
            "heart",
            "vitals",
            "body",
            "nutrition",
            "mobility",
            "reproductive health",
            "mindfulness",
            "workouts",
        )
    }
}

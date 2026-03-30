package com.healthmd.data.export

class MarkdownMerger {

    fun merge(existingContent: String, newContent: String): String {
        val existingFrontmatter = extractFrontmatter(existingContent)
        val newFrontmatter = extractFrontmatter(newContent)
        val existingBody = extractBody(existingContent)
        val newBody = extractBody(newContent)

        // Merge frontmatter: new values override, existing custom values preserved
        val mergedFrontmatter = mergeFrontmatter(existingFrontmatter, newFrontmatter)

        // Merge body: replace app-managed sections, preserve user sections
        val mergedBody = mergeBody(existingBody, newBody)

        return buildString {
            if (mergedFrontmatter.isNotEmpty()) {
                append("---\n")
                append(mergedFrontmatter)
                append("---\n\n")
            }
            append(mergedBody)
        }
    }

    private fun extractFrontmatter(content: String): String {
        if (!content.startsWith("---")) return ""
        val endIndex = content.indexOf("---", 3)
        if (endIndex == -1) return ""
        return content.substring(4, endIndex).trim() + "\n"
    }

    private fun extractBody(content: String): String {
        if (!content.startsWith("---")) return content
        val endIndex = content.indexOf("---", 3)
        if (endIndex == -1) return content
        return content.substring(endIndex + 3).trimStart()
    }

    private fun mergeFrontmatter(existing: String, new: String): String {
        val existingMap = parseFrontmatterToMap(existing)
        val newMap = parseFrontmatterToMap(new)

        // New values override existing, existing custom values preserved
        val merged = LinkedHashMap(existingMap)
        merged.putAll(newMap)

        return merged.entries.joinToString("\n") { "${it.key}: ${it.value}" } + "\n"
    }

    private fun parseFrontmatterToMap(frontmatter: String): LinkedHashMap<String, String> {
        val map = LinkedHashMap<String, String>()
        for (line in frontmatter.lines()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
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
        val existingSections = parseSections(existing)
        val newSections = parseSections(new)

        if (newSections.isEmpty()) return existing
        if (existingSections.isEmpty()) return new

        // Known app-managed section headings
        val appSections = setOf(
            "sleep", "activity", "heart", "vitals", "body",
            "nutrition", "mobility", "workouts", "health data",
        )

        val result = StringBuilder()
        val replacedSections = mutableSetOf<String>()

        for ((heading, content) in existingSections) {
            val normalizedHeading = normalizeHeading(heading)
            val newSection = newSections.entries.find { normalizeHeading(it.key) == normalizedHeading }
            if (newSection != null && normalizedHeading in appSections) {
                result.append(newSection.key).append("\n").append(newSection.value)
                replacedSections.add(normalizeHeading(newSection.key))
            } else {
                result.append(heading).append("\n").append(content)
            }
        }

        // Append any new sections not in existing
        for ((heading, content) in newSections) {
            if (normalizeHeading(heading) !in replacedSections) {
                result.append(heading).append("\n").append(content)
            }
        }

        return result.toString()
    }

    private fun parseSections(body: String): LinkedHashMap<String, String> {
        val sections = LinkedHashMap<String, String>()
        val lines = body.lines()
        var currentHeading: String? = null
        val currentContent = StringBuilder()

        for (line in lines) {
            if (line.startsWith("#")) {
                if (currentHeading != null) {
                    sections[currentHeading] = currentContent.toString()
                    currentContent.clear()
                }
                currentHeading = line
            } else {
                currentContent.append(line).append("\n")
            }
        }
        if (currentHeading != null) {
            sections[currentHeading] = currentContent.toString()
        }

        return sections
    }

    private fun normalizeHeading(heading: String): String {
        return heading.lowercase()
            .replace(Regex("[#*_~`]"), "")
            .replace(Regex("[^a-z0-9 ]"), "")
            .trim()
    }
}

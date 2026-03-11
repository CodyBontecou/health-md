import Foundation

/// Section-based markdown merge utility for the "Update" write mode.
///
/// When re-syncing health data to an existing file, this merger:
/// - Replaces app-managed sections (Sleep, Activity, etc.) with fresh data
/// - Preserves any user-added sections the app doesn't manage
/// - Appends new sections that weren't in the previous file
/// - Updates frontmatter and the title/summary preamble
struct MarkdownMerger {

    // MARK: - Types

    /// A parsed section of markdown: heading line + body text up to the next section.
    struct Section {
        /// The full heading line, e.g. "## 😴 Sleep"
        let headingLine: String
        /// Lowercased ASCII-only name used for matching, e.g. "sleep"
        let normalizedName: String
        /// Content after the heading line until the next section (includes leading/trailing newlines)
        var body: String
    }

    /// A fully parsed markdown document.
    struct ParsedDocument {
        /// Frontmatter block including `---` delimiters and trailing newline, or empty string.
        var frontmatter: String
        /// Content between frontmatter and the first section heading (title line, summary, etc.)
        var preamble: String
        /// Ordered list of sections.
        var sections: [Section]
    }

    // MARK: - Public API

    /// Merge new health-data markdown into an existing file's content.
    ///
    /// - Parameters:
    ///   - existing: The current file contents on disk.
    ///   - new: The freshly generated health-data markdown.
    /// - Returns: Merged markdown with app sections updated and user sections preserved.
    static func merge(existing: String, new: String) -> String {
        let newLevel = detectSectionLevel(in: new)
        let existingLevel = detectSectionLevel(in: existing)

        let existingDoc = parse(existing, sectionLevel: existingLevel)
        let newDoc = parse(new, sectionLevel: newLevel)

        // Build a lookup of new sections keyed by normalized name, preserving order.
        var newSectionMap: [String: Section] = [:]
        var newSectionOrder: [String] = []
        for section in newDoc.sections {
            let key = section.normalizedName
            newSectionMap[key] = section
            if !newSectionOrder.contains(key) {
                newSectionOrder.append(key)
            }
        }

        // Merge frontmatter: preserve existing properties, add/update with new properties.
        let mergedFrontmatter = mergeFrontmatter(existing: existingDoc.frontmatter, new: newDoc.frontmatter)

        // Start result with merged frontmatter + new preamble (title, summary).
        var result = mergedFrontmatter + newDoc.preamble

        // Track which new sections have been placed into the result.
        var placed: Set<String> = []

        // Walk through existing sections in their original order.
        for section in existingDoc.sections {
            let key = section.normalizedName
            if let newSection = newSectionMap[key] {
                // App-managed section → replace with fresh data.
                result += newSection.headingLine + newSection.body
                placed.insert(key)
            } else {
                // User-added section → preserve as-is.
                result += section.headingLine + section.body
            }
        }

        // Append any new sections that weren't present in the existing file.
        for key in newSectionOrder {
            if !placed.contains(key), let section = newSectionMap[key] {
                result += section.headingLine + section.body
            }
        }

        return result
    }

    // MARK: - Frontmatter Merging

    /// Merge two frontmatter blocks, preserving existing properties and adding/updating with new ones.
    ///
    /// - Parameters:
    ///   - existing: The existing frontmatter block (including `---` delimiters).
    ///   - new: The new frontmatter block (including `---` delimiters).
    /// - Returns: A merged frontmatter block with all properties.
    static func mergeFrontmatter(existing: String, new: String) -> String {
        let existingProps = parseFrontmatterProperties(existing)
        let newProps = parseFrontmatterProperties(new)

        // If both are empty, return empty string
        if existingProps.isEmpty && newProps.isEmpty {
            return ""
        }

        // If only new has content, return new as-is
        if existingProps.isEmpty {
            return new
        }

        // If only existing has content but new is empty, return existing
        if newProps.isEmpty {
            return existing
        }

        // Merge: start with existing, then add/overwrite with new
        var mergedKeys: [String] = []
        var mergedValues: [String: String] = [:]

        // First, add all existing properties (preserving order)
        for (key, value) in existingProps {
            if !mergedKeys.contains(key) {
                mergedKeys.append(key)
            }
            mergedValues[key] = value
        }

        // Then, add/overwrite with new properties
        for (key, value) in newProps {
            if !mergedKeys.contains(key) {
                mergedKeys.append(key)
            }
            mergedValues[key] = value
        }

        // Build the merged frontmatter
        var result = "---\n"
        for key in mergedKeys {
            if let value = mergedValues[key] {
                result += "\(key): \(value)\n"
            }
        }
        result += "---\n"

        return result
    }

    /// Parse frontmatter into an ordered list of key-value pairs.
    ///
    /// Returns an array of tuples to preserve the original order of keys.
    /// Handles multi-line values (arrays, objects) by detecting continuation lines.
    static func parseFrontmatterProperties(_ frontmatter: String) -> [(key: String, value: String)] {
        // Strip the --- delimiters
        let lines = frontmatter.components(separatedBy: "\n")
        guard lines.count >= 2 else { return [] }

        var properties: [(key: String, value: String)] = []
        var currentKey: String?
        var currentValue: String = ""
        var inMultilineValue = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip delimiter lines
            if trimmed == "---" {
                continue
            }

            // Skip empty lines unless we're in a multiline value
            if trimmed.isEmpty && !inMultilineValue {
                continue
            }

            // Check if this line starts a new key-value pair
            if let colonIndex = line.firstIndex(of: ":"), !inMultilineValue || !line.hasPrefix(" ") {
                // Save the previous key-value pair if exists
                if let key = currentKey {
                    properties.append((key: key, value: currentValue.trimmingCharacters(in: .whitespaces)))
                }

                // Start a new key-value pair
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let valueStart = line.index(after: colonIndex)
                let value = String(line[valueStart...]).trimmingCharacters(in: .whitespaces)

                currentKey = key
                currentValue = value

                // Check if this starts a multiline value (array or object)
                inMultilineValue = value.isEmpty || value == "|" || value == ">" || value.hasPrefix("[") && !value.hasSuffix("]")
            } else if inMultilineValue && currentKey != nil {
                // Continuation of a multiline value
                if currentValue.isEmpty {
                    currentValue = line
                } else {
                    currentValue += "\n" + line
                }

                // Check if multiline value is complete (for inline arrays)
                if currentValue.hasPrefix("[") && line.contains("]") {
                    inMultilineValue = false
                }
            }
        }

        // Don't forget the last key-value pair
        if let key = currentKey {
            properties.append((key: key, value: currentValue.trimmingCharacters(in: .whitespaces)))
        }

        return properties
    }

    // MARK: - Parsing

    /// Parse markdown content into a structured document, splitting sections at `sectionLevel`.
    ///
    /// Only headings at exactly `sectionLevel` start a new section.
    /// Sub-headings (higher level numbers, e.g. ### under ##) remain part of the parent section body.
    static func parse(_ content: String, sectionLevel: Int) -> ParsedDocument {
        let lines = content.components(separatedBy: "\n")

        // --- Extract frontmatter ---
        var frontmatter = ""
        var contentStartIndex = 0

        if let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" {
            // Look for the closing ---
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    // Include everything from start through closing --- plus the trailing newline
                    frontmatter = lines[0...i].joined(separator: "\n") + "\n"
                    contentStartIndex = i + 1
                    break
                }
            }
        }

        // --- Split remaining content into preamble and sections ---
        var preamble = ""
        var sections: [Section] = []
        var currentHeadingLine: String?
        var currentNormalizedName: String?
        var bodyLines: [String] = []

        for i in contentStartIndex..<lines.count {
            let line = lines[i]
            let level = headingLevel(of: line)

            if level == sectionLevel {
                // Flush the previous section, if any.
                if let heading = currentHeadingLine, let name = currentNormalizedName {
                    // Rejoin body lines preserving each line's trailing newline.
                    // Using map { $0 + "\n" }.joined() instead of joined(separator: "\n")
                    // ensures the blank line before the next heading is preserved.
                    let body = bodyLines.map { $0 + "\n" }.joined()
                    sections.append(Section(headingLine: heading, normalizedName: name, body: body))
                    bodyLines = []
                }

                // Start a new section. The heading line includes a trailing newline.
                currentHeadingLine = line + "\n"
                currentNormalizedName = normalizeHeadingText(line)
            } else if currentHeadingLine == nil {
                // Still in the preamble.
                preamble += line + "\n"
            } else {
                // Part of the current section's body.
                bodyLines.append(line)
            }
        }

        // Flush the last section.
        if let heading = currentHeadingLine, let name = currentNormalizedName {
            let body = bodyLines.map { $0 + "\n" }.joined()
            sections.append(Section(headingLine: heading, normalizedName: name, body: body))
        }

        return ParsedDocument(frontmatter: frontmatter, preamble: preamble, sections: sections)
    }

    // MARK: - Heading Utilities

    /// Returns the heading level (number of leading `#` characters) of a line,
    /// or 0 if the line is not a valid markdown heading.
    static func headingLevel(of line: String) -> Int {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return 0 }

        var level = 0
        for char in trimmed {
            if char == "#" { level += 1 }
            else { break }
        }

        // A valid heading must have a space after the `#` characters.
        guard level < trimmed.count else { return 0 }
        let afterHashes = trimmed[trimmed.index(trimmed.startIndex, offsetBy: level)]
        return afterHashes == " " ? level : 0
    }

    /// Normalize a heading line to a lowercase, ASCII-only key for matching.
    ///
    /// Examples:
    /// - `"## 😴 Sleep"` → `"sleep"`
    /// - `"### 🏃 Activity"` → `"activity"`
    /// - `"## My Custom Notes"` → `"my custom notes"`
    static func normalizeHeadingText(_ heading: String) -> String {
        // Strip leading # and whitespace
        let stripped = heading.drop(while: { $0 == "#" || $0 == " " })

        // Keep only ASCII alphanumeric characters and spaces (strips emoji, accents, etc.)
        let ascii = stripped.unicodeScalars
            .filter { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == UnicodeScalar(" ")) }
            .map { Character($0) }

        return String(ascii)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    /// Detect the primary section heading level used in the content by looking
    /// for known app-managed section names.
    ///
    /// Falls back to level 2 (`##`) if no known sections are found.
    static func detectSectionLevel(in content: String) -> Int {
        let knownNames: Set<String> = [
            "sleep", "activity", "heart", "vitals", "body",
            "nutrition", "mindfulness", "mobility", "hearing", "workouts"
        ]

        for line in content.components(separatedBy: "\n") {
            let level = headingLevel(of: line)
            guard level > 0 else { continue }
            let name = normalizeHeadingText(line)
            if knownNames.contains(name) {
                return level
            }
        }

        return 2 // Default section level
    }
}

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

        // Start result with the new frontmatter + preamble (title, summary).
        var result = newDoc.frontmatter + newDoc.preamble

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

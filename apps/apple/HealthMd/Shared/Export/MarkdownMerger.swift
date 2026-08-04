import Foundation

/// Section-based markdown merge utility for the "Update" write mode.
///
/// When re-syncing health data to an existing file, this merger:
/// - Replaces app-managed sections (Sleep, Activity, etc.) with fresh data
/// - Preserves any user-added sections the app doesn't manage
/// - Appends new sections that weren't in the previous file
/// - Updates frontmatter and the title/summary preamble
nonisolated struct MarkdownMerger {

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
        merge(existing: existing, new: new, preservingPreamble: false)
    }

    /// Same section-aware merge as `merge`, but preserves the existing file's preamble
    /// (the user's own title/intro between frontmatter and the first section heading)
    /// instead of replacing it with the new doc's preamble.
    ///
    /// Used by daily-note injection, where the preamble is owned by the user, not the app.
    static func mergePreservingPreamble(existing: String, new: String) -> String {
        merge(existing: existing, new: new, preservingPreamble: true)
    }

    private static func merge(existing: String, new: String, preservingPreamble: Bool) -> String {
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

        // Choose preamble: existing (daily-note injection) or new (full export rewrite).
        let preamble = preservingPreamble ? existingDoc.preamble : newDoc.preamble
        var result = mergedFrontmatter + preamble

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

    /// One physical line, retaining its original terminator so untouched YAML can be emitted byte-for-byte.
    private struct PhysicalLine {
        let content: String
        let ending: String

        var raw: String { content + ending }
    }

    private struct FrontmatterPropertyBlock {
        let key: String
        let range: Range<Int>
    }

    private struct FrontmatterDocument {
        let opening: PhysicalLine
        let content: [PhysicalLine]
        let closing: PhysicalLine
        let suffix: [PhysicalLine]
    }

    /// Merge two frontmatter blocks by splicing complete top-level YAML property blocks.
    ///
    /// Existing physical lines are never parsed into values or reserialized. An incoming property replaces
    /// every existing block with the same key at the first block's position; genuinely new blocks are
    /// appended immediately before the closing delimiter.
    static func mergeFrontmatter(existing: String, new: String) -> String {
        let existingDocument = frontmatterDocument(from: existing)
        let newDocument = frontmatterDocument(from: new)

        guard let existingDocument else {
            return newDocument == nil ? "" : new
        }
        guard let newDocument else {
            return existing
        }

        let incomingBlocks = propertyBlocks(in: newDocument.content)
        guard !incomingBlocks.isEmpty else {
            return existing
        }

        let lineEnding = preferredLineEnding(in: existingDocument)
        var incomingOrder: [String] = []
        var incomingLinesByKey: [String: [PhysicalLine]] = [:]

        for block in incomingBlocks {
            if incomingLinesByKey[block.key] == nil {
                incomingOrder.append(block.key)
            }
            // Generated frontmatter should not contain duplicate keys. If it does, retain its last value,
            // matching the previous merge policy while still emitting one authoritative block.
            incomingLinesByKey[block.key] = newDocument.content[block.range].map {
                PhysicalLine(content: $0.content, ending: lineEnding)
            }
        }

        let existingBlocks = propertyBlocks(in: existingDocument.content)
        let existingBlocksByStart = Dictionary(uniqueKeysWithValues: existingBlocks.map {
            ($0.range.lowerBound, $0)
        })

        var mergedContent: [PhysicalLine] = []
        var emittedIncomingKeys: Set<String> = []
        var index = 0

        while index < existingDocument.content.count {
            guard let block = existingBlocksByStart[index] else {
                mergedContent.append(existingDocument.content[index])
                index += 1
                continue
            }

            if let replacement = incomingLinesByKey[block.key] {
                if !emittedIncomingKeys.contains(block.key) {
                    mergedContent.append(contentsOf: replacement)
                    emittedIncomingKeys.insert(block.key)
                }
                // Skip every stale occurrence of an incoming key after replacing the first one.
            } else {
                mergedContent.append(contentsOf: existingDocument.content[block.range])
            }
            index = block.range.upperBound
        }

        for key in incomingOrder where !emittedIncomingKeys.contains(key) {
            if let lines = incomingLinesByKey[key] {
                mergedContent.append(contentsOf: lines)
                emittedIncomingKeys.insert(key)
            }
        }

        return render(
            [existingDocument.opening]
                + mergedContent
                + [existingDocument.closing]
                + existingDocument.suffix
        )
    }

    /// Split a complete Markdown document at a valid column-zero frontmatter envelope.
    /// The returned strings retain every original line ending.
    static func splitFrontmatter(from content: String) -> (frontmatter: String, body: String)? {
        guard let document = frontmatterDocument(from: content) else { return nil }
        return (
            render([document.opening] + document.content + [document.closing]),
            render(document.suffix)
        )
    }

    private static func frontmatterDocument(from text: String) -> FrontmatterDocument? {
        let lines = physicalLines(in: text)
        guard lines.count >= 2, isFrontmatterDelimiter(lines[0].content) else { return nil }
        guard let closingIndex = lines.indices.dropFirst().first(where: {
            isFrontmatterDelimiter(lines[$0].content)
        }) else {
            return nil
        }

        let content = closingIndex > 1 ? Array(lines[1..<closingIndex]) : []
        let suffixStart = closingIndex + 1
        let suffix = suffixStart < lines.count ? Array(lines[suffixStart...]) : []
        return FrontmatterDocument(
            opening: lines[0],
            content: content,
            closing: lines[closingIndex],
            suffix: suffix
        )
    }

    private static func propertyBlocks(in lines: [PhysicalLine]) -> [FrontmatterPropertyBlock] {
        var blocks: [FrontmatterPropertyBlock] = []
        var index = 0

        while index < lines.count {
            guard let key = topLevelKey(in: lines[index].content) else {
                index += 1
                continue
            }

            var end = index + 1
            while end < lines.count {
                if isIndented(lines[end].content) {
                    end += 1
                    continue
                }

                // YAML permits physically empty lines inside an indented block scalar. Keep them in the
                // property block when another indented continuation follows.
                if lines[end].content.isEmpty {
                    var nextNonempty = end + 1
                    while nextNonempty < lines.count, lines[nextNonempty].content.isEmpty {
                        nextNonempty += 1
                    }
                    if nextNonempty < lines.count, isIndented(lines[nextNonempty].content) {
                        end += 1
                        continue
                    }
                }
                break
            }

            blocks.append(FrontmatterPropertyBlock(key: key, range: index..<end))
            index = end
        }

        return blocks
    }

    private static func topLevelKey(in line: String) -> String? {
        guard let firstScalar = line.unicodeScalars.first,
              !CharacterSet.whitespaces.contains(firstScalar),
              !line.hasPrefix("#"),
              !line.hasPrefix("%"),
              !isFrontmatterDelimiter(line) else {
            return nil
        }

        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]

            if inDoubleQuote {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inDoubleQuote = false
                }
            } else if inSingleQuote {
                if character == "'" {
                    inSingleQuote = false
                }
            } else if character == "\"" {
                inDoubleQuote = true
            } else if character == "'" {
                inSingleQuote = true
            } else if character == ":" {
                let valueStart = line.index(after: index)
                if valueStart == line.endIndex || isWhitespace(line[valueStart]) {
                    let key = String(line[..<index]).trimmingCharacters(in: .whitespaces)
                    guard !key.isEmpty,
                          key != "-", !key.hasPrefix("- "), !key.hasPrefix("-\t"),
                          key != "?", !key.hasPrefix("? "), !key.hasPrefix("?\t") else {
                        return nil
                    }
                    return key
                }
            }

            index = line.index(after: index)
        }

        return nil
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    private static func isIndented(_ line: String) -> Bool {
        guard let first = line.unicodeScalars.first else { return false }
        return CharacterSet.whitespaces.contains(first)
    }

    private static func isFrontmatterDelimiter(_ line: String) -> Bool {
        guard line.hasPrefix("---") else { return false }
        return line.dropFirst(3).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func preferredLineEnding(in document: FrontmatterDocument) -> String {
        for line in [document.opening] + document.content + [document.closing] where !line.ending.isEmpty {
            return line.ending
        }
        return "\n"
    }

    private static func physicalLines(in text: String) -> [PhysicalLine] {
        let bytes = Array(text.utf8)
        guard !bytes.isEmpty else { return [] }

        var lines: [PhysicalLine] = []
        var start = 0
        var index = 0

        while index < bytes.count {
            if bytes[index] == 0x0D {
                let content = String(decoding: bytes[start..<index], as: UTF8.self)
                if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                    lines.append(PhysicalLine(content: content, ending: "\r\n"))
                    index += 2
                } else {
                    lines.append(PhysicalLine(content: content, ending: "\r"))
                    index += 1
                }
                start = index
            } else if bytes[index] == 0x0A {
                let content = String(decoding: bytes[start..<index], as: UTF8.self)
                lines.append(PhysicalLine(content: content, ending: "\n"))
                index += 1
                start = index
            } else {
                index += 1
            }
        }

        if start < bytes.count {
            lines.append(PhysicalLine(
                content: String(decoding: bytes[start...], as: UTF8.self),
                ending: ""
            ))
        }

        return lines
    }

    private static func render(_ lines: [PhysicalLine]) -> String {
        lines.map(\.raw).joined()
    }

    // MARK: - Parsing

    /// Parse markdown content into a structured document, splitting sections at `sectionLevel`.
    ///
    /// Only headings at exactly `sectionLevel` start a new section.
    /// Sub-headings (higher level numbers, e.g. ### under ##) remain part of the parent section body.
    static func parse(_ content: String, sectionLevel: Int) -> ParsedDocument {
        let document = frontmatterDocument(from: content)
        let lines: [PhysicalLine]
        let frontmatter: String

        if let document {
            frontmatter = render([document.opening] + document.content + [document.closing])
            lines = document.suffix
        } else {
            frontmatter = ""
            lines = physicalLines(in: content)
        }

        var preamble = ""
        var sections: [Section] = []
        var currentHeadingLine: String?
        var currentNormalizedName: String?
        var bodyLines: [PhysicalLine] = []

        for line in lines {
            let level = headingLevel(of: line.content)

            if level == sectionLevel {
                if let heading = currentHeadingLine, let name = currentNormalizedName {
                    sections.append(Section(
                        headingLine: heading,
                        normalizedName: name,
                        body: render(bodyLines)
                    ))
                    bodyLines = []
                }

                currentHeadingLine = line.raw
                currentNormalizedName = normalizeHeadingText(line.content)
            } else if currentHeadingLine == nil {
                preamble += line.raw
            } else {
                bodyLines.append(line)
            }
        }

        if let heading = currentHeadingLine, let name = currentNormalizedName {
            sections.append(Section(
                headingLine: heading,
                normalizedName: name,
                body: render(bodyLines)
            ))
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
            "nutrition", "mindfulness", "mobility", "hearing", "workouts",
            "medications"
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

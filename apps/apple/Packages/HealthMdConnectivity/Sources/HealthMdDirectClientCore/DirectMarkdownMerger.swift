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

    /// Detailed result used by destination writers so a conservative parser rejection is never
    /// reported as a successful update. Compatibility string APIs still preserve existing bytes.
    enum MergeOutcome: Equatable {
        case merged(String)
        case rejected
    }

    // MARK: - Public API

    /// Merge new health-data markdown into an existing file's content.
    ///
    /// - Parameters:
    ///   - existing: The current file contents on disk.
    ///   - new: The freshly generated health-data markdown.
    /// - Returns: Merged markdown with app sections updated and user sections preserved.
    static func merge(existing: String, new: String) -> String {
        switch mergeOutcome(existing: existing, new: new) {
        case .merged(let content): content
        case .rejected: existing
        }
    }

    static func mergeOutcome(existing: String, new: String) -> MergeOutcome {
        mergeOutcome(existing: existing, new: new, preservingPreamble: false)
    }

    /// Same section-aware merge as `merge`, but preserves the existing file's preamble
    /// (the user's own title/intro between frontmatter and the first section heading)
    /// instead of replacing it with the new doc's preamble.
    ///
    /// Used by daily-note injection, where the preamble is owned by the user, not the app.
    static func mergePreservingPreamble(existing: String, new: String) -> String {
        switch mergePreservingPreambleOutcome(existing: existing, new: new) {
        case .merged(let content): content
        case .rejected: existing
        }
    }

    static func mergePreservingPreambleOutcome(existing: String, new: String) -> MergeOutcome {
        mergeOutcome(existing: existing, new: new, preservingPreamble: true)
    }

    private static func mergeOutcome(
        existing: String,
        new: String,
        preservingPreamble: Bool
    ) -> MergeOutcome {
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
        let mergedFrontmatter: String
        switch mergeFrontmatterOutcome(existing: existingDoc.frontmatter, new: newDoc.frontmatter) {
        case .merged(let content):
            mergedFrontmatter = content
        case .rejected:
            return .rejected
        }
        let boundaryLineEnding = firstLineEnding(in: existing) ?? firstLineEnding(in: new) ?? "\n"

        // Choose preamble: existing (daily-note injection) or new (full export rewrite).
        let preamble = preservingPreamble ? existingDoc.preamble : newDoc.preamble
        var result = ""
        appendMarkdownFragment(mergedFrontmatter, to: &result, lineEnding: boundaryLineEnding)
        appendMarkdownFragment(preamble, to: &result, lineEnding: boundaryLineEnding)

        // Track which new sections have been placed into the result.
        var placed: Set<String> = []

        // Walk through existing sections in their original order.
        for section in existingDoc.sections {
            let key = section.normalizedName
            if let newSection = newSectionMap[key] {
                // App-managed section → replace with fresh data.
                appendMarkdownFragment(newSection.headingLine, to: &result, lineEnding: boundaryLineEnding)
                appendMarkdownFragment(newSection.body, to: &result, lineEnding: boundaryLineEnding)
                placed.insert(key)
            } else {
                // User-added section → preserve as-is.
                appendMarkdownFragment(section.headingLine, to: &result, lineEnding: boundaryLineEnding)
                appendMarkdownFragment(section.body, to: &result, lineEnding: boundaryLineEnding)
            }
        }

        // Append any new sections that weren't present in the existing file.
        for key in newSectionOrder {
            if !placed.contains(key), let section = newSectionMap[key] {
                appendMarkdownFragment(section.headingLine, to: &result, lineEnding: boundaryLineEnding)
                appendMarkdownFragment(section.body, to: &result, lineEnding: boundaryLineEnding)
            }
        }

        return .merged(result)
    }

    /// Join independently parsed Markdown fragments without changing a fragment's EOF bytes unless
    /// another nonempty fragment follows it. A single boundary is enough to keep the next heading or
    /// preamble from being glued to an unterminated delimiter/body line.
    private static func appendMarkdownFragment(
        _ fragment: String,
        to output: inout String,
        lineEnding: String
    ) {
        guard !fragment.isEmpty else { return }
        if !output.isEmpty,
           output.utf8.last != 0x0A,
           output.utf8.last != 0x0D,
           fragment.utf8.first != 0x0A,
           fragment.utf8.first != 0x0D {
            output += lineEnding
        }
        output += fragment
    }

    private static func firstLineEnding(in text: String) -> String? {
        physicalLines(in: text).first(where: { !$0.ending.isEmpty })?.ending
    }

    // MARK: - Frontmatter Merging

    /// One physical line, retaining its original terminator so untouched YAML can be emitted byte-for-byte.
    private struct PhysicalLine {
        let content: String
        let ending: String

        var raw: String { content + ending }
    }

    private enum FrontmatterPropertyKey: Hashable {
        case string(String)
        case implicitlyTypedPlain(String)
    }

    private struct FrontmatterPropertyBlock {
        let key: FrontmatterPropertyKey
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
        switch mergeFrontmatterOutcome(existing: existing, new: new) {
        case .merged(let content): content
        case .rejected: existing
        }
    }

    static func mergeFrontmatterOutcome(existing: String, new: String) -> MergeOutcome {
        let existingDocument = frontmatterDocument(from: existing)
        let newDocument = frontmatterDocument(from: new)

        guard let existingDocument else {
            return .merged(newDocument == nil ? "" : new)
        }
        guard let newDocument else {
            return .merged(existing)
        }

        guard let incomingBlocks = propertyBlocks(in: newDocument.content) else {
            return .rejected
        }
        guard !incomingBlocks.isEmpty else {
            return .merged(existing)
        }

        let lineEnding = preferredLineEnding(in: existingDocument)
        var incomingOrder: [FrontmatterPropertyKey] = []
        var incomingLinesByKey: [FrontmatterPropertyKey: [PhysicalLine]] = [:]

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

        guard let existingBlocks = propertyBlocks(in: existingDocument.content) else {
            // Unsupported or ambiguous YAML must remain byte-for-byte intact rather than risk a
            // partial replacement that leaves continuations attached to the wrong property.
            return .rejected
        }
        let existingBlocksByStart = Dictionary(uniqueKeysWithValues: existingBlocks.map {
            ($0.range.lowerBound, $0)
        })

        let incomingKeys = Set(incomingLinesByKey.keys)
        var replacedAnchors: Set<String> = []
        var preservedAliases: Set<String> = []
        for block in existingBlocks {
            guard let references = anchorReferences(in: Array(existingDocument.content[block.range])) else {
                return .rejected
            }
            if incomingKeys.contains(block.key) {
                replacedAnchors.formUnion(references.anchors)
            } else {
                preservedAliases.formUnion(references.aliases)
            }
        }
        guard replacedAnchors.isDisjoint(with: preservedAliases) else {
            // Replacing the defining block would leave a preserved alias with changed or missing meaning.
            return .rejected
        }

        var mergedContent: [PhysicalLine] = []
        var emittedIncomingKeys: Set<FrontmatterPropertyKey> = []
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

        return .merged(render(
            [existingDocument.opening]
                + mergedContent
                + [existingDocument.closing]
                + existingDocument.suffix
        ))
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

    private struct FrontmatterPropertyHeader {
        let key: FrontmatterPropertyKey
        let value: String
    }

    private struct BlockScalarHeader {
        let indentation: Int?
        let keepsTrailingBlankLines: Bool
    }

    private enum BlockScalarHeaderParse {
        case notBlockScalar
        case header(BlockScalarHeader)
        case invalid
    }

    /// Minimal YAML flow lexer used only to prove where a top-level property's physical block ends.
    /// It deliberately rejects mismatched or trailing syntax instead of guessing ownership.
    private struct FlowCollectionState {
        private var expectedClosers: [Character] = []
        private var quote: Character?
        private var escaped = false

        var isOpen: Bool { !expectedClosers.isEmpty }

        mutating func scan(_ text: Substring) -> Bool {
            var index = text.startIndex

            while index < text.endIndex {
                let character = text[index]
                let nextIndex = text.index(after: index)

                if quote == "\"" {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }

                if quote == "'" {
                    if character == "'" {
                        if nextIndex < text.endIndex, text[nextIndex] == "'" {
                            index = text.index(after: nextIndex)
                            continue
                        }
                        quote = nil
                    }
                    index = nextIndex
                    continue
                }

                if character == "#" {
                    let previous = index == text.startIndex ? nil : text[text.index(before: index)]
                    if previous == nil || previous == " " || previous == "\t"
                        || previous == "," || previous == "[" || previous == "{" {
                        break
                    }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "[" {
                    expectedClosers.append("]")
                } else if character == "{" {
                    expectedClosers.append("}")
                } else if character == "]" || character == "}" {
                    guard expectedClosers.last == character else { return false }
                    expectedClosers.removeLast()
                    if expectedClosers.isEmpty {
                        let remainder = text[nextIndex...].drop(while: {
                            $0 == " " || $0 == "\t"
                        })
                        return remainder.isEmpty || remainder.first == "#"
                    }
                }

                index = nextIndex
            }

            // A backslash at the end of a double-quoted flow line escapes the physical line break,
            // not the first character on the continuation line.
            escaped = false
            return true
        }
    }

    /// Tracks a top-level quoted scalar value across physical lines. A continuation line remains
    /// owned by its original property even when it looks like another `key: value` pair.
    private struct QuotedScalarState {
        private let quote: Character
        private var escaped = false
        private(set) var isOpen = true

        init(quote: Character) {
            self.quote = quote
        }

        mutating func scan(_ text: Substring) -> Bool {
            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                let nextIndex = text.index(after: index)

                if quote == "\"" {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        isOpen = false
                        let remainder = text[nextIndex...].drop(while: {
                            $0 == " " || $0 == "\t"
                        })
                        return remainder.isEmpty || remainder.first == "#"
                    }
                    index = nextIndex
                    continue
                }

                if character == "'" {
                    if nextIndex < text.endIndex, text[nextIndex] == "'" {
                        index = text.index(after: nextIndex)
                        continue
                    }
                    isOpen = false
                    let remainder = text[nextIndex...].drop(while: {
                        $0 == " " || $0 == "\t"
                    })
                    return remainder.isEmpty || remainder.first == "#"
                }
                index = nextIndex
            }

            // A trailing backslash consumes the physical line break, not the first continuation byte.
            escaped = false
            return true
        }
    }

    private struct YAMLAnchorReferences {
        var anchors: Set<String> = []
        var aliases: Set<String> = []
    }

    /// Conservative YAML token scan for anchor dependencies. It tracks comments and quotes and is
    /// applied to every nested/flow line, while block-scalar payload lines are skipped entirely.
    private struct YAMLAnchorLexer {
        private(set) var quote: Character?
        private var escaped = false

        mutating func scan(_ line: String, references: inout YAMLAnchorReferences) -> Bool {
            var expectsNode = quote == nil
            var previous: Character?
            var index = line.startIndex

            while index < line.endIndex {
                let character = line[index]
                let nextIndex = line.index(after: index)

                if quote == "\"" {
                    if escaped {
                        escaped = false
                    } else if character == "\\" {
                        escaped = true
                    } else if character == "\"" {
                        quote = nil
                    }
                    previous = character
                    index = nextIndex
                    continue
                }

                if quote == "'" {
                    if character == "'" {
                        if nextIndex < line.endIndex, line[nextIndex] == "'" {
                            previous = "'"
                            index = line.index(after: nextIndex)
                            continue
                        }
                        quote = nil
                    }
                    previous = character
                    index = nextIndex
                    continue
                }

                if character == "#",
                   previous == nil || previous == " " || previous == "\t"
                    || previous == "," || previous == "[" || previous == "{" {
                    break
                }

                if character == " " || character == "\t" {
                    previous = character
                    index = nextIndex
                    continue
                }

                if character == "\"" || character == "'" {
                    quote = character
                    expectsNode = false
                    previous = character
                    index = nextIndex
                    continue
                }

                if expectsNode, character == "!" {
                    let tokenEnd: String.Index
                    if nextIndex < line.endIndex, line[nextIndex] == "<" {
                        guard let closing = line[nextIndex...].firstIndex(of: ">") else { return false }
                        tokenEnd = line.index(after: closing)
                    } else {
                        tokenEnd = line[nextIndex...].firstIndex(where: {
                            $0 == " " || $0 == "\t" || "[]{},".contains($0)
                        }) ?? line.endIndex
                    }
                    guard tokenEnd > nextIndex else { return false }
                    expectsNode = true
                    previous = "!"
                    index = tokenEnd
                    continue
                }

                if expectsNode, character == "&" || character == "*" {
                    let tokenEnd = line[nextIndex...].firstIndex(where: {
                        $0 == " " || $0 == "\t" || "[]{},#?:".contains($0)
                    }) ?? line.endIndex
                    guard tokenEnd > nextIndex else { return false }
                    let name = String(line[nextIndex..<tokenEnd])
                    if character == "&" {
                        references.anchors.insert(name)
                        expectsNode = true
                    } else {
                        references.aliases.insert(name)
                        expectsNode = false
                    }
                    previous = character
                    index = tokenEnd
                    continue
                }

                if character == "[" || character == "{" || character == "," {
                    expectsNode = true
                } else if character == "]" || character == "}" {
                    expectsNode = false
                } else if character == ":" {
                    let next = nextIndex < line.endIndex ? line[nextIndex] : nil
                    expectsNode = next == nil || next == " " || next == "\t"
                        || next == "[" || next == "{"
                } else if expectsNode, character == "-" || character == "?" {
                    let next = nextIndex < line.endIndex ? line[nextIndex] : nil
                    expectsNode = next == " " || next == "\t"
                } else {
                    expectsNode = false
                }

                previous = character
                index = nextIndex
            }

            // A trailing double-quote escape applies to the physical line break, not the next byte.
            escaped = false
            return true
        }
    }

    private static func anchorReferences(in lines: [PhysicalLine]) -> YAMLAnchorReferences? {
        var references = YAMLAnchorReferences()
        var lexer = YAMLAnchorLexer()
        var index = 0

        while index < lines.count {
            let quoteWasOpen = lexer.quote != nil
            guard lexer.scan(lines[index].content, references: &references) else { return nil }

            if !quoteWasOpen, lexer.quote == nil,
               let scalar = blockScalarContinuationHeader(in: lines[index].content) {
                guard let end = blockScalarEnd(
                    in: lines,
                    startingAt: index + 1,
                    header: scalar.header,
                    baseIndentation: scalar.baseIndentation
                ) else {
                    return nil
                }
                index = max(index + 1, end)
            } else {
                index += 1
            }
        }

        return references
    }

    /// Discover complete top-level property blocks. Returning nil means some non-trivia line could
    /// not be assigned safely, so callers must preserve the original frontmatter unchanged.
    private static func propertyBlocks(in lines: [PhysicalLine]) -> [FrontmatterPropertyBlock]? {
        var blocks: [FrontmatterPropertyBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].content
            guard !hasTabInYAMLIndentation(line) else { return nil }
            if isYAMLTrivia(line) {
                index += 1
                continue
            }
            guard !isIndented(line), let header = propertyHeader(in: line) else {
                return nil
            }

            let end: Int
            switch blockScalarHeader(in: header.value) {
            case .invalid:
                return nil
            case .header(let scalarHeader):
                guard let scalarEnd = blockScalarEnd(
                    in: lines,
                    startingAt: index + 1,
                    header: scalarHeader,
                    baseIndentation: 0
                ) else {
                    return nil
                }
                end = scalarEnd
            case .notBlockScalar:
                var flowState = FlowCollectionState()
                var quotedScalarState: QuotedScalarState?
                guard let initialNode = yamlNode(in: header.value[...]) else { return nil }
                if initialNode.first == "[" || initialNode.first == "{" {
                    guard flowState.scan(initialNode) else { return nil }
                } else if let quote = initialNode.first, quote == "\"" || quote == "'" {
                    var state = QuotedScalarState(quote: quote)
                    guard state.scan(initialNode.dropFirst()) else { return nil }
                    quotedScalarState = state
                }

                let allowsIndentationlessSequence = initialNode.isEmpty || initialNode.first == "#"
                var continuationEnd = index + 1
                while continuationEnd < lines.count {
                    let continuation = lines[continuationEnd].content
                    guard !hasTabInYAMLIndentation(continuation) else { return nil }

                    if var state = quotedScalarState, state.isOpen {
                        guard state.scan(continuation[...]) else { return nil }
                        quotedScalarState = state
                        continuationEnd += 1
                        continue
                    }
                    if flowState.isOpen {
                        guard flowState.scan(continuation[...]) else { return nil }
                        continuationEnd += 1
                        continue
                    }
                    guard !hasTabAfterBlockSequenceDash(continuation) else { return nil }

                    if allowsIndentationlessSequence,
                       indentationlessSequenceNode(in: continuation) != nil {
                        if let scalar = blockScalarContinuationHeader(in: continuation) {
                            guard let scalarEnd = blockScalarEnd(
                                in: lines,
                                startingAt: continuationEnd + 1,
                                header: scalar.header,
                                baseIndentation: scalar.baseIndentation
                            ) else {
                                return nil
                            }
                            continuationEnd = scalarEnd
                            continue
                        }
                        if let node = flowCollectionNode(inIndentedLine: continuation) {
                            guard flowState.scan(node) else { return nil }
                        }
                        continuationEnd += 1
                        continue
                    }

                    if isIndented(continuation), !isYAMLTrivia(continuation) {
                        if let scalar = blockScalarContinuationHeader(in: continuation) {
                            guard let scalarEnd = blockScalarEnd(
                                in: lines,
                                startingAt: continuationEnd + 1,
                                header: scalar.header,
                                baseIndentation: scalar.baseIndentation
                            ) else {
                                return nil
                            }
                            continuationEnd = scalarEnd
                            continue
                        }
                        if let node = flowCollectionNode(inIndentedLine: continuation) {
                            guard flowState.scan(node) else { return nil }
                        }
                        continuationEnd += 1
                        continue
                    }

                    if isYAMLTrivia(continuation) {
                        // Comments and blank lines belong to this block only when owned content resumes.
                        var nextContent = continuationEnd + 1
                        while nextContent < lines.count,
                              isYAMLTrivia(lines[nextContent].content) {
                            guard !hasTabInYAMLIndentation(lines[nextContent].content) else { return nil }
                            nextContent += 1
                        }
                        if nextContent < lines.count,
                           isOwnedYAMLContinuation(
                               lines[nextContent].content,
                               allowsIndentationlessSequence: allowsIndentationlessSequence
                           ) {
                            continuationEnd = nextContent
                            continue
                        }
                        break
                    }

                    if propertyHeader(in: continuation) != nil {
                        break
                    }

                    // A column-zero closer, explicit complex key, directive, root sequence after a
                    // nonempty value, or other unsupported construct has ambiguous ownership.
                    return nil
                }

                guard !flowState.isOpen, quotedScalarState?.isOpen != true else { return nil }
                end = continuationEnd
            }

            blocks.append(FrontmatterPropertyBlock(key: header.key, range: index..<end))
            index = end
        }

        return blocks
    }

    private static func indentationlessSequenceNode(in line: String) -> Substring? {
        guard line.first == "-" else { return nil }
        let afterDash = line.index(after: line.startIndex)
        guard afterDash == line.endIndex || line[afterDash] == " " else { return nil }
        return line[afterDash...].drop(while: { $0 == " " })
    }

    private static func isOwnedYAMLContinuation(
        _ line: String,
        allowsIndentationlessSequence: Bool
    ) -> Bool {
        if isIndented(line) { return true }
        return allowsIndentationlessSequence && indentationlessSequenceNode(in: line) != nil
    }

    private static func propertyHeader(in line: String) -> FrontmatterPropertyHeader? {
        guard let first = line.first,
              !isWhitespace(first),
              !line.hasPrefix("#"),
              !line.hasPrefix("%"),
              !isFrontmatterDelimiter(line) else {
            return nil
        }

        if first == "'" || first == "\"" {
            guard let quoted = decodedQuotedKey(in: line, quote: first) else { return nil }
            var separator = quoted.nextIndex
            while separator < line.endIndex,
                  line[separator] == " " || line[separator] == "\t" {
                separator = line.index(after: separator)
            }
            guard separator < line.endIndex, line[separator] == ":" else { return nil }
            let valueStart = line.index(after: separator)
            guard valueStart == line.endIndex || isWhitespace(line[valueStart]) else { return nil }
            return FrontmatterPropertyHeader(
                key: .string(quoted.key.precomposedStringWithCanonicalMapping),
                value: String(line[valueStart...])
            )
        }

        var separator = line.startIndex
        while separator < line.endIndex {
            if line[separator] == ":" {
                let valueStart = line.index(after: separator)
                if valueStart == line.endIndex || isWhitespace(line[valueStart]) {
                    let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                    guard isSupportedPlainKey(key) else { return nil }
                    return FrontmatterPropertyHeader(
                        key: propertyKey(forPlainKey: key),
                        value: String(line[valueStart...])
                    )
                }
            }
            separator = line.index(after: separator)
        }
        return nil
    }

    private static func decodedQuotedKey(
        in line: String,
        quote: Character
    ) -> (key: String, nextIndex: String.Index)? {
        var key = ""
        var index = line.index(after: line.startIndex)

        while index < line.endIndex {
            let character = line[index]
            let nextIndex = line.index(after: index)

            if quote == "'" {
                if character == "'" {
                    if nextIndex < line.endIndex, line[nextIndex] == "'" {
                        key.append("'")
                        index = line.index(after: nextIndex)
                        continue
                    }
                    return (key, nextIndex)
                }
                key.append(character)
                index = nextIndex
                continue
            }

            if character == "\"" {
                return (key, nextIndex)
            }
            guard character == "\\" else {
                key.append(character)
                index = nextIndex
                continue
            }

            guard nextIndex < line.endIndex else { return nil }
            let escape = line[nextIndex]
            let afterEscape = line.index(after: nextIndex)
            switch escape {
            case "0": key.append("\0")
            case "a": key.append("\u{0007}")
            case "b": key.append("\u{0008}")
            case "t", "\t": key.append("\t")
            case "n": key.append("\n")
            case "v": key.append("\u{000B}")
            case "f": key.append("\u{000C}")
            case "r": key.append("\r")
            case "e": key.append("\u{001B}")
            case " ": key.append(" ")
            case "\"": key.append("\"")
            case "/": key.append("/")
            case "\\": key.append("\\")
            case "N": key.append("\u{0085}")
            case "_": key.append("\u{00A0}")
            case "L": key.append("\u{2028}")
            case "P": key.append("\u{2029}")
            case "x", "u", "U":
                let count = escape == "x" ? 2 : (escape == "u" ? 4 : 8)
                var digitsEnd = afterEscape
                for _ in 0..<count {
                    guard digitsEnd < line.endIndex else { return nil }
                    digitsEnd = line.index(after: digitsEnd)
                }
                let digits = String(line[afterEscape..<digitsEnd])
                guard digits.unicodeScalars.allSatisfy({
                    CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
                }),
                let value = UInt32(digits, radix: 16),
                let scalar = UnicodeScalar(value) else {
                    return nil
                }
                key.unicodeScalars.append(scalar)
                index = digitsEnd
                continue
            default:
                return nil
            }
            index = afterEscape
        }
        return nil
    }

    private static func propertyKey(forPlainKey key: String) -> FrontmatterPropertyKey {
        let normalized = key.precomposedStringWithCanonicalMapping
        let lowercased = normalized.lowercased()
        let typedKeywords: Set<String> = [
            "~", "null", "y", "n", "true", "false", "yes", "no", "on", "off",
            ".nan", ".inf", "+.inf", "-.inf"
        ]
        if typedKeywords.contains(lowercased) {
            return .implicitlyTypedPlain(lowercased)
        }
        if isImplicitNumericOrTimestampKey(normalized) {
            return .implicitlyTypedPlain(normalized)
        }
        return .string(normalized)
    }

    /// Obsidian YAML implementations have used both YAML 1.1- and 1.2-style implicit schemas.
    /// Keep their scalar-looking plain keys in a separate identity domain from quoted strings.
    private static func isImplicitNumericOrTimestampKey(_ key: String) -> Bool {
        let digitRun = #"[0-9][0-9_]*"#
        let patterns = [
            #"^[+-]?\#(digitRun)$"#,
            #"^[+-]?0[bB][01][01_]*$"#,
            #"^[+-]?0[oO][0-7][0-7_]*$"#,
            #"^[+-]?0[xX][0-9a-fA-F][0-9a-fA-F_]*$"#,
            #"^[+-]?(?:(?:\#(digitRun))?\.\#(digitRun)|\#(digitRun)\.)(?:[eE][+-]?[0-9]+)?$"#,
            #"^[+-]?\#(digitRun)[eE][+-]?[0-9]+$"#,
            #"^[+-]?\#(digitRun)(?::[0-5]?[0-9])+(?:\.\#(digitRun))?$"#,
            #"^[0-9]{4}-[0-9]{2}-[0-9]{2}(?:$|[Tt \t])"#
        ]
        return patterns.contains { pattern in
            key.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func isSupportedPlainKey(_ key: String) -> Bool {
        guard let first = key.first,
              !key.isEmpty,
              !"[]{},&*#!|>%@`".contains(first),
              key != "-", !key.hasPrefix("- "), !key.hasPrefix("-\t"),
              key != "?", !key.hasPrefix("? "), !key.hasPrefix("?\t") else {
            return false
        }

        var previousWasWhitespace = false
        for character in key {
            if character == "#", previousWasWhitespace { return false }
            previousWasWhitespace = isWhitespace(character)
        }
        return true
    }

    private static func blockScalarHeader(in value: String) -> BlockScalarHeaderParse {
        guard let node = yamlNode(in: value[...]) else { return .invalid }
        guard node.first == "|" || node.first == ">" else { return .notBlockScalar }

        var indentation: Int?
        var chomping: Character?
        var index = node.index(after: node.startIndex)

        while index < node.endIndex {
            let character = node[index]
            if character == " " || character == "\t" {
                let remainder = node[index...].drop(while: { $0 == " " || $0 == "\t" })
                guard remainder.isEmpty || remainder.first == "#" else { return .invalid }
                return .header(BlockScalarHeader(
                    indentation: indentation,
                    keepsTrailingBlankLines: chomping == "+"
                ))
            }
            if character == "+" || character == "-" {
                guard chomping == nil else { return .invalid }
                chomping = character
            } else if "123456789".contains(character),
                      let digit = character.wholeNumberValue {
                guard indentation == nil else { return .invalid }
                indentation = digit
            } else {
                return .invalid
            }
            index = node.index(after: index)
        }

        return .header(BlockScalarHeader(
            indentation: indentation,
            keepsTrailingBlankLines: chomping == "+"
        ))
    }

    private static func blockScalarEnd(
        in lines: [PhysicalLine],
        startingAt start: Int,
        header: BlockScalarHeader,
        baseIndentation: Int
    ) -> Int? {
        var contentIndent = header.indentation.map { baseIndentation + $0 }
        var consumedEnd = start
        var lastNonblankEnd: Int?
        var index = start

        while index < lines.count {
            let line = lines[index].content
            if isBlankYAMLLine(line) {
                if line.contains("\t") {
                    let spacesBeforeTab = line.prefix(while: { $0 == " " }).count
                    let minimum = contentIndent ?? (baseIndentation + 1)
                    guard spacesBeforeTab >= minimum else { return nil }
                }
                consumedEnd = index + 1
                index += 1
                continue
            }

            guard let indentation = blockScalarIndentation(
                in: line,
                required: contentIndent,
                baseIndentation: baseIndentation
            ) else {
                return nil
            }
            if contentIndent == nil {
                guard indentation > baseIndentation else { break }
                contentIndent = indentation
            }
            guard indentation >= contentIndent! else { break }

            consumedEnd = index + 1
            lastNonblankEnd = index + 1
            index += 1
        }

        return header.keepsTrailingBlankLines ? consumedEnd : (lastNonblankEnd ?? start)
    }

    /// Tabs are scalar payload only after the required space indentation has been satisfied.
    private static func blockScalarIndentation(
        in line: String,
        required: Int?,
        baseIndentation: Int
    ) -> Int? {
        var spaces = 0
        for character in line {
            if character == " " {
                spaces += 1
            } else if character == "\t" {
                let minimum = required ?? (baseIndentation + 1)
                return spaces >= minimum ? spaces : nil
            } else {
                break
            }
        }
        return spaces
    }

    private static func blockScalarContinuationHeader(
        in line: String
    ) -> (header: BlockScalarHeader, baseIndentation: Int)? {
        guard let indentation = leadingSpaceIndentation(in: line) else { return nil }
        let unindented = String(line.dropFirst(indentation))
        var candidate = unindented[...]
        var nestedMappingIndentation = indentation
        if let sequenceNode = indentationlessSequenceNode(in: unindented) {
            nestedMappingIndentation += unindented.distance(
                from: unindented.startIndex,
                to: sequenceNode.startIndex
            )
            candidate = sequenceNode
        }

        let value: String
        let baseIndentation: Int
        if let nestedHeader = propertyHeader(in: String(candidate)) {
            value = nestedHeader.value
            baseIndentation = nestedMappingIndentation
        } else {
            value = String(candidate)
            baseIndentation = indentation
        }
        guard case .header(let header) = blockScalarHeader(in: value) else { return nil }
        return (header, baseIndentation)
    }

    private static func flowCollectionNode(inIndentedLine line: String) -> Substring? {
        var candidate = line[...].drop(while: { $0 == " " || $0 == "\t" })
        if candidate.first == "-" {
            let afterDash = candidate.index(after: candidate.startIndex)
            if afterDash == candidate.endIndex
                || candidate[afterDash] == " " || candidate[afterDash] == "\t" {
                candidate = candidate[afterDash...].drop(while: { $0 == " " || $0 == "\t" })
            }
        }

        if candidate.first != "[", candidate.first != "{",
           let nested = propertyHeader(in: String(candidate)) {
            candidate = nested.value[...]
        }
        guard let node = yamlNode(in: candidate),
              node.first == "[" || node.first == "{" else {
            return nil
        }
        return node
    }

    /// Skip supported YAML tag/anchor node properties before a scalar or flow collection.
    private static func yamlNode(in text: Substring) -> Substring? {
        var node = text.drop(while: { $0 == " " || $0 == "\t" })

        while node.first == "!" || node.first == "&" {
            let marker = node.first!
            let tokenEnd: Substring.Index
            if marker == "!", node.hasPrefix("!<") {
                guard let closing = node.firstIndex(of: ">") else { return nil }
                tokenEnd = node.index(after: closing)
            } else {
                tokenEnd = node.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? node.endIndex
                guard tokenEnd != node.index(after: node.startIndex) else { return nil }
            }
            node = node[tokenEnd...].drop(while: { $0 == " " || $0 == "\t" })
        }

        return node
    }

    private static func isYAMLTrivia(_ line: String) -> Bool {
        isBlankYAMLLine(line) || line.drop(while: { $0 == " " || $0 == "\t" }).first == "#"
    }

    private static func isBlankYAMLLine(_ line: String) -> Bool {
        line.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func leadingSpaceIndentation(in line: String) -> Int? {
        var count = 0
        for character in line {
            if character == " " {
                count += 1
            } else if character == "\t" {
                return nil
            } else {
                break
            }
        }
        return count
    }

    private static func hasTabInYAMLIndentation(_ line: String) -> Bool {
        for character in line {
            if character == " " { continue }
            return character == "\t"
        }
        return false
    }

    private static func hasTabAfterBlockSequenceDash(_ line: String) -> Bool {
        var candidate = line.drop(while: { $0 == " " })
        guard candidate.first == "-" else { return false }
        candidate = candidate.dropFirst().drop(while: { $0 == " " })
        return candidate.first == "\t"
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) }
    }

    private static func isIndented(_ line: String) -> Bool {
        line.first == " " || line.first == "\t"
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

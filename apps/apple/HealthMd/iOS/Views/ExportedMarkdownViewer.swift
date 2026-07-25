import Foundation
import SwiftUI

/// Routes Markdown around Quick Look because iOS can classify the `.md` extension
/// as a game ROM instead of a text document.
enum ExportFilePreviewRoute: Equatable {
    case inAppMarkdown
    case quickLook

    static func route(for url: URL) -> Self {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": return .inAppMarkdown
        default: return .quickLook
        }
    }
}

struct ExportedMarkdownPresentation: Identifiable {
    let id = UUID()
    let target: ExportPresentationTarget
}

struct ExportedMarkdownViewer: View {
    private static let richPreviewByteLimit = 1_000_000

    enum DisplayMode: Hashable {
        case preview
        case source
    }

    let target: ExportPresentationTarget

    @Environment(\.dismiss) private var dismiss
    @State private var document: ExportedMarkdownDocument?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var displayMode: DisplayMode = .preview
    @State private var loadRequestID = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading exported file…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier(AccessibilityID.ExportedFile.loading)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("Couldn’t Open File", systemImage: "doc.badge.exclamationmark")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try Again") {
                            loadRequestID = UUID()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(AccessibilityID.ExportedFile.retry)
                    }
                } else if let document {
                    documentView(document)
                }
            }
            .background(Color.bgPrimary)
            .navigationTitle(target.fileURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.ExportedFile.done)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityID.ExportedFile.viewer)
        .task(id: loadRequestID) {
            await loadDocument()
        }
    }

    @ViewBuilder
    private func documentView(_ document: ExportedMarkdownDocument) -> some View {
        VStack(spacing: 0) {
            if document.hasRichPreview {
                Picker("File display", selection: $displayMode) {
                    Text("Preview").tag(DisplayMode.preview)
                    Text("Source").tag(DisplayMode.source)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s3)
                .accessibilityIdentifier(AccessibilityID.ExportedFile.displayMode)
            } else {
                Label(
                    "This export is too large for rich preview. The complete source is shown instead.",
                    systemImage: "doc.text"
                )
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bgSecondary)
                .accessibilityIdentifier(AccessibilityID.ExportedFile.largeFileNotice)
            }

            Divider()

            if displayMode == .preview, document.hasRichPreview {
                ExportedMarkdownRenderedView(blocks: document.blocks)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(document.source.isEmpty ? "This file is empty." : document.source)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(Spacing.s4)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityIdentifier(AccessibilityID.ExportedFile.source)
                }
                .background(Color.bgPrimary)
            }
        }
    }

    private func loadDocument() async {
        isLoading = true
        errorMessage = nil

        let fileURL = target.fileURL
        let securityScopedRootURL = target.securityScopedRootURL

        do {
            let payload = try await Task.detached(priority: .userInitiated) {
                let startedSecurityScope = securityScopedRootURL?.startAccessingSecurityScopedResource() ?? false
                defer {
                    if startedSecurityScope {
                        securityScopedRootURL?.stopAccessingSecurityScopedResource()
                    }
                }

                let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory != true else {
                    throw ExportedMarkdownReaderError.isDirectory
                }

                let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                guard let source = String(data: data, encoding: .utf8) else {
                    throw ExportedMarkdownReaderError.invalidUTF8
                }
                return ExportedMarkdownPayload(source: source, byteCount: data.count)
            }.value

            guard !Task.isCancelled else { return }
            let hasRichPreview = payload.byteCount <= Self.richPreviewByteLimit
            document = ExportedMarkdownDocument(
                source: payload.source,
                blocks: hasRichPreview ? ExportedMarkdownParser.parse(payload.source) : [],
                hasRichPreview: hasRichPreview
            )
            displayMode = hasRichPreview ? .preview : .source
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            document = nil
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

private struct ExportedMarkdownPayload: Sendable {
    let source: String
    let byteCount: Int
}

private enum ExportedMarkdownReaderError: LocalizedError {
    case isDirectory
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .isDirectory:
            return "The selected item is a folder, not a Markdown file."
        case .invalidUTF8:
            return "This file isn’t valid UTF-8 text."
        }
    }
}

struct ExportedMarkdownDocument {
    let source: String
    let blocks: [ExportedMarkdownBlock]
    let hasRichPreview: Bool
}

struct ExportedMarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(level: Int)
        case paragraph
        case bullet(level: Int)
        case numbered(marker: String, level: Int)
        case code(language: String?)
        case table
        case metadata
        case divider
    }

    let id: Int
    let kind: Kind
    let text: String
}

enum ExportedMarkdownParser {
    static func parse(_ source: String) -> [ExportedMarkdownBlock] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [ExportedMarkdownBlock] = []
        var paragraphLines: [String] = []
        var index = 0
        var nextID = 0

        func append(_ kind: ExportedMarkdownBlock.Kind, _ text: String = "") {
            blocks.append(ExportedMarkdownBlock(id: nextID, kind: kind, text: text))
            nextID += 1
        }

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            append(.paragraph, paragraphLines.joined(separator: " "))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            var metadata: [String] = []
            index = 1
            while index < lines.count,
                  lines[index].trimmingCharacters(in: .whitespaces) != "---" {
                metadata.append(lines[index])
                index += 1
            }
            if index < lines.count {
                append(.metadata, metadata.joined(separator: "\n"))
                index += 1
            } else {
                index = 0
            }
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(.code(language: language.isEmpty ? nil : language), codeLines.joined(separator: "\n"))
                continue
            }

            let headingLevel = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(headingLevel),
               trimmed.dropFirst(headingLevel).first == " " {
                flushParagraph()
                append(.heading(level: headingLevel), String(trimmed.dropFirst(headingLevel + 1)))
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                append(.divider)
                index += 1
                continue
            }

            if trimmed.hasPrefix("|") {
                flushParagraph()
                var tableLines: [String] = []
                while index < lines.count,
                      lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    tableLines.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                append(.table, tableLines.joined(separator: "\n"))
                continue
            }

            let indentation = line.prefix { $0 == " " }.count
            let listLevel = max(0, indentation / 2)
            if let bulletText = bulletText(from: trimmed) {
                flushParagraph()
                append(.bullet(level: listLevel), bulletText)
                index += 1
                continue
            }

            if let numbered = numberedListItem(from: trimmed) {
                flushParagraph()
                append(.numbered(marker: numbered.marker, level: listLevel), numbered.text)
                index += 1
                continue
            }

            paragraphLines.append(trimmed)
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func bulletText(from line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func numberedListItem(from line: String) -> (marker: String, text: String)? {
        guard let separator = line.firstIndex(of: ".") else { return nil }
        let marker = String(line[..<separator])
        guard !marker.isEmpty,
              marker.allSatisfy(\.isNumber),
              line.index(after: separator) < line.endIndex,
              line[line.index(after: separator)] == " " else { return nil }
        return (marker + ".", String(line[line.index(separator, offsetBy: 2)...]))
    }
}

private struct ExportedMarkdownRenderedView: View {
    let blocks: [ExportedMarkdownBlock]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s3) {
                if blocks.isEmpty {
                    Text("This file is empty.")
                        .foregroundStyle(Color.textSecondary)
                } else {
                    ForEach(blocks) { block in
                        blockView(block)
                    }
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bgPrimary)
        .accessibilityIdentifier(AccessibilityID.ExportedFile.rendered)
    }

    @ViewBuilder
    private func blockView(_ block: ExportedMarkdownBlock) -> some View {
        switch block.kind {
        case .heading(let level):
            Text(inlineMarkdown(block.text))
                .font(headingFont(level: level))
                .fontWeight(.semibold)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

        case .paragraph:
            Text(inlineMarkdown(block.text))
                .font(.body)
                .foregroundStyle(Color.textPrimary)
                .textSelection(.enabled)

        case .bullet(let level):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Text("•")
                    .accessibilityHidden(true)
                Text(inlineMarkdown(block.text))
                    .textSelection(.enabled)
            }
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .padding(.leading, CGFloat(level) * Spacing.s4)
            .accessibilityElement(children: .combine)

        case .numbered(let marker, let level):
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                Text(marker)
                    .foregroundStyle(Color.textSecondary)
                Text(inlineMarkdown(block.text))
                    .textSelection(.enabled)
            }
            .font(.body)
            .foregroundStyle(Color.textPrimary)
            .padding(.leading, CGFloat(level) * Spacing.s4)
            .accessibilityElement(children: .combine)

        case .code(let language):
            VStack(alignment: .leading, spacing: Spacing.s2) {
                if let language {
                    Text(language.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textMuted)
                }
                Text(block.text)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm))

        case .table:
            ScrollView(.horizontal) {
                Text(block.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(Spacing.s3)
            }
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm))

        case .metadata:
            DisclosureGroup {
                Text(block.text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Spacing.s2)
            } label: {
                Label("Export Metadata", systemImage: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(Spacing.s3)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: GeistRadius.sm))

        case .divider:
            Divider()
        }
    }

    private func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }
}

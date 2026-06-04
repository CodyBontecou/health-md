import Foundation
import ExportKit

/// Health.md compatibility facade for Markdown section merging.
///
/// The reusable merge strategy is domain-free; this facade supplies the
/// app-owned section names that existing exports manage so update mode and Daily
/// Note Injection keep their historical behavior.
enum MarkdownMerger {
    typealias Section = MarkdownMergeStrategy.Section
    typealias ParsedDocument = MarkdownMergeStrategy.ParsedDocument

    static let managedSectionNames: Set<String> = [
        "sleep", "activity", "heart", "vitals", "body",
        "nutrition", "mindfulness", "mobility", "hearing", "workouts",
        "medications"
    ]

    static func merge(existing: String, new: String) -> String {
        MarkdownMergeStrategy.merge(
            existing: existing,
            new: new,
            managedSectionNames: managedSectionNames
        )
    }

    static func mergePreservingPreamble(existing: String, new: String) -> String {
        MarkdownMergeStrategy.mergePreservingPreamble(
            existing: existing,
            new: new,
            managedSectionNames: managedSectionNames
        )
    }

    static func mergeFrontmatter(existing: String, new: String) -> String {
        MarkdownMergeStrategy.mergeFrontmatter(existing: existing, new: new)
    }

    static func parseFrontmatterProperties(_ frontmatter: String) -> [(key: String, value: String)] {
        MarkdownMergeStrategy.parseFrontmatterProperties(frontmatter)
    }

    static func parse(_ content: String, sectionLevel: Int) -> ParsedDocument {
        MarkdownMergeStrategy.parse(content, sectionLevel: sectionLevel)
    }

    static func headingLevel(of line: String) -> Int {
        MarkdownMergeStrategy.headingLevel(of: line)
    }

    static func normalizeHeadingText(_ heading: String) -> String {
        MarkdownMergeStrategy.normalizeHeadingText(heading)
    }

    static func detectSectionLevel(in content: String) -> Int {
        MarkdownMergeStrategy.detectSectionLevel(
            in: content,
            managedSectionNames: managedSectionNames
        )
    }
}

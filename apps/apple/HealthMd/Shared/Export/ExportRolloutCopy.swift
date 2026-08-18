import Foundation

// MARK: - Export rollout guardrail copy

/// Shared explanatory text for schema-affecting export settings.
///
/// Keeping this copy in one place makes the rollout guidance testable while
/// preserving exporter output and schema signatures.
enum ExportRolloutCopy {
    static let versionedExportsHelp = String(localized: "Exports are versioned and self-describing with schema \(HealthMdExportSchema.identifier) v\(HealthMdExportSchema.version). Existing files continue to work; re-export old ranges only when you want fully consistent v\(HealthMdExportSchema.version) units and history.")

    static let canonicalUnitsHelp = String(localized: "Structured frontmatter, Obsidian Bases, JSON, and CSV store canonical metric values (`unit_system: metric`) regardless of your Metric/Imperial display preference. Human-readable Markdown prose can still use your selected display units.")

    static let dataDictionaryHelp = String(localized: "When Write Data Dictionary is enabled, Health.md writes \(HealthMdExportSchema.dataDictionaryFilename) at the export root so Obsidian plugins, scripts, and AI assistants can read field units, daily aggregations, and roll-up rules. Turn it off for a Markdown-only folder.")

    static let formatSelectionHelp = String(localized: "JSON preserves the complete structured export, including workouts, route points, samples, medications, and metadata. Markdown and Obsidian Bases are optimized for readable notes and flat queryable properties. CSV is best for spreadsheets, with nested data flattened into rows.")

    static let jsonFormatTip = String(localized: "Tip: include JSON when you want the most complete backup for automation or future re-imports.")

    static let formatFoldersHelp = String(localized: "Organize by File Type is off by default. Turn it on only when you want Markdown/, Bases/, JSON/, and CSV/ folders; update plugins, shortcuts, or scripts that expect flat paths first.")

    static let rollupSummariesHelp = String(localized: "Roll-up summaries are off by default. They are aggregate weekly/monthly/yearly files (`\(HealthRollupExportSchema.identifier)`) generated from HealthKit daily snapshots and are not daily records. Each enabled period processes its complete touched calendar windows, so a yearly summary can read hundreds of source days even when the final files are small. Turn on Summary files only to skip daily files and write just the enabled summaries.")

}

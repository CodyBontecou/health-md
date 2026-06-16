import Foundation

// MARK: - Export rollout guardrail copy

/// Shared explanatory text for schema-affecting export settings.
///
/// Keeping this copy in one place makes the rollout guidance testable while
/// preserving exporter output and schema signatures.
enum ExportRolloutCopy {
    static let versionedExportsHelp = "Exports are versioned and self-describing with schema \(HealthMdExportSchema.identifier) v\(HealthMdExportSchema.version). Existing files continue to work; re-export old ranges only when you want fully consistent v\(HealthMdExportSchema.version) units and history."

    static let canonicalUnitsHelp = "Structured frontmatter, Obsidian Bases, JSON, and CSV store canonical metric values (`unit_system: metric`) regardless of your Metric/Imperial display preference. Human-readable Markdown prose can still use your selected display units."

    static let dataDictionaryHelp = "Health.md writes \(HealthMdExportSchema.dataDictionaryFilename) at the Health folder root so Obsidian plugins, scripts, and AI assistants can read field units, daily aggregations, and roll-up rules."

    static let formatFoldersHelp = "Organize by File Type is off by default. Turn it on only when you want Markdown/, Bases/, JSON/, and CSV/ folders; update plugins, shortcuts, or scripts that expect flat paths first."

    static let rollupSummariesHelp = "Roll-up summaries are off by default. They are aggregate weekly/monthly/yearly files (`\(HealthRollupExportSchema.identifier)`) generated from HealthKit daily snapshots and are not daily records."

    static let pluginCompatibilityHelp = "Before enabling roll-up summaries or format folders broadly, update the Obsidian plugin and run a mixed-export compatibility smoke test."
}

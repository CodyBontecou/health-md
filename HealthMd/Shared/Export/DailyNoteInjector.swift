//
//  DailyNoteInjector.swift
//  Health.md
//
//  Injects health metrics into an existing daily note. By default writes only
//  to YAML frontmatter, leaving the body untouched. When
//  `settings.injectMarkdownSections` is on, also writes the markdown export's
//  body sections (Sleep, Activity, …), replacing app-managed sections in place
//  while preserving the user's preamble and any user-added sections.
//
//  Which metrics are injected is driven entirely by MetricSelectionState —
//  no separate field selection needed.
//

import Foundation
import ExportKit

// MARK: - Daily Note Injector

struct DailyNoteInjector {

    // MARK: - Injection Result

    enum InjectionResult {
        case updated(path: String)
        case skipped(reason: String)
        case failed(Error)
    }

    struct InjectionPreview {
        let filename: String
        let path: String
        let content: String
    }

    enum InjectionPreviewBase: Equatable {
        /// Merge into the note content that already exists on disk.
        case existingContent(String)
        /// Preview the exact content created when Daily Note Injection starts from an empty note.
        case emptyDocument
    }

    enum InjectionPreviewResult {
        case preview(InjectionPreview)
        case skipped(reason: String)
    }

    private struct InjectionContent {
        let frontmatter: String
        let body: String
    }

    // MARK: - Public API

    /// Inject health metrics for the enabled metrics into a daily note.
    ///
    /// Which metrics are injected is determined by `metricSelection` — the same
    /// selection the user configures in Health Metrics settings.
    @discardableResult
    static func inject(
        healthData: HealthData,
        into vaultURL: URL,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization,
        metricSelection: MetricSelectionState
    ) -> InjectionResult {
        guard settings.enabled else { return .skipped(reason: "Injection disabled") }

        // 1. Resolve target file URL from the selected vault/root destination.
        // Use the rejecting safety policy for writes so templates cannot escape
        // the selected vault/root through `..` traversal or absolute paths.
        let targetURL: URL
        let relativePath: String
        do {
            targetURL = try ExportPathPlanner.safeDailyNoteURL(
                vaultURL: vaultURL,
                settings: settings,
                date: healthData.date
            )
            relativePath = try ExportPathPlanner.safeDailyNoteRelativePath(settings: settings, date: healthData.date)
        } catch {
            return .failed(error)
        }

        let fm = FileManager.default

        // 2. Handle missing file
        if !fm.fileExists(atPath: targetURL.path) {
            if settings.createIfMissing {
                do {
                    // Always call createDirectory with withIntermediateDirectories:true —
                    // it is idempotent and creates the full path (e.g. vault/Daily/) in one call.
                    let parent = targetURL.deletingLastPathComponent()
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: nil)
                    try "".write(to: targetURL, atomically: true, encoding: .utf8)
                } catch {
                    return .failed(error)
                }
            } else {
                return .skipped(reason: "Daily note not found: \(relativePath)")
            }
        }

        // 3. Read existing content
        let existingContent: String
        do {
            existingContent = try String(contentsOf: targetURL, encoding: .utf8)
        } catch {
            return .failed(error)
        }

        // 4. Build the frontmatter and optional body sections from enabled metrics.
        guard let injectionContent = buildInjectionContent(
            healthData: healthData,
            settings: settings,
            customization: customization,
            metricSelection: metricSelection
        ) else {
            return .skipped(reason: "No data available for enabled metrics on this date")
        }

        // 5. Merge into existing content.
        let updatedContent = mergedContent(
            existing: existingContent,
            injectionContent: injectionContent,
            settings: settings
        )

        // 6. Write back
        do {
            try updatedContent.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            return .failed(error)
        }

        return .updated(path: relativePath)
    }

    /// Builds the same merged daily-note content as `inject` without touching disk.
    /// Use `.existingContent` when the current note bytes are available; use
    /// `.emptyDocument` for a create-if-missing preview or when previewing a
    /// remote destination whose existing daily note cannot be read locally.
    static func preview(
        healthData: HealthData,
        base: InjectionPreviewBase,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization,
        metricSelection: MetricSelectionState
    ) -> InjectionPreviewResult {
        guard settings.enabled else { return .skipped(reason: "Injection disabled") }

        guard let injectionContent = buildInjectionContent(
            healthData: healthData,
            settings: settings,
            customization: customization,
            metricSelection: metricSelection
        ) else {
            return .skipped(reason: "No data available for enabled metrics on this date")
        }

        let existingContent: String
        switch base {
        case .existingContent(let content):
            existingContent = content
        case .emptyDocument:
            existingContent = ""
        }

        let content = mergedContent(
            existing: existingContent,
            injectionContent: injectionContent,
            settings: settings
        )
        let filename = settings.formatFilename(for: healthData.date) + ".md"

        return .preview(InjectionPreview(
            filename: filename,
            path: ExportPathPlanner.dailyNoteRelativePath(settings: settings, date: healthData.date),
            content: content
        ))
    }

    // MARK: - Private helpers

    /// Returns the ordered set of frontmatter originalKeys that correspond to
    /// metrics enabled in the given MetricSelectionState.
    static func frontmatterKeys(enabledIn metricSelection: MetricSelectionState) -> [String] {
        HealthMetricExportMapping.frontmatterKeys(enabledIn: metricSelection)
    }

    private static func buildInjectionContent(
        healthData: HealthData,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization,
        metricSelection: MetricSelectionState
    ) -> InjectionContent? {
        let allMetrics = healthData.allMetricsDictionary(using: customization.unitConverter, timeFormat: customization.timeFormat)
        let fmConfig = customization.frontmatterConfig
        let allowedKeys = frontmatterKeys(enabledIn: metricSelection)

        var injectionLines: [String] = ["---"]
        for originalKey in allowedKeys {
            guard let value = allMetrics[originalKey] else { continue }
            let outputKey = resolvedOutputKey(originalKey: originalKey, fmConfig: fmConfig)
            injectionLines.append("\(outputKey): \(value)")
        }
        let hasFrontmatterContent = injectionLines.count > 1
        injectionLines.append("---")
        let injectionFrontmatter = hasFrontmatterContent
            ? injectionLines.joined(separator: "\n") + "\n"
            : ""

        let injectionBody: String
        let hasBodySections: Bool
        if settings.injectMarkdownSections {
            let filtered = healthData.filtered(by: metricSelection)
            let body = filtered.toMarkdown(includeMetadata: false, customization: customization)
            let sectionLevel = customization.markdownTemplate.sectionHeaderLevel
            hasBodySections = MarkdownMerger.parse(body, sectionLevel: sectionLevel).sections.isEmpty == false
            injectionBody = body
        } else {
            injectionBody = ""
            hasBodySections = false
        }

        guard hasFrontmatterContent || hasBodySections else { return nil }
        return InjectionContent(frontmatter: injectionFrontmatter, body: injectionBody)
    }

    private static func mergedContent(
        existing: String,
        injectionContent: InjectionContent,
        settings: DailyNoteInjectionSettings
    ) -> String {
        if settings.injectMarkdownSections {
            return MarkdownMerger.mergePreservingPreamble(
                existing: existing,
                new: injectionContent.frontmatter + injectionContent.body
            )
        }

        return mergeIntoContent(
            existing: existing,
            injectionFrontmatter: injectionContent.frontmatter
        )
    }

    private static func resolvedOutputKey(
        originalKey: String,
        fmConfig: FrontmatterConfiguration
    ) -> String {
        if let field = fmConfig.fields.first(where: { $0.originalKey == originalKey }) {
            let key = field.customKey.trimmingCharacters(in: .whitespaces)
            return key.isEmpty ? originalKey : key
        }
        return originalKey
    }

    private static func mergeIntoContent(existing: String, injectionFrontmatter: String) -> String {
        let lines = existing.components(separatedBy: "\n")
        var existingFrontmatter = ""
        var bodyStartIndex = 0

        if let first = lines.first,
           first.trimmingCharacters(in: .whitespaces) == "---" {
            for i in 1..<lines.count {
                if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                    existingFrontmatter = lines[0...i].joined(separator: "\n") + "\n"
                    bodyStartIndex = i + 1
                    break
                }
            }
        }

        if existingFrontmatter.isEmpty {
            if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return injectionFrontmatter
            }
            return injectionFrontmatter + "\n" + existing
        }

        let mergedFrontmatter = MarkdownMerger.mergeFrontmatter(
            existing: existingFrontmatter,
            new: injectionFrontmatter
        )

        let body = lines[bodyStartIndex...].joined(separator: "\n")
        if body.hasPrefix("\n") || body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return mergedFrontmatter + body
        }
        return mergedFrontmatter + "\n" + body
    }
}

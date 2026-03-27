//
//  DailyNoteInjector.swift
//  Health.md
//
//  Injects health metrics into the YAML frontmatter of an existing daily note
//  without touching the rest of the file's content.
//  Which metrics are injected is driven entirely by MetricSelectionState —
//  no separate field selection needed.
//

import Foundation

// MARK: - Daily Note Injector

struct DailyNoteInjector {

    // MARK: - Injection Result

    enum InjectionResult {
        case updated(path: String)
        case skipped(reason: String)
        case failed(Error)
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

        // 1. Resolve target file URL
        var targetURL = vaultURL
        let folder = settings.folderPath.trimmingCharacters(in: .whitespaces)
        if !folder.isEmpty {
            targetURL = targetURL.appendingPathComponent(folder, isDirectory: true)
        }
        let filename = settings.formatFilename(for: healthData.date) + ".md"
        targetURL = targetURL.appendingPathComponent(filename)

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
                return .skipped(reason: "Daily note not found: \(filename)")
            }
        }

        // 3. Read existing content
        let existingContent: String
        do {
            existingContent = try String(contentsOf: targetURL, encoding: .utf8)
        } catch {
            return .failed(error)
        }

        // 4. Build the set of frontmatter keys to inject based on enabled metrics
        let allMetrics = healthData.allMetricsDictionary(using: customization.unitConverter, timeFormat: customization.timeFormat)
        let fmConfig = customization.frontmatterConfig
        let allowedKeys = frontmatterKeys(enabledIn: metricSelection)

        var injectionLines: [String] = ["---"]
        // Preserve order: iterate over allowedKeys in a stable sequence
        for originalKey in allowedKeys {
            guard let value = allMetrics[originalKey] else { continue }
            let outputKey = resolvedOutputKey(originalKey: originalKey, fmConfig: fmConfig)
            injectionLines.append("\(outputKey): \(value)")
        }

        guard injectionLines.count > 1 else {
            return .skipped(reason: "No data available for enabled metrics on this date")
        }
        injectionLines.append("---")
        let injectionFrontmatter = injectionLines.joined(separator: "\n") + "\n"

        // 5. Merge into existing content (body preserved)
        let updatedContent = mergeIntoContent(
            existing: existingContent,
            injectionFrontmatter: injectionFrontmatter
        )

        // 6. Write back
        do {
            try updatedContent.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            return .failed(error)
        }

        return .updated(path: settings.previewPath(for: healthData.date))
    }

    // MARK: - Private helpers

    /// Returns the ordered set of frontmatter originalKeys that correspond to
    /// metrics enabled in the given MetricSelectionState.
    static func frontmatterKeys(enabledIn metricSelection: MetricSelectionState) -> [String] {
        HealthMetricExportMapping.frontmatterKeys(enabledIn: metricSelection)
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

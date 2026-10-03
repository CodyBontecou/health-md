import Foundation
import HealthMdCoreRust

// Cross-version Shared Setup support types. These survived the v1 contract
// removal because v2 and the settings store still depend on them: the
// metric-equivalence classification the pinned registry projects, the
// internal portable settings envelope AdvancedExportSettings persists, and
// the shared presentation-placeholder grammar. They are internal support
// types, not part of any public setup contract — every public wire type
// lives in SharedSetupV2.swift.

/// Metric-equivalence classification the pinned cross-platform metric
/// registry projects. `SharedSetupV2.Equivalence` carries the same three
/// wire values in the v2 document; the registry keeps this internal twin and
/// the v2 mapper converts between them.
enum SharedSetupEquivalence: String, Codable, Sendable {
    case platformExactOrUnavailable = "platform_exact_or_unavailable"
    case mappedAlias = "mapped_alias"
    case platformDistinct = "platform_distinct"
}

enum SharedSetupCompatibilityStatus: String, Codable, Sendable { case applied; case requiresAction = "requires_action"; case unsupported; case invalid }

/// Errors surfaced by the internal portable settings envelope and its
/// validators inside AdvancedExportSettings.
enum SharedSetupError: LocalizedError, Equatable {
    case oversized
    case invalid(String)
    case persistenceVerificationFailed

    var errorDescription: String? {
        switch self {
        case .oversized: "This setup file is larger than 256 KB."
        case .invalid(let reason): reason
        case .persistenceVerificationFailed: "Health.md could not verify the imported setup and restored the previous setup."
        }
    }
}

/// Internal path and filename safety validators for the portable settings
/// envelope AdvancedExportSettings persists in UserDefaults.
enum SharedSetupValidation {
    static func validateRelativePath(_ path: String) throws {
        guard path.count <= 4096, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("%"), !path.contains("//"), !path.contains("://"), !path.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }),
              path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ $0 != "." && $0 != ".." }),
              path.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else { throw SharedSetupError.invalid("A setup path is unsafe.") }
    }

    static func validateFilename(_ value: String) throws {
        guard !value.isEmpty, value != ".", value != "..", value.count <= 4096, !value.contains("/"), !value.contains("\\"), !value.contains("%"), !value.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 32 } == true }), value.range(of: #"^[A-Za-z]:"#, options: .regularExpression) == nil else { throw SharedSetupError.invalid("A filename template is unsafe.") }
    }
}

enum SharedSetupPlaceholderValidator {
    private static let replacements: Set<String> = ["date", "metrics", "sleep_metrics", "activity_metrics", "heart_metrics", "vitals_metrics", "body_metrics", "nutrition_metrics", "mobility_metrics", "mindfulness_metrics", "workout_list"]
    private static let sections: Set<String> = ["sleep", "activity", "heart", "vitals", "body", "nutrition", "mobility", "mindfulness", "workouts"]
    private static let tokenRegex = try! NSRegularExpression(pattern: #"\{\{([#/]?)([A-Za-z0-9_]+)\}\}"#)

    static func isSyntacticallyValid(_ text: String) -> Bool {
        let matches = tokenRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var stack: [String] = []
        for match in matches {
            guard let prefixRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text) else { return false }
            let prefix = String(text[prefixRange])
            let name = String(text[nameRange])
            if prefix == "#" {
                guard stack.isEmpty else { return false }
                stack.append(name)
            } else if prefix == "/" {
                guard stack.last == name else { return false }
                stack.removeLast()
            }
        }
        let stripped = tokenRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return stack.isEmpty && !stripped.contains("{{") && !stripped.contains("}}")
    }

    static func isCompatible(_ text: String) -> Bool {
        guard isSyntacticallyValid(text) else { return false }
        let matches = tokenRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.allSatisfy { match in
            guard let prefixRange = Range(match.range(at: 1), in: text),
                  let nameRange = Range(match.range(at: 2), in: text) else { return false }
            let prefix = String(text[prefixRange])
            let name = String(text[nameRange])
            return prefix.isEmpty ? replacements.contains(name) : sections.contains(name)
        }
    }
}

struct SharedSetupMetricRegistry {
    let version: Int
    let sha256: String
    let semanticToApple: [String: String]
    let semanticToAndroid: [String: String]
    let equivalence: [String: SharedSetupEquivalence]

    static func current(service: HealthMdCoreService = HealthMdCoreService()) throws -> SharedSetupMetricRegistry {
        let apple = try service.metricRegistry(profile: .appleHealthDataV8)
        let android = try service.metricRegistry(profile: .androidAnalyticalV5)
        guard apple.registryVersion == 1,
              apple.registryVersion == android.registryVersion,
              apple.registrySha256 == android.registrySha256 else {
            throw SharedSetupError.invalid("The bundled Apple and Android metric projections do not share one pinned registry identity.")
        }
        let androidMap = Dictionary(uniqueKeysWithValues: android.metrics.map { ($0.semanticId, $0.selectionId) })
        var equivalence: [String: SharedSetupEquivalence] = [:]
        var semanticToAndroid: [String: String] = [:]
        var semanticToApple: [String: String] = [:]
        for metric in apple.metrics {
            semanticToApple[metric.semanticId] = metric.selectionId
            if let mapped = androidMap[metric.semanticId] { semanticToAndroid[metric.semanticId] = mapped }
            let a = metric.selectionId
            let b = semanticToAndroid[metric.semanticId]
            equivalence[metric.semanticId] = b == nil || a == b ? .platformExactOrUnavailable : .mappedAlias
        }
        for metric in android.metrics where semanticToApple[metric.semanticId] == nil {
            semanticToAndroid[metric.semanticId] = metric.selectionId
            equivalence[metric.semanticId] = metric.semanticId.hasPrefix("android.") ? .platformDistinct : .platformExactOrUnavailable
        }
        return SharedSetupMetricRegistry(version: Int(apple.registryVersion), sha256: apple.registrySha256, semanticToApple: semanticToApple, semanticToAndroid: semanticToAndroid, equivalence: equivalence)
    }
}

struct SharedSetupPortableSnapshot: Codable, Equatable {
    /// Settings-store bound for the internal portable-snapshot envelope
    /// AdvancedExportSettings persists in UserDefaults. This is a local
    /// persistence bound, not a Shared Setup contract limit.
    static let maximumPersistedEncodedBytes = 262_144

    var exportFormats: Set<ExportFormat>
    var includeMetadata: Bool
    var groupByCategory: Bool
    var filenameFormat: String
    var folderStructure: String
    var organizeFormatsIntoFolders: Bool
    var archiveExportFiles: Bool
    var includeDataDictionary: Bool
    var summaryOnlyExport: Bool
    var writeMode: WriteMode
    var includeGranularData: Bool
    var compatibilityDetail: ExportCompatibilityDetail? = nil
    var healthKitSourceArchivePolicy: HealthKitSourceArchivePolicy? = nil
    var generateWeeklyRollups: Bool
    var generateMonthlyRollups: Bool
    var generateYearlyRollups: Bool
    var metricSelectionIDs: Set<String>
    var dateFormat: DateFormatPreference
    var timeFormat: TimeFormatPreference
    var unitPreference: UnitPreference
    var frontmatter: FrontmatterConfigurationSnapshot
    var frontmatterPreservesExactFieldSet: Bool
    var markdownTemplate: MarkdownTemplateConfig
    var individualTracking: IndividualTrackingSnapshot
    var dailyNotes: DailyNoteInjectionSnapshot

    var detailPolicy: AppleExportDetailPolicy {
        if let compatibilityDetail, let healthKitSourceArchivePolicy {
            return AppleExportDetailPolicy(
                compatibilityDetail: compatibilityDetail,
                healthKitSourceArchive: healthKitSourceArchivePolicy
            )
        }
        return includeGranularData ? .lossless : .summary
    }

    static func capture(_ settings: AdvancedExportSettings) -> SharedSetupPortableSnapshot {
        SharedSetupPortableSnapshot(exportFormats: settings.exportFormats, includeMetadata: settings.includeMetadata, groupByCategory: settings.groupByCategory, filenameFormat: settings.filenameFormat, folderStructure: settings.folderStructure, organizeFormatsIntoFolders: settings.organizeFormatsIntoFolders, archiveExportFiles: settings.archiveExportFiles, includeDataDictionary: settings.includeDataDictionary, summaryOnlyExport: settings.summaryOnlyExport, writeMode: settings.writeMode, includeGranularData: settings.detailPolicy.legacyIncludeGranularData, compatibilityDetail: settings.compatibilityDetail, healthKitSourceArchivePolicy: settings.healthKitSourceArchivePolicy, generateWeeklyRollups: settings.generateWeeklyRollups, generateMonthlyRollups: settings.generateMonthlyRollups, generateYearlyRollups: settings.generateYearlyRollups, metricSelectionIDs: settings.metricSelection.enabledMetrics, dateFormat: settings.formatCustomization.dateFormat, timeFormat: settings.formatCustomization.timeFormat, unitPreference: settings.formatCustomization.unitPreference, frontmatter: .from(settings.formatCustomization.frontmatterConfig), frontmatterPreservesExactFieldSet: settings.formatCustomization.frontmatterConfig.preservesExactFieldSet, markdownTemplate: settings.formatCustomization.markdownTemplate, individualTracking: .from(settings.individualTracking), dailyNotes: .from(settings.dailyNoteInjection))
    }
}

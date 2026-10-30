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
import HealthMdCoreRust

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

    fileprivate struct InjectionContent {
        let frontmatter: String
        let body: String
        let isWakeDateCapture: Bool
        let nightCaptureJSON: (() throws -> String)?

        init(frontmatter: String, body: String, isWakeDateCapture: Bool = false,
             nightCaptureJSON: (() throws -> String)? = nil) {
            self.frontmatter = frontmatter
            self.body = body
            self.isWakeDateCapture = isWakeDateCapture
            self.nightCaptureJSON = nightCaptureJSON
        }
    }

    /// A projection of an accepted successor plan, never a relabelling of the
    /// user's whole note. Construction requires the native renderer's authority.
    nonisolated struct PreparedContent: Equatable, Sendable {
        let ownerDate: Date
        let relativePath: String
        let identity: AppleExportOperationIdentity
        let pin: AppleExportEnginePin
        fileprivate let context: ExportTimeContext
        fileprivate let settings: DailyNoteInjectionSnapshot
        fileprivate let frontmatter: String
        fileprivate let body: String
    }

    private static func preparedContent(_ prepared: PreparedContent) -> InjectionContent {
        InjectionContent(frontmatter: prepared.frontmatter, body: prepared.body, isWakeDateCapture: true)
    }

    static func mergePrepared(_ prepared: PreparedContent, existing: String) throws -> String {
        let settings = DailyNoteInjectionSettings()
        prepared.settings.apply(to: settings)
        return try mergedContent(existing: existing, injectionContent: preparedContent(prepared), settings: settings)
    }

    static func createsMissingNote(_ prepared: PreparedContent) -> Bool { prepared.settings.createIfMissing }

    @discardableResult
    static func injectPrepared(_ prepared: PreparedContent, into vaultURL: URL,
        fileSystem: FileSystemAccessing = SystemFileSystem(),
        fileCoordinator: FileCoordinating = PassthroughFileCoordinator(),
        destinationBinding: AppleVaultDestinationBinding? = nil,
        beforeCommit: (@Sendable () throws -> Void)? = nil,
        afterValidationBeforeRename: (@Sendable () throws -> Void)? = nil
    ) -> InjectionResult {
        guard let zone = TimeZone(identifier: prepared.context.calendarTimeZoneIdentifier) else {
            return .failed(AppleLooseDailyExportPlannerError.rustPlanningFailed)
        }
        let settings = DailyNoteInjectionSettings()
        prepared.settings.apply(to: settings)
        return commitContent(preparedContent(prepared), date: prepared.ownerDate, into: vaultURL,
            settings: settings, calendarTimeZone: zone, fileSystem: fileSystem, fileCoordinator: fileCoordinator,
            destinationBinding: destinationBinding, beforeCommit: beforeCommit,
            afterValidationBeforeRename: afterValidationBeforeRename)
    }

    private static let captureKey = "healthmd_daily_injection_v1"
    private static let captureKindKey = "healthmd_injection_kind"

    static func prepareWakeDateContent(
        healthData: HealthData,
        operation: AppleLooseDailyPlannedOperation,
        settingsSnapshot: ExportSettingsSnapshot
    ) throws -> PreparedContent {
        let context = try settingsSnapshot.validatedSleepCaptureContext()
        guard context.sleepDayAttribution == .morningEnds,
              healthData.timeContext.sleepDayAttribution == .morningEnds,
              healthData.timeContext.calendarTimeZoneIdentifier == context.calendarTimeZoneIdentifier,
              operation.authority == .rust, operation.pin == settingsSnapshot.appleExportEnginePin,
              operation.pin.hasExplicitWakeDateContracts else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        func text(_ format: ExportFormat) throws -> String {
            let artifacts = operation.artifacts.filter { $0.kind == .daily && $0.format == format }
            guard artifacts.count == 1 else { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
            let data: Data
            switch artifacts[0].artifact.content {
            case .inline(let bytes): data = bytes
            case .file(let file):
                try file.validateIntegrity()
                data = try Data(contentsOf: file.url)
            }
            guard let result = String(data: data, encoding: .utf8) else { throw ExportError.markdownMergeRejected }
            return result
        }
        let json = try text(.json)
        guard let record = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              record["type"] as? String == "health-data",
              record["schema_profile"] as? String == "apple-v11",
              record["healthkit_record_archive"] == nil,
              record["schema_version"] as? Int == 11,
              let clock = record["time_context"] as? [String: String],
              clock == ["calendar_timezone": context.calendarTimeZoneIdentifier, "timestamp_timezone": "UTC",
                "sleep_day_attribution": "morning_ends", "sleep_owner_day_rule": "session_end_date",
                "sleep_interval_clipping": "none"],
              record["date"] as? String == HealthKitDailyOwnershipMetadata.ownerDate(
                for: healthData.date, calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier) else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        let settings = settingsSnapshot.makeAdvancedExportSettings()
        let keys = frontmatterKeys(enabledIn: settings.metricSelection).map {
            resolvedOutputKey(originalKey: $0, fmConfig: settings.formatCustomization.frontmatterConfig)
        }
        guard !keys.contains(captureKey), !keys.contains(captureKindKey), Set(keys).count == keys.count else {
            throw ExportError.markdownMergeRejected
        }
        let patch = try HealthMdCoreService().prepareScopedNote(profile: .appleHealthDataV11,
            recordJSON: json, bases: text(.obsidianBases), markdown: text(.markdown),
            selectedProperties: keys, injectSections: settings.dailyNoteInjection.injectMarkdownSections)
        guard let parts = MarkdownMerger.splitFrontmatter(from: patch) else { throw ExportError.markdownMergeRejected }
        let path = ExportPathPlanner.dailyNoteRelativePath(settings: settings.dailyNoteInjection,
            date: healthData.date, timeZone: context.timeZone)
        _ = try ExportPathPlanner.canonicalPortablePathKey(path)
        return PreparedContent(ownerDate: healthData.date, relativePath: path, identity: operation.identity, pin: operation.pin,
            context: healthData.timeContext, settings: settingsSnapshot.dailyNoteInjection,
            frontmatter: parts.frontmatter, body: parts.body)
    }

    private static func scopedCaptureProperties(json: String) throws -> String {
        let envelope = try JSONSerialization.data(withJSONObject: [
            "kind": "healthmd_daily_capture", "version": 1, "record_json": json
        ], options: [.sortedKeys, .withoutEscapingSlashes])
        let quoted = try JSONEncoder().encode(String(decoding: envelope, as: UTF8.self))
        return "\(captureKindKey): daily_capture_v1\n\(captureKey): "
            + String(decoding: quoted, as: UTF8.self) + "\n"
    }

    private static func resolvedContent(
        healthData: HealthData, settings: DailyNoteInjectionSettings,
        customization: FormatCustomization, metricSelection: MetricSelectionState,
        prepared: PreparedContent?
    ) throws -> InjectionContent? {
        if healthData.timeContext.sleepDayAttribution == .morningEnds {
            guard let prepared, prepared.ownerDate == healthData.date,
                  prepared.context == healthData.timeContext,
                  prepared.settings == .from(settings) else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            return preparedContent(prepared)
        }
        guard prepared == nil else { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
        return buildInjectionContent(healthData: healthData, settings: settings,
            customization: customization, metricSelection: metricSelection)
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
        metricSelection: MetricSelectionState,
        calendarTimeZone: TimeZone = .current,
        preparedContent: PreparedContent? = nil,
        fileSystem: FileSystemAccessing = SystemFileSystem(),
        fileCoordinator: FileCoordinating = PassthroughFileCoordinator(),
        destinationBinding: AppleVaultDestinationBinding? = nil,
        beforeCommit: (@Sendable () throws -> Void)? = nil,
        afterValidationBeforeRename: (@Sendable () throws -> Void)? = nil
    ) -> InjectionResult {
        guard settings.enabled else { return .skipped(reason: "Injection disabled") }

        let injectionContent: InjectionContent
        do {
            guard let content = try resolvedContent(healthData: healthData, settings: settings,
                customization: customization, metricSelection: metricSelection, prepared: preparedContent) else {
                return .skipped(reason: "No data available for enabled metrics on this date")
            }
            guard preparedContent == nil || calendarTimeZone.identifier == healthData.timeContext.calendarTimeZoneIdentifier else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            injectionContent = content
        } catch { return .failed(error) }

        return commitContent(injectionContent, date: healthData.date, into: vaultURL,
            settings: settings, calendarTimeZone: calendarTimeZone, fileSystem: fileSystem,
            fileCoordinator: fileCoordinator, destinationBinding: destinationBinding,
            beforeCommit: beforeCommit, afterValidationBeforeRename: afterValidationBeforeRename)
    }

    private static func commitContent(_ injectionContent: InjectionContent, date: Date, into vaultURL: URL,
        settings: DailyNoteInjectionSettings, calendarTimeZone: TimeZone, fileSystem: FileSystemAccessing,
        fileCoordinator: FileCoordinating, destinationBinding: AppleVaultDestinationBinding?,
        beforeCommit: (@Sendable () throws -> Void)?, afterValidationBeforeRename: (@Sendable () throws -> Void)?
    ) -> InjectionResult {
        let targetURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings,
            date: date,
            timeZone: calendarTimeZone
        )
        let relativePath = ExportPathPlanner.dailyNoteRelativePath(
            settings: settings,
            date: date,
            timeZone: calendarTimeZone
        )

        do {
            return try fileCoordinator.coordinateWriting(
                at: targetURL,
                intent: .replace,
                cancellationCheck: { try Task.checkCancellation() }
            ) { coordinatedURL in
                if fileSystem is SystemFileSystem, let destinationBinding {
                    let coordinatedRootURL = try SecureExactArtifactIO.coordinatedRootURL(
                        for: coordinatedURL,
                        rootURL: vaultURL,
                        relativePath: relativePath,
                        binding: destinationBinding
                    )
                    let existingData = try SecureExactArtifactIO.read(
                        rootURL: coordinatedRootURL,
                        relativePath: relativePath,
                        binding: destinationBinding,
                        maximumByteCount: 8 * 1024 * 1024
                    )
                    guard existingData != nil || settings.createIfMissing else {
                        return .skipped(reason: "Daily note not found: \(relativePath)")
                    }
                    let existingContent: String
                    if let existingData {
                        guard let content = String(data: existingData, encoding: .utf8) else {
                            throw CocoaError(.fileReadInapplicableStringEncoding)
                        }
                        existingContent = content
                    } else {
                        existingContent = ""
                    }
                    let updatedContent = try mergedContent(
                        existing: existingContent,
                        injectionContent: injectionContent,
                        settings: settings
                    )
                    try SecureExactArtifactIO.overwrite(
                        rootURL: coordinatedRootURL,
                        relativePath: relativePath,
                        data: Data(updatedContent.utf8),
                        binding: destinationBinding,
                        beforeCommit: beforeCommit,
                        afterValidationBeforeRename: afterValidationBeforeRename
                    )
                    return .updated(path: relativePath)
                }

                if !fileSystem.fileExists(atPath: coordinatedURL.path) {
                    guard settings.createIfMissing else {
                        return .skipped(reason: "Daily note not found: \(relativePath)")
                    }
                    let parent = coordinatedURL.deletingLastPathComponent()
                    try fileSystem.createDirectory(
                        at: parent,
                        withIntermediateDirectories: true
                    )
                    try fileSystem.writeString("", to: coordinatedURL, atomically: true)
                }

                let existingContent = try fileSystem.contentsOfFile(at: coordinatedURL)

                let updatedContent = try mergedContent(
                    existing: existingContent,
                    injectionContent: injectionContent,
                    settings: settings
                )
                try fileSystem.writeString(updatedContent, to: coordinatedURL, atomically: true)
                return .updated(path: relativePath)
            }
        } catch FileCoordinationError.destinationChanged {
            return .failed(ExportError.destinationChanged)
        } catch AppleExactDestinationError.destinationRebound {
            return .failed(ExportError.destinationChanged)
        } catch {
            return .failed(error)
        }
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
        metricSelection: MetricSelectionState,
        calendarTimeZone: TimeZone = .current,
        preparedContent: PreparedContent? = nil
    ) -> InjectionPreviewResult {
        guard settings.enabled else { return .skipped(reason: "Injection disabled") }

        guard preparedContent == nil || calendarTimeZone.identifier == healthData.timeContext.calendarTimeZoneIdentifier,
            let injectionContent = try? resolvedContent(
            healthData: healthData,
            settings: settings,
            customization: customization,
            metricSelection: metricSelection,
            prepared: preparedContent
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

        let content: String
        do {
            content = try mergedContent(
                existing: existingContent,
                injectionContent: injectionContent,
                settings: settings
            )
        } catch {
            return .skipped(reason: error.localizedDescription)
        }
        let filename = settings.formatFilename(
            for: healthData.date,
            timeZone: calendarTimeZone
        ) + ".md"

        return .preview(InjectionPreview(
            filename: filename,
            path: ExportPathPlanner.dailyNoteRelativePath(
                settings: settings,
                date: healthData.date,
                timeZone: calendarTimeZone
            ),
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
            appendFrontmatterField(key: outputKey, value: value, to: &injectionLines)
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
        // Freeze the possible successor-to-historical transition before a file
        // coordinator can invoke callbacks. Ordinary historical notes do not
        // render this extra record or acquire a new annotation.
        let source = ConnectedExportDetailPolicy.sanitized(healthData.filtered(by: metricSelection),
            detailPolicy: settings.injectMarkdownSections ? .detailedTimeSeries : .summary)
        let format = FormatCustomizationSnapshot.from(customization)
        return InjectionContent(frontmatter: injectionFrontmatter, body: injectionBody, nightCaptureJSON: {
            let config = FormatCustomization()
            format.apply(to: config)
            guard let zone = TimeZone(identifier: source.timeContext.calendarTimeZoneIdentifier) else {
                throw AppleWakeDateJSONError.incompatibleCaptureAuthority
            }
            let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
            return try source.toJSONThrowing(customization: config, captureContext: context)
        })
    }

    private static func mergedContent(
        existing: String,
        injectionContent: InjectionContent,
        settings: DailyNoteInjectionSettings
    ) throws -> String {
        var injectionContent = injectionContent
        var scopedProfile: CoreMetricRegistryProfile? = injectionContent.isWakeDateCapture ? .appleHealthDataV11 : nil
        if !injectionContent.isWakeDateCapture,
           let properties = MarkdownMerger.frontmatterProperties(named: [captureKey, captureKindKey], in: existing),
           !properties.isEmpty {
            // The personal note can retain unselected Morning properties and
            // sections. Keep the new Night capture scoped too, so none of those
            // retained values are adopted by a generic legacy-note parser.
            guard let makeRecord = injectionContent.nightCaptureJSON else { throw ExportError.markdownMergeRejected }
            let annotation = "---\n" + (try scopedCaptureProperties(json: makeRecord())) + "---\n"
            switch MarkdownMerger.mergeFrontmatterOutcome(existing: injectionContent.frontmatter, new: annotation) {
            case .merged(let frontmatter):
                injectionContent = InjectionContent(frontmatter: frontmatter, body: injectionContent.body)
            case .rejected: throw ExportError.markdownMergeRejected
            }
            scopedProfile = .appleHealthDataV8
        }
        if let scopedProfile {
            return try HealthMdCoreService().mergeScopedNote(profile: scopedProfile, existing: existing,
                patch: injectionContent.frontmatter + injectionContent.body,
                injectSections: settings.injectMarkdownSections)
        }
        if settings.injectMarkdownSections {
            switch MarkdownMerger.mergePreservingPreambleOutcome(
                existing: existing,
                new: injectionContent.frontmatter + injectionContent.body
            ) {
            case .merged(let content):
                return content
            case .rejected:
                throw ExportError.markdownMergeRejected
            }
        }

        return try mergeIntoContent(
            existing: existing,
            injectionFrontmatter: injectionContent.frontmatter
        )
    }

    private static func appendFrontmatterField(key: String, value: String, to lines: inout [String]) {
        if value.contains("\n") {
            lines.append("\(key):")
            lines.append(contentsOf: value.components(separatedBy: "\n"))
        } else {
            lines.append("\(key): \(value)")
        }
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

    private static func mergeIntoContent(
        existing: String,
        injectionFrontmatter: String
    ) throws -> String {
        guard let parts = MarkdownMerger.splitFrontmatter(from: existing) else {
            if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return injectionFrontmatter
            }
            return injectionFrontmatter + "\n" + existing
        }

        switch MarkdownMerger.mergeFrontmatterOutcome(
            existing: parts.frontmatter,
            new: injectionFrontmatter
        ) {
        case .merged(let frontmatter):
            return frontmatter + parts.body
        case .rejected:
            throw ExportError.markdownMergeRejected
        }
    }
}

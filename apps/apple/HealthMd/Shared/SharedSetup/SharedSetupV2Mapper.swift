import Foundation

/// Immutable values copied from ProfileDestinationStore for one pure mapping
/// operation. Vault rows are accepted so the mapper can prove they are never
/// projected: bookmark bytes, paths, display names, and identities are absent
/// from every SharedSetupV2 destination DTO.
struct SharedSetupV2DestinationSnapshots {
    var vaults: [SavedVaultDestination]
    var apiEndpoints: [SavedAPIEndpoint]

    init(
        vaults: [SavedVaultDestination] = [],
        apiEndpoints: [SavedAPIEndpoint] = []
    ) {
        self.vaults = vaults
        self.apiEndpoints = apiEndpoints
    }
}

struct SharedSetupV2CompatibilityItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var detail: String
    var status: SharedSetupCompatibilityStatus
}

struct SharedSetupV2SupportedIndividualMetric: Equatable, Sendable {
    var semanticID: String
    var nativeSelectionID: String
    var configuration: SharedSetupV2.IndividualMetric
}

/// A write-free, per-profile cycle-2 input. Unsupported meanings remain in
/// `document`; this plan only identifies what the current Apple build can apply
/// exactly after a later transaction has been confirmed.
struct SharedSetupV2ProfileImportPlan: Identifiable, Equatable, Sendable {
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var items: [SharedSetupV2CompatibilityItem]
    var supportedMetricSelectionIDs: [String]
    var supportedIndividualMetrics: [SharedSetupV2SupportedIndividualMetric]
    var unsupportedPreservedSemanticIDs: [String]
    var installCustomTemplate: Bool
    var destinationIntent: SharedSetupV2.Destination
    var destinationKindIsSupported: Bool
    var scheduleIntent: SharedSetupV2.Schedule?
    var scheduleCanApplyExactly: Bool
    var preservedAndroidExtension: SharedSetupV2.AndroidExtension?

    /// Cycle-2 transactions must materialize schedule configuration with the
    /// native enabled bit off regardless of sender activation intent.
    var importsScheduleEnabled: Bool { false }
    /// Destination DTOs are reviewable intent only; none is a local binding.
    var destinationIsLocallyBound: Bool { false }

    var hasInvalidItems: Bool {
        items.contains { $0.status == .invalid }
    }
}

struct SharedSetupV2ImportPlan: Equatable, Sendable {
    var document: SharedSetupV2
    var items: [SharedSetupV2CompatibilityItem]
    var profiles: [SharedSetupV2ProfileImportPlan]
    var activeBundleID: String
    /// Ordered exactly like the document, never a Set. Cycle 2 can change the
    /// selection explicitly without acquiring dictionary/hash iteration order.
    var defaultSelectedBundleIDs: [String]

    var hasInvalidItems: Bool {
        items.contains { $0.status == .invalid } || profiles.contains(where: \.hasInvalidItems)
    }
}

enum SharedSetupV2Mapper {
    /// Maps every native profile in profile-store order. This function performs
    /// no persistence, service calls, URL requests, or destination access.
    static func exportDocument(
        profiles: [ExportProfile],
        activeProfileID: UUID?,
        destinations: SharedSetupV2DestinationSnapshots,
        scheduledEntries: [ScheduledExportEntry],
        registry: SharedSetupMetricRegistry,
        appVersion: String,
        preservedAndroidExtensions: [UUID: SharedSetupV2.AndroidExtension] = [:],
        calendar: Calendar
    ) throws -> SharedSetupV2 {
        guard !profiles.isEmpty, profiles.count <= SharedSetupV2.maximumProfiles else {
            throw SharedSetupV2Error.invalid("A Shared Setup v2 bundle must contain 1 to 100 profiles.")
        }
        guard Set(profiles.map(\.id)).count == profiles.count else {
            throw SharedSetupV2Error.invalid("Native profile IDs are not unique.")
        }
        guard let activeProfileID,
              let activeIndex = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            throw SharedSetupV2Error.invalid("The active native profile is missing from the exported profile order.")
        }

        try validateDestinationSnapshotIdentity(destinations)
        let endpointByID = Dictionary(uniqueKeysWithValues: destinations.apiEndpoints.map { ($0.id, $0) })
        let profileIDs = Set(profiles.map(\.id))
        guard scheduledEntries.allSatisfy({ profileIDs.contains($0.profileID) }),
              Set(scheduledEntries.map(\.profileID)).count == scheduledEntries.count else {
            throw SharedSetupV2Error.invalid(
                "Scheduled entries must reference exported profiles exactly once."
            )
        }
        guard Set(preservedAndroidExtensions.keys).isSubset(of: profileIDs) else {
            throw SharedSetupV2Error.invalid(
                "A preserved Android extension references a profile outside this bundle."
            )
        }
        let scheduleByProfile = Dictionary(
            uniqueKeysWithValues: scheduledEntries.map { ($0.profileID, $0) }
        )

        let reverseApple = try reverseAppleRegistry(registry)
        var semanticUnion = Set<String>()
        var mappedProfiles: [SharedSetupV2.Profile] = []
        mappedProfiles.reserveCapacity(profiles.count)

        for (offset, nativeProfile) in profiles.enumerated() {
            let enabledSemanticIDs = try semanticIDs(
                for: nativeProfile.settings.metricSelection.enabledMetricIDs,
                reverseApple: reverseApple,
                context: "metric selection"
            )
            let individualSemantic = try individualEntries(
                nativeProfile.settings.individualTracking,
                reverseApple: reverseApple
            )
            semanticUnion.formUnion(enabledSemanticIDs)
            semanticUnion.formUnion(individualSemantic.keys)

            let scheduledEntry = scheduleByProfile[nativeProfile.id]
            let schedule = try scheduledEntry.map {
                try scheduleIntent(from: $0, calendar: calendar)
            }
            let bundleID = String(format: "profile-%03d", offset + 1)
            mappedProfiles.append(
                try profileDTO(
                    bundleID: bundleID,
                    nativeProfile: nativeProfile,
                    enabledSemanticIDs: enabledSemanticIDs,
                    individualSemantic: individualSemantic,
                    endpoint: nativeProfile.apiEndpointID.flatMap { endpointByID[$0] },
                    scheduledEntry: scheduledEntry,
                    schedule: schedule,
                    preservedAndroidExtension: preservedAndroidExtensions[nativeProfile.id]
                )
            )
        }

        let aliases = try semanticUnion.sorted().map { semanticID in
            guard let appleSelectionID = registry.semanticToApple[semanticID],
                  let equivalence = registry.equivalence[semanticID] else {
                throw SharedSetupV2Error.invalid(
                    "The metric registry cannot prove the Apple meaning for \(semanticID)."
                )
            }
            return SharedSetupV2.MetricAlias(
                semanticID: semanticID,
                equivalence: sharedEquivalence(equivalence),
                appleSelectionID: appleSelectionID,
                androidSelectionID: registry.semanticToAndroid[semanticID]
            )
        }

        let document = SharedSetupV2(
            schema: SharedSetupV2.schemaName,
            schemaVersion: SharedSetupV2.schemaVersion,
            createdBy: .init(platform: .apple, appVersion: appVersion),
            metricRegistry: .init(
                schema: "healthmd.metric_registry",
                registryVersion: registry.version,
                registrySHA256: registry.sha256
            ),
            profiles: mappedProfiles,
            activeProfile: String(format: "profile-%03d", activeIndex + 1),
            metricAliases: aliases
        )
        try SharedSetupV2Validation.validate(document)
        return document
    }

    /// Produces a deterministic all-profile compatibility plan and performs no
    /// writes. Exact local registry mappings are the only source of native IDs;
    /// labels and foreign selection IDs are never used as substitutes.
    static func preview(
        _ document: SharedSetupV2,
        registry: SharedSetupMetricRegistry
    ) -> SharedSetupV2ImportPlan {
        do {
            try SharedSetupV2Validation.validate(document)
        } catch {
            let item = SharedSetupV2CompatibilityItem(
                id: "document",
                title: "Shared Setup",
                detail: error.localizedDescription,
                status: .invalid
            )
            return SharedSetupV2ImportPlan(
                document: document,
                items: [item],
                profiles: [],
                activeBundleID: document.activeProfile,
                defaultSelectedBundleIDs: []
            )
        }

        let sourceRegistryMatches = document.metricRegistry.registryVersion == registry.version &&
            document.metricRegistry.registrySHA256 == registry.sha256
        let ledger = Dictionary(
            uniqueKeysWithValues: document.metricAliases.map { ($0.semanticID, $0) }
        )
        var plans: [SharedSetupV2ProfileImportPlan] = []
        plans.reserveCapacity(document.profiles.count)

        for profile in document.profiles {
            let usedMeanings = Set(profile.metrics.enabledIDs)
                .union(profile.individualEntries.metrics.keys)
                .sorted()
            var items: [SharedSetupV2CompatibilityItem] = []
            var unsupported = Set<String>()
            var invalidMeanings = Set<String>()

            for semanticID in usedMeanings {
                guard let alias = ledger[semanticID] else {
                    invalidMeanings.insert(semanticID)
                    items.append(.init(
                        id: "\(profile.bundleID).metric.\(semanticID)",
                        title: semanticID,
                        detail: "The required metric alias evidence is missing.",
                        status: .invalid
                    ))
                    continue
                }
                if sourceRegistryMatches && !aliasMatchesRegistry(
                    alias,
                    semanticID: semanticID,
                    registry: registry
                ) {
                    invalidMeanings.insert(semanticID)
                    items.append(.init(
                        id: "\(profile.bundleID).metric.\(semanticID)",
                        title: semanticID,
                        detail: "The metric alias evidence does not match the pinned registry.",
                        status: .invalid
                    ))
                    continue
                }
                if registry.semanticToApple[semanticID] == nil {
                    unsupported.insert(semanticID)
                    items.append(.init(
                        id: "\(profile.bundleID).metric.\(semanticID)",
                        title: semanticID,
                        detail: "This meaning is unavailable on Apple. It is preserved and will not be approximated.",
                        status: .requiresAction
                    ))
                }
            }

            let supportedMetricIDs = Array(Set(
                profile.metrics.enabledIDs.compactMap { semanticID -> String? in
                    guard !invalidMeanings.contains(semanticID) else { return nil }
                    return registry.semanticToApple[semanticID]
                }
            )).sorted()

            let supportedIndividual = profile.individualEntries.metrics.compactMap {
                semanticID, configuration -> SharedSetupV2SupportedIndividualMetric? in
                guard !invalidMeanings.contains(semanticID),
                      let nativeID = registry.semanticToApple[semanticID] else {
                    return nil
                }
                return SharedSetupV2SupportedIndividualMetric(
                    semanticID: semanticID,
                    nativeSelectionID: nativeID,
                    configuration: configuration
                )
            }.sorted {
                if $0.semanticID != $1.semanticID { return $0.semanticID < $1.semanticID }
                return $0.nativeSelectionID < $1.nativeSelectionID
            }

            items.append(.init(
                id: "\(profile.bundleID).metrics",
                title: "Metrics",
                detail: "\(supportedMetricIDs.count) exact Apple metric selections can be applied; unsupported meanings remain preserved.",
                status: !invalidMeanings.isEmpty
                    ? .invalid
                    : (unsupported.isEmpty ? .applied : .requiresAction)
            ))
            items.append(.init(
                id: "\(profile.bundleID).export",
                title: "Formats and presentation",
                detail: "Portable output, naming, presentation, Daily Notes, and individual-entry intent can be reviewed for this profile.",
                status: .applied
            ))

            let markdown = profile.presentation.markdown
            let installCustomTemplate = markdown.style != .custom ||
                (markdown.originDialect == .apple &&
                    SharedSetupPlaceholderValidator.isSyntacticallyValid(markdown.customText)) ||
                SharedSetupPlaceholderValidator.isCompatible(
                    markdown.customText,
                    dialect: .portable
                )
            if !installCustomTemplate {
                items.append(.init(
                    id: "\(profile.bundleID).template",
                    title: "Custom template",
                    detail: "This template has malformed or unsupported placeholders. Preserve it for review, but do not install it on Apple.",
                    status: .requiresAction
                ))
            } else if markdown.style == .custom ||
                        !profile.presentation.frontmatter.customValues.isEmpty {
                items.append(.init(
                    id: "\(profile.bundleID).custom-content",
                    title: "Custom content",
                    detail: "Custom Markdown and frontmatter values are copied verbatim. Review them for personal, tenant, routing, or secret text.",
                    status: .requiresAction
                ))
            }

            let destinationKindIsSupported = profile.destination.kind != .cloud
            switch profile.destination.kind {
            case .cloud:
                items.append(.init(
                    id: "\(profile.bundleID).destination",
                    title: "Cloud destination",
                    detail: "Cloud intent is preserved but unsupported on Apple and will not be approximated as a folder.",
                    status: .unsupported
                ))
            case .apiEndpoint:
                let endpointDescription = profile.destination.apiEndpoint.map {
                    "\($0.host)\($0.path)"
                } ?? "an unconfigured API endpoint"
                items.append(.init(
                    id: "\(profile.bundleID).destination",
                    title: "API endpoint",
                    detail: "\(endpointDescription) remains inert until locally confirmed with new credentials.",
                    status: .requiresAction
                ))
            case .deviceFolder:
                items.append(.init(
                    id: "\(profile.bundleID).destination",
                    title: "Device folder",
                    detail: "Folder access is not included. A local folder must be selected before this intent can run.",
                    status: .requiresAction
                ))
            case .connectedMac:
                items.append(.init(
                    id: "\(profile.bundleID).destination",
                    title: "Connected Mac",
                    detail: "Pairing is not included. A Mac must be paired and rebound locally before this intent can run.",
                    status: .requiresAction
                ))
            }

            let scheduleCanApplyExactly = profile.schedule.map {
                $0.lookbackDays <= ExportSchedule.maximumLookbackDays
            } ?? true
            if let schedule = profile.schedule {
                let scheduleDetail: String
                if !scheduleCanApplyExactly {
                    scheduleDetail = "This schedule exceeds Apple's exact lookback range. Preserve it for review, but do not clamp or approximate it."
                } else if schedule.activationRequested {
                    scheduleDetail = "Activation was requested, but import must keep this schedule disabled until local review."
                } else {
                    scheduleDetail = "Schedule configuration is preserved as disabled intent."
                }
                items.append(.init(
                    id: "\(profile.bundleID).schedule",
                    title: "Schedule",
                    detail: scheduleDetail,
                    status: .requiresAction
                ))
            }

            if profile.platformExtensions.android != nil {
                items.append(.init(
                    id: "\(profile.bundleID).android-extension",
                    title: "Android-only settings",
                    detail: "The typed Android export extension is preserved but not applied or mapped to Apple approximations.",
                    status: .unsupported
                ))
            }

            plans.append(SharedSetupV2ProfileImportPlan(
                bundleID: profile.bundleID,
                name: profile.name,
                items: items,
                supportedMetricSelectionIDs: supportedMetricIDs,
                supportedIndividualMetrics: supportedIndividual,
                unsupportedPreservedSemanticIDs: unsupported.sorted(),
                installCustomTemplate: installCustomTemplate,
                destinationIntent: profile.destination,
                destinationKindIsSupported: destinationKindIsSupported,
                scheduleIntent: profile.schedule,
                scheduleCanApplyExactly: scheduleCanApplyExactly,
                preservedAndroidExtension: profile.platformExtensions.android
            ))
        }

        let defaultSelection = plans.filter { !$0.hasInvalidItems }.map(\.bundleID)
        let rootItems: [SharedSetupV2CompatibilityItem] = sourceRegistryMatches
            ? []
            : [.init(
                id: "registry",
                title: "Metric registry",
                detail: "The sender used a different bounded registry. Only exact meanings known to this Apple build are selectable; unknown meanings remain preserved.",
                status: .requiresAction
            )]
        return SharedSetupV2ImportPlan(
            document: document,
            items: rootItems,
            profiles: plans,
            activeBundleID: document.activeProfile,
            defaultSelectedBundleIDs: defaultSelection
        )
    }

    private static func profileDTO(
        bundleID: String,
        nativeProfile: ExportProfile,
        enabledSemanticIDs: [String],
        individualSemantic: [String: SharedSetupV2.IndividualMetric],
        endpoint: SavedAPIEndpoint?,
        scheduledEntry: ScheduledExportEntry?,
        schedule: SharedSetupV2.Schedule?,
        preservedAndroidExtension: SharedSetupV2.AndroidExtension?
    ) throws -> SharedSetupV2.Profile {
        let settings = nativeProfile.settings
        let frontmatter = settings.formatCustomization.frontmatterConfig
        let markdown = settings.formatCustomization.markdownTemplate
        // Field and placeholder order is user-authored presentation state, so
        // preserve its stable native order. Set-like arrays (formats, metric
        // IDs, aliases) are sorted separately.
        let frontmatterFields = frontmatter.fields.map {
            SharedSetupV2.FrontmatterField(
                sourceKey: $0.originalKey,
                outputKey: $0.customKey,
                enabled: $0.isEnabled
            )
        }
        let originDialect: SharedSetupV2.OriginDialect = markdown.style == .custom &&
            !SharedSetupPlaceholderValidator.isCompatible(
                markdown.customTemplate,
                dialect: .portable
            ) ? .apple : .portable

        let destination: SharedSetupV2.Destination
        switch nativeProfile.target {
        case .localIPhoneFolder:
            // File Provider/iCloud path details are intentionally ignored. A
            // native folder target is always inert device_folder intent.
            destination = .init(kind: .deviceFolder, apiEndpoint: nil)
        case .connectedMac:
            destination = .init(kind: .connectedMac, apiEndpoint: nil)
        case .apiEndpoint:
            destination = .init(
                kind: .apiEndpoint,
                apiEndpoint: endpoint.flatMap { endpointHint($0.endpointURLString) }
            )
        }

        let trimmedName = nativeProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedSetupV2.Profile(
            bundleID: bundleID,
            name: trimmedName,
            export: .init(
                formats: settings.exportFormats.map(sharedFormat).sorted {
                    $0.rawValue < $1.rawValue
                },
                includeMetadata: settings.includeMetadata,
                groupByCategory: settings.groupByCategory,
                filenameTemplate: settings.filenameFormat,
                folderTemplate: settings.folderStructure,
                writeMode: sharedWriteMode(settings.writeMode),
                compatibilityDetail: settings.compatibilityDetail == .selectedTimeSeries
                    ? .selectedTimeSeries
                    : .summary
            ),
            metrics: .init(enabledIDs: enabledSemanticIDs),
            presentation: .init(
                dateFormat: sharedDate(settings.formatCustomization.dateFormat),
                timeFormat: sharedTime(settings.formatCustomization.timeFormat),
                units: settings.formatCustomization.unitPreference == .metric ? .metric : .imperial,
                frontmatter: .init(
                    fields: frontmatterFields,
                    customValues: frontmatter.customFields,
                    placeholders: frontmatter.placeholderFields,
                    includeDate: frontmatter.includeDate,
                    includeType: frontmatter.includeType,
                    dateKey: frontmatter.customDateKey,
                    typeKey: frontmatter.customTypeKey,
                    typeValue: frontmatter.customTypeValue,
                    keyStyle: frontmatter.keyStyle == .snakeCase ? .snakeCase : .camelCase
                ),
                markdown: .init(
                    style: sharedMarkdownStyle(markdown.style),
                    customText: markdown.customTemplate,
                    headerLevel: markdown.sectionHeaderLevel,
                    useEmoji: markdown.useEmoji,
                    includeSummary: markdown.includeSummary,
                    bulletStyle: sharedBullet(markdown.bulletStyle),
                    originDialect: originDialect
                )
            ),
            individualEntries: .init(
                enabled: settings.individualTracking.globalEnabled,
                metrics: individualSemantic,
                entriesFolder: settings.individualTracking.entriesFolder,
                organizeByCategory: settings.individualTracking.useCategoryFolders,
                filenameTemplate: settings.individualTracking.filenameTemplate
            ),
            dailyNotes: .init(
                enabled: settings.dailyNoteInjection.enabled,
                folder: settings.dailyNoteInjection.folderPath,
                filenameTemplate: settings.dailyNoteInjection.filenamePattern,
                createIfMissing: settings.dailyNoteInjection.createIfMissing,
                injectSections: settings.dailyNoteInjection.injectMarkdownSections
            ),
            destination: destination,
            schedule: schedule,
            platformExtensions: .init(
                apple: .init(
                    extensionVersion: 2,
                    export: .init(
                        organizeFormatsIntoFolders: settings.organizeFormatsIntoFolders,
                        archiveFiles: settings.archiveExportFiles,
                        includeDataDictionary: settings.includeDataDictionary,
                        summaryOnly: settings.summaryOnlyExport,
                        healthKitSourceArchive: settings.healthKitSourceArchivePolicy == .canonicalV1
                            ? .canonicalV1
                            : .none,
                        generateRangeSummary: settings.generateRangeSummary
                    ),
                    dailyNotes: .init(only: settings.dailyNoteInjection.dailyNotesOnly),
                    schedule: scheduledEntry.map { entry in
                        appleScheduleIntent(from: entry)
                    }
                ),
                android: preservedAndroidExtension
            )
        )
    }

    private static func scheduleIntent(
        from entry: ScheduledExportEntry,
        calendar: Calendar
    ) throws -> SharedSetupV2.Schedule {
        let cadence: SharedSetupV2.Cadence
        let unit: SharedSetupV2.CadenceUnit
        let value: Int
        switch entry.frequency {
        case .daily:
            value = 1
            unit = .days
        case .weekly:
            value = 1
            unit = .weeks
        case .custom:
            value = entry.customInterval
            switch entry.customUnit {
            case .day: unit = .days
            case .week: unit = .weeks
            case .month: unit = .months
            }
        }
        cadence = .init(
            value: value,
            unit: unit,
            anchorDate: try dateOnly(entry.customAnchorDate, calendar: calendar)
        )
        return .init(
            activationRequested: entry.isEnabled,
            cadence: cadence,
            localTime: .init(hour: entry.preferredHour, minute: entry.preferredMinute),
            weekday: entry.weekday,
            lookbackDays: entry.lookbackDays,
            dateWindow: .pastCompleteDays
        )
    }

    private static func appleScheduleIntent(
        from entry: ScheduledExportEntry
    ) -> SharedSetupV2.AppleSchedule {
        let frequency: SharedSetupV2.AppleFrequency
        switch entry.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .custom: frequency = .custom
        }
        let customUnit: SharedSetupV2.AppleCustomUnit
        switch entry.customUnit {
        case .day: customUnit = .days
        case .week: customUnit = .weeks
        case .month: customUnit = .months
        }
        return .init(
            frequency: frequency,
            customUnit: customUnit,
            todayRefreshRequested: entry.todayRefreshEnabled,
            todayRefreshIntervalHours: entry.todayRefreshIntervalHours
        )
    }

    private static func semanticIDs(
        for nativeIDs: Set<String>,
        reverseApple: [String: String],
        context: String
    ) throws -> [String] {
        try nativeIDs.map { nativeID in
            guard let semanticID = reverseApple[nativeID] else {
                throw SharedSetupV2Error.invalid(
                    "The \(context) contains an Apple metric without registry evidence: \(nativeID)."
                )
            }
            return semanticID
        }.sorted()
    }

    private static func individualEntries(
        _ snapshot: IndividualTrackingSnapshot,
        reverseApple: [String: String]
    ) throws -> [String: SharedSetupV2.IndividualMetric] {
        var result: [String: SharedSetupV2.IndividualMetric] = [:]
        for nativeID in snapshot.metricConfigs.keys.sorted() {
            guard let semanticID = reverseApple[nativeID],
                  let config = snapshot.metricConfigs[nativeID] else {
                throw SharedSetupV2Error.invalid(
                    "Individual-entry settings contain an Apple metric without registry evidence: \(nativeID)."
                )
            }
            result[semanticID] = .init(
                enabled: config.trackIndividually,
                customFolder: config.customFolder
            )
        }
        return result
    }

    private static func reverseAppleRegistry(
        _ registry: SharedSetupMetricRegistry
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        for semanticID in registry.semanticToApple.keys.sorted() {
            guard let nativeID = registry.semanticToApple[semanticID] else { continue }
            if let existing = result[nativeID], existing != semanticID {
                throw SharedSetupV2Error.invalid(
                    "The metric registry maps multiple semantic meanings to one Apple selection ID."
                )
            }
            result[nativeID] = semanticID
        }
        return result
    }

    private static func validateDestinationSnapshotIdentity(
        _ snapshots: SharedSetupV2DestinationSnapshots
    ) throws {
        guard Set(snapshots.vaults.map(\.id)).count == snapshots.vaults.count,
              Set(snapshots.apiEndpoints.map(\.id)).count == snapshots.apiEndpoints.count else {
            throw SharedSetupV2Error.invalid("Destination snapshot IDs are not unique.")
        }
    }

    private static func endpointHint(_ rawValue: String) -> SharedSetupV2.APIEndpoint? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              SharedSetupV2Validation.isDNSHost(host) else {
            return nil
        }
        let queryOmitted = components.query != nil
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard !path.contains("%") else { return nil }
        let hint = SharedSetupV2.APIEndpoint(
            scheme: "https",
            host: host.lowercased(),
            port: components.port,
            path: path,
            queryOmitted: queryOmitted,
            credentialsRequired: true
        )
        return hint.validatedURLString == nil ? nil : hint
    }

    private static func dateOnly(_ date: Date, calendar: Calendar) throws -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              (1...9_999).contains(year) else {
            throw SharedSetupV2Error.invalid("The schedule anchor date cannot be represented.")
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func aliasMatchesRegistry(
        _ alias: SharedSetupV2.MetricAlias,
        semanticID: String,
        registry: SharedSetupMetricRegistry
    ) -> Bool {
        alias.appleSelectionID == registry.semanticToApple[semanticID] &&
            alias.androidSelectionID == registry.semanticToAndroid[semanticID] &&
            alias.equivalence == registry.equivalence[semanticID].map(sharedEquivalence)
    }

    private nonisolated static func sharedEquivalence(
        _ value: SharedSetupV1.Equivalence
    ) -> SharedSetupV2.Equivalence {
        switch value {
        case .platformExactOrUnavailable: .platformExactOrUnavailable
        case .mappedAlias: .mappedAlias
        case .platformDistinct: .platformDistinct
        }
    }

    private nonisolated static func sharedFormat(_ value: ExportFormat) -> SharedSetupV2.Format {
        switch value {
        case .markdown: .markdown
        case .obsidianBases: .obsidianBases
        case .json: .json
        case .csv: .csv
        }
    }

    private nonisolated static func sharedWriteMode(_ value: WriteMode) -> SharedSetupV2.SharedWriteMode {
        switch value {
        case .overwrite: .overwrite
        case .append: .append
        case .update: .update
        }
    }

    private nonisolated static func sharedDate(_ value: DateFormatPreference) -> SharedSetupV2.DateFormat {
        switch value {
        case .iso8601: .iso8601
        case .usShort: .usShort
        case .usLong: .usLong
        case .euShort: .euShort
        case .euLong: .euLong
        case .compact: .compact
        case .friendly: .friendly
        }
    }

    private nonisolated static func sharedTime(_ value: TimeFormatPreference) -> SharedSetupV2.TimeFormat {
        switch value {
        case .hour24: .hour24
        case .hour24WithSeconds: .hour24Seconds
        case .hour12: .hour12
        case .hour12WithSeconds: .hour12Seconds
        }
    }

    private nonisolated static func sharedMarkdownStyle(
        _ value: MarkdownTemplateStyle
    ) -> SharedSetupV2.MarkdownStyle {
        switch value {
        case .standard: .standard
        case .compact: .compact
        case .detailed: .detailed
        case .custom: .custom
        }
    }

    private nonisolated static func sharedBullet(
        _ value: MarkdownTemplateConfig.BulletStyle
    ) -> SharedSetupV2.BulletStyle {
        switch value {
        case .dash: .dash
        case .asterisk: .asterisk
        case .plus: .plus
        }
    }
}

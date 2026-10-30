import Foundation

/// Readable compatibility detail retained alongside daily aggregates.
///
/// These projections are intentionally distinct from canonical HealthKit source
/// records: they use Health.md's established day ownership, clipping, units, and
/// presentation semantics.
nonisolated enum ExportCompatibilityDetail: String, Codable, CaseIterable, Sendable {
    case summary
    case selectedTimeSeries = "selected_time_series"

    var includesSelectedTimeSeries: Bool { self == .selectedTimeSeries }
}

/// Apple-only canonical source-record archive policy.
nonisolated enum HealthKitSourceArchivePolicy: String, Codable, CaseIterable, Sendable {
    case none
    case canonicalV1 = "canonical_v1"

    var includesCanonicalArchive: Bool { self == .canonicalV1 }
}

/// Orthogonal detail policy for one Apple export operation.
///
/// The durable model deliberately supports archive-only output even though the
/// primary UI presents Summary, Detailed Time-Series, and Lossless presets.
nonisolated struct AppleExportDetailPolicy: Codable, Equatable, Sendable {
    var compatibilityDetail: ExportCompatibilityDetail
    var healthKitSourceArchive: HealthKitSourceArchivePolicy

    static let summary = AppleExportDetailPolicy(
        compatibilityDetail: .summary,
        healthKitSourceArchive: .none
    )
    static let detailedTimeSeries = AppleExportDetailPolicy(
        compatibilityDetail: .selectedTimeSeries,
        healthKitSourceArchive: .none
    )
    static let archiveOnly = AppleExportDetailPolicy(
        compatibilityDetail: .summary,
        healthKitSourceArchive: .canonicalV1
    )
    static let lossless = AppleExportDetailPolicy(
        compatibilityDetail: .selectedTimeSeries,
        healthKitSourceArchive: .canonicalV1
    )

    var includesSelectedTimeSeries: Bool {
        compatibilityDetail.includesSelectedTimeSeries
    }

    var includesCanonicalArchive: Bool {
        healthKitSourceArchive.includesCanonicalArchive
    }

    var hasAnyDetail: Bool {
        includesSelectedTimeSeries || includesCanonicalArchive
    }

    /// The historical Boolean can represent only Summary and Lossless exactly.
    var isLegacyRepresentable: Bool {
        self == .summary || self == .lossless
    }

    /// Safe downgrade projection. Split states become Summary instead of
    /// unexpectedly enabling a very large archive or claiming dropped detail.
    var legacyIncludeGranularData: Bool {
        self == .lossless
    }

    var historyDetailLevelToken: String {
        if self == .detailedTimeSeries {
            return "detailed_time_series"
        } else if self == .archiveOnly {
            return "archive_only"
        } else if self == .lossless {
            return "lossless"
        }
        return "summary"
    }
}

/// User-facing presets backed by the orthogonal durable policy.
nonisolated enum AppleExportDetailPreset: String, CaseIterable, Identifiable, Sendable {
    case summary
    case detailedTimeSeries = "detailed_time_series"
    case losslessHealthRecords = "lossless_health_records"
    case archiveOnly = "archive_only"

    var id: String { rawValue }

    var policy: AppleExportDetailPolicy {
        switch self {
        case .summary: .summary
        case .detailedTimeSeries: .detailedTimeSeries
        case .losslessHealthRecords: .lossless
        case .archiveOnly: .archiveOnly
        }
    }

    var localizedTitle: String {
        switch self {
        case .summary:
            String(localized: "Summary", comment: "Export data-detail preset")
        case .detailedTimeSeries:
            String(localized: "Detailed Time-Series", comment: "Export data-detail preset")
        case .losslessHealthRecords:
            String(localized: "Lossless Health Records", comment: "Export data-detail preset")
        case .archiveOnly:
            String(localized: "HealthKit Archive Only", comment: "Advanced export data-detail preset")
        }
    }

    var localizedDescription: String {
        switch self {
        case .summary:
            String(localized: "Daily aggregates such as averages, minimums, and maximums.", comment: "Export data-detail preset description")
        case .detailedTimeSeries:
            String(localized: "Adds selected timestamped samples such as heart rate, HRV, blood oxygen, respiratory rate, and sleep stages without the canonical source archive.", comment: "Export data-detail preset description")
        case .losslessHealthRecords:
            String(localized: "Adds detailed time-series and the canonical HealthKit source archive with identities, provenance, metadata, and relationships. Files may be much larger.", comment: "Export data-detail preset description")
        case .archiveOnly:
            String(localized: "Adds the canonical HealthKit source archive without duplicate compatibility time-series projections.", comment: "Advanced export data-detail preset description")
        }
    }

    init(policy: AppleExportDetailPolicy) {
        if policy == .summary {
            self = .summary
        } else if policy == .detailedTimeSeries {
            self = .detailedTimeSeries
        } else if policy == .lossless {
            self = .losslessHealthRecords
        } else if policy == .archiveOnly {
            self = .archiveOnly
        } else {
            // Both dimensions are closed enums, so this is defensive against a
            // future additive combination until the preset UI is extended.
            self = .summary
        }
    }
}

/// Immutable, portable copy of every setting that affects export output.
///
/// iOS sends this snapshot to macOS with a Mac export job. The Mac can then
/// render/write files exactly as iOS would without persisting these choices as
/// Mac-local preferences.
struct ExportSettingsSnapshot: Codable, Equatable {
    var exportFormats: Set<ExportFormat>
    var includeMetadata: Bool
    var groupByCategory: Bool
    var filenameFormat: String
    var folderStructure: String
    /// iPhone-owned export subfolder appended to the Mac-selected destination root.
    /// Nil preserves compatibility with jobs sent by older iPhone versions.
    var healthSubfolder: String?
    var organizeFormatsIntoFolders: Bool
    var archiveExportFiles: Bool
    var includeDataDictionary: Bool
    var summaryOnlyExport: Bool
    var writeMode: WriteMode
    var formatCustomization: FormatCustomizationSnapshot
    var individualTracking: IndividualTrackingSnapshot
    var dailyNoteInjection: DailyNoteInjectionSnapshot
    var compatibilityDetail: ExportCompatibilityDetail
    var healthKitSourceArchivePolicy: HealthKitSourceArchivePolicy

    var detailPolicy: AppleExportDetailPolicy {
        get {
            AppleExportDetailPolicy(
                compatibilityDetail: compatibilityDetail,
                healthKitSourceArchive: healthKitSourceArchivePolicy
            )
        }
        set {
            compatibilityDetail = newValue.compatibilityDetail
            healthKitSourceArchivePolicy = newValue.healthKitSourceArchive
        }
    }

    /// Source compatibility for historical callers. New runtime decisions must
    /// use `detailPolicy`; the legacy Boolean represents only Summary/Lossless.
    var includeGranularData: Bool {
        get { detailPolicy.legacyIncludeGranularData }
        set { detailPolicy = newValue ? .lossless : .summary }
    }

    /// New v9 range-summary preference. New snapshots encode only this key.
    var generateRangeSummary: Bool
    /// Decoded operation state, never a new setting or a new wire key. A known v7 pin
    /// keeps the exact historical calendar keys instead of migrating its pending work.
    private(set) var historicalCalendarRollupPeriods: [HealthRollupPeriod]? = nil
    var metricSelection: MetricSelectionSnapshot

    var operationRollupPeriods: [HealthRollupPeriod] {
        guard !dailyNotesOnlyModeEnabled else { return [] }
        return historicalCalendarRollupPeriods ?? (generateRangeSummary ? [.range] : [])
    }

    // Transitional source compatibility for call sites migrating to the single
    // range-summary preference. New durable snapshots never encode these keys.
    var generateWeeklyRollups: Bool {
        get { historicalCalendarRollupPeriods?.contains(.weekly) ?? generateRangeSummary }
        set { generateRangeSummary = newValue }
    }
    var generateMonthlyRollups: Bool {
        get { historicalCalendarRollupPeriods?.contains(.monthly) ?? generateRangeSummary }
        set { if newValue { generateRangeSummary = true } }
    }
    var generateYearlyRollups: Bool {
        get { historicalCalendarRollupPeriods?.contains(.yearly) ?? generateRangeSummary }
        set { if newValue { generateRangeSummary = true } }
    }
    /// Immutable renderer provenance for newly planned Apple output. Missing means the snapshot
    /// predates engine pinning and must retain legacy renderer authority.
    var appleExportEnginePin: AppleExportEnginePin?
    /// Whether authority was resolved when this durable snapshot was created. Nil pin plus true is
    /// explicit legacy; it must not inherit a later rollout default during resume.
    var appleExportEngineAuthorityIsFrozen: Bool
    /// Explicit source calendar used for day ownership, roll-ups, filenames, and clock fields.
    /// Missing preserves the legacy behavior of consulting the process's current time zone.
    var calendarTimeZoneIdentifier: String?
    /// Internal durable capture authority. Missing remains missing on decode;
    /// a pending job cannot acquire today's mutable preference during recovery.
    var sleepCaptureContext: AppleSleepCaptureContext? = nil
    /// Private local job source selection. Never included in wire settings or exports.
    var externalProviderCaptureAuthority: ExternalProviderCaptureAuthority? = nil
    /// Journal stores opt in explicitly. Wire packets, canonical request
    /// fingerprints and portable configuration retain their historical bytes.
    static let durableSleepContextEncoding = CodingUserInfoKey(rawValue: "healthmd.durable_sleep_context")!

    enum CodingKeys: String, CodingKey {
        case exportFormats
        case includeMetadata
        case groupByCategory
        case filenameFormat
        case folderStructure
        case healthSubfolder
        case organizeFormatsIntoFolders
        case archiveExportFiles
        case includeDataDictionary
        case summaryOnlyExport
        case writeMode
        case formatCustomization
        case individualTracking
        case dailyNoteInjection
        case compatibilityDetail
        case healthKitSourceArchivePolicy
        case includeGranularData
        case generateRangeSummary
        case generateWeeklyRollups
        case generateMonthlyRollups
        case generateYearlyRollups
        case metricSelection
        case appleExportEnginePin
        case appleExportEngineAuthorityIsFrozen
        case calendarTimeZoneIdentifier
        case sleepCaptureContext
        case externalProviderCaptureAuthority
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case archiveMarkdownExports
    }

    var dailyNotesOnlyModeEnabled: Bool {
        dailyNoteInjection.enabled && dailyNoteInjection.dailyNotesOnly
    }

    var hasFileDestinationOutput: Bool {
        dailyNotesOnlyModeEnabled || !exportFormats.isEmpty
    }

    init(
        exportFormats: Set<ExportFormat>,
        includeMetadata: Bool,
        groupByCategory: Bool,
        filenameFormat: String,
        folderStructure: String,
        healthSubfolder: String? = nil,
        organizeFormatsIntoFolders: Bool,
        archiveExportFiles: Bool,
        includeDataDictionary: Bool = true,
        summaryOnlyExport: Bool = false,
        writeMode: WriteMode,
        formatCustomization: FormatCustomizationSnapshot,
        individualTracking: IndividualTrackingSnapshot,
        dailyNoteInjection: DailyNoteInjectionSnapshot,
        includeGranularData: Bool,
        compatibilityDetail: ExportCompatibilityDetail? = nil,
        healthKitSourceArchivePolicy: HealthKitSourceArchivePolicy? = nil,
        generateRangeSummary: Bool,
        metricSelection: MetricSelectionSnapshot,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        appleExportEngineAuthorityIsFrozen: Bool = true,
        calendarTimeZoneIdentifier: String? = nil
    ) {
        self.exportFormats = exportFormats
        self.includeMetadata = includeMetadata
        self.groupByCategory = groupByCategory
        self.filenameFormat = filenameFormat
        self.folderStructure = folderStructure
        self.healthSubfolder = healthSubfolder
        self.organizeFormatsIntoFolders = organizeFormatsIntoFolders
        self.archiveExportFiles = archiveExportFiles
        self.includeDataDictionary = includeDataDictionary
        self.summaryOnlyExport = summaryOnlyExport
        self.writeMode = writeMode
        self.formatCustomization = formatCustomization
        self.individualTracking = individualTracking
        self.dailyNoteInjection = dailyNoteInjection
        let legacyPolicy: AppleExportDetailPolicy = includeGranularData ? .lossless : .summary
        self.compatibilityDetail = compatibilityDetail ?? legacyPolicy.compatibilityDetail
        self.healthKitSourceArchivePolicy = healthKitSourceArchivePolicy
            ?? legacyPolicy.healthKitSourceArchive
        self.generateRangeSummary = generateRangeSummary
        self.metricSelection = metricSelection
        self.appleExportEnginePin = appleExportEnginePin
        self.appleExportEngineAuthorityIsFrozen = appleExportEngineAuthorityIsFrozen
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        exportFormats = try container.decode(Set<ExportFormat>.self, forKey: .exportFormats)
        includeMetadata = try container.decode(Bool.self, forKey: .includeMetadata)
        groupByCategory = try container.decode(Bool.self, forKey: .groupByCategory)
        filenameFormat = try container.decode(String.self, forKey: .filenameFormat)
        folderStructure = try container.decode(String.self, forKey: .folderStructure)
        healthSubfolder = try container.decodeIfPresent(String.self, forKey: .healthSubfolder)
        organizeFormatsIntoFolders = try container.decodeIfPresent(Bool.self, forKey: .organizeFormatsIntoFolders) ?? false
        archiveExportFiles = try container.decodeIfPresent(Bool.self, forKey: .archiveExportFiles)
            ?? legacyContainer.decodeIfPresent(Bool.self, forKey: .archiveMarkdownExports)
            ?? false
        includeDataDictionary = try container.decodeIfPresent(
            Bool.self,
            forKey: .includeDataDictionary
        ) ?? true
        summaryOnlyExport = try container.decodeIfPresent(Bool.self, forKey: .summaryOnlyExport) ?? false
        writeMode = try container.decode(WriteMode.self, forKey: .writeMode)
        formatCustomization = try container.decode(FormatCustomizationSnapshot.self, forKey: .formatCustomization)
        individualTracking = try container.decode(IndividualTrackingSnapshot.self, forKey: .individualTracking)
        dailyNoteInjection = try container.decode(DailyNoteInjectionSnapshot.self, forKey: .dailyNoteInjection)
        // The historical Boolean coupled compatibility time-series with the
        // canonical archive. Exact fields win when present; old durable work maps
        // true to both and false/missing to neither without consulting live defaults.
        let legacyIncludeGranularData = try container.decodeIfPresent(
            Bool.self,
            forKey: .includeGranularData
        ) ?? false
        let legacyPolicy: AppleExportDetailPolicy = legacyIncludeGranularData ? .lossless : .summary
        compatibilityDetail = try container.decodeIfPresent(
            ExportCompatibilityDetail.self,
            forKey: .compatibilityDetail
        ) ?? legacyPolicy.compatibilityDetail
        healthKitSourceArchivePolicy = try container.decodeIfPresent(
            HealthKitSourceArchivePolicy.self,
            forKey: .healthKitSourceArchivePolicy
        ) ?? legacyPolicy.healthKitSourceArchive
        if let rangeSummary = try container.decodeIfPresent(Bool.self, forKey: .generateRangeSummary) {
            generateRangeSummary = rangeSummary
        } else {
            let legacyWeekly = try container.decodeIfPresent(Bool.self, forKey: .generateWeeklyRollups) ?? false
            let legacyMonthly = try container.decodeIfPresent(Bool.self, forKey: .generateMonthlyRollups) ?? false
            let legacyYearly = try container.decodeIfPresent(Bool.self, forKey: .generateYearlyRollups) ?? false
            generateRangeSummary = legacyWeekly || legacyMonthly || legacyYearly
        }
        metricSelection = try container.decode(MetricSelectionSnapshot.self, forKey: .metricSelection)
        // Decoding is data-only. In particular, it never resolves the current engine flag or calls
        // the packaged Rust core. Missing fields are explicitly legacy.
        appleExportEnginePin = try container.decodeIfPresent(
            AppleExportEnginePin.self,
            forKey: .appleExportEnginePin
        )
        if appleExportEnginePin?.profile == "apple_health_data_v7",
           appleExportEnginePin?.registrySHA256 == AppleExportEnginePin.historicalRegistrySHA256,
           !container.contains(.generateRangeSummary),
           [CodingKeys.generateWeeklyRollups, .generateMonthlyRollups, .generateYearlyRollups]
            .contains(where: container.contains) {
            historicalCalendarRollupPeriods = try [
                (CodingKeys.generateWeeklyRollups, HealthRollupPeriod.weekly),
                (.generateMonthlyRollups, .monthly),
                (.generateYearlyRollups, .yearly)
            ].compactMap { key, period in
                try container.decodeIfPresent(Bool.self, forKey: key) == true ? period : nil
            }
            generateRangeSummary = false
        }
        // Snapshots from builds before this marker are already durable work. Missing pin always
        // meant legacy, so decode the absent marker as frozen rather than consulting current flags.
        appleExportEngineAuthorityIsFrozen = try container.decodeIfPresent(
            Bool.self,
            forKey: .appleExportEngineAuthorityIsFrozen
        ) ?? true
        calendarTimeZoneIdentifier = try container.decodeIfPresent(
            String.self,
            forKey: .calendarTimeZoneIdentifier
        )
        sleepCaptureContext = try container.decodeIfPresent(AppleSleepCaptureContext.self, forKey: .sleepCaptureContext)
        if decoder.userInfo[Self.durableSleepContextEncoding] as? Bool == true {
            externalProviderCaptureAuthority = try container.decodeIfPresent(ExternalProviderCaptureAuthority.self,
                forKey: .externalProviderCaptureAuthority)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(exportFormats, forKey: .exportFormats)
        try container.encode(includeMetadata, forKey: .includeMetadata)
        try container.encode(groupByCategory, forKey: .groupByCategory)
        try container.encode(filenameFormat, forKey: .filenameFormat)
        try container.encode(folderStructure, forKey: .folderStructure)
        try container.encodeIfPresent(healthSubfolder, forKey: .healthSubfolder)
        try container.encode(organizeFormatsIntoFolders, forKey: .organizeFormatsIntoFolders)
        try container.encode(archiveExportFiles, forKey: .archiveExportFiles)
        // Missing is the canonical legacy/default-on representation. Preserving it keeps
        // durable corpus fingerprints stable across upgrades and mixed-version peers.
        if !includeDataDictionary {
            try container.encode(false, forKey: .includeDataDictionary)
        }
        try container.encode(summaryOnlyExport, forKey: .summaryOnlyExport)
        try container.encode(writeMode, forKey: .writeMode)
        try container.encode(formatCustomization, forKey: .formatCustomization)
        try container.encode(individualTracking, forKey: .individualTracking)
        try container.encode(dailyNoteInjection, forKey: .dailyNoteInjection)
        try container.encode(compatibilityDetail, forKey: .compatibilityDetail)
        try container.encode(healthKitSourceArchivePolicy, forKey: .healthKitSourceArchivePolicy)
        // Keep a safe bridge for old decoders. Connected peers reject split
        // policies before transfer, so this field is never used to approximate
        // a split state on an old Mac.
        try container.encode(
            detailPolicy.legacyIncludeGranularData,
            forKey: .includeGranularData
        )
        if let periods = historicalCalendarRollupPeriods {
            try container.encode(periods.contains(.weekly), forKey: .generateWeeklyRollups)
            try container.encode(periods.contains(.monthly), forKey: .generateMonthlyRollups)
            try container.encode(periods.contains(.yearly), forKey: .generateYearlyRollups)
        } else {
            try container.encode(generateRangeSummary, forKey: .generateRangeSummary)
        }
        try container.encode(metricSelection, forKey: .metricSelection)
        try container.encodeIfPresent(appleExportEnginePin, forKey: .appleExportEnginePin)
        try container.encode(
            appleExportEngineAuthorityIsFrozen,
            forKey: .appleExportEngineAuthorityIsFrozen
        )
        try container.encodeIfPresent(
            calendarTimeZoneIdentifier,
            forKey: .calendarTimeZoneIdentifier
        )
        if encoder.userInfo[Self.durableSleepContextEncoding] as? Bool == true {
            try container.encodeIfPresent(sleepCaptureContext, forKey: .sleepCaptureContext)
            try container.encodeIfPresent(externalProviderCaptureAuthority, forKey: .externalProviderCaptureAuthority)
        }
    }

    static func from(
        _ settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        appleExportEngineAuthorityIsFrozen: Bool = true,
        calendarTimeZoneIdentifier: String? = nil
    ) -> ExportSettingsSnapshot {
        var snapshot = ExportSettingsSnapshot(
            exportFormats: settings.exportFormats,
            includeMetadata: settings.includeMetadata,
            groupByCategory: settings.groupByCategory,
            filenameFormat: settings.filenameFormat,
            folderStructure: settings.folderStructure,
            healthSubfolder: healthSubfolder,
            organizeFormatsIntoFolders: settings.organizeFormatsIntoFolders,
            archiveExportFiles: settings.archiveExportFiles,
            includeDataDictionary: settings.includeDataDictionary,
            summaryOnlyExport: settings.summaryOnlyExport,
            writeMode: settings.writeMode,
            formatCustomization: .from(settings.formatCustomization),
            individualTracking: .from(settings.individualTracking),
            dailyNoteInjection: .from(settings.dailyNoteInjection),
            includeGranularData: settings.detailPolicy.legacyIncludeGranularData,
            compatibilityDetail: settings.compatibilityDetail,
            healthKitSourceArchivePolicy: settings.healthKitSourceArchivePolicy,
            generateRangeSummary: settings.generateRangeSummary,
            metricSelection: .from(settings.metricSelection),
            appleExportEnginePin: appleExportEnginePin ?? settings.executionAppleExportEnginePin,
            appleExportEngineAuthorityIsFrozen: appleExportEngineAuthorityIsFrozen
                || settings.executionAppleExportEngineAuthorityIsFrozen,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
                ?? settings.exportTimeZoneOverride?.identifier
        )
        snapshot.sleepCaptureContext = settings.executionSleepCaptureContext
            ?? (settings.executionSleepCaptureContextIsFrozen ? nil : AppleSleepCaptureContext.pinned.wrappedValue)
        snapshot.externalProviderCaptureAuthority = settings.executionExternalProviderCaptureAuthority
        return snapshot
    }

    /// Check saved capture and renderer authority as one value without opening a
    /// production gate or borrowing today's settings. Capture-only pending requests
    /// may provide their own separately persisted context.
    func validatedSleepCaptureContext(captureContext: AppleSleepCaptureContext? = nil) throws -> AppleSleepCaptureContext {
        guard let context = captureContext ?? sleepCaptureContext else {
            throw AppleSleepCaptureContext.AvailabilityError.missingDurableAttribution
        }
        if let captureContext, let sleepCaptureContext, captureContext != sleepCaptureContext {
            throw AppleSleepCaptureContext.AvailabilityError.incompatibleDurableAuthority
        }
        try context.validatePersistedOperationAuthority(enginePin: appleExportEnginePin,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
            engineAuthorityIsFrozen: appleExportEngineAuthorityIsFrozen)
        return context
    }

    func recoveredSleepCaptureContext(captureContext: AppleSleepCaptureContext? = nil) throws -> AppleSleepCaptureContext {
        // Preserve the production-gated error for capture-only historical draft jobs.
        if (captureContext ?? sleepCaptureContext)?.sleepDayAttribution == .morningEnds, appleExportEnginePin == nil {
            _ = try AppleSleepCaptureContext.recovered(captureContext ?? sleepCaptureContext)
        }
        let context = try validatedSleepCaptureContext(captureContext: captureContext)
        try context.requireShippedProfile()
        return context
    }

    /// Freezes the nondeterministic Apple operation inputs only while planning new work. Persisted
    /// snapshots must be copied directly and must never call this factory during resume.
    /// Preview daily files separately from the operation's range outputs, retaining
    /// its captured profile, registry and clock. The original snapshot remains intact.
    func forDailyArtifactPreview() -> Self {
        guard sleepCaptureContext?.sleepDayAttribution == .morningEnds else { return self }
        var daily = self
        daily.generateRangeSummary = false
        daily.historicalCalendarRollupPeriods = nil
        return daily
    }

    static func forNewAppleOperation(
        _ settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        calendarTimeZone: TimeZone? = nil,
        surface: AppleExportOperationSurface = .legacyOnly,
        hasNativeOnlyCompanionAction: Bool = false,
        policyResolver: AppleExportEnginePolicyResolver = AppleExportEnginePolicyResolver(),
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor()
    ) async -> ExportSettingsSnapshot {
        if settings.executionSleepCaptureContextIsFrozen, settings.executionSleepCaptureContext == nil {
            // A frozen missing context cannot borrow a parent operation's clock,
            // attribution or new renderer authority. Preserve the stored settings.
            return from(settings, healthSubfolder: healthSubfolder,
                appleExportEngineAuthorityIsFrozen: true)
        }
        let resolvedTimeZone = settings.executionSleepCaptureContext?.timeZone
            ?? AppleSleepCaptureContext.pinned.wrappedValue?.timeZone
            ?? calendarTimeZone ?? settings.exportTimeZoneOverride ?? .current
        let identifier = resolvedTimeZone.identifier
        var snapshot = from(
            settings,
            healthSubfolder: healthSubfolder,
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: identifier
        )

        if snapshot.sleepCaptureContext == nil, !settings.executionSleepCaptureContextIsFrozen {
            snapshot.sleepCaptureContext = AppleSleepCaptureContext.resolve(
                timeZone: resolvedTimeZone, attribution: HealthKitManager.shared.sleepDayAttribution
            )
        }

        // This factory is only for new work, but preserve an injected execution pin defensively so
        // an accidental call during resume can never replace persisted authority with today's flag.
        if snapshot.appleExportEnginePin != nil {
            return snapshot
        }
        if snapshot.sleepCaptureContext?.sleepDayAttribution == .morningEnds {
            // Wake-date semantics have one renderer authority: explicit Apple-v11
            // Rust. Apple-v8 rollout flags cannot select or retag this profile.
            // Durable frozen nil authority and old draft markers retain their identity.
            guard !(settings.executionAppleExportEngineAuthorityIsFrozen
                        && settings.executionSleepCaptureContextIsFrozen),
                  !hasNativeOnlyCompanionAction,
                  (surface == .apiEndpoint ? APIEndpointExportRunner.supportsNewEnginePin(settingsSnapshot: snapshot)
                    : AppleLooseDailyExportPlanner.supportsNewWakeDateSettings(
                        settingsSnapshot: snapshot, surface: surface)) else { return snapshot }
            snapshot.appleExportEnginePin = await policyResolver.pinForNewWakeDateOperation(
                calendarTimeZoneIdentifier: identifier,
                expectedRegistryVersion: surface != .apiEndpoint && snapshot.generateRangeSummary ? AppleExportEnginePin.wakeDateRangeRegistryVersion
                    : AppleExportEnginePin.wakeDateDailyRegistryVersion,
                coreExecutor: coreExecutor)
            return snapshot
        }
        guard !hasNativeOnlyCompanionAction,
              supportsNewEnginePin(snapshot: snapshot, surface: surface) else {
            snapshot.appleExportEnginePin = nil
            return snapshot
        }

        let requestedMode = policyResolver.requestedAppleModeForNewOperation()
        if ApplePureRustAuthorityAdmission.applies(to: surface),
           requestedMode == .rust,
           !ApplePureRustAuthorityAdmission.supports(
               settings: snapshot,
               surface: surface
           ) {
            // Pure Rust authority is narrower than shadow coverage. Unsupported new Rust requests
            // resolve wholly to explicit legacy before the packaged core or native renderer opens.
            snapshot.appleExportEnginePin = nil
            return snapshot
        }

        snapshot.appleExportEnginePin = await policyResolver.pinForNewOperation(
            calendarTimeZoneIdentifier: identifier,
            requestedMode: requestedMode,
            coreExecutor: coreExecutor
        )
        return snapshot
    }

    private static func supportsNewEnginePin(
        snapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) -> Bool {
        switch surface {
        case .localVaultWithoutSideEffects,
             .localVaultRangeWithoutSideEffects,
             .localVaultRangeWithProviderSidecars,
             .connectedReceivedRangeWithProviderSidecars,
             .directGeneratedFilesWithProviderSidecars,
             .directGeneratedFilesWithoutSideEffects,
             .connectedReceivedFilesWithoutSideEffects,
             .connectedReceivedRangeWithoutSideEffects,
             .preview:
            return AppleLooseDailyExportPlanner.supports(
                settingsSnapshot: snapshot,
                surface: surface
            )
        case .apiEndpoint:
            return APIEndpointExportRunner.supportsNewEnginePin(settingsSnapshot: snapshot)
        case .legacyOnly:
            return false
        }
    }

    /// Builds a temporary `AdvancedExportSettings` object backed by isolated
    /// UserDefaults so applying a received iOS snapshot never mutates the Mac's
    /// persisted export preferences.
    func makeAdvancedExportSettings(
        userDefaults: UserDefaults = ExportSettingsSnapshot.makeTemporaryUserDefaults(),
        forNewConfiguration: Bool = false
    ) -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(snapshot: self, userDefaults: userDefaults)
        if forNewConfiguration {
            settings.executionSleepCaptureContext = nil
            settings.executionSleepCaptureContextIsFrozen = false
            settings.executionExternalProviderCaptureAuthority = nil
            settings.executionExternalProviderCaptureAuthorityIsFrozen = false
        }
        applyCalendarTimeZone(to: settings, includeSleepContext: !forNewConfiguration)
        return settings
    }

    func apply(to settings: AdvancedExportSettings) {
        settings.historicalCalendarRollupPeriods = historicalCalendarRollupPeriods
        settings.exportFormats = exportFormats
        settings.includeMetadata = includeMetadata
        settings.groupByCategory = groupByCategory
        settings.filenameFormat = filenameFormat
        settings.folderStructure = folderStructure
        settings.organizeFormatsIntoFolders = organizeFormatsIntoFolders
        settings.archiveExportFiles = archiveExportFiles
        settings.includeDataDictionary = includeDataDictionary
        settings.summaryOnlyExport = summaryOnlyExport
        settings.writeMode = writeMode
        formatCustomization.apply(to: settings.formatCustomization)
        individualTracking.apply(to: settings.individualTracking)
        dailyNoteInjection.apply(to: settings.dailyNoteInjection)
        settings.detailPolicy = detailPolicy
        settings.generateRangeSummary = generateRangeSummary
        metricSelection.apply(to: settings.metricSelection)
        settings.executionAppleExportEnginePin = appleExportEnginePin
        settings.executionAppleExportEngineAuthorityIsFrozen = appleExportEngineAuthorityIsFrozen
        applyCalendarTimeZone(to: settings)
    }

    private func applyCalendarTimeZone(to settings: AdvancedExportSettings, includeSleepContext: Bool = false) {
        if includeSleepContext, let sleepCaptureContext {
            settings.exportTimeZoneOverride = sleepCaptureContext.timeZone
            return
        }
        if let calendarTimeZoneIdentifier,
           AppleExportEnginePin.isIANAIdentifier(calendarTimeZoneIdentifier),
           let timeZone = TimeZone(identifier: calendarTimeZoneIdentifier) {
            settings.exportTimeZoneOverride = timeZone
        }
    }

    static func makeTemporaryUserDefaults() -> UserDefaults {
        let suiteName = "ExportSettingsSnapshot.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults for ExportSettingsSnapshot")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

extension ExportSettingsSnapshot {
    /// Source-compatible initializer for call sites that still construct the
    /// historical shape. Any enabled legacy period opts into the range summary.
    init(
        exportFormats: Set<ExportFormat>,
        includeMetadata: Bool,
        groupByCategory: Bool,
        filenameFormat: String,
        folderStructure: String,
        healthSubfolder: String? = nil,
        organizeFormatsIntoFolders: Bool,
        archiveExportFiles: Bool,
        includeDataDictionary: Bool = true,
        summaryOnlyExport: Bool = false,
        writeMode: WriteMode,
        formatCustomization: FormatCustomizationSnapshot,
        individualTracking: IndividualTrackingSnapshot,
        dailyNoteInjection: DailyNoteInjectionSnapshot,
        includeGranularData: Bool,
        generateWeeklyRollups: Bool,
        generateMonthlyRollups: Bool,
        generateYearlyRollups: Bool,
        metricSelection: MetricSelectionSnapshot,
        appleExportEnginePin: AppleExportEnginePin? = nil,
        appleExportEngineAuthorityIsFrozen: Bool = true,
        calendarTimeZoneIdentifier: String? = nil
    ) {
        self.init(
            exportFormats: exportFormats,
            includeMetadata: includeMetadata,
            groupByCategory: groupByCategory,
            filenameFormat: filenameFormat,
            folderStructure: folderStructure,
            healthSubfolder: healthSubfolder,
            organizeFormatsIntoFolders: organizeFormatsIntoFolders,
            archiveExportFiles: archiveExportFiles,
            includeDataDictionary: includeDataDictionary,
            summaryOnlyExport: summaryOnlyExport,
            writeMode: writeMode,
            formatCustomization: formatCustomization,
            individualTracking: individualTracking,
            dailyNoteInjection: dailyNoteInjection,
            includeGranularData: includeGranularData,
            generateRangeSummary: generateWeeklyRollups
                || generateMonthlyRollups || generateYearlyRollups,
            metricSelection: metricSelection,
            appleExportEnginePin: appleExportEnginePin,
            appleExportEngineAuthorityIsFrozen: appleExportEngineAuthorityIsFrozen,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
    }
}

// MARK: - Format Customization Snapshot

/// Audited subset where Rust can plan exact Apple v8 bytes without asking a native renderer for
/// expected content. Shadow remains broader because native output stays authoritative there.
nonisolated enum ApplePureRustAuthorityAdmission {
    static func applies(to surface: AppleExportOperationSurface) -> Bool {
        switch surface {
        case .localVaultWithoutSideEffects,
             .localVaultRangeWithoutSideEffects,
             .localVaultRangeWithProviderSidecars,
             .connectedReceivedRangeWithProviderSidecars,
             .directGeneratedFilesWithProviderSidecars,
             .directGeneratedFilesWithoutSideEffects,
             .connectedReceivedFilesWithoutSideEffects,
             .connectedReceivedRangeWithoutSideEffects,
             .apiEndpoint,
             .preview:
            true
        case .legacyOnly:
            false
        }
    }

    static func supports(
        settings: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) -> Bool {
        let isRangeSummaryOnly = settings.summaryOnlyExport && settings.generateRangeSummary
        let isRangeLimitDailyFallback = settings.summaryOnlyExport && !settings.generateRangeSummary
        guard isRangeSummaryOnly || isRangeLimitDailyFallback else { return false }
        switch surface {
        case .localVaultRangeWithoutSideEffects,
             .directGeneratedFilesWithoutSideEffects,
             .connectedReceivedRangeWithoutSideEffects:
            return true
        case .legacyOnly,
             .localVaultRangeWithProviderSidecars,
             .connectedReceivedRangeWithProviderSidecars,
             .directGeneratedFilesWithProviderSidecars,
             .localVaultWithoutSideEffects,
             .connectedReceivedFilesWithoutSideEffects,
             .apiEndpoint,
             .preview:
            return false
        }
    }
}

struct FormatCustomizationSnapshot: Codable, Equatable {
    var dateFormat: DateFormatPreference
    var timeFormat: TimeFormatPreference
    var unitPreference: UnitPreference
    var frontmatterConfig: FrontmatterConfigurationSnapshot
    var markdownTemplate: MarkdownTemplateConfig

    static func from(_ customization: FormatCustomization) -> FormatCustomizationSnapshot {
        FormatCustomizationSnapshot(
            dateFormat: customization.dateFormat,
            timeFormat: customization.timeFormat,
            unitPreference: customization.unitPreference,
            frontmatterConfig: .from(customization.frontmatterConfig),
            markdownTemplate: customization.markdownTemplate
        )
    }

    func apply(to customization: FormatCustomization) {
        customization.dateFormat = dateFormat
        customization.timeFormat = timeFormat
        customization.unitPreference = unitPreference
        frontmatterConfig.apply(to: customization.frontmatterConfig)
        customization.markdownTemplate = markdownTemplate
    }
}

struct FrontmatterConfigurationSnapshot: Codable, Equatable {
    var fields: [CustomFrontmatterField]
    var customFields: [String: String]
    var placeholderFields: [String]
    var includeDate: Bool
    var includeType: Bool
    var customDateKey: String
    var customTypeKey: String
    var customTypeValue: String
    var keyStyle: FrontmatterKeyStyle

    static func from(_ config: FrontmatterConfiguration) -> FrontmatterConfigurationSnapshot {
        FrontmatterConfigurationSnapshot(
            fields: config.fields,
            customFields: config.customFields,
            placeholderFields: config.placeholderFields,
            includeDate: config.includeDate,
            includeType: config.includeType,
            customDateKey: config.customDateKey,
            customTypeKey: config.customTypeKey,
            customTypeValue: config.customTypeValue,
            keyStyle: config.keyStyle
        )
    }

    func apply(to config: FrontmatterConfiguration) {
        config.fields = fields
        config.customFields = customFields
        config.placeholderFields = placeholderFields
        config.includeDate = includeDate
        config.includeType = includeType
        config.customDateKey = customDateKey
        config.customTypeKey = customTypeKey
        config.customTypeValue = customTypeValue
        config.keyStyle = keyStyle
    }
}

// MARK: - Individual Tracking Snapshot

struct IndividualTrackingSnapshot: Codable, Equatable {
    var globalEnabled: Bool
    var metricConfigs: [String: MetricTrackingConfig]
    var entriesFolder: String
    var useCategoryFolders: Bool
    var filenameTemplate: String

    static func from(_ settings: IndividualTrackingSettings) -> IndividualTrackingSnapshot {
        IndividualTrackingSnapshot(
            globalEnabled: settings.globalEnabled,
            metricConfigs: settings.metricConfigs,
            entriesFolder: settings.entriesFolder,
            useCategoryFolders: settings.useCategoryFolders,
            filenameTemplate: settings.filenameTemplate
        )
    }

    func apply(to settings: IndividualTrackingSettings) {
        settings.globalEnabled = globalEnabled
        settings.metricConfigs = metricConfigs
        settings.entriesFolder = entriesFolder
        settings.useCategoryFolders = useCategoryFolders
        settings.filenameTemplate = filenameTemplate
    }
}

// MARK: - Daily Note Injection Snapshot

struct DailyNoteInjectionSnapshot: Codable, Equatable {
    var enabled: Bool
    var folderPath: String
    var filenamePattern: String
    var createIfMissing: Bool
    var injectMarkdownSections: Bool
    var dailyNotesOnly: Bool

    enum CodingKeys: String, CodingKey {
        case enabled, folderPath, filenamePattern, createIfMissing, injectMarkdownSections, dailyNotesOnly
    }

    init(
        enabled: Bool,
        folderPath: String,
        filenamePattern: String,
        createIfMissing: Bool,
        injectMarkdownSections: Bool,
        dailyNotesOnly: Bool = false
    ) {
        self.enabled = enabled
        self.folderPath = folderPath
        self.filenamePattern = filenamePattern
        self.createIfMissing = createIfMissing
        self.injectMarkdownSections = injectMarkdownSections
        self.dailyNotesOnly = dailyNotesOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath) ?? "Daily"
        filenamePattern = try container.decodeIfPresent(String.self, forKey: .filenamePattern) ?? "{date}"
        createIfMissing = try container.decodeIfPresent(Bool.self, forKey: .createIfMissing) ?? false
        injectMarkdownSections = try container.decodeIfPresent(Bool.self, forKey: .injectMarkdownSections) ?? false
        dailyNotesOnly = try container.decodeIfPresent(Bool.self, forKey: .dailyNotesOnly) ?? false
    }

    static func from(_ settings: DailyNoteInjectionSettings) -> DailyNoteInjectionSnapshot {
        DailyNoteInjectionSnapshot(
            enabled: settings.enabled,
            folderPath: settings.folderPath,
            filenamePattern: settings.filenamePattern,
            createIfMissing: settings.createIfMissing,
            injectMarkdownSections: settings.injectMarkdownSections,
            dailyNotesOnly: settings.dailyNotesOnly
        )
    }

    func apply(to settings: DailyNoteInjectionSettings) {
        settings.enabled = enabled
        settings.folderPath = folderPath
        settings.filenamePattern = filenamePattern
        settings.createIfMissing = createIfMissing
        settings.injectMarkdownSections = injectMarkdownSections
        settings.dailyNotesOnly = dailyNotesOnly
    }
}

// MARK: - Metric Selection Snapshot

struct MetricSelectionSnapshot: Codable, Equatable {
    var enabledMetricIDs: Set<String>
    var enabledCategoryIDs: Set<String>

    static func from(_ selection: MetricSelectionState) -> MetricSelectionSnapshot {
        MetricSelectionSnapshot(
            enabledMetricIDs: selection.enabledMetrics,
            enabledCategoryIDs: selection.enabledCategories
        )
    }

    func apply(to selection: MetricSelectionState) {
        selection.enabledMetrics = enabledMetricIDs
        selection.enabledCategories = enabledCategoryIDs
    }
}

import Foundation

/// Explicit mutation policy for importing selected profiles from a validated
/// Shared Setup v2 plan.
enum SharedSetupV2TransactionMode: String, Codable, Equatable, Sendable {
    case add
    case replace
}

enum SharedSetupV2TransactionError: LocalizedError, Equatable {
    case invalidSelection(String)
    case invalidPersistedState
    case sidecarTooLarge
    case undoTooLarge
    case persistenceVerificationFailed
    case rollbackVerificationFailed
    case noUndoSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidSelection(let reason):
            reason
        case .invalidPersistedState:
            "Health.md could not safely read the existing profile configuration."
        case .sidecarTooLarge:
            "The selected setup profile state is larger than 4 MiB."
        case .undoTooLarge:
            "The complete local Undo snapshot is larger than 8 MiB."
        case .persistenceVerificationFailed:
            "Health.md could not verify the imported profiles and restored the previous configuration."
        case .rollbackVerificationFailed:
            "Health.md could not verify rollback of the imported profiles."
        case .noUndoSnapshot:
            "There is no Shared Setup v2 import to undo."
        }
    }
}

/// Bounded Apple sidecar retaining meanings that cannot safely live in native
/// profile or schedule fields. Rows follow native profile-store order.
struct SharedSetupV2AppleProfileState: Codable, Equatable, Sendable {
    nonisolated static let currentVersion = 1

    var version: Int
    var profiles: [Profile]

    init(version: Int = currentVersion, profiles: [Profile]) {
        self.version = version
        self.profiles = profiles
    }

    struct Profile: Codable, Equatable, Sendable {
        var profileID: UUID
        var sourceBundleID: String
        var sourceProfile: SharedSetupV2.Profile
        var unsupportedSemanticIDs: [String]

        enum CodingKeys: String, CodingKey {
            case profileID = "profile_id"
            case sourceBundleID = "source_bundle_id"
            case sourceProfile = "source_profile"
            case unsupportedSemanticIDs = "unsupported_semantic_ids"
        }
    }
}

struct SharedSetupV2TransactionResult: Equatable, Sendable {
    var mode: SharedSetupV2TransactionMode
    var importedProfileIDs: [UUID]
    var activeProfileID: UUID?
    var importedScheduleCount: Int
}

struct SharedSetupV2UndoResult: Equatable, Sendable {
    var restoredProfileIDs: [UUID]
    var activeProfileID: UUID?
    var restoredScheduleCount: Int
}

/// Pure selection and materialization helpers. They never touch defaults,
/// destination stores, Keychain, automation, or live settings.
enum SharedSetupV2AppleProfileMaterializer {
    static func normalizedSelection(
        from plan: SharedSetupV2ImportPlan,
        selectedBundleIDs: [String]
    ) throws -> [SharedSetupV2ProfileImportPlan] {
        do {
            try SharedSetupV2Validation.validate(plan.document)
        } catch {
            throw SharedSetupV2TransactionError.invalidSelection(
                "The Shared Setup v2 import plan is not valid."
            )
        }
        guard !plan.hasInvalidItems else {
            throw SharedSetupV2TransactionError.invalidSelection(
                "The Shared Setup v2 import plan contains invalid items."
            )
        }
        guard !selectedBundleIDs.isEmpty else {
            throw SharedSetupV2TransactionError.invalidSelection(
                "Select at least one setup profile."
            )
        }
        guard Set(selectedBundleIDs).count == selectedBundleIDs.count else {
            throw SharedSetupV2TransactionError.invalidSelection(
                "The selected setup profile IDs must be unique."
            )
        }

        let documentIDs = plan.document.profiles.map(\.bundleID)
        let planIDs = plan.profiles.map(\.bundleID)
        guard planIDs == documentIDs,
              Set(planIDs).count == planIDs.count,
              plan.activeBundleID == plan.document.activeProfile else {
            throw SharedSetupV2TransactionError.invalidSelection(
                "The Shared Setup v2 import plan order is ambiguous."
            )
        }
        let knownIDs = Set(planIDs)
        guard selectedBundleIDs.allSatisfy(knownIDs.contains) else {
            throw SharedSetupV2TransactionError.invalidSelection(
                "A selected setup profile is unknown."
            )
        }

        for (profilePlan, sourceProfile) in zip(plan.profiles, plan.document.profiles) {
            guard profilePlan.bundleID == sourceProfile.bundleID,
                  profilePlan.name == sourceProfile.name,
                  profilePlan.destinationIntent == sourceProfile.destination,
                  profilePlan.scheduleIntent == sourceProfile.schedule,
                  profilePlan.supportedMetricSelectionIDs ==
                    Array(Set(profilePlan.supportedMetricSelectionIDs)).sorted(),
                  profilePlan.unsupportedPreservedSemanticIDs ==
                    Array(Set(profilePlan.unsupportedPreservedSemanticIDs)).sorted() else {
                throw SharedSetupV2TransactionError.invalidSelection(
                    "The Shared Setup v2 import plan does not match its source document."
                )
            }
        }

        let selected = Set(selectedBundleIDs)
        return plan.profiles.filter { selected.contains($0.bundleID) }
    }

    static func profile(
        source: SharedSetupV2.Profile,
        plan: SharedSetupV2ProfileImportPlan,
        nativeID: UUID,
        name: String,
        now: Date
    ) -> ExportProfile {
        let apple = source.platformExtensions.apple
        let markdown: MarkdownTemplateConfig
        if plan.installCustomTemplate {
            markdown = MarkdownTemplateConfig(
                style: nativeMarkdownStyle(source.presentation.markdown.style),
                customTemplate: source.presentation.markdown.customText,
                sectionHeaderLevel: source.presentation.markdown.headerLevel,
                useEmoji: source.presentation.markdown.useEmoji,
                includeSummary: source.presentation.markdown.includeSummary,
                bulletStyle: nativeBulletStyle(source.presentation.markdown.bulletStyle)
            )
        } else {
            // There is no pre-existing local value for a fresh profile. Keep
            // the unsupported source text/style only in the sidecar and use
            // the inert native standard text rather than reinterpreting foreign
            // placeholders. Orthogonal, exactly supported presentation fields
            // still retain their source meanings.
            let standard = MarkdownTemplateConfig()
            markdown = MarkdownTemplateConfig(
                style: .standard,
                customTemplate: standard.customTemplate,
                sectionHeaderLevel: source.presentation.markdown.headerLevel,
                useEmoji: source.presentation.markdown.useEmoji,
                includeSummary: source.presentation.markdown.includeSummary,
                bulletStyle: nativeBulletStyle(source.presentation.markdown.bulletStyle)
            )
        }

        let settings = ExportSettingsSnapshot(
            exportFormats: Set(source.export.formats.map(nativeFormat)),
            includeMetadata: source.export.includeMetadata,
            groupByCategory: source.export.groupByCategory,
            filenameFormat: source.export.filenameTemplate,
            folderStructure: source.export.folderTemplate,
            healthSubfolder: nil,
            organizeFormatsIntoFolders: apple?.export.organizeFormatsIntoFolders ?? false,
            archiveExportFiles: apple?.export.archiveFiles ?? false,
            includeDataDictionary: apple?.export.includeDataDictionary ?? true,
            summaryOnlyExport: apple?.export.summaryOnly ?? false,
            writeMode: nativeWriteMode(source.export.writeMode),
            formatCustomization: FormatCustomizationSnapshot(
                dateFormat: nativeDateFormat(source.presentation.dateFormat),
                timeFormat: nativeTimeFormat(source.presentation.timeFormat),
                unitPreference: source.presentation.units == .metric ? .metric : .imperial,
                frontmatterConfig: FrontmatterConfigurationSnapshot(
                    fields: source.presentation.frontmatter.fields.map {
                        CustomFrontmatterField(
                            originalKey: $0.sourceKey,
                            customKey: $0.outputKey,
                            isEnabled: $0.enabled
                        )
                    },
                    customFields: source.presentation.frontmatter.customValues,
                    placeholderFields: source.presentation.frontmatter.placeholders,
                    includeDate: source.presentation.frontmatter.includeDate,
                    includeType: source.presentation.frontmatter.includeType,
                    customDateKey: source.presentation.frontmatter.dateKey,
                    customTypeKey: source.presentation.frontmatter.typeKey,
                    customTypeValue: source.presentation.frontmatter.typeValue,
                    keyStyle: source.presentation.frontmatter.keyStyle == .snakeCase
                        ? .snakeCase : .camelCase
                ),
                markdownTemplate: markdown
            ),
            individualTracking: IndividualTrackingSnapshot(
                globalEnabled: source.individualEntries.enabled,
                metricConfigs: Dictionary(uniqueKeysWithValues: plan.supportedIndividualMetrics.map {
                    ($0.nativeSelectionID, MetricTrackingConfig(
                        trackIndividually: $0.configuration.enabled,
                        customFolder: $0.configuration.customFolder
                    ))
                }),
                entriesFolder: source.individualEntries.entriesFolder,
                useCategoryFolders: source.individualEntries.organizeByCategory,
                filenameTemplate: source.individualEntries.filenameTemplate
            ),
            dailyNoteInjection: DailyNoteInjectionSnapshot(
                enabled: source.dailyNotes.enabled,
                folderPath: source.dailyNotes.folder,
                filenamePattern: source.dailyNotes.filenameTemplate,
                createIfMissing: source.dailyNotes.createIfMissing,
                injectMarkdownSections: source.dailyNotes.injectSections,
                dailyNotesOnly: apple?.dailyNotes.only ?? false
            ),
            includeGranularData: false,
            compatibilityDetail: source.export.compatibilityDetail == .selectedTimeSeries
                ? .selectedTimeSeries : .summary,
            healthKitSourceArchivePolicy: apple?.export.healthKitSourceArchive == .canonicalV1
                ? .canonicalV1 : HealthKitSourceArchivePolicy.none,
            generateRangeSummary: apple?.export.generateRangeSummary ?? false,
            metricSelection: MetricSelectionSnapshot(
                enabledMetricIDs: Set(plan.supportedMetricSelectionIDs),
                enabledCategoryIDs: []
            ),
            appleExportEnginePin: nil,
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: nil
        )

        return ExportProfile(
            id: nativeID,
            name: name,
            settings: settings,
            target: nativeTarget(source.destination.kind),
            folderVaultID: nil,
            apiEndpointID: nil,
            createdAt: now,
            updatedAt: now,
            isMigrationDefault: false
        )
    }

    static func schedule(
        source: SharedSetupV2.Profile,
        plan: SharedSetupV2ProfileImportPlan,
        nativeProfileID: UUID,
        nativeScheduleID: UUID,
        calendar: Calendar
    ) throws -> ScheduledExportEntry? {
        guard let intent = source.schedule else {
            guard source.platformExtensions.apple?.schedule == nil else {
                throw SharedSetupV2TransactionError.invalidSelection(
                    "The common and Apple schedule meanings contradict each other."
                )
            }
            return nil
        }
        guard plan.scheduleCanApplyExactly else { return nil }
        guard intent.lookbackDays <= ExportSchedule.maximumLookbackDays,
              let anchor = dateOnly(intent.cadence.anchorDate, calendar: calendar) else {
            return nil
        }

        let frequency: ScheduleFrequency
        let customUnit: ScheduleIntervalUnit
        let todayRefreshEnabled: Bool
        let todayRefreshIntervalHours: Int
        if let apple = source.platformExtensions.apple?.schedule {
            switch apple.frequency {
            case .daily:
                guard intent.cadence.value == 1, intent.cadence.unit == .days else {
                    throw scheduleContradiction()
                }
                frequency = .daily
            case .weekly:
                guard intent.cadence.value == 1, intent.cadence.unit == .weeks else {
                    throw scheduleContradiction()
                }
                frequency = .weekly
            case .custom:
                guard intent.cadence.unit.rawValue == apple.customUnit.rawValue else {
                    throw scheduleContradiction()
                }
                frequency = .custom
            }
            customUnit = nativeCustomUnit(apple.customUnit)
            todayRefreshEnabled = apple.todayRefreshRequested
            todayRefreshIntervalHours = apple.todayRefreshIntervalHours
        } else {
            if intent.cadence.value == 1, intent.cadence.unit == .days {
                frequency = .daily
            } else if intent.cadence.value == 1, intent.cadence.unit == .weeks {
                frequency = .weekly
            } else {
                frequency = .custom
            }
            customUnit = nativeCustomUnit(intent.cadence.unit)
            todayRefreshEnabled = false
            todayRefreshIntervalHours = ExportSchedule.defaultTodayRefreshIntervalHours
        }

        let entry = ScheduledExportEntry(
            id: nativeScheduleID,
            profileID: nativeProfileID,
            isEnabled: false,
            frequency: frequency,
            customInterval: intent.cadence.value,
            customUnit: customUnit,
            customAnchorDate: anchor,
            preferredHour: intent.localTime.hour,
            preferredMinute: intent.localTime.minute,
            weekday: intent.weekday,
            lookbackDays: intent.lookbackDays,
            todayRefreshEnabled: todayRefreshEnabled,
            todayRefreshIntervalHours: todayRefreshIntervalHours,
            lastExportDate: nil,
            lastTodayRefreshDate: nil,
            enabledAt: nil
        )
        guard !entry.isEnabled,
              entry.enabledAt == nil,
              entry.lastExportDate == nil,
              entry.lastTodayRefreshDate == nil else {
            throw SharedSetupV2TransactionError.invalidSelection(
                "The imported schedule could not be made inert."
            )
        }
        return entry
    }

    private static func scheduleContradiction() -> SharedSetupV2TransactionError {
        .invalidSelection("The common and Apple schedule meanings contradict each other.")
    }

    private static func dateOnly(_ value: String, calendar: Calendar) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        )
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == parts[0], roundTrip.month == parts[1], roundTrip.day == parts[2] else {
            return nil
        }
        return date
    }

    private static func nativeTarget(_ value: SharedSetupV2.DestinationKind) -> ExportTargetSelection {
        switch value {
        case .deviceFolder, .cloud: .localIPhoneFolder
        case .connectedMac: .connectedMac
        case .apiEndpoint: .apiEndpoint
        }
    }

    nonisolated private static func nativeFormat(_ value: SharedSetupV2.Format) -> ExportFormat {
        switch value {
        case .csv: .csv
        case .json: .json
        case .markdown: .markdown
        case .obsidianBases: .obsidianBases
        }
    }

    private static func nativeWriteMode(_ value: SharedSetupV2.SharedWriteMode) -> WriteMode {
        switch value {
        case .overwrite: .overwrite
        case .append: .append
        case .update: .update
        }
    }

    private static func nativeDateFormat(_ value: SharedSetupV2.DateFormat) -> DateFormatPreference {
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

    private static func nativeTimeFormat(_ value: SharedSetupV2.TimeFormat) -> TimeFormatPreference {
        switch value {
        case .hour24: .hour24
        case .hour24Seconds: .hour24WithSeconds
        case .hour12: .hour12
        case .hour12Seconds: .hour12WithSeconds
        }
    }

    private static func nativeMarkdownStyle(_ value: SharedSetupV2.MarkdownStyle) -> MarkdownTemplateStyle {
        switch value {
        case .standard: .standard
        case .compact: .compact
        case .detailed: .detailed
        case .custom: .custom
        }
    }

    private static func nativeBulletStyle(
        _ value: SharedSetupV2.BulletStyle
    ) -> MarkdownTemplateConfig.BulletStyle {
        switch value {
        case .dash: .dash
        case .asterisk: .asterisk
        case .plus: .plus
        }
    }

    private static func nativeCustomUnit(_ value: SharedSetupV2.AppleCustomUnit) -> ScheduleIntervalUnit {
        switch value {
        case .days: .day
        case .weeks: .week
        case .months: .month
        }
    }

    private static func nativeCustomUnit(_ value: SharedSetupV2.CadenceUnit) -> ScheduleIntervalUnit {
        switch value {
        case .days: .day
        case .weeks: .week
        case .months: .month
        }
    }
}

@MainActor
final class SharedSetupV2ProfileTransaction {
    nonisolated deinit {}

    static let profileListKey = "exportProfiles.list"
    static let activeProfileIDKey = "exportProfiles.activeProfileID"
    static let scheduledEntriesKey = "scheduledExportEntries.list"
    static let profileStateKey = "sharedSetup.apple.v2.profileState"
    static let blockedProfileIDsKey = "sharedSetup.apple.v2.blockedProfileIDs"
    static let undoKey = "sharedSetup.apple.v2.undo"
    static let maximumProfileStateBytes = 4_194_304
    static let maximumUndoBytes = 8_388_608

    private let userDefaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let makeProfileID: () -> UUID
    private let makeScheduleID: () -> UUID
    private let verificationOverride: (() -> Bool)?

    init(
        userDefaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        makeProfileID: @escaping () -> UUID = UUID.init,
        makeScheduleID: @escaping () -> UUID = UUID.init,
        verificationOverride: (() -> Bool)? = nil
    ) {
        self.userDefaults = userDefaults
        self.now = now
        self.calendar = calendar
        self.makeProfileID = makeProfileID
        self.makeScheduleID = makeScheduleID
        self.verificationOverride = verificationOverride
    }

    var canUndo: Bool {
        guard let data = userDefaults.data(forKey: Self.undoKey),
              data.count <= Self.maximumUndoBytes,
              let snapshot = try? decoder().decode(UndoSnapshot.self, from: data) else {
            return false
        }
        return snapshot.version == UndoSnapshot.currentVersion &&
            (try? decodeState(snapshot.raw)) != nil
    }

    func apply(
        _ plan: SharedSetupV2ImportPlan,
        selectedBundleIDs: [String],
        mode: SharedSetupV2TransactionMode
    ) throws -> SharedSetupV2TransactionResult {
        let selectedPlans = try SharedSetupV2AppleProfileMaterializer.normalizedSelection(
            from: plan,
            selectedBundleIDs: selectedBundleIDs
        )
        let prior = try readState()
        let previousUndo = try rawDataOrAbsence(forKey: Self.undoKey)
        let sourceByID = Dictionary(
            uniqueKeysWithValues: plan.document.profiles.map { ($0.bundleID, $0) }
        )

        let priorProfileIDs = Set(prior.profiles.map(\.id))
        let priorScheduleIDs = Set(prior.schedules.map(\.id))
        var generatedProfileIDs = Set<UUID>()
        var generatedScheduleIDs = Set<UUID>()
        var importedProfiles: [ExportProfile] = []
        var importedSchedules: [ScheduledExportEntry] = []
        var importedSidecarRows: [SharedSetupV2AppleProfileState.Profile] = []
        var sourceToNative: [String: UUID] = [:]

        for selected in selectedPlans {
            guard let source = sourceByID[selected.bundleID] else {
                throw SharedSetupV2TransactionError.invalidSelection(
                    "A selected setup profile is missing from its source document."
                )
            }
            let profileID = makeProfileID()
            guard !priorProfileIDs.contains(profileID),
                  generatedProfileIDs.insert(profileID).inserted else {
                throw SharedSetupV2TransactionError.invalidSelection(
                    "Health.md could not create fresh native profile identities."
                )
            }
            sourceToNative[selected.bundleID] = profileID
            let importedName: String
            switch mode {
            case .add:
                importedName = Self.uniquified(
                    source.name,
                    against: prior.profiles.map(\.name) + importedProfiles.map(\.name)
                )
            case .replace:
                importedName = source.name
            }
            let timestamp = now()
            importedProfiles.append(SharedSetupV2AppleProfileMaterializer.profile(
                source: source,
                plan: selected,
                nativeID: profileID,
                name: importedName,
                now: timestamp
            ))

            if source.schedule != nil, selected.scheduleCanApplyExactly {
                let scheduleID = makeScheduleID()
                guard !priorScheduleIDs.contains(scheduleID),
                      generatedScheduleIDs.insert(scheduleID).inserted else {
                    throw SharedSetupV2TransactionError.invalidSelection(
                        "Health.md could not create fresh native schedule identities."
                    )
                }
                if let schedule = try SharedSetupV2AppleProfileMaterializer.schedule(
                    source: source,
                    plan: selected,
                    nativeProfileID: profileID,
                    nativeScheduleID: scheduleID,
                    calendar: calendar
                ) {
                    importedSchedules.append(schedule)
                }
            }
            importedSidecarRows.append(.init(
                profileID: profileID,
                sourceBundleID: source.bundleID,
                sourceProfile: source,
                unsupportedSemanticIDs: selected.unsupportedPreservedSemanticIDs.sorted()
            ))
        }

        let candidateProfiles: [ExportProfile]
        let candidateSchedules: [ScheduledExportEntry]
        let candidateRows: [SharedSetupV2AppleProfileState.Profile]
        let candidateBlockedIDs: [UUID]
        let activeProfileID: UUID
        switch mode {
        case .add:
            candidateProfiles = prior.profiles + importedProfiles
            candidateSchedules = prior.schedules + importedSchedules
            candidateRows = prior.sidecar.profiles + importedSidecarRows
            candidateBlockedIDs = Self.orderedUnique(
                prior.blockedProfileIDs + importedProfiles.map(\.id),
                profileOrder: candidateProfiles.map(\.id)
            )
            if let priorActive = prior.activeProfileID,
               prior.profiles.contains(where: { $0.id == priorActive }) {
                activeProfileID = priorActive
            } else if let importedActive = sourceToNative[plan.activeBundleID] {
                activeProfileID = importedActive
            } else {
                activeProfileID = importedProfiles[0].id
            }
        case .replace:
            candidateProfiles = importedProfiles
            candidateSchedules = importedSchedules
            candidateRows = importedSidecarRows
            candidateBlockedIDs = importedProfiles.map(\.id)
            activeProfileID = sourceToNative[plan.activeBundleID] ?? importedProfiles[0].id
        }

        let candidateProfileIDs = Set(candidateProfiles.map(\.id))
        guard candidateProfileIDs.count == candidateProfiles.count,
              candidateProfiles.contains(where: { $0.id == activeProfileID }),
              candidateSchedules.count <= ScheduledExportEntryStore.maximumScheduledEntries,
              Set(candidateSchedules.map(\.id)).count == candidateSchedules.count,
              Set(candidateSchedules.map(\.profileID)).count == candidateSchedules.count,
              candidateSchedules.allSatisfy({ candidateProfileIDs.contains($0.profileID) }) else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }

        let sidecar = SharedSetupV2AppleProfileState(
            profiles: Self.rowsInProfileOrder(candidateRows, profiles: candidateProfiles)
        )
        try Self.validate(sidecar, profileIDs: candidateProfileIDs)
        let sidecarData = try encoder().encode(sidecar)
        guard sidecarData.count <= Self.maximumProfileStateBytes else {
            throw SharedSetupV2TransactionError.sidecarTooLarge
        }
        let blockedData = try Self.encodeBlockedProfileIDs(candidateBlockedIDs)
        let profileData = try encoder().encode(candidateProfiles)
        let scheduleData = try encoder().encode(candidateSchedules)
        let undoData = try encoder().encode(prior.undoSnapshot)
        guard undoData.count <= Self.maximumUndoBytes else {
            throw SharedSetupV2TransactionError.undoTooLarge
        }

        let candidate = RawState(
            profiles: profileData,
            activeProfileID: activeProfileID.uuidString,
            schedules: scheduleData,
            profileState: sidecarData,
            blockedProfileIDs: blockedData
        )
        do {
            write(candidate)
            userDefaults.set(undoData, forKey: Self.undoKey)
            _ = userDefaults.synchronize()
            guard matches(candidate),
                  userDefaults.data(forKey: Self.undoKey) == undoData,
                  verificationOverride?() ?? true else {
                throw SharedSetupV2TransactionError.persistenceVerificationFailed
            }
        } catch {
            let originalError = error
            write(prior.raw)
            restoreRawData(previousUndo, forKey: Self.undoKey)
            _ = userDefaults.synchronize()
            guard matches(prior.raw), rawDataOrNil(forKey: Self.undoKey) == previousUndo else {
                throw SharedSetupV2TransactionError.rollbackVerificationFailed
            }
            throw originalError
        }

        return SharedSetupV2TransactionResult(
            mode: mode,
            importedProfileIDs: importedProfiles.map(\.id),
            activeProfileID: activeProfileID,
            importedScheduleCount: importedSchedules.count
        )
    }

    func undo() throws -> SharedSetupV2UndoResult {
        guard let undoData = userDefaults.data(forKey: Self.undoKey),
              undoData.count <= Self.maximumUndoBytes,
              let snapshot = try? decoder().decode(UndoSnapshot.self, from: undoData),
              snapshot.version == UndoSnapshot.currentVersion else {
            throw SharedSetupV2TransactionError.noUndoSnapshot
        }
        let target = snapshot.raw
        // Undo data is locally generated, but it is still durable input. Prove
        // the full aggregate is decodable and internally consistent before
        // replacing any live key or consuming the one-shot snapshot.
        let restored: DecodedState
        do {
            restored = try decodeState(target)
        } catch {
            throw SharedSetupV2TransactionError.noUndoSnapshot
        }
        let current = try readState()

        do {
            write(target)
            _ = userDefaults.synchronize()
            guard matches(target) else {
                throw SharedSetupV2TransactionError.persistenceVerificationFailed
            }
            userDefaults.removeObject(forKey: Self.undoKey)
            _ = userDefaults.synchronize()
            guard userDefaults.object(forKey: Self.undoKey) == nil else {
                throw SharedSetupV2TransactionError.persistenceVerificationFailed
            }
        } catch {
            write(current.raw)
            userDefaults.set(undoData, forKey: Self.undoKey)
            _ = userDefaults.synchronize()
            guard matches(current.raw), userDefaults.data(forKey: Self.undoKey) == undoData else {
                throw SharedSetupV2TransactionError.rollbackVerificationFailed
            }
            throw error
        }

        return SharedSetupV2UndoResult(
            restoredProfileIDs: restored.profiles.map(\.id),
            activeProfileID: restored.activeProfileID,
            restoredScheduleCount: restored.schedules.count
        )
    }

    private struct DecodedState {
        var raw: RawState
        var profiles: [ExportProfile]
        var activeProfileID: UUID?
        var schedules: [ScheduledExportEntry]
        var sidecar: SharedSetupV2AppleProfileState
        var blockedProfileIDs: [UUID]

        var undoSnapshot: UndoSnapshot {
            UndoSnapshot(
                profiles: raw.profiles,
                activeProfileID: raw.activeProfileID,
                schedules: raw.schedules,
                profileState: raw.profileState,
                blockedProfileIDs: raw.blockedProfileIDs
            )
        }
    }

    private struct RawState: Equatable {
        var profiles: Data?
        var activeProfileID: String?
        var schedules: Data?
        var profileState: Data?
        var blockedProfileIDs: Data?
    }

    private struct UndoSnapshot: Codable, Equatable {
        nonisolated static let currentVersion = 1

        var version: Int
        var profiles: Data?
        var activeProfileID: String?
        var schedules: Data?
        var profileState: Data?
        var blockedProfileIDs: Data?

        init(
            version: Int = currentVersion,
            profiles: Data?,
            activeProfileID: String?,
            schedules: Data?,
            profileState: Data?,
            blockedProfileIDs: Data?
        ) {
            self.version = version
            self.profiles = profiles
            self.activeProfileID = activeProfileID
            self.schedules = schedules
            self.profileState = profileState
            self.blockedProfileIDs = blockedProfileIDs
        }

        var raw: RawState {
            RawState(
                profiles: profiles,
                activeProfileID: activeProfileID,
                schedules: schedules,
                profileState: profileState,
                blockedProfileIDs: blockedProfileIDs
            )
        }
    }

    private func readState() throws -> DecodedState {
        try decodeState(RawState(
            profiles: rawDataOrAbsence(forKey: Self.profileListKey),
            activeProfileID: rawStringOrAbsence(forKey: Self.activeProfileIDKey),
            schedules: rawDataOrAbsence(forKey: Self.scheduledEntriesKey),
            profileState: rawDataOrAbsence(forKey: Self.profileStateKey),
            blockedProfileIDs: rawDataOrAbsence(forKey: Self.blockedProfileIDsKey)
        ))
    }

    private func decodeState(_ raw: RawState) throws -> DecodedState {
        let profiles: [ExportProfile]
        let schedules: [ScheduledExportEntry]
        let sidecar: SharedSetupV2AppleProfileState
        let blocked: [UUID]
        do {
            profiles = try raw.profiles.map {
                try decoder().decode([ExportProfile].self, from: $0)
            } ?? []
            schedules = try raw.schedules.map {
                try decoder().decode([ScheduledExportEntry].self, from: $0)
            } ?? []
            sidecar = try raw.profileState.map {
                guard $0.count <= Self.maximumProfileStateBytes else {
                    throw SharedSetupV2TransactionError.sidecarTooLarge
                }
                return try decoder().decode(SharedSetupV2AppleProfileState.self, from: $0)
            } ?? SharedSetupV2AppleProfileState(profiles: [])
            blocked = try raw.blockedProfileIDs.map(Self.decodeBlockedProfileIDs) ?? []
        } catch let error as SharedSetupV2TransactionError {
            throw error
        } catch {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        let profileIDs = Set(profiles.map(\.id))
        guard profileIDs.count == profiles.count,
              schedules.count <= ScheduledExportEntryStore.maximumScheduledEntries,
              Set(schedules.map(\.id)).count == schedules.count,
              Set(schedules.map(\.profileID)).count == schedules.count,
              schedules.allSatisfy({ profileIDs.contains($0.profileID) }) else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        // Deleted profiles can leave old cycle-2 rows in builds without the
        // final UI adapter. Treat those rows as deleted state, but never retain
        // a blocked ID without its bounded source row.
        let liveRows = sidecar.profiles.filter { profileIDs.contains($0.profileID) }
        let liveSidecar = SharedSetupV2AppleProfileState(profiles: liveRows)
        let liveBlocked = blocked.filter { profileIDs.contains($0) }
        try Self.validate(liveSidecar, profileIDs: profileIDs)
        guard Set(liveBlocked).isSubset(of: Set(liveRows.map(\.profileID))) else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        let active = raw.activeProfileID.flatMap(UUID.init(uuidString:))
        return DecodedState(
            raw: raw,
            profiles: profiles,
            activeProfileID: active,
            schedules: schedules,
            sidecar: liveSidecar,
            blockedProfileIDs: liveBlocked
        )
    }

    private func write(_ state: RawState) {
        restoreRawData(state.profiles, forKey: Self.profileListKey)
        if let activeProfileID = state.activeProfileID {
            userDefaults.set(activeProfileID, forKey: Self.activeProfileIDKey)
        } else {
            userDefaults.removeObject(forKey: Self.activeProfileIDKey)
        }
        restoreRawData(state.schedules, forKey: Self.scheduledEntriesKey)
        restoreRawData(state.profileState, forKey: Self.profileStateKey)
        restoreRawData(state.blockedProfileIDs, forKey: Self.blockedProfileIDsKey)
    }

    private func matches(_ state: RawState) -> Bool {
        rawDataOrNil(forKey: Self.profileListKey) == state.profiles &&
            rawStringOrNil(forKey: Self.activeProfileIDKey) == state.activeProfileID &&
            rawDataOrNil(forKey: Self.scheduledEntriesKey) == state.schedules &&
            rawDataOrNil(forKey: Self.profileStateKey) == state.profileState &&
            rawDataOrNil(forKey: Self.blockedProfileIDsKey) == state.blockedProfileIDs
    }

    private func rawDataOrAbsence(forKey key: String) throws -> Data? {
        guard let object = userDefaults.object(forKey: key) else { return nil }
        guard let data = object as? Data else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        return data
    }

    private func rawStringOrAbsence(forKey key: String) throws -> String? {
        guard let object = userDefaults.object(forKey: key) else { return nil }
        guard let string = object as? String else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        return string
    }

    private func rawDataOrNil(forKey key: String) -> Data? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.data(forKey: key)
    }

    private func rawStringOrNil(forKey key: String) -> String? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return userDefaults.string(forKey: key)
    }

    private func restoreRawData(_ value: Data?, forKey key: String) {
        if let value { userDefaults.set(value, forKey: key) }
        else { userDefaults.removeObject(forKey: key) }
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func decoder() -> JSONDecoder { JSONDecoder() }

    static func encodeBlockedProfileIDs(_ ids: [UUID]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(ids.map { $0.uuidString.lowercased() })
    }

    static func decodeBlockedProfileIDs(_ data: Data) throws -> [UUID] {
        guard data.count <= maximumProfileStateBytes,
              let values = try? JSONDecoder().decode([String].self, from: data),
              values.count == Set(values).count else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        let ids = values.compactMap(UUID.init(uuidString:))
        guard ids.count == values.count, Set(ids).count == ids.count else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        return ids
    }

    static func decodeProfileState(_ data: Data) throws -> SharedSetupV2AppleProfileState {
        guard data.count <= maximumProfileStateBytes,
              let value = try? JSONDecoder().decode(SharedSetupV2AppleProfileState.self, from: data),
              value.version == SharedSetupV2AppleProfileState.currentVersion else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
        return value
    }

    private static func validate(
        _ state: SharedSetupV2AppleProfileState,
        profileIDs: Set<UUID>
    ) throws {
        let rowIDs = state.profiles.map(\.profileID)
        guard state.version == SharedSetupV2AppleProfileState.currentVersion,
              Set(rowIDs).count == rowIDs.count,
              Set(rowIDs).isSubset(of: profileIDs),
              state.profiles.allSatisfy({ row in
                  row.sourceBundleID == row.sourceProfile.bundleID &&
                      row.unsupportedSemanticIDs ==
                        Array(Set(row.unsupportedSemanticIDs)).sorted() &&
                      row.unsupportedSemanticIDs.allSatisfy(
                        SharedSetupV2Validation.isIdentifier
                      )
              }) else {
            throw SharedSetupV2TransactionError.invalidPersistedState
        }
    }

    private static func rowsInProfileOrder(
        _ rows: [SharedSetupV2AppleProfileState.Profile],
        profiles: [ExportProfile]
    ) -> [SharedSetupV2AppleProfileState.Profile] {
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.profileID, $0) })
        return profiles.compactMap { byID[$0.id] }
    }

    private static func orderedUnique(_ ids: [UUID], profileOrder: [UUID]) -> [UUID] {
        let selected = Set(ids)
        return profileOrder.filter(selected.contains)
    }

    private static func uniquified(_ base: String, against existingNames: [String]) -> String {
        let existing = Set(existingNames.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        guard existing.contains(base.lowercased()) else { return base }
        var counter = 2
        while existing.contains("\(base) \(counter)".lowercased()) {
            counter += 1
        }
        return "\(base) \(counter)"
    }
}

private extension MarkdownTemplateConfig {
    init(
        style: MarkdownTemplateStyle,
        customTemplate: String,
        sectionHeaderLevel: Int,
        useEmoji: Bool,
        includeSummary: Bool,
        bulletStyle: BulletStyle
    ) {
        self.style = style
        self.customTemplate = customTemplate
        self.sectionHeaderLevel = sectionHeaderLevel
        self.useEmoji = useEmoji
        self.includeSummary = includeSummary
        self.bulletStyle = bulletStyle
    }
}

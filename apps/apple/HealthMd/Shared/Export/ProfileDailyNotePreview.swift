import Foundation

/// The daily note a saved profile writes for one day, built the way Export Preview builds
/// it (#345): the same accepted capture clock, frozen operation, calendar time zone and
/// injector, and for Morning ends the same accepted plan. The automation composer shows it.
///
/// It previews a fresh note. Export Preview merges into the note on disk; this does not read
/// the vault, because a profile may write to a different folder than the active vault.
@MainActor
enum ProfileDailyNotePreview {
    /// Why no note could be shown. Each case names its real cause, so a failure is never
    /// reported as missing Apple Health access.
    enum Issue: Equatable, Sendable {
        /// Apple Health access hasn't been granted.
        case healthAccess
        /// The profile's sleep day or calendar couldn't be accepted for a new export.
        case captureSettings
        /// Apple Health couldn't be read for the day.
        case healthData
        /// A Morning ends note needs the vault's renderer, which isn't available here.
        case rendererUnavailable
        /// The renderer couldn't prepare this day's note.
        case notePreparation
        /// The injector wrote nothing, with its own reason (for example no data).
        case skipped(String)

        var message: String {
            switch self {
            case .healthAccess:
                return String(localized: "Connect Apple Health to see this file rendered.")
            case .captureSettings:
                return String(localized: "This profile’s sleep day or time zone can’t be used for a new export, so its daily note can’t be previewed.")
            case .healthData:
                return String(localized: "Apple Health data for this day couldn’t be read.")
            case .rendererUnavailable:
                return String(localized: "This daily note can’t be previewed here.")
            case .notePreparation:
                return String(localized: "This day’s daily note couldn’t be prepared for preview.")
            case .skipped(let reason):
                return reason
            }
        }
    }

    enum Outcome: Equatable {
        case note(path: String, content: String)
        case unavailable(Issue)
    }

    typealias Fetch = (_ date: Date, _ context: AppleSleepCaptureContext, _ settings: AdvancedExportSettings)
        async throws -> HealthData

    /// Export Preview's calendar time zone, `exportTimeZoneOverride ?? .current`, for a profile.
    /// Loading a profile sets the override from its calendar identifier
    /// (`AdvancedExportSettings.apply(snapshot:)`), so this is the zone Export Preview uses.
    static func timeZone(for settings: ExportSettingsSnapshot) -> TimeZone {
        settings.calendarTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// The vault-relative path of the profile's note for `date`, in the preview's time zone.
    static func notePath(for settings: ExportSettingsSnapshot, date: Date) -> String {
        let note = DailyNoteInjectionSettings()
        settings.dailyNoteInjection.apply(to: note)
        return ExportPathPlanner.dailyNoteRelativePath(settings: note, date: date, timeZone: Self.timeZone(for: settings))
    }

    /// - Parameter fetch: Reads the day's record; by default Apple Health through
    ///   `healthKitManager`, which must be authorized.
    static func render(
        settings: ExportSettingsSnapshot,
        date: Date,
        healthKitManager: HealthKitManager,
        vaultManager: VaultManager?,
        userDefaults: UserDefaults = ExportSettingsSnapshot.makeTemporaryUserDefaults(),
        fetch: Fetch? = nil
    ) async -> Outcome {
        // A profile is configuration, not a saved operation: start new capture authority.
        let draft = settings.makeAdvancedExportSettings(userDefaults: userDefaults, forNewConfiguration: true)
        let timeZone = Self.timeZone(for: settings)
        draft.exportTimeZoneOverride = timeZone
        // Accept the capture clock first, as Export Preview does. Provider sidecars are not
        // part of a daily note, so this preview never opens a provider capture.
        guard let context = try? healthKitManager.resolveSleepCaptureContext(settings: draft, timeZone: timeZone),
              let accepted = try? AcceptedExternalProviderFileCapture(settings: draft, context: context,
                healthSubfolder: settings.healthSubfolder, includesProviders: false, providers: nil)
        else { return .unavailable(.captureSettings) }
        let acceptedSettings = accepted.snapshot.makeAdvancedExportSettings()
        acceptedSettings.executionSleepCaptureContextIsFrozen = draft.executionSleepCaptureContextIsFrozen
        let operation = await ExportSettingsSnapshot.forNewAppleOperation(acceptedSettings,
            healthSubfolder: accepted.snapshot.healthSubfolder, calendarTimeZone: timeZone, surface: .preview)
        guard let captureContext = try? operation.recoveredSleepCaptureContext() else {
            return .unavailable(.captureSettings)
        }
        let advanced = operation.makeAdvancedExportSettings()

        let data: HealthData
        do {
            if let fetch {
                data = try await fetch(date, captureContext, advanced)
            } else {
                guard healthKitManager.isAuthorized else { return .unavailable(.healthAccess) }
                data = try await healthKitManager.fetchHealthData(for: date, detailPolicy: .summary,
                    metricSelection: advanced.metricSelection, timeZone: timeZone, captureContext: captureContext)
            }
        } catch {
            return .unavailable(.healthData)
        }

        let prepared: DailyNoteInjector.PreparedContent?
        if data.timeContext.sleepDayAttribution == .morningEnds {
            // Morning ends notes come only from an accepted plan, as in the export.
            guard let vaultManager else { return .unavailable(.rendererUnavailable) }
            guard let plan = try? await vaultManager.prepareWakeDateDailyNote(data, settingsSnapshot: operation) else {
                return .unavailable(.notePreparation)
            }
            prepared = plan
        } else {
            prepared = nil
        }
        switch DailyNoteInjector.preview(healthData: data, base: .emptyDocument,
            settings: advanced.dailyNoteInjection, customization: advanced.formatCustomization,
            metricSelection: advanced.metricSelection, calendarTimeZone: timeZone, preparedContent: prepared) {
        case .preview(let preview): return .note(path: preview.path, content: preview.content)
        case .skipped(let reason): return .unavailable(.skipped(reason))
        }
    }
}

import Foundation

/// Detects when two export profiles would write the same output files for
/// shared dates — the multi-profile footgun that is invisible in the UI
/// because profile names never appear in file paths (`ExportPathPlanner`
/// builds paths from the bound destination and the frozen settings snapshot
/// alone). Overlap is not an error: it is legitimate for "update the same
/// note from two cadences". But a duplicated profile with default settings
/// silently overwrites the source profile's files later in the day, so
/// creation-time and detail-surface warnings name the collision explicitly.
enum ExportProfileOverlapDetector {
    /// Path-relevant identity of one profile: everything that decides where
    /// its files land, independent of cadence and profile naming.
    struct ProfilePathIdentity: Equatable {
        let profileID: UUID
        let name: String
        let target: ExportTargetSelection
        let settings: ExportSettingsSnapshot
        /// Resolved destination root key. For local-folder profiles: the
        /// bound vault's standardized path, or the live shared vault's path
        /// when unbound (unbound profiles use the legacy shared vault state).
        /// For Connected Mac profiles: all Connected Mac exports share the
        /// Mac's own selected destination, so a constant key is used. Nil for
        /// API endpoints, which upload rather than write files.
        let destinationRootKey: String?

        init(
            profileID: UUID,
            name: String,
            target: ExportTargetSelection,
            settings: ExportSettingsSnapshot,
            destinationRootKey: String?
        ) {
            self.profileID = profileID
            self.name = name
            self.target = target
            self.settings = settings
            self.destinationRootKey = destinationRootKey
        }
    }

    /// Shared destination-root key for Connected Mac targets: the Mac owns
    /// one selected folder, so every Connected Mac profile writes under it.
    static let connectedMacRootKey = "connected-mac-destination"

    /// Deterministic sample dates used to render each profile's path
    /// templates. Templates only vary through date placeholders, so two
    /// rendered dates catch both identical and date-equivalent templates
    /// (for example `{YR}-{month}-{day}` vs `{date}`) without a symbolic
    /// comparison. Dates with different month/quarter/weekday coverage keep
    /// the equivalence check honest.
    static let sampleDates: [Date] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return [
            calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)),
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15))
        ].compactMap { $0 }
    }()

    /// Names of other profiles whose exports write the same relative paths
    /// under the same destination root for at least one sample date and one
    /// shared format. Sorted for deterministic presentation.
    static func overlappingProfileNames(
        for profileID: UUID,
        among identities: [ProfilePathIdentity],
        sampleDates: [Date] = sampleDates
    ) -> [String] {
        guard let subject = identities.first(where: { $0.profileID == profileID }),
              let subjectRoot = subject.destinationRootKey else {
            return []
        }

        // Snapshot → live settings instances are expensive (observable
        // objects); resolve the subject's rendered paths once.
        let subjectSettings = subject.settings.makeAdvancedExportSettings()
        let subjectPaths = renderedRelativePaths(
            settings: subjectSettings,
            healthSubfolder: subject.settings.healthSubfolder ?? "",
            formats: subject.settings.exportFormats,
            dates: sampleDates
        )

        var overlapping: [String] = []
        for other in identities where other.profileID != profileID {
            guard other.target == subject.target,
                  let otherRoot = other.destinationRootKey,
                  normalizedRoot(otherRoot) == normalizedRoot(subjectRoot),
                  !subject.settings.exportFormats.isEmpty,
                  !other.settings.exportFormats.isEmpty else {
                continue
            }

            let sharedFormats = subject.settings.exportFormats
                .intersection(other.settings.exportFormats)
            guard !sharedFormats.isEmpty else { continue }

            let otherSettings = other.settings.makeAdvancedExportSettings()
            let otherPaths = renderedRelativePaths(
                settings: otherSettings,
                healthSubfolder: other.settings.healthSubfolder ?? "",
                formats: sharedFormats,
                dates: sampleDates
            )

            if !subjectPaths.isDisjoint(with: otherPaths) {
                overlapping.append(other.name)
            }
        }
        return overlapping.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// True when any pair of identities overlaps — used to badge the list
    /// surface without computing per-profile detail.
    static func hasAnyOverlap(
        among identities: [ProfilePathIdentity],
        sampleDates: [Date] = sampleDates
    ) -> Bool {
        identities.contains { profileID in
            !overlappingProfileNames(
                for: profileID.profileID,
                among: identities,
                sampleDates: sampleDates
            ).isEmpty
        }
    }

    // MARK: - Path rendering

    private static func renderedRelativePaths(
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        formats: Set<ExportFormat>,
        dates: [Date]
    ) -> Set<String> {
        var paths = Set<String>()
        for date in dates {
            for format in formats {
                paths.insert(
                    ExportPathPlanner.aggregateRelativePath(
                        healthSubfolder: healthSubfolder,
                        settings: settings,
                        date: date,
                        format: format
                    )
                )
            }
        }
        return paths
    }

    private static func normalizedRoot(_ root: String) -> String {
        root
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .lowercased()
    }
}

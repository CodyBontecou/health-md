import Foundation

// MARK: - Pure summary derivation

/// Where a profile sends its files, resolved without activating it.
enum ExportProfileDestinationSummary: Equatable {
    /// A local folder binding; the vault name is nil when the profile still
    /// follows the folder selected in the Export tab (unbound legacy state).
    case localFolder(vaultName: String?)
    case connectedMac
    case apiEndpoint(url: String?)
    case googleDrive(folderLabel: String?)

    static func from(
        profile: ExportProfile,
        vault: SavedVaultDestination?,
        endpoint: SavedAPIEndpoint?,
        googleDriveDestination: GoogleDriveDestination? = nil
    ) -> ExportProfileDestinationSummary {
        switch profile.target {
        case .localIPhoneFolder:
            return .localFolder(vaultName: vault?.name)
        case .connectedMac:
            return .connectedMac
        case .apiEndpoint:
            return .apiEndpoint(url: endpoint?.endpointURLString)
        case .googleDrive:
            return .googleDrive(folderLabel: googleDriveDestination?.folderLabel)
        }
    }
}

/// Whether a profile runs on a cadence, independent of the cadence details.
enum ExportProfileScheduleStatus: Equatable {
    case notConfigured
    case paused
    case scheduled

    static func from(_ entry: ScheduledExportEntry?) -> ExportProfileScheduleStatus {
        guard let entry else { return .notConfigured }
        return entry.isEnabled ? .scheduled : .paused
    }
}

/// Cadence facts for display, derived from a scheduled entry.
struct ExportProfileCadenceSummary: Equatable {
    let frequencyDescription: String
    let timeLabel: String
    let lookbackDays: Int
    /// ISO weekday (1 = Monday … 7 = Sunday) for weekly cadences.
    let weekdayIndex: Int?
    let customInterval: Int?
    let customUnit: ScheduleIntervalUnit?

    static func from(
        _ entry: ScheduledExportEntry,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> ExportProfileCadenceSummary {
        let weekday: Int?
        switch entry.frequency {
        case .weekly:
            weekday = entry.weekday
        case .daily, .custom:
            weekday = nil
        }

        return ExportProfileCadenceSummary(
            frequencyDescription: entry.frequency.description,
            timeLabel: Self.timeLabel(hour: entry.preferredHour, minute: entry.preferredMinute, locale: locale),
            lookbackDays: entry.lookbackDays,
            weekdayIndex: weekday,
            customInterval: entry.frequency == .custom ? entry.customInterval : nil,
            customUnit: entry.frequency == .custom ? entry.customUnit : nil
        )
    }

    /// Locale-formatted clock time for a preferred hour/minute pair.
    static func timeLabel(hour: Int, minute: Int, locale: Locale, calendar: Calendar = .current) -> String {
        var components = DateComponents()
        components.hour = max(0, min(23, hour))
        components.minute = max(0, min(59, minute))
        let date = calendar.date(from: components) ?? calendar.startOfDay(for: Date())

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Localized weekday name for an ISO weekday index (1 = Monday … 7 = Sunday).
    static func weekdayName(_ isoWeekday: Int, locale: Locale = .current) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let gregorianIndex = ((isoWeekday - 1) % 7) + 1
        let symbolIndex = gregorianIndex % 7
        guard symbols.indices.contains(symbolIndex) else { return "" }
        return symbols[symbolIndex]
    }
}

/// Row- and detail-level facts about one export profile, derived purely from
/// the frozen profile, its destination bindings, and its scheduled entry.
/// Kept free of view concerns so summary derivation stays unit-testable.
struct ExportProfileCardSummary: Equatable {
    let profile: ExportProfile
    let isActive: Bool
    let destination: ExportProfileDestinationSummary
    let scheduleStatus: ExportProfileScheduleStatus
    let cadence: ExportProfileCadenceSummary?
    let formats: [ExportFormat]
    let enabledMetricCount: Int

    /// Formats in stable catalogue order for consistent display.
    static func sortedFormats(_ formats: Set<ExportFormat>) -> [ExportFormat] {
        ExportFormat.allCases.filter { formats.contains($0) }
    }
}

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Management view

/// Dedicated management surface for export profiles (see
/// `docs/features/export-profiles.md`): every profile at a glance with its
/// destination, schedule status, formats, and metric count; a read-only
/// detail view of the frozen snapshot with the copyable profile ID used by
/// the CLI and automation references; and activate / rename / duplicate /
/// delete management. Editing output settings stays in the Export tab by
/// activating the profile first (feature decision 1: single editing
/// authority), so this view never mutates a frozen snapshot in place.
struct ExportProfilesView: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var destinationStore: ProfileDestinationStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    @State private var showCreationSheet = false

    init(coordinator: ExportProfileCoordinator) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _destinationStore = ObservedObject(wrappedValue: coordinator.destinationStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                header

                if profileStore.profiles.isEmpty {
                    emptyStateCard
                } else {
                    ForEach(profileStore.profiles) { profile in
                        NavigationLink {
                            ExportProfileDetailView(coordinator: coordinator, profileID: profile.id)
                        } label: {
                            profileCard(summary(for: profile))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("export.profiles.row.\(profile.name)")
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle(Text("Export Profiles"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Creating a profile is a configuration mutation, so the
                    // shared lock rejects it with the explanatory toast while
                    // Prevent Accidental Changes is on.
                    configurationProtection.performConfigurationChange {
                        showCreationSheet = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "New profile", comment: "Toolbar action opening the profile creation form"))
            }
        }
        .sheet(isPresented: $showCreationSheet) {
            ExportProfileEditorSheet(coordinator: coordinator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text("Export Profiles")
                .font(Typography.displayMedium())
                .foregroundStyle(Color.textPrimary)
            Text("Every saved export configuration in one place. Activate a profile to edit it in the Export tab; schedules run even when this screen is closed.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyStateCard: some View {
        VStack(spacing: Spacing.s2) {
            Image(systemName: "square.and.arrow.down.on.square")
                .font(.title2)
                .foregroundStyle(Color.textMuted)
            Text("No export profiles yet.")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Use the + button to create one from your current export settings.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bgSecondary)
        )
    }

    private func summary(for profile: ExportProfile) -> ExportProfileCardSummary {
        let vault = destinationStore.vault(id: profile.folderVaultID)
        let endpoint = destinationStore.apiEndpoint(id: profile.apiEndpointID)
        let drive = coordinator.googleDriveDestinationStore.destination(id: profile.googleDriveDestinationID)
        let entry = entryStore.entry(profileID: profile.id)
        return ExportProfileCardSummary(
            profile: profile,
            isActive: profile.id == profileStore.activeProfileID,
            destination: .from(
                profile: profile,
                vault: vault,
                endpoint: endpoint,
                googleDriveDestination: drive
            ),
            scheduleStatus: .from(entry),
            cadence: entry.map { ExportProfileCadenceSummary.from($0) },
            formats: ExportProfileCardSummary.sortedFormats(profile.settings.exportFormats),
            enabledMetricCount: profile.settings.metricSelection.enabledMetricIDs.count
        )
    }

    private func profileCard(_ summary: ExportProfileCardSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.body.weight(.medium))
                    .foregroundStyle(summary.isActive ? Color.accent : Color.textMuted)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Spacing.s2) {
                        Text(summary.profile.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        if summary.isActive {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accent.opacity(0.14)))
                        }
                    }

                    Text(destinationLine(summary.destination))
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(scheduleLine(summary))
                        .font(.footnote)
                        .foregroundStyle(scheduleColor(summary.scheduleStatus))
                        .lineLimit(2)

                    Text(formatsLine(summary))
                        .font(.caption)
                        .foregroundStyle(Color.textMuted)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textMuted)
            }
        }
        .padding(Spacing.s4)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bgSecondary)
        )
        .accessibilityHint(String(localized: "Opens profile details", comment: "Accessibility hint for an export profile row"))
    }

    private func destinationLine(_ destination: ExportProfileDestinationSummary) -> String {
        switch destination {
        case .localFolder(let vaultName):
            if let vaultName {
                return String(
                    localized: "Folder: \(vaultName)",
                    comment: "Profile row destination line for a bound vault folder"
                )
            }
            return String(localized: "Folder: from Export tab", comment: "Profile row destination line for an unbound folder")
        case .connectedMac:
            return String(localized: "Connected Mac", comment: "Profile row destination line for the Mac target")
        case .apiEndpoint(let url):
            return String(
                localized: "API: \(url ?? "not configured")",
                comment: "Profile row destination line for an API endpoint target"
            )
        case .googleDrive(let folderLabel):
            return String(localized: "Google Drive: \(folderLabel ?? "folder selected")")
        }
    }

    private func scheduleLine(_ summary: ExportProfileCardSummary) -> String {
        switch summary.scheduleStatus {
        case .notConfigured:
            return String(localized: "No schedule", comment: "Profile row schedule line when no entry exists")
        case .paused:
            return String(localized: "Schedule paused", comment: "Profile row schedule line for a disabled entry")
        case .scheduled:
            guard let cadence = summary.cadence else {
                return String(localized: "Scheduled", comment: "Profile row schedule line without cadence facts")
            }
            var line = cadence.frequencyDescription
            if let weekdayIndex = cadence.weekdayIndex {
                line += " · " + ExportProfileCadenceSummary.weekdayName(weekdayIndex)
            } else if let interval = cadence.customInterval, let unit = cadence.customUnit {
                line += " · \(interval) \(unit.rawValue.lowercased())"
            }
            line += " · \(cadence.timeLabel)"
            return line
        }
    }

    private func scheduleColor(_ status: ExportProfileScheduleStatus) -> Color {
        switch status {
        case .notConfigured: return .textSecondary
        case .paused: return .textSecondary
        case .scheduled: return .accent
        }
    }

    private func formatsLine(_ summary: ExportProfileCardSummary) -> String {
        if summary.profile.settings.dailyNotesOnlyModeEnabled {
            return String(localized: "Daily Notes only", comment: "Profile row formats line in daily-notes-only mode")
        }
        let formats = summary.formats.map(\.localizedDisplayName).joined(separator: " · ")
        let metrics = String(
            localized: "\(summary.enabledMetricCount) metrics",
            comment: "Profile row metric count; the number of enabled health metrics"
        )
        return formats.isEmpty ? metrics : "\(formats) · \(metrics)"
    }
}

// MARK: - Detail view

/// Read-only inspection of one profile's frozen configuration plus
/// management actions. The stable profile ID is copyable for
/// `healthmd export --profile` and automation references.
struct ExportProfileDetailView: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var destinationStore: ProfileDestinationStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID

    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false
    @State private var showScheduleEditor = false
    @State private var showSettingsEditor = false
    @State private var idCopied = false
    /// Pending overlap warning for a just-duplicated profile; undo deletes
    /// the copy (the source profile stays untouched and active).
    @State private var duplicateOverlapWarning: (copyID: UUID, names: [String])?

    init(coordinator: ExportProfileCoordinator, profileID: UUID) {
        self.coordinator = coordinator
        self.profileID = profileID
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _destinationStore = ObservedObject(wrappedValue: coordinator.destinationStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
    }

    private var profile: ExportProfile? {
        profileStore.profile(id: profileID)
    }

    var body: some View {
        Group {
            if let profile {
                content(for: profile)
            } else {
                // The profile was deleted elsewhere while this detail was open.
                VStack(spacing: Spacing.s2) {
                    Image(systemName: "tray")
                        .font(.title2)
                        .foregroundStyle(Color.textMuted)
                    Text("This profile no longer exists.")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .navigationTitle(Text(profile?.name ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func content(for profile: ExportProfile) -> some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                activeBanner(for: profile)
                overlapCard(for: profile)
                destinationCard(for: profile)
                outputCard(for: profile)
                scheduleCard(for: profile)
                profileIDCard(for: profile)
                actionsCard(for: profile)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    configurationProtection.performConfigurationChange {
                        showSettingsEditor = true
                    }
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel(String(localized: "Edit profile settings", comment: "Toolbar action opening the profile settings editor"))
                .accessibilityIdentifier("export.profiles.edit.button")
            }
        }
        .sheet(isPresented: $showSettingsEditor) {
            ExportProfileEditorSheet(coordinator: coordinator, editing: profile)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .geistDialog(
            isPresented: Binding(
                get: { duplicateOverlapWarning != nil },
                set: { if !$0 { duplicateOverlapWarning = nil } }
            ),
            title: Text("Overlapping Exports"),
            message: Text(duplicateOverlapMessage),
            actions: [
                .cancel("Keep It") {
                    duplicateOverlapWarning = nil
                },
                .destructive("Undo Duplicate") {
                    undoDuplicate()
                }
            ]
        )
    }

    /// Persistent warning while this profile's output paths overlap another
    /// profile's: binds/settings can change after creation, so the detail
    /// surface keeps naming the collision.
    private func overlapCard(for profile: ExportProfile) -> some View {
        let overlapping = coordinator.overlappingProfileNames(for: profile.id)
        return Group {
            if !overlapping.isEmpty {
                let names = overlapping.joined(separator: ", ")
                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Label(
                        String(localized: "Overlapping exports", comment: "Card title for the profile output-overlap warning"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(Typography.bodyEmphasis())
                    .foregroundStyle(Color.warning)

                    Text(String(
                        localized: "This profile writes the same files as \(names). The later run overwrites the earlier one. Give each profile its own folder or filename template to keep them separate.",
                        comment: "Detail warning that this profile's output files overlap other profiles; the interpolated value is a comma-separated profile name list"
                    ))
                    .font(Typography.caption())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.warning.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.warning.opacity(0.35), lineWidth: 1)
                )
                .accessibilityIdentifier("export.profiles.overlap-warning")
            }
        }
    }

    private func duplicateAndWarn(_ profile: ExportProfile) {
        guard let copy = coordinator.duplicateProfile(id: profile.id) else { return }
        let overlapping = coordinator.overlappingProfileNames(for: copy.id)
        guard !overlapping.isEmpty else { return }
        duplicateOverlapWarning = (copyID: copy.id, names: overlapping)
    }

    private func undoDuplicate() {
        guard let warning = duplicateOverlapWarning else { return }
        duplicateOverlapWarning = nil
        _ = coordinator.deleteProfile(id: warning.copyID)
    }

    private var duplicateOverlapMessage: String {
        guard let warning = duplicateOverlapWarning else { return "" }
        let names = warning.names.joined(separator: ", ")
        return String(
            localized: "The duplicate writes the same files as \(names). Later runs overwrite earlier ones. Undo, then change its folder or filename template if you want separate files.",
            comment: "Warning when a duplicated export profile overlaps another profile's output files; the interpolated value is a comma-separated profile name list"
        )
    }

    // MARK: Cards

    private func activeBanner(for profile: ExportProfile) -> some View {
        Group {
            if profile.id == profileStore.activeProfileID {
                Label(
                    String(localized: "Active profile — edit it in the Export tab", comment: "Banner on the active profile's detail"),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.s3)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.accent.opacity(0.10)))
            }
        }
    }

    private func destinationCard(for profile: ExportProfile) -> some View {
        let vault = destinationStore.vault(id: profile.folderVaultID)
        let endpoint = destinationStore.apiEndpoint(id: profile.apiEndpointID)
        let drive = coordinator.googleDriveDestinationStore.destination(id: profile.googleDriveDestinationID)
        return sectionCard(title: String(localized: "Destination", comment: "Profile detail card title")) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                factRow(
                    title: String(localized: "Target", comment: "Profile detail target row"),
                    value: profile.target.title
                )
                switch ExportProfileDestinationSummary.from(
                    profile: profile,
                    vault: vault,
                    endpoint: endpoint,
                    googleDriveDestination: drive
                ) {
                case .localFolder(let vaultName):
                    factRow(
                        title: String(localized: "Folder", comment: "Profile detail folder row"),
                        value: vaultName ?? String(localized: "Selected in Export tab", comment: "Unbound folder fallback")
                    )
                case .connectedMac:
                    EmptyView()
                case .apiEndpoint(let url):
                    factRow(
                        title: String(localized: "Endpoint", comment: "Profile detail endpoint row"),
                        value: url ?? String(localized: "Not configured", comment: "Missing endpoint fallback")
                    )
                case .googleDrive(let folderLabel):
                    factRow(
                        title: String(localized: "Folder", comment: "Profile detail Drive folder row"),
                        value: folderLabel ?? String(localized: "Google Drive folder", comment: "Private Drive folder label fallback")
                    )
                }
            }
        }
    }

    private func outputCard(for profile: ExportProfile) -> some View {
        let settings = profile.settings
        let enabledCount = settings.metricSelection.enabledMetricIDs.count
        let totalMetricCount = HealthMetrics.availableInCurrentBuild
            .filter { !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform }
            .count
        return sectionCard(title: String(localized: "Output", comment: "Profile detail card title")) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                if settings.dailyNotesOnlyModeEnabled {
                    factRow(
                        title: String(localized: "Mode", comment: "Profile detail mode row"),
                        value: String(localized: "Daily Notes only", comment: "Daily-notes-only mode value")
                    )
                } else {
                    factRow(
                        title: String(localized: "Formats", comment: "Profile detail formats row"),
                        value: ExportProfileCardSummary.sortedFormats(settings.exportFormats)
                            .map(\.localizedDisplayName)
                            .joined(separator: " · ")
                    )
                    factRow(
                        title: String(localized: "Metrics", comment: "Profile detail metrics row"),
                        value: String(
                            localized: "\(enabledCount) of \(totalMetricCount) enabled",
                            comment: "Enabled versus total health metric count"
                        )
                    )
                    factRow(
                        title: String(localized: "Lossless records", comment: "Profile detail lossless row"),
                        value: settings.includeGranularData
                            ? String(localized: "On", comment: "Enabled state")
                            : String(localized: "Off", comment: "Disabled state")
                    )
                    rollupRow(settings)
                    factRow(
                        title: String(localized: "Zip archive", comment: "Profile detail zip row"),
                        value: settings.archiveExportFiles
                            ? String(localized: "On", comment: "Enabled state")
                            : String(localized: "Off", comment: "Disabled state")
                    )
                    factRow(
                        title: String(localized: "Data dictionary", comment: "Profile detail data dictionary row"),
                        value: settings.includeDataDictionary
                            ? String(localized: "On", comment: "Enabled state")
                            : String(localized: "Off", comment: "Disabled state")
                    )
                    factRow(
                        title: String(localized: "When file exists", comment: "Profile detail write mode row"),
                        value: settings.writeMode.localizedDisplayName
                    )
                    factRow(
                        title: String(localized: "Filename format", comment: "Profile detail filename row"),
                        value: settings.filenameFormat
                    )
                    factRow(
                        title: String(localized: "Folder structure", comment: "Profile detail folder structure row"),
                        value: settings.folderStructure
                    )
                    if let subfolder = settings.healthSubfolder, !subfolder.isEmpty {
                        factRow(
                            title: String(localized: "Subfolder", comment: "Profile detail subfolder row"),
                            value: subfolder
                        )
                    }
                }
                factRow(
                    title: String(localized: "Daily Note injection", comment: "Profile detail daily note injection row"),
                    value: settings.dailyNoteInjection.enabled
                        ? String(localized: "On", comment: "Enabled state")
                        : String(localized: "Off", comment: "Disabled state")
                )
                factRow(
                    title: String(localized: "Individual entries", comment: "Profile detail individual tracking row"),
                    value: settings.individualTracking.globalEnabled
                        ? String(localized: "On", comment: "Enabled state")
                        : String(localized: "Off", comment: "Disabled state")
                )
            }
        }
    }

    private func rollupRow(_ settings: ExportSettingsSnapshot) -> some View {
        let periods: [String] = [
            settings.generateWeeklyRollups ? String(localized: "Weekly", comment: "Roll-up period") : nil,
            settings.generateMonthlyRollups ? String(localized: "Monthly", comment: "Roll-up period") : nil,
            settings.generateYearlyRollups ? String(localized: "Yearly", comment: "Roll-up period") : nil
        ].compactMap { $0 }
        let value = periods.isEmpty
            ? String(localized: "Off", comment: "Disabled state")
            : (settings.summaryOnlyExport
                ? periods.joined(separator: " · ") + String(localized: " (summary only)", comment: "Summary-only roll-up suffix")
                : periods.joined(separator: " · "))
        return factRow(
            title: String(localized: "Roll-up summaries", comment: "Profile detail rollup row"),
            value: value
        )
    }

    private func scheduleCard(for profile: ExportProfile) -> some View {
        let entry = entryStore.entry(profileID: profile.id)
        let status = ExportProfileScheduleStatus.from(entry)
        return sectionCard(title: String(localized: "Schedule", comment: "Profile detail card title")) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                switch status {
                case .notConfigured:
                    Text("This profile has no schedule yet. It runs only when you export manually.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .paused:
                    Text("Schedule paused. Its cadence is remembered and resumes when enabled.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                case .scheduled:
                    if let entry {
                        let cadence = ExportProfileCadenceSummary.from(entry)
                        Label(scheduleDescription(cadence), systemImage: "clock.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Color.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(String(
                            localized: "Looks back \(cadence.lookbackDays) day(s) each run.",
                            comment: "Profile detail schedule lookback line"
                        ))
                        .font(.caption)
                        .foregroundStyle(Color.textMuted)
                    }
                }

                Button {
                    configurationProtection.performConfigurationChange {
                        showScheduleEditor = true
                    }
                } label: {
                    Label(
                        String(localized: "Edit Schedule…", comment: "Action opening the profile schedule editor"),
                        systemImage: "calendar.badge.clock"
                    )
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
        }
        .sheet(isPresented: $showScheduleEditor) {
            ProfileScheduleEditorSheet(
                profile: profile,
                entry: entryStore.entry(profileID: profile.id)
            ) { entry in
                _ = entryStore.upsert(entry)
                schedulingManager.refreshScheduledAutomation()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func scheduleDescription(_ cadence: ExportProfileCadenceSummary) -> String {
        var line = cadence.frequencyDescription
        if let weekdayIndex = cadence.weekdayIndex {
            line += " · " + ExportProfileCadenceSummary.weekdayName(weekdayIndex)
        } else if let interval = cadence.customInterval, let unit = cadence.customUnit {
            line += " · \(interval) \(unit.rawValue.lowercased())"
        }
        line += " · \(cadence.timeLabel)"
        return line
    }

    private func profileIDCard(for profile: ExportProfile) -> some View {
        sectionCard(title: String(localized: "Profile ID", comment: "Profile detail card title")) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Use this ID to pin the profile in Shortcuts, the CLI (`healthmd export --profile`), and API automation.")
                    .font(.caption)
                    .foregroundStyle(Color.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.s2) {
                    Text(profile.id.uuidString)
                        .font(Typography.monoEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.6)

                    Spacer(minLength: 0)

                    Button {
                        UIPasteboard.general.string = profile.id.uuidString
                        idCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            idCopied = false
                        }
                    } label: {
                        Label(
                            idCopied
                                ? String(localized: "Copied", comment: "Confirmation after copying the profile ID")
                                : String(localized: "Copy", comment: "Action copying the profile ID"),
                            systemImage: idCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(AccessibilityID.ExportProfiles.copyIDButton)
                    .accessibilityLabel(String(localized: "Copy profile ID", comment: "Accessibility label for the copy ID button"))
                }
            }
        }
    }

    private func actionsCard(for profile: ExportProfile) -> some View {
        sectionCard(title: String(localized: "Actions", comment: "Profile detail card title")) {
            VStack(spacing: 0) {
                if profile.id != profileStore.activeProfileID {
                    Button {
                        configurationProtection.performConfigurationChange {
                            coordinator.activate(profileID: profile.id)
                            dismiss()
                        }
                    } label: {
                        actionRowLabel(
                            icon: "checkmark.circle.fill",
                            title: String(localized: "Make Active & Edit", comment: "Action activating this profile"),
                            isDestructive: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(AccessibilityID.ExportProfiles.makeActiveButton)

                    rowDivider()
                }

                Button {
                    configurationProtection.performConfigurationChange {
                        renameText = profile.name
                        showRenameAlert = true
                    }
                } label: {
                    actionRowLabel(
                        icon: "pencil",
                        title: String(localized: "Rename…", comment: "Action renaming this profile"),
                        isDestructive: false
                    )
                }
                .buttonStyle(.plain)

                rowDivider()

                Button {
                    configurationProtection.performConfigurationChange {
                        duplicateAndWarn(profile)
                    }
                } label: {
                    actionRowLabel(
                        icon: "plus.square.on.square",
                        title: String(localized: "Duplicate", comment: "Action duplicating this profile"),
                        isDestructive: false
                    )
                }
                .buttonStyle(.plain)

                rowDivider()

                Button(role: .destructive) {
                    configurationProtection.performConfigurationChange {
                        showDeleteConfirmation = true
                    }
                } label: {
                    actionRowLabel(
                        icon: "trash",
                        title: String(localized: "Delete Profile…", comment: "Action deleting this profile"),
                        isDestructive: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(profileStore.profiles.count <= 1)
            }
        }
        .alert(
            String(localized: "Rename Profile", comment: "Alert title: rename export profile"),
            isPresented: $showRenameAlert
        ) {
            TextField(
                String(localized: "Profile name", comment: "Placeholder for export profile name"),
                text: $renameText
            )
            Button(String(localized: "Save", comment: "Confirm rename")) {
                _ = coordinator.renameProfile(id: profile.id, to: renameText)
            }
            Button(String(localized: "Cancel", comment: "Dismiss rename"), role: .cancel) { }
        }
        .confirmationDialog(
            String(localized: "Delete this profile?", comment: "Confirm deleting an export profile"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                String(
                    localized: "Delete “%@”",
                    comment: "Destructive action deleting the named export profile"
                ),
                role: .destructive
            ) {
                if coordinator.deleteProfile(id: profile.id) {
                    dismiss()
                }
            }
            Button(String(localized: "Cancel", comment: "Dismiss delete"), role: .cancel) { }
        } message: {
            Text(String(
                localized: "Its saved settings, destination bindings, and schedule are removed. Scheduled exports for other profiles are not affected.",
                comment: "Explanation shown when deleting an export profile"
            ))
        }
    }

    // MARK: Row helpers

    private func sectionCard(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            content()
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bgSecondary)
        )
    }

    private func factRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s3) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Color.textMuted)
                .frame(width: 110, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func actionRowLabel(icon: String, title: String, isDestructive: Bool) -> some View {
        HStack(spacing: Spacing.s3) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(isDestructive ? Color.error : Color.accent)
                .frame(width: 28)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(isDestructive ? Color.error : Color.textPrimary)
            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func rowDivider() -> some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 1)
    }
}
#endif

#if os(iOS)
/// Unified full-field profile editor. Serves both creation (no profile) and
/// editing (existing profile): name, destination, output formats, templates,
/// roll-ups, metric selection (the shipped picker, pushed), Daily Notes, and
/// Individual Entries all edit a draft, with the live overlap warning
/// recomputing against the draft — so nothing is saved until Create/Save,
/// and overlap is visible while choices can still change.
struct ExportProfileEditorSheet: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var destinationStore: ProfileDestinationStore
    @ObservedObject private var googleDriveDestinationStore: GoogleDriveDestinationStore
    @StateObject private var googleDriveConnectionManager: GoogleDriveConnectionManager
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.dismiss) private var dismiss

    /// Nil = creation mode; the profile being edited otherwise.
    private let editingProfileID: UUID?

    @State private var name: String
    @State private var target: ExportTargetSelection
    @State private var folderVaultID: UUID?
    @State private var apiEndpointID: UUID?
    @State private var googleDriveDestinationID: UUID?
    @State private var driveConnectionError: String?
    @State private var showGoogleDrivePrivacyDisclosure = false
    @State private var draft: ExportSettingsSnapshot
    @StateObject private var metricState: MetricSelectionState
    /// Presents the system folder picker for a new destination binding.
    @State private var showFolderImporter = false
    /// Presents the inline form for a new API endpoint binding.
    @State private var showEndpointForm = false

    init(
        coordinator: ExportProfileCoordinator,
        editing profile: ExportProfile? = nil
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _destinationStore = ObservedObject(wrappedValue: coordinator.destinationStore)
        _googleDriveDestinationStore = ObservedObject(wrappedValue: coordinator.googleDriveDestinationStore)
        _googleDriveConnectionManager = StateObject(wrappedValue: GoogleDriveConnectionManager(
            destinationStore: coordinator.googleDriveDestinationStore
        ))
        editingProfileID = profile?.id

        if let profile {
            _name = State(initialValue: profile.name)
            _target = State(initialValue: profile.target)
            _folderVaultID = State(initialValue: profile.folderVaultID)
            _apiEndpointID = State(initialValue: profile.apiEndpointID)
            _googleDriveDestinationID = State(initialValue: profile.googleDriveDestinationID)
            _driveConnectionError = State(initialValue: nil)
            _draft = State(initialValue: profile.settings)
        } else {
            // Creation defaults mirror what a plain duplicate would produce,
            // so the overlap warning starts honest.
            _name = State(initialValue: coordinator.suggestedProfileName())
            _target = State(initialValue: coordinator.activeTarget ?? .localIPhoneFolder)
            let active = coordinator.profileStore.activeProfile
            _folderVaultID = State(initialValue: active?.folderVaultID)
            _apiEndpointID = State(initialValue: active?.apiEndpointID)
            _googleDriveDestinationID = State(initialValue: active?.googleDriveDestinationID)
            _driveConnectionError = State(initialValue: nil)
            _draft = State(initialValue: ExportSettingsSnapshot.from(coordinator.liveSettings))
        }

        let state = MetricSelectionState()
        (profile?.settings ?? ExportSettingsSnapshot.from(coordinator.liveSettings))
            .metricSelection.apply(to: state)
        _metricState = StateObject(wrappedValue: state)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editingProfile: ExportProfile? {
        editingProfileID.flatMap { profileStore.profile(id: $0) }
    }

    private var canSave: Bool {
        let outputReady = draft.dailyNoteInjection.dailyNotesOnly || !draft.exportFormats.isEmpty
        let destinationReady = target != .googleDrive || (
            googleDriveDestinationID != nil && googleDriveConnectionManager.readiness != .configurationMissing
        )
        return !trimmedName.isEmpty && outputReady && destinationReady
    }

    private var overlappingNames: [String] {
        coordinator.overlapPreviewNames(
            target: target,
            folderVaultID: folderVaultID,
            googleDriveDestinationID: googleDriveDestinationID,
            settings: savedSnapshot()
        )
    }

    /// The snapshot Save/Create will persist, with the picker's metric state
    /// folded back in.
    private func savedSnapshot() -> ExportSettingsSnapshot {
        var snapshot = draft
        snapshot.metricSelection = MetricSelectionSnapshot.from(metricState)
        return snapshot
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                destinationSection
                outputSection
                rollupSection
                metricsSection
                dailyNotesSection
                individualTrackingSection
                overlapSection
            }
            .navigationTitle(Text(editingProfile == nil ? "New Profile" : "Edit Profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingProfile == nil ? "Create" : "Save") {
                        // The draft stays inspectable, but persisting a profile
                        // is a configuration mutation, so the shared lock can
                        // reject an editor that was already open when
                        // protection was turned on.
                        configurationProtection.performConfigurationChange {
                            save()
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("export.profiles.editor.confirm")
                }
            }
        }
        .sheet(isPresented: $showFolderImporter) {
            FolderPicker { url in
                // Picking a folder persists a destination binding immediately,
                // so the shared lock still guards this completion.
                configurationProtection.performConfigurationChange {
                    if let destinationID = coordinator.importFolderSelection(url) {
                        folderVaultID = destinationID
                    }
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        // Presentation modifiers must attach at the body's top level, not
        // inside the Form's conditional Section: a Section re-render (for
        // example when the destination store publishes) tears down sheets
        // attached within it, which dismissed the endpoint form a moment
        // after it appeared.
        .sheet(isPresented: $showEndpointForm) {
            ExportProfileEndpointFormSheet { name, url, token in
                // Adding an endpoint persists it (and its Keychain token)
                // immediately, so the shared lock still guards this completion.
                configurationProtection.performConfigurationChange {
                    if let endpointID = coordinator.importAPIEndpointSelection(
                        name: name,
                        endpointURLString: url,
                        bearerToken: token
                    ) {
                        apiEndpointID = endpointID
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            GoogleDrivePrivacyDisclosure.title,
            isPresented: $showGoogleDrivePrivacyDisclosure,
            titleVisibility: .visible
        ) {
            Button(GoogleDrivePrivacyDisclosure.confirm) {
                beginGoogleDriveAuthorization()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(GoogleDrivePrivacyDisclosure.message)
        }
        // The sheet covers the app-level toast, so blocked changes surface a
        // sheet-local one (also covering the pushed metric picker), and the
        // toast's settings shortcut dismisses the editor.
        .overlay(alignment: .top) {
            ConfigurationProtectionToast(configurationProtection: configurationProtection)
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
        }
        .onChange(of: configurationProtection.settingsNavigationRequestID) { _, requestID in
            if requestID != nil {
                dismiss()
            }
        }
    }

    private func save() {
        let snapshot = savedSnapshot()
        if let editingProfile {
            coordinator.updateProfile(
                id: editingProfile.id,
                name: trimmedName,
                target: target,
                folderVaultID: target == .localIPhoneFolder ? folderVaultID : nil,
                apiEndpointID: target == .apiEndpoint ? apiEndpointID : nil,
                googleDriveDestinationID: target == .googleDrive ? googleDriveDestinationID : nil,
                settings: snapshot
            )
        } else {
            coordinator.createProfile(
                name: trimmedName,
                target: target,
                folderVaultID: target == .localIPhoneFolder ? folderVaultID : nil,
                googleDriveDestinationID: target == .googleDrive ? googleDriveDestinationID : nil,
                settings: snapshot
            )
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section {
            TextField(
                String(localized: "Name", comment: "Profile editor name field label"),
                text: $name
            )
        } header: {
            Text("Profile")
        } footer: {
            Text(editingProfile == nil
                ? "Starts from the current export settings."
                : "Scheduled exports pick up the new settings on their next run.")
        }
    }

    private var destinationSection: some View {
        Section {
            Picker(
                String(localized: "Target", comment: "Profile editor target picker label"),
                selection: $target
            ) {
                Text("Local Folder").tag(ExportTargetSelection.localIPhoneFolder)
                Text("Connected Mac").tag(ExportTargetSelection.connectedMac)
                Text("API Endpoint").tag(ExportTargetSelection.apiEndpoint)
                Text("Google Drive").tag(ExportTargetSelection.googleDrive)
            }
            .pickerStyle(.menu)

            switch target {
            case .localIPhoneFolder:
                Picker(
                    String(localized: "Folder", comment: "Profile editor folder picker label"),
                    selection: $folderVaultID
                ) {
                    Text(String(
                        localized: "Current folder (from Export tab)",
                        comment: "Editor option using the live shared vault"
                    ))
                    .tag(UUID?.none)
                    ForEach(destinationStore.vaults) { vault in
                        Text(vault.name).tag(UUID?.some(vault.id))
                    }
                }
                Button {
                    configurationProtection.performConfigurationChange {
                        showFolderImporter = true
                    }
                } label: {
                    Label(
                        String(localized: "Choose New Folder…", comment: "Profile editor action opening the system folder picker"),
                        systemImage: "folder.badge.plus"
                    )
                }
                .accessibilityIdentifier("export.profiles.editor.chooseFolder")
            case .apiEndpoint:
                Picker(
                    String(localized: "Endpoint", comment: "Profile editor endpoint picker label"),
                    selection: $apiEndpointID
                ) {
                    Text(String(
                        localized: "Current endpoint (from Export tab)",
                        comment: "Editor option using the live API endpoint"
                    ))
                    .tag(UUID?.none)
                    ForEach(destinationStore.apiEndpoints) { endpoint in
                        Text(endpoint.name).tag(UUID?.some(endpoint.id))
                    }
                }
                Button {
                    configurationProtection.performConfigurationChange {
                        showEndpointForm = true
                    }
                } label: {
                    Label(
                        String(localized: "Add Endpoint…", comment: "Profile editor action adding a new API endpoint"),
                        systemImage: "network.badge.plus"
                    )
                }
                .accessibilityIdentifier("export.profiles.editor.addEndpoint")
            case .connectedMac:
                EmptyView()
            case .googleDrive:
                Picker("Drive folder", selection: $googleDriveDestinationID) {
                    Text("Select a Google Drive folder").tag(UUID?.none)
                    ForEach(googleDriveDestinationStore.destinations) { destination in
                        Text(destination.folderLabel ?? "Google Drive folder")
                            .tag(UUID?.some(destination.id))
                    }
                }
                Button {
                    configurationProtection.performConfigurationChange {
                        showGoogleDrivePrivacyDisclosure = true
                    }
                } label: {
                    Label(
                        googleDriveDestinationID == nil ? "Connect & Choose Folder…" : "Reconnect or Change Folder…",
                        systemImage: "externaldrive.connected.to.line.below"
                    )
                }
                if let destinationID = googleDriveDestinationID {
                    Button(role: .destructive) {
                        configurationProtection.performConfigurationChange {
                            Task {
                                do {
                                    try await coordinator.disconnectGoogleDrive(destinationID: destinationID)
                                    googleDriveDestinationID = nil
                                    driveConnectionError = nil
                                } catch {
                                    driveConnectionError = "Finish or recover pending Google Drive exports before disconnecting (partial_completion)."
                                }
                            }
                        }
                    } label: {
                        Label("Disconnect Google Drive", systemImage: "link.badge.minus")
                    }
                }
                if let driveConnectionError {
                    Text(driveConnectionError)
                        .font(.caption)
                        .foregroundStyle(Color.error)
                } else if googleDriveConnectionManager.readiness == .configurationMissing {
                    Text("Google Drive is unavailable in this build (configuration_missing).")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
            }
        } header: {
            Text("Destination")
        }
    }

    private func beginGoogleDriveAuthorization() {
        Task {
            do {
                let destination = try await googleDriveConnectionManager.connect(
                    replacing: googleDriveDestinationID
                )
                googleDriveDestinationID = destination.id
                driveConnectionError = nil
            } catch is CancellationError {
                driveConnectionError = nil
            } catch {
                driveConnectionError = (error as? GoogleDriveError)?.errorDescription
                    ?? GoogleDriveError(.reauthorizationRequired).errorDescription
            }
        }
    }

    private var outputSection: some View {
        Section {
            ForEach(ExportFormat.allCases, id: \.rawValue) { format in
                Toggle(
                    format.localizedDisplayName,
                    isOn: Binding(
                        get: { draft.exportFormats.contains(format) },
                        set: { isEnabled in
                            if isEnabled {
                                draft.exportFormats.insert(format)
                            } else {
                                draft.exportFormats.remove(format)
                            }
                        }
                    )
                )
                .disabled(draft.dailyNoteInjection.dailyNotesOnly)
            }

            Picker(
                String(localized: "When file exists", comment: "Profile editor write mode picker label"),
                selection: $draft.writeMode
            ) {
                ForEach(WriteMode.allCases, id: \.rawValue) { mode in
                    Text(mode.localizedDisplayName).tag(mode)
                }
            }

            TextField(
                String(localized: "Filename template", comment: "Profile editor filename template field"),
                text: $draft.filenameFormat
            )
            .font(Typography.mono())
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            TextField(
                String(localized: "Folder template", comment: "Profile editor folder template field"),
                text: $draft.folderStructure
            )
            .font(Typography.mono())
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            Toggle(
                String(localized: "Format folders", comment: "Profile editor format folders toggle"),
                isOn: $draft.organizeFormatsIntoFolders
            )
            Toggle(
                String(localized: "Zip archive", comment: "Profile editor zip toggle"),
                isOn: $draft.archiveExportFiles
            )
            Toggle(
                String(localized: "Data dictionary", comment: "Profile editor data dictionary toggle"),
                isOn: $draft.includeDataDictionary
            )
            Toggle(
                String(localized: "Lossless records", comment: "Profile editor lossless toggle"),
                isOn: $draft.includeGranularData
            )
            Toggle(
                String(localized: "Summary only", comment: "Profile editor summary-only toggle"),
                isOn: $draft.summaryOnlyExport
            )
        } header: {
            Text("Output")
        } footer: {
            Text("Templates accept {date}, {year}, {month}, {day}, {weekday}, {monthName}, and {quarter}.")
        }
    }

    private var rollupSection: some View {
        Section {
            Toggle(
                String(localized: "Weekly roll-ups", comment: "Profile editor weekly rollup toggle"),
                isOn: $draft.generateWeeklyRollups
            )
            Toggle(
                String(localized: "Monthly roll-ups", comment: "Profile editor monthly rollup toggle"),
                isOn: $draft.generateMonthlyRollups
            )
            Toggle(
                String(localized: "Yearly roll-ups", comment: "Profile editor yearly rollup toggle"),
                isOn: $draft.generateYearlyRollups
            )
        } header: {
            Text("Roll-Ups")
        }
    }

    private var metricsSection: some View {
        Section {
            let enabled = metricState.enabledMetrics.count
            let total = HealthMetrics.availableInCurrentBuild
                .filter { !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform }
                .count
            NavigationLink {
                MetricSelectionView(
                    selectionState: metricState,
                    healthKitManager: HealthKitManager.shared
                )
            } label: {
                HStack {
                    Text("Health Metrics")
                    Spacer()
                    Text(String(
                        localized: "\(enabled) of \(total)",
                        comment: "Enabled versus total metric count in the profile editor"
                    ))
                    .foregroundStyle(Color.textSecondary)
                }
            }
        } header: {
            Text("Metrics")
        }
    }

    private var dailyNotesSection: some View {
        Section {
            Toggle(
                String(localized: "Inject into daily notes", comment: "Profile editor daily note injection toggle"),
                isOn: $draft.dailyNoteInjection.enabled
            )
            Toggle(
                String(localized: "Daily Notes only", comment: "Profile editor daily-notes-only toggle"),
                isOn: $draft.dailyNoteInjection.dailyNotesOnly
            )
            if draft.dailyNoteInjection.enabled {
                TextField(
                    String(localized: "Notes folder", comment: "Profile editor daily notes folder field"),
                    text: $draft.dailyNoteInjection.folderPath
                )
                .font(Typography.mono())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                TextField(
                    String(localized: "Notes filename", comment: "Profile editor daily notes filename field"),
                    text: $draft.dailyNoteInjection.filenamePattern
                )
                .font(Typography.mono())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                Toggle(
                    String(localized: "Create if missing", comment: "Profile editor daily notes create toggle"),
                    isOn: $draft.dailyNoteInjection.createIfMissing
                )
                Toggle(
                    String(localized: "Markdown sections", comment: "Profile editor daily notes sections toggle"),
                    isOn: $draft.dailyNoteInjection.injectMarkdownSections
                )
            }
        } header: {
            Text("Daily Notes")
        }
    }

    private var individualTrackingSection: some View {
        Section {
            Toggle(
                String(localized: "Individual entries", comment: "Profile editor individual tracking toggle"),
                isOn: $draft.individualTracking.globalEnabled
            )
            if draft.individualTracking.globalEnabled {
                TextField(
                    String(localized: "Entries folder", comment: "Profile editor entries folder field"),
                    text: $draft.individualTracking.entriesFolder
                )
                .font(Typography.mono())
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                Toggle(
                    String(localized: "Category folders", comment: "Profile editor category folders toggle"),
                    isOn: $draft.individualTracking.useCategoryFolders
                )
            }
        } header: {
            Text("Individual Entries")
        } footer: {
            Text("Per-metric entry rules are edited from the Export tab while this profile is active.")
        }
    }

    @ViewBuilder
    private var overlapSection: some View {
        if !overlappingNames.isEmpty {
            let names = overlappingNames.joined(separator: ", ")
            Section {
                Label(String(
                    localized: "Overlaps \(names): later runs overwrite earlier ones. Choose a different folder or filename template to keep them separate.",
                    comment: "Live editor warning that the profile's output files overlap other profiles; the interpolated value is a comma-separated profile name list"
                ), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warning)
                    .font(Typography.caption())
            }
        }
    }
}

/// Inline form for adding a new API endpoint destination from the profile
/// editor. Nothing is imported until Add; the token is stored in the
/// destination store's Keychain-backed slot, not in the live shared endpoint
/// settings.
private struct ExportProfileEndpointFormSheet: View {
    let onAdd: (String, String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var token = ""

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        !trimmedURL.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "Name", comment: "Endpoint form name field label"),
                        text: $name
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text("Optional. Defaults to the URL.")
                }

                Section {
                    TextField(
                        String(localized: "URL", comment: "Endpoint form URL field label"),
                        text: $url
                    )
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    SecureField(
                        String(localized: "Bearer token", comment: "Endpoint form token field label"),
                        text: $token
                    )
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Stored in the Keychain. Optional if your endpoint doesn't require one.")
                }
            }
            .navigationTitle(Text("New Endpoint"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
                        onAdd(
                            name,
                            trimmedURL,
                            trimmedToken.isEmpty ? nil : trimmedToken
                        )
                        dismiss()
                    }
                    .disabled(!canAdd)
                    .accessibilityIdentifier("export.profiles.editor.addEndpoint.confirm")
                }
            }
        }
    }
}
#endif

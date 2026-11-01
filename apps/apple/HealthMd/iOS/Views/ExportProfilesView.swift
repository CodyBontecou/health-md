#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Pure summary derivation

/// Where a profile sends its files, resolved without activating it.
enum ExportProfileDestinationSummary: Equatable {
    /// A local folder binding; the vault name is nil when the profile still
    /// follows the folder selected in the Export tab (unbound legacy state).
    case localFolder(vaultName: String?)
    case connectedMac
    case apiEndpoint(url: String?)
    case agentDataGateway(url: String?)

    static func from(
        profile: ExportProfile,
        vault: SavedVaultDestination?,
        endpoint: SavedAPIEndpoint?,
        gateway: SavedAgentDataGateway? = nil
    ) -> ExportProfileDestinationSummary {
        switch profile.target {
        case .localIPhoneFolder:
            return .localFolder(vaultName: vault?.name)
        case .connectedMac:
            return .connectedMac
        case .apiEndpoint:
            return .apiEndpoint(url: endpoint?.endpointURLString)
        case .agentDataGateway:
            return .agentDataGateway(url: gateway?.endpointURLString)
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
        let gateway = destinationStore.agentDataGateway(
            id: destinationStore.agentDataGatewayBinding(profileID: profile.id)
        )
        let entry = entryStore.entry(profileID: profile.id)
        return ExportProfileCardSummary(
            profile: profile,
            isActive: profile.id == profileStore.activeProfileID,
            destination: .from(profile: profile, vault: vault, endpoint: endpoint, gateway: gateway),
            scheduleStatus: .from(entry),
            cadence: entry.map { ExportProfileCadenceSummary.from($0) },
            formats: ExportProfileCardSummary.sortedFormats(profile.settings.exportFormats),
            enabledMetricCount: profile.settings.metricSelection.enabledMetricIDs.count
        )
    }

    private func profileCard(_ summary: ExportProfileCardSummary) -> some View {
        SchedulingProfileSummary(
            name: summary.profile.name,
            destination: destinationLine(summary.destination),
            cadence: scheduleLine(summary),
            formats: formatsLine(summary),
            isActive: summary.isActive,
            cadenceColor: scheduleColor(summary.scheduleStatus)
        )
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
                localized: "API: \(url ?? String(localized: "not configured"))",
                comment: "Profile row destination line for an API endpoint target"
            )
        case .agentDataGateway(let url):
            return String(
                localized: "Agent Data gateway: \(url ?? String(localized: "not configured"))",
                comment: "Profile row destination line for an Agent Data gateway target"
            )
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
                return ScheduleDisplayCopy.cadence(count: interval, unit: unit, at: cadence.timeLabel)
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
    @EnvironmentObject private var syncService: SyncService
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID

    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var showDeleteConfirmation = false
    @State private var showScheduleEditor = false
    @State private var showSettingsEditor = false
    // Keep the immutable ID's copy receipt readable until this detail closes.
    // A timer can erase it before a slow AX snapshot or VoiceOver read finishes.
    @State private var idCopied = false
    @State private var contextBindingPeer: UUID?
    @State private var pendingContextPeer: UUID?
    @State private var showContextBindingConfirmation = false
    @State private var contextBindingError: String?
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
                if profile.target == .connectedMac {
                    contextAutomationCard
                }
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
        .onAppear {
            contextBindingPeer = AppleContextPhoneClient.shared.boundPeer(profileID: profileID)
        }
        .alert("Bind context automation?", isPresented: $showContextBindingConfirmation) {
            Button("Bind to this Mac") { bindContextAutomation() }
            Button("Cancel", role: .cancel) { pendingContextPeer = nil }
        } message: {
            Text("Allow this profile’s refresh shortcuts to use the currently authenticated Mac’s encrypted context. Confirm again to replace an earlier binding. This does not change file exports.")
        }
        .alert("Context automation unavailable", isPresented: Binding(
            get: { contextBindingError != nil },
            set: { if !$0 { contextBindingError = nil } }
        )) {
            Button("OK", role: .cancel) { contextBindingError = nil }
        } message: {
            Text(contextBindingError ?? "")
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

    private var contextAutomationCard: some View {
        sectionCard(title: String(localized: "Mac context automation")) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Text(contextBindingPeer == nil
                     ? String(localized: "Not bound. Refresh shortcuts require a separate authenticated Mac binding.")
                     : String(localized: "A Mac binding is saved. Refresh shortcuts require that same authenticated Mac."))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Connect both updated apps using authenticated Manual IP pairing before binding. Refresh uses this profile’s Apple Health scope without creating export files.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Bind context automation to this authenticated Mac") {
                    configurationProtection.performConfigurationChange {
                        guard syncService.canUsePhoneContextAutomation,
                              let peer = syncService.authenticatedContextPeerID else {
                            contextBindingError = AppleContextPhoneClient.ClientError.unavailable.localizedDescription
                            return
                        }
                        pendingContextPeer = peer
                        showContextBindingConfirmation = true
                    }
                }
                .accessibilityIdentifier("export.profiles.bind-context")
                .accessibilityHint("Confirms the authenticated Mac used by this profile’s context refresh shortcuts.")
            }
        }
    }

    private func bindContextAutomation() {
        let peer = pendingContextPeer
        pendingContextPeer = nil
        configurationProtection.performConfigurationChange {
            do {
                guard let peer, let profile, profile.target == .connectedMac else {
                    throw AppleContextPhoneClient.ClientError.profile
                }
                try AppleContextPhoneClient.shared.bind(profileID: profileID, expectedPeerID: peer)
                contextBindingPeer = peer
            } catch {
                contextBindingError = error.localizedDescription
            }
        }
    }

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
        let gateway = destinationStore.agentDataGateway(
            id: destinationStore.agentDataGatewayBinding(profileID: profile.id)
        )
        return sectionCard(title: String(localized: "Destination", comment: "Profile detail card title")) {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                factRow(
                    title: String(localized: "Target", comment: "Profile detail target row"),
                    value: profile.target.title
                )
                switch ExportProfileDestinationSummary.from(profile: profile, vault: vault, endpoint: endpoint, gateway: gateway) {
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
                case .agentDataGateway(let url):
                    factRow(
                        title: String(localized: "Gateway", comment: "Profile detail gateway row"),
                        value: url ?? String(localized: "Not configured", comment: "Missing gateway fallback")
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
                        title: String(localized: "Data Detail", comment: "Profile detail data-detail row"),
                        value: AppleExportDetailPreset(
                            policy: settings.detailPolicy
                        ).localizedTitle
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
        let periods: [String] = settings.generateRangeSummary
            ? [String(localized: "Range", comment: "Roll-up period")]
            : []
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
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Spacing.s2)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
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
            return ScheduleDisplayCopy.cadence(count: interval, unit: unit, at: cadence.timeLabel)
        }
        line += " · \(cadence.timeLabel)"
        return line
    }

    private func profileIDCard(for profile: ExportProfile) -> some View {
        sectionCard(title: String(localized: "Profile ID", comment: "Profile detail card title")) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text("Use this ID to pin the profile in Shortcuts, the CLI (`healthmd export --profile`), and API automation.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: Spacing.s2) {
                    Text(profile.id.uuidString)
                        .font(Typography.monoEmphasis())
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        UIPasteboard.general.string = profile.id.uuidString
                        // Keep the completion state readable for the lifetime of this detail,
                        // including accessibility clients that observe after tap synchronization.
                        idCopied = true
                    } label: {
                        Label(
                            idCopied
                                ? String(localized: "Copied", comment: "Confirmation after copying the profile ID")
                                : String(localized: "Copy", comment: "Action copying the profile ID"),
                            systemImage: idCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, Spacing.s2)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(AccessibilityID.ExportProfiles.copyIDButton)
                    .accessibilityLabel(String(localized: "Copy profile ID", comment: "Accessibility label for the copy ID button"))
                    .accessibilityValue(
                        idCopied
                            ? String(localized: "Copied", comment: "Accessibility value after copying the profile ID")
                            : String(localized: "Not copied", comment: "Accessibility value before copying the profile ID")
                    )
                }
            }
        }
    }

    private func actionsCard(for profile: ExportProfile) -> some View {
        sectionCard(title: String(localized: "Actions", comment: "Profile detail card title")) {
            VStack(spacing: 0) {
                if profile.id != profileStore.activeProfileID {
                    SchedulingProfileManagementAction(
                        icon: "checkmark.circle.fill",
                        title: String(localized: "Make Active & Edit", comment: "Action activating this profile")
                    ) {
                        configurationProtection.performConfigurationChange {
                            coordinator.activate(profileID: profile.id)
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.ExportProfiles.makeActiveButton)

                    rowDivider()
                }

                SchedulingProfileManagementAction(
                    icon: "pencil",
                    title: String(localized: "Rename…", comment: "Action renaming this profile")
                ) {
                    configurationProtection.performConfigurationChange {
                        renameText = profile.name
                        showRenameAlert = true
                    }
                }

                rowDivider()

                SchedulingProfileManagementAction(
                    icon: "plus.square.on.square",
                    title: String(localized: "Duplicate", comment: "Action duplicating this profile")
                ) {
                    configurationProtection.performConfigurationChange {
                        duplicateAndWarn(profile)
                    }
                }

                rowDivider()

                SchedulingProfileManagementAction(
                    icon: "trash",
                    title: String(localized: "Delete Profile…", comment: "Action deleting this profile"),
                    isDestructive: true
                ) {
                    configurationProtection.performConfigurationChange {
                        showDeleteConfirmation = true
                    }
                }
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
                    localized: "Delete “\(profile.name)”",
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
        SchedulingProfileFact(title: title, value: value)
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
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @Environment(\.dismiss) private var dismiss

    /// Nil = creation mode; the profile being edited otherwise.
    private let editingProfileID: UUID?

    @State private var name: String
    @State private var target: ExportTargetSelection
    @State private var folderVaultID: UUID?
    @State private var apiEndpointID: UUID?
    @State private var agentDataGatewayID: UUID?
    @State private var draft: ExportSettingsSnapshot
    @StateObject private var metricState: MetricSelectionState
    /// Presents the system folder picker for a new destination binding.
    @State private var showFolderImporter = false
    /// Presents the inline form for a new API endpoint binding.
    @State private var showEndpointForm = false
    /// Presents the inline form for a new Agent Data gateway binding.
    @State private var showGatewayForm = false

    init(
        coordinator: ExportProfileCoordinator,
        editing profile: ExportProfile? = nil
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _destinationStore = ObservedObject(wrappedValue: coordinator.destinationStore)
        editingProfileID = profile?.id

        if let profile {
            _name = State(initialValue: profile.name)
            _target = State(initialValue: profile.target)
            _folderVaultID = State(initialValue: profile.folderVaultID)
            _apiEndpointID = State(initialValue: profile.apiEndpointID)
            _agentDataGatewayID = State(initialValue: coordinator.destinationStore.agentDataGatewayBinding(profileID: profile.id))
            _draft = State(initialValue: profile.settings)
        } else {
            // Creation defaults mirror what a plain duplicate would produce,
            // so the overlap warning starts honest.
            _name = State(initialValue: coordinator.suggestedProfileName())
            _target = State(initialValue: coordinator.activeTarget ?? .localIPhoneFolder)
            let active = coordinator.profileStore.activeProfile
            _folderVaultID = State(initialValue: active?.folderVaultID)
            _apiEndpointID = State(initialValue: active?.apiEndpointID)
            _agentDataGatewayID = State(initialValue: active.flatMap {
                coordinator.destinationStore.agentDataGatewayBinding(profileID: $0.id)
            })
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
        !trimmedName.isEmpty
            && (draft.dailyNoteInjection.dailyNotesOnly || !draft.exportFormats.isEmpty)
    }

    private var overlappingNames: [String] {
        coordinator.overlapPreviewNames(
            target: target,
            folderVaultID: folderVaultID,
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Resolved here rather than read from the environment, because this sheet
    /// is presented from both the glass shell and the legacy profiles list.
    private var palette: GlassPalette {
        GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
    }

    private static let dateTokens = ["{date}", "{year}", "{month}", "{day}", "{weekday}", "{monthName}", "{quarter}"]

    private var titleText: String {
        editingProfile == nil
            ? String(localized: "New Profile")
            : String(localized: "Edit Profile")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                    identitySection
                    destinationSection
                    outputSection
                    rollupSection
                    metricsSection
                    dailyNotesSection
                    individualTrackingSection
                    overlapSection
                }
                .padding(GlassMetrics.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .tint(palette.accent)
            .background(palette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { header }
            // The root draws its own glass header; the title still names the
            // back button of the pushed metric picker.
            .navigationTitle(Text(titleText))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .glassTheme()
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
        // inside a conditional section: a section re-render (for example when
        // the destination store publishes) tears down sheets attached within
        // it, which dismissed the endpoint form a moment after it appeared.
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
        .sheet(isPresented: $showGatewayForm) {
            ExportProfileGatewayFormSheet { name, url in
                // Adding a gateway persists it immediately, so the shared
                // lock still guards this completion.
                configurationProtection.performConfigurationChange {
                    if let gatewayID = coordinator.importAgentDataGatewaySelection(
                        name: name,
                        endpointURLString: url
                    ) {
                        agentDataGatewayID = gatewayID
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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

    /// Glass header: Cancel and Create/Save capsules around the title.
    private var header: some View {
        ZStack {
            Text(titleText)
                .glassFont(.navTitle)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .padding(.horizontal, 96)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Button { dismiss() } label: {
                    Text(String(localized: "Cancel"))
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(palette.surface2))
                        .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: GlassMetrics.touchTarget)

                Spacer(minLength: 8)

                Button {
                    // The draft stays inspectable, but persisting a profile
                    // is a configuration mutation, so the shared lock can
                    // reject an editor that was already open when
                    // protection was turned on.
                    configurationProtection.performConfigurationChange {
                        save()
                        dismiss()
                    }
                } label: {
                    Text(editingProfile == nil ? String(localized: "Create") : String(localized: "Save"))
                        .glassFont(.navTitle)
                        .foregroundStyle(palette.accentInk)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background(Capsule().fill(palette.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .frame(minHeight: GlassMetrics.touchTarget)
                .opacity(canSave ? 1 : 0.4)
                .disabled(!canSave)
                .accessibilityIdentifier("export.profiles.editor.confirm")
            }
        }
        .padding(.horizontal, GlassMetrics.screenMargin)
        .padding(.top, Spacing.s3)
        .padding(.bottom, Spacing.s2)
        .background(palette.bg.ignoresSafeArea(edges: .top))
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
                agentDataGatewayID: target == .agentDataGateway ? agentDataGatewayID : nil,
                settings: snapshot
            )
        } else {
            coordinator.createProfile(
                name: trimmedName,
                target: target,
                folderVaultID: target == .localIPhoneFolder ? folderVaultID : nil,
                apiEndpointID: target == .apiEndpoint ? apiEndpointID : nil,
                agentDataGatewayID: target == .agentDataGateway ? agentDataGatewayID : nil,
                settings: snapshot
            )
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Profile"))
            GlassPanel {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Name", comment: "Profile editor name field label"))
                        .glassFont(.caption)
                        .foregroundStyle(palette.muted)
                    TextField(
                        String(localized: "Name", comment: "Profile editor name field label"),
                        text: $name
                    )
                    .textFieldStyle(.plain)
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                    .frame(minHeight: GlassMetrics.touchTarget)
                    .accessibilityIdentifier("export.profiles.editor.name")
                }
                .padding(.horizontal, GlassMetrics.panelPadding)
                .padding(.vertical, 10)
            }
            footnote(editingProfile == nil
                ? String(localized: "Starts from the current export settings.")
                : String(localized: "Scheduled exports pick up the new settings on their next run."))
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Destination"))
            GlassPanel {
                EditorMenuRow(
                    title: String(localized: "Target", comment: "Profile editor target picker label"),
                    selection: $target,
                    options: [.localIPhoneFolder, .connectedMac, .apiEndpoint, .agentDataGateway],
                    label: Self.targetTitle,
                    palette: palette
                )

                switch target {
                case .localIPhoneFolder:
                    rowDivider
                    EditorMenuRow(
                        title: String(localized: "Folder", comment: "Profile editor folder picker label"),
                        selection: $folderVaultID,
                        options: [nil] + destinationStore.vaults.map { Optional($0.id) },
                        label: { id in
                            destinationStore.vaults.first { $0.id == id }?.name
                                ?? String(
                                    localized: "Current folder (from Export tab)",
                                    comment: "Editor option using the live shared vault"
                                )
                        },
                        palette: palette
                    )
                    rowDivider
                    addRow(
                        String(localized: "Choose New Folder…", comment: "Profile editor action opening the system folder picker"),
                        systemImage: "folder.badge.plus",
                        identifier: "export.profiles.editor.chooseFolder"
                    ) { showFolderImporter = true }
                case .apiEndpoint:
                    rowDivider
                    EditorMenuRow(
                        title: String(localized: "Endpoint", comment: "Profile editor endpoint picker label"),
                        selection: $apiEndpointID,
                        options: [nil] + destinationStore.apiEndpoints.map { Optional($0.id) },
                        label: { id in
                            destinationStore.apiEndpoints.first { $0.id == id }?.name
                                ?? String(
                                    localized: "Current endpoint (from Export tab)",
                                    comment: "Editor option using the live API endpoint"
                                )
                        },
                        palette: palette
                    )
                    rowDivider
                    addRow(
                        String(localized: "Add Endpoint…", comment: "Profile editor action adding a new API endpoint"),
                        systemImage: "network.badge.plus",
                        identifier: "export.profiles.editor.addEndpoint"
                    ) { showEndpointForm = true }
                case .agentDataGateway:
                    rowDivider
                    EditorMenuRow(
                        title: String(localized: "Gateway", comment: "Profile editor gateway picker label"),
                        selection: $agentDataGatewayID,
                        options: [nil] + destinationStore.agentDataGateways.map { Optional($0.id) },
                        label: { id in
                            destinationStore.agentDataGateways.first { $0.id == id }?.name
                                ?? String(
                                    localized: "Current gateway (from Export tab)",
                                    comment: "Editor option using the live Agent Data gateway"
                                )
                        },
                        palette: palette
                    )
                    rowDivider
                    addRow(
                        String(localized: "Add Gateway…", comment: "Profile editor action adding a new Agent Data gateway"),
                        systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                        identifier: "export.profiles.editor.addGateway"
                    ) { showGatewayForm = true }
                case .connectedMac:
                    EmptyView()
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
            VStack(alignment: .leading, spacing: 8) {
                GlassSectionLabel(title: String(localized: "Output"))
                GlassPanel {
                    ForEach(Array(ExportFormat.allCases.enumerated()), id: \.element.rawValue) { index, format in
                        if index > 0 { rowDivider }
                        GlassToggleRow(
                            title: format.localizedDisplayName,
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
                        .opacity(draft.dailyNoteInjection.dailyNotesOnly ? 0.45 : 1)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GlassSectionLabel(title: String(localized: "When file exists", comment: "Profile editor write mode picker label"))
                GlassSegmentedControl(
                    segments: WriteMode.allCases.map { .init(value: $0, title: $0.localizedDisplayName) },
                    selection: $draft.writeMode
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(String(localized: "When file exists", comment: "Profile editor write mode picker label"))
            }

            GlassPanel {
                GlassTemplateField(
                    title: String(localized: "Filename template", comment: "Profile editor filename template field"),
                    text: $draft.filenameFormat,
                    tokens: Self.dateTokens
                )
                rowDivider
                GlassTemplateField(
                    title: String(localized: "Folder template", comment: "Profile editor folder template field"),
                    text: $draft.folderStructure,
                    tokens: Self.dateTokens
                )
            }
            footnote(String(localized: "Templates accept {date}, {year}, {month}, {day}, {weekday}, {monthName}, and {quarter}."))

            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Format folders", comment: "Profile editor format folders toggle"),
                    isOn: $draft.organizeFormatsIntoFolders
                )
                rowDivider
                GlassToggleRow(
                    title: String(localized: "Zip archive", comment: "Profile editor zip toggle"),
                    isOn: $draft.archiveExportFiles
                )
                rowDivider
                GlassToggleRow(
                    title: String(localized: "Data dictionary", comment: "Profile editor data dictionary toggle"),
                    isOn: $draft.includeDataDictionary
                )
                rowDivider
                EditorMenuRow(
                    title: String(localized: "Data Detail", comment: "Profile editor data-detail picker"),
                    selection: Binding(
                        get: { AppleExportDetailPreset(policy: draft.detailPolicy) },
                        set: { draft.detailPolicy = $0.policy }
                    ),
                    options: detailPresetOptions,
                    label: { $0.localizedTitle },
                    palette: palette
                )
                Text(AppleExportDetailPreset(policy: draft.detailPolicy).localizedDescription)
                    .glassFont(.rowSubtitle)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, GlassMetrics.panelPadding)
                    .padding(.bottom, 12)
                rowDivider
                GlassToggleRow(
                    title: String(localized: "Summary only", comment: "Profile editor summary-only toggle"),
                    isOn: $draft.summaryOnlyExport
                )
            }
        }
    }

    private var detailPresetOptions: [AppleExportDetailPreset] {
        var options: [AppleExportDetailPreset] = [.summary, .detailedTimeSeries, .losslessHealthRecords]
        if draft.detailPolicy == .archiveOnly {
            options.append(.archiveOnly)
        }
        return options
    }

    private var rollupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Roll-Ups"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Range summary", comment: "Profile editor range-summary toggle"),
                    isOn: $draft.generateRangeSummary
                )
            }
        }
    }

    private var metricsSection: some View {
        let enabled = metricState.enabledMetrics.count
        let total = HealthMetrics.availableInCurrentBuild
            .filter { !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform }
            .count
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Metrics"))
            GlassPanel {
                NavigationLink {
                    MetricSelectionView(
                        selectionState: metricState,
                        healthKitManager: HealthKitManager.shared
                    )
                } label: {
                    GlassRow(title: String(localized: "Health Metrics")) {
                        HStack(spacing: 8) {
                            Text(String(
                                localized: "\(enabled) of \(total)",
                                comment: "Enabled versus total metric count in the profile editor"
                            ))
                            .glassFont(.body)
                            .foregroundStyle(palette.sec)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(palette.muted)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dailyNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Daily Notes"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Inject into daily notes", comment: "Profile editor daily note injection toggle"),
                    isOn: $draft.dailyNoteInjection.enabled
                )
                rowDivider
                GlassToggleRow(
                    title: String(localized: "Daily Notes only", comment: "Profile editor daily-notes-only toggle"),
                    isOn: $draft.dailyNoteInjection.dailyNotesOnly
                )
                if draft.dailyNoteInjection.enabled {
                    rowDivider
                    GlassTemplateField(
                        title: String(localized: "Notes folder", comment: "Profile editor daily notes folder field"),
                        text: $draft.dailyNoteInjection.folderPath
                    )
                    rowDivider
                    GlassTemplateField(
                        title: String(localized: "Notes filename", comment: "Profile editor daily notes filename field"),
                        text: $draft.dailyNoteInjection.filenamePattern
                    )
                    rowDivider
                    GlassToggleRow(
                        title: String(localized: "Create if missing", comment: "Profile editor daily notes create toggle"),
                        isOn: $draft.dailyNoteInjection.createIfMissing
                    )
                    rowDivider
                    GlassToggleRow(
                        title: String(localized: "Markdown sections", comment: "Profile editor daily notes sections toggle"),
                        isOn: $draft.dailyNoteInjection.injectMarkdownSections
                    )
                }
            }
        }
    }

    private var individualTrackingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionLabel(title: String(localized: "Individual Entries"))
            GlassPanel {
                GlassToggleRow(
                    title: String(localized: "Individual entries", comment: "Profile editor individual tracking toggle"),
                    isOn: $draft.individualTracking.globalEnabled
                )
                if draft.individualTracking.globalEnabled {
                    rowDivider
                    GlassTemplateField(
                        title: String(localized: "Entries folder", comment: "Profile editor entries folder field"),
                        text: $draft.individualTracking.entriesFolder
                    )
                    rowDivider
                    GlassToggleRow(
                        title: String(localized: "Category folders", comment: "Profile editor category folders toggle"),
                        isOn: $draft.individualTracking.useCategoryFolders
                    )
                }
            }
            footnote(String(localized: "Per-metric entry rules are edited from the Export tab while this profile is active."))
        }
    }

    @ViewBuilder
    private var overlapSection: some View {
        if !overlappingNames.isEmpty {
            let names = overlappingNames.joined(separator: ", ")
            GlassBanner(
                title: String(
                    localized: "Overlaps \(names): later runs overwrite earlier ones. Choose a different folder or filename template to keep them separate.",
                    comment: "Live editor warning that the profile's output files overlap other profiles; the interpolated value is a comma-separated profile name list"
                ),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }
    }

    // MARK: - Glass building blocks

    private var rowDivider: some View {
        Rectangle()
            .fill(palette.line)
            .frame(height: 1)
            .padding(.leading, GlassMetrics.panelPadding)
            .accessibilityHidden(true)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .glassFont(.rowSubtitle)
            .foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    /// Accent "+ Add…" row. Adding a destination persists it, so the shared
    /// lock guards opening the form.
    private func addRow(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            configurationProtection.performConfigurationChange(action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .glassFont(.body)
                    .foregroundStyle(palette.accent)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .frame(minHeight: GlassMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }

    private static func targetTitle(_ target: ExportTargetSelection) -> String {
        switch target {
        case .localIPhoneFolder: return String(localized: "Local Folder")
        case .connectedMac: return String(localized: "Connected Mac")
        case .apiEndpoint: return String(localized: "API Endpoint")
        case .agentDataGateway: return String(localized: "Agent Data gateway")
        }
    }
}

/// A labelled glass row whose current value opens a menu of choices. The value
/// sits in the accent colour with a down chevron so it reads as tappable, and
/// the menu marks the current choice. The whole row is one button named by its
/// title, so VoiceOver and UI tests address it as "Target", "Folder", etc.
private struct EditorMenuRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    let palette: GlassPalette

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .glassFont(.body)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text(label(selection))
                    .glassFont(.body)
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GlassMetrics.panelPadding)
            .frame(minHeight: GlassMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection))
    }
}

/// Inline form for adding a new API endpoint destination from the profile
/// editor. Nothing is imported until Add; the token is stored in the
/// destination store's Keychain-backed slot, not in the live shared endpoint
/// settings.
struct ExportProfileEndpointFormSheet: View {
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
                .glassFormRows()

                Section {
                    TextField(
                        String(localized: "URL", comment: "Endpoint form URL field label"),
                        text: $url
                    )
                    .keyboardType(.URL)
                    .accessibilityIdentifier("export.profiles.editor.endpointURL")
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
                .glassFormRows()
            }
            .glassFormChrome()
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

/// Inline form for adding a new Agent Data gateway destination binding.
/// Gateways carry no credential in ingestion protocol v1, so the form is a
/// name plus one endpoint URL.
struct ExportProfileGatewayFormSheet: View {
    let onAdd: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""

    private var trimmedURL: String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool {
        AgentDataGatewayEndpoint.isConfigured(trimmedURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        String(localized: "Name", comment: "Gateway form name field label"),
                        text: $name
                    )
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                } header: {
                    Text("Gateway")
                } footer: {
                    Text("Optional. Defaults to the URL.")
                }
                .glassFormRows()

                Section {
                    TextField(
                        String(localized: "URL", comment: "Gateway form URL field label"),
                        text: $url
                    )
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                    HStack {
                        Image(systemName: canAdd ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(canAdd ? Color.success : Color.warning)
                        Text(LocalizedStringKey(canAdd ? "Valid gateway URL" : "Enter a valid HTTP or HTTPS URL"))
                    }
                } footer: {
                    Text("Health.md uploads each exported artifact file unchanged to this gateway's /v1/ingest endpoint using the Agent Data protocol. Gateways need no token in this version.")
                }
                .glassFormRows()
            }
            .glassFormChrome()
            .navigationTitle(Text("New Gateway"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(name, trimmedURL)
                        dismiss()
                    }
                    .disabled(!canAdd)
                    .accessibilityIdentifier("export.profiles.editor.addGateway.confirm")
                }
            }
        }
    }
}
#endif

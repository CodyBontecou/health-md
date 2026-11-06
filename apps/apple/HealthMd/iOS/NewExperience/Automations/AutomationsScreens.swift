#if os(iOS)
import SwiftUI
import UIKit

/// Shared derivations for automation screens.
struct AutomationFacts {
    let coordinator: ExportProfileCoordinator

    func entry(_ profile: ExportProfile) -> ScheduledExportEntry? {
        coordinator.scheduledEntryStore.entry(profileID: profile.id)
    }

    func destination(_ profile: ExportProfile) -> String {
        let store = coordinator.destinationStore
        let summary = ExportProfileDestinationSummary.from(
            profile: profile,
            vault: store.vault(id: profile.folderVaultID),
            endpoint: store.apiEndpoint(id: profile.apiEndpointID),
            gateway: store.agentDataGateway(id: store.agentDataGatewayBinding(profileID: profile.id))
        )
        switch summary {
        case .localFolder(let name): return name ?? String(localized: "iPhone folder")
        case .connectedMac: return String(localized: "Connected Mac")
        case .apiEndpoint(let url), .agentDataGateway(let url):
            return url ?? String(localized: "not configured")
        }
    }

    func sentence(_ profile: ExportProfile, style: AutomationSentence.Style = .summary) -> AutomationSentence {
        .make(profile: profile, entry: entry(profile), destination: destination(profile), style: style)
    }

    /// The editable sentence of a profile with staged, unsaved settings.
    func composerSentence(_ profile: ExportProfile, settings: ExportSettingsSnapshot) -> AutomationSentence {
        .make(
            settings: settings,
            sends: profile.target == .apiEndpoint || profile.target == .agentDataGateway,
            entry: entry(profile),
            destination: destination(profile),
            style: .composer,
            availableMetricCount: AutomationSentence.availableMetricCount
        )
    }

    func nextRun(_ profile: ExportProfile, now: Date = Date()) -> Date? {
        guard let entry = entry(profile), entry.isEnabled else { return nil }
        return ScheduleDateMath.calculateNextRunDate(schedule: entry.dateMathProjection, now: now)
    }

    func statusLine(_ profile: ExportProfile, now: Date = Date()) -> String {
        guard let entry = entry(profile) else { return String(localized: "No schedule") }
        guard entry.isEnabled else { return String(localized: "Paused") }
        guard let next = nextRun(profile, now: now) else { return String(localized: "Scheduled") }
        return String(localized: "Next · \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
    }

    /// The short status of the iPad list: "Sun 7:30", "Paused" or "No schedule".
    func shortStatus(_ profile: ExportProfile, now: Date = Date()) -> String {
        guard let entry = entry(profile) else { return String(localized: "No schedule") }
        guard entry.isEnabled else { return String(localized: "Paused") }
        guard let next = nextRun(profile, now: now) else { return String(localized: "Scheduled") }
        return next.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    /// Coverage of the 14 completed days before today, oldest first.
    func recentDays(_ profile: ExportProfile, ledger: CoverageLedger, now: Date = Date(), calendar: Calendar = .current) -> [CoverageStatus] {
        let today = calendar.startOfDay(for: now)
        let input = CoverageProjection.Input(
            profileID: profile.id,
            entry: entry(profile),
            ledger: ledger,
            now: now,
            calendar: calendar
        )
        return (1...14).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today)
        }.map { CoverageProjection.day(for: $0, input: input).status }
    }

    /// "Daily 7:30", "Sunday 8:00", a custom cadence, "Paused" or "Off".
    static func scheduleShortLabel(_ entry: ScheduledExportEntry?) -> String {
        guard let entry else { return String(localized: "Off") }
        guard entry.isEnabled else { return String(localized: "Paused") }
        let cadence = ExportProfileCadenceSummary.from(entry)
        if let interval = cadence.customInterval, let unit = cadence.customUnit {
            return ScheduleDisplayCopy.cadence(count: interval, unit: unit, at: cadence.timeLabel)
        }
        if let weekday = cadence.weekdayIndex {
            return "\(ExportProfileCadenceSummary.weekdayName(weekday)) \(cadence.timeLabel)"
        }
        return "\(cadence.frequencyDescription) \(cadence.timeLabel)"
    }

    /// "MD · Bases": file-type abbreviations, so they are not translated.
    static func formatsShortLabel(_ formats: Set<ExportFormat>) -> String {
        ExportProfileCardSummary.sortedFormats(formats).map { format in
            switch format {
            case .markdown: return "MD"
            case .obsidianBases: return "Bases"
            case .json: return "JSON"
            case .csv: return "CSV"
            }
        }.joined(separator: " · ")
    }

    /// "Standard" until the frontmatter fields or Markdown body are customized.
    static func formatStyleLabel(_ customization: FormatCustomizationSnapshot) -> String {
        let standard = FormatCustomizationSnapshot.from(FormatCustomization())
        let isStandard = customization.frontmatterConfig == standard.frontmatterConfig
            && customization.markdownTemplate == standard.markdownTemplate
        return isStandard ? String(localized: "Standard") : String(localized: "Custom")
    }
}

/// The settings rows of one automation, shared by its detail and the wide composer.
struct AutomationSettingsRows: View {
    let profile: ExportProfile
    let entry: ScheduledExportEntry?
    var includesAllRows = true
    let onPage: (GlassProfilePageKind) -> Void
    let onSchedule: () -> Void

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        GlassPanel {
            row(String(localized: "Metrics"), value: "\(profile.settings.metricSelection.enabledMetricIDs.count)") {
                onPage(.metrics)
            }
            .accessibilityIdentifier("glass.automation.metrics")
            row(
                String(localized: "Formats & detail"),
                value: AutomationFacts.formatsShortLabel(profile.settings.exportFormats)
            ) { onPage(.formats) }
            .accessibilityIdentifier("glass.automation.formats")
            row(String(localized: "Output"), value: profile.settings.writeMode.localizedDisplayName) {
                onPage(.output)
            }
            .accessibilityIdentifier("glass.automation.output")
            if includesAllRows {
                row(
                    String(localized: "Format"),
                    value: AutomationFacts.formatStyleLabel(profile.settings.formatCustomization)
                ) { onPage(.formatCustom) }
                .accessibilityIdentifier("glass.automation.formatCustom")
            }
            row(String(localized: "Daily notes"), value: onOff(profile.settings.dailyNoteInjection.enabled)) {
                onPage(.dailyNotes)
            }
            .accessibilityIdentifier("glass.automation.dailyNotes")
            if includesAllRows {
                row(
                    String(localized: "Individual entries"),
                    value: onOff(profile.settings.individualTracking.globalEnabled)
                ) { onPage(.entries) }
                .accessibilityIdentifier("glass.automation.entries")
            }
            row(String(localized: "Schedule"), value: AutomationFacts.scheduleShortLabel(entry), action: onSchedule)
                .accessibilityIdentifier("glass.automation.schedule")
        }
    }

    private func onOff(_ isOn: Bool) -> String {
        isOn ? String(localized: "On") : String(localized: "Off")
    }

    private func row(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button {
            configurationProtection.performConfigurationChange(action)
        } label: {
            GlassRow(title: title) {
                Text(value).glassFont(.rowSubtitle).foregroundStyle(palette.muted).lineLimit(1)
                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The last 14 completed days of one automation, as small tiles.
struct AutomationRecentStrip: View {
    let days: [CoverageStatus]
    @Environment(\.glassPalette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, status in
                tile(status)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func tile(_ status: CoverageStatus) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        switch status {
        case .complete:
            shape.fill(palette.fill).overlay(alignment: .top) { Color.glassWhite(0.22).frame(height: 1).clipShape(shape) }
                .frame(width: 12, height: 12)
        case .partial, .inProgress:
            shape.fill(palette.tint).frame(width: 12, height: 12)
        case .missing:
            shape.strokeBorder(palette.coral, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 12, height: 12)
        case .notDue, .paused:
            shape.fill(palette.surface).frame(width: 12, height: 12)
        }
    }
}

/// AutomationsGlass. An automation is an export profile with an optional schedule.
struct AutomationsScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    @ObservedObject private var ledgerStore = CoverageLedgerStore.shared
    let onRun: (UUID) -> Void
    let onPreview: (UUID) -> Void
    let onSchedulesChanged: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var showCreation = false
    @State private var selectedProfileID: UUID?
    /// The composer pane's unsaved choices; kept here so a switch can ask first.
    @State private var paneDraft = ComposerDraft()
    /// The automation picked while the pane had unsaved choices.
    @State private var pendingSelectionID: UUID?

    /// `historyContent` and `onOpenExportSettings` are ignored: AutomationsGlass has no
    /// "Schedule & history" or "All export settings" rows. Scheduling lives on each card's
    /// switch and ScheduleG, history and retry on the Archive and ExportResultG, and the
    /// old Export tab's settings on the automation pages (FormatsG holds sleep attribution).
    init(
        coordinator: ExportProfileCoordinator,
        historyContent: AnyView = AnyView(EmptyView()),
        onRun: @escaping (UUID) -> Void,
        onPreview: @escaping (UUID) -> Void,
        onSchedulesChanged: @escaping () -> Void,
        onOpenExportSettings: @escaping () -> Void = {}
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.onRun = onRun
        self.onPreview = onPreview
        self.onSchedulesChanged = onSchedulesChanged
    }

    private var facts: AutomationFacts { AutomationFacts(coordinator: coordinator) }

    /// iPadAutomationsG: regular width on iPad shows the list beside the selected
    /// automation. An unfolded phone keeps the column; its composer is DuoInnerComposeG.
    private var usesTwoPanes: Bool {
        horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad
    }

    /// The selected automation, or the first one once the selection is deleted.
    private var paneProfileID: UUID? {
        if let selectedProfileID, profileStore.profile(id: selectedProfileID) != nil { return selectedProfileID }
        return profileStore.profiles.first?.id
    }

    private func detail(_ profileID: UUID) -> some View {
        AutomationDetailScreen(
            coordinator: coordinator,
            profileID: profileID,
            onRun: onRun,
            onPreview: onPreview,
            onSchedulesChanged: onSchedulesChanged
        )
    }

    var body: some View {
        Group {
            if usesTwoPanes {
                HStack(spacing: 0) {
                    NavigationStack { list }
                        .frame(width: GlassMetrics.listPaneWidth)
                    // iPadAutomationsG: the selected automation opens as the composer.
                    NavigationStack {
                        if let id = paneProfileID {
                            AutomationComposerPane(
                                coordinator: coordinator,
                                profileID: id,
                                draft: $paneDraft,
                                onRun: onRun,
                                onPreview: onPreview,
                                onSchedulesChanged: onSchedulesChanged
                            )
                            .id(id)
                        }
                    }
                }
            } else {
                NavigationStack { list.glassTabRoot() }
            }
        }
        .sheet(isPresented: $showCreation) {
            ExportProfileEditorSheet(coordinator: coordinator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            String(localized: "Save changes to this automation?"),
            isPresented: Binding(
                get: { pendingSelectionID != nil },
                set: { if !$0 { pendingSelectionID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Save")) { saveDraftAndSwitch() }
            Button(String(localized: "Discard"), role: .destructive) { switchPane(to: pendingSelectionID) }
            Button(String(localized: "Cancel"), role: .cancel) { pendingSelectionID = nil }
        }
        // A deleted selection falls back to another automation; its staged choices go with it.
        .onChange(of: paneProfileID) { _, _ in paneDraft = ComposerDraft() }
        .accessibilityIdentifier("glass.automations")
    }

    /// "… or call with `healthmd export --profile`." with the command in mono.
    private var introText: AttributedString {
        let command = "healthmd export --profile"
        var text = AttributedString(String(localized: "Saved exports you can schedule, run from Shortcuts, or call with \(command)."))
        if let range = text.range(of: command) {
            text[range].font = .system(size: 13, design: .monospaced)
        }
        return text
    }

    private var list: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Automations").glassFont(.largeTitle).foregroundStyle(palette.text)
                        Spacer()
                        Button {
                            configurationProtection.performConfigurationChange { showCreation = true }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.text)
                                .frame(width: GlassMetrics.touchTarget, height: GlassMetrics.touchTarget)
                                .glassSurface(in: Circle(), isInteractive: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "New automation"))
                    }
                    // AutomationsGlass leads with the intro; iPadAutomationsG's list pane has none.
                    if !usesTwoPanes {
                        Text(introText)
                            .glassFont(.body)
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                    }

                    ForEach(profileStore.profiles) { profile in
                        if usesTwoPanes {
                            Button { select(profile.id) } label: { compactCard(profile) }
                                .accessibilityIdentifier("glass.automation.card")
                                .buttonStyle(.plain)
                        } else {
                            NavigationLink { detail(profile.id) } label: { card(profile) }
                                .accessibilityIdentifier("glass.automation.card")
                                .buttonStyle(.plain)
                                .overlay(alignment: .topTrailing) { enabledSwitch(profile) }
                        }
                    }
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, GlassMetrics.scrollBottomInset)
            }
            .background(palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }

    /// Unsaved pane choices are never dropped silently: switching asks to Save or Discard.
    private func select(_ profileID: UUID) {
        guard profileID != paneProfileID else { return }
        if paneDraft.isEmpty {
            selectedProfileID = profileID
        } else {
            pendingSelectionID = profileID
        }
    }

    private func saveDraftAndSwitch() {
        // The dialog clears the pending choice as it closes, possibly before an unlock finishes.
        let target = pendingSelectionID
        let staged = paneDraft
        configurationProtection.performConfigurationChange {
            if let id = paneProfileID, let current = profileStore.profile(id: id) {
                coordinator.saveSettings(staged.settings(from: current.settings), for: current)
            }
            switchPane(to: target)
        }
    }

    private func switchPane(to target: UUID?) {
        paneDraft = ComposerDraft()
        if let target { selectedProfileID = target }
        pendingSelectionID = nil
    }

    /// The schedule switch sits over the card, outside its link.
    @ViewBuilder private func enabledSwitch(_ profile: ExportProfile) -> some View {
        if let entry = entryStore.entries.first(where: { $0.profileID == profile.id }) {
            Toggle(isOn: Binding(
                get: { entry.isEnabled },
                set: { setEnabled($0, profileID: profile.id) }
            )) {
                Text(profile.name)
            }
            .labelsHidden()
            .toggleStyle(GlassToggleStyle())
            .fixedSize()
            .padding(.top, 10)
            .padding(.trailing, 20)
        }
    }

    private func setEnabled(_ isEnabled: Bool, profileID: UUID) {
        configurationProtection.performConfigurationChange {
            entryStore.update(profileID: profileID) { $0.isEnabled = isEnabled }
            AutomationScheduleSwitch.didSwitch(
                isEnabled: isEnabled,
                entries: entryStore.entries,
                schedulingManager: schedulingManager
            )
            onSchedulesChanged()
        }
    }

    private func card(_ profile: ExportProfile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(profile.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.text)
                Spacer()
                // Room for the switch overlaid by the list.
                Color.clear.frame(width: GlassMetrics.switchSize.width, height: GlassMetrics.switchSize.height)
            }
            AutomationSentenceView(sentence: facts.sentence(profile), style: .body)
            HStack {
                AutomationRecentStrip(days: facts.recentDays(profile, ledger: ledgerStore.ledger))
                Spacer(minLength: 8)
                Text(facts.statusLine(profile)).glassFont(.caption).foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .contentShape(Rectangle())
    }

    /// iPadAutomationsG's list row: name, next run, and "when → where".
    private func compactCard(_ profile: ExportProfile) -> some View {
        let sentence = facts.sentence(profile)
        let isSelected = paneProfileID == profile.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.name).glassFont(.navTitle).foregroundStyle(palette.text)
                Spacer(minLength: 8)
                Text(facts.shortStatus(profile)).glassFont(.caption).foregroundStyle(palette.muted)
            }
            Text(verbatim: "\(sentence.values[.when] ?? "") → \(sentence.values[.where] ?? "")")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.sec)
                .lineLimit(2)
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(style: isSelected ? .strong : .regular)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// AutomationDetailG: the hub for one profile.
struct AutomationDetailScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    let profileID: UUID
    let onRun: (UUID) -> Void
    let onPreview: (UUID) -> Void
    let onSchedulesChanged: () -> Void
    /// The iPad pane is already the composer, so its pushed detail drops "Edit sentence".
    let showsComposerLink: Bool

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @EnvironmentObject private var syncService: SyncService
    @State private var showSchedule = false
    @State private var page: GlassProfilePageKind?
    @State private var idCopied = false
    @State private var showDeleteConfirmation = false
    @State private var showRename = false
    @State private var renameText = ""
    @State private var contextBindingPeer: UUID?
    @State private var pendingContextPeer: UUID?
    @State private var showContextBindingConfirmation = false
    @State private var contextBindingError: String?

    init(
        coordinator: ExportProfileCoordinator,
        profileID: UUID,
        onRun: @escaping (UUID) -> Void,
        onPreview: @escaping (UUID) -> Void,
        onSchedulesChanged: @escaping () -> Void,
        showsComposerLink: Bool = true
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.profileID = profileID
        self.onRun = onRun
        self.onPreview = onPreview
        self.onSchedulesChanged = onSchedulesChanged
        self.showsComposerLink = showsComposerLink
    }

    private var facts: AutomationFacts { AutomationFacts(coordinator: coordinator) }

    var body: some View {
        if let profile = profileStore.profile(id: profileID) {
            content(profile)
        }
    }

    private func content(_ profile: ExportProfile) -> some View {
        let entry = entryStore.entries.first { $0.profileID == profile.id }
        return ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 10) {
                    GlassSectionLabel(title: String(localized: "Automation"))
                    AutomationSentenceView(sentence: facts.sentence(profile), style: .body)
                    if showsComposerLink {
                        NavigationLink {
                            ComposerScreen(coordinator: coordinator, profileID: profile.id, onPreview: onPreview, onSchedulesChanged: onSchedulesChanged)
                        } label: {
                            Text(verbatim: String(localized: "Edit sentence") + " →")
                                .glassFont(.caption)
                                .foregroundStyle(palette.accent)
                                .frame(minHeight: GlassMetrics.touchTarget)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("glass.automation.editSentence")
                    }
                }
                .padding(GlassMetrics.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface()

                HStack(spacing: 8) {
                    GlassChip(title: String(localized: "Run now"), isSelected: true) { onRun(profile.id) }
                    GlassChip(title: String(localized: "Duplicate")) {
                        configurationProtection.performConfigurationChange {
                            _ = coordinator.duplicateProfile(id: profile.id)
                        }
                    }
                    if let entry {
                        GlassChip(title: entry.isEnabled ? String(localized: "Pause") : String(localized: "Resume")) {
                            setEnabled(!entry.isEnabled, profileID: profile.id)
                        }
                    }
                }

                let overlapping = coordinator.overlappingProfileNames(for: profile.id)
                if !overlapping.isEmpty {
                    GlassBanner(
                        title: String(localized: "Overlapping exports", comment: "Card title for the profile output-overlap warning"),
                        message: String(
                            localized: "This profile writes the same files as \(overlapping.joined(separator: ", ")). The later run overwrites the earlier one. Give each profile its own folder or filename template to keep them separate.",
                            comment: "Detail warning that this profile's output files overlap other profiles; the interpolated value is a comma-separated profile name list"
                        ),
                        systemImage: "exclamationmark.triangle",
                        tone: .warning
                    )
                    .accessibilityIdentifier("export.profiles.overlap-warning")
                }

                section(String(localized: "Settings")) {
                    AutomationSettingsRows(
                        profile: profile,
                        entry: entry,
                        onPage: { page = $0 },
                        onSchedule: { showSchedule = true }
                    )
                }

                section(String(localized: "Automation & CLI")) {
                    GlassPanel {
                        GlassRow(title: String(localized: "Profile ID"), subtitle: profile.id.uuidString) {
                            Button(idCopied ? String(localized: "Copied") : String(localized: "Copy")) {
                                UIPasteboard.general.string = profile.id.uuidString
                                idCopied = true
                            }
                            .buttonStyle(.plain)
                            .glassFont(.caption)
                            .foregroundStyle(palette.text)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .background(Capsule().fill(palette.surface2))
                            .frame(minHeight: GlassMetrics.touchTarget)
                            .accessibilityLabel(String(localized: "Copy profile ID", comment: "Accessibility label for the copy ID button"))
                        }
                        Button {
                            if let url = URL(string: "shortcuts://") { openURL(url) }
                        } label: {
                            GlassRow(
                                title: String(localized: "Use in Shortcuts"),
                                subtitle: String(localized: "“Export Yesterday's Health Data” → Profile: \(profile.name)")
                            ) {
                                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                            }
                        }
                        .buttonStyle(.plain)
                        if profile.target == .connectedMac {
                            Button(action: requestContextBinding) {
                                GlassRow(
                                    title: String(localized: "Bind context to this Mac"),
                                    subtitle: String(localized: "Lets refresh shortcuts use the authenticated Mac’s encrypted context")
                                ) {
                                    if contextBindingPeer != nil {
                                        Text(String(localized: "Bound")).glassFont(.rowSubtitle).foregroundStyle(palette.ok)
                                    }
                                    Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("export.profiles.bind-context")
                        }
                        ProfileRunOverlapRow(profileID: profile.id)
                    }
                    Text(verbatim: "healthmd export --profile \(profile.id.uuidString)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(palette.muted)
                        .textSelection(.enabled)
                        .padding(.horizontal, 20)
                        .padding(.top, 6)
                }

                VStack(alignment: .leading, spacing: 6) {
                    GlassPanel {
                        Button(role: .destructive) {
                            configurationProtection.performConfigurationChange { showDeleteConfirmation = true }
                        } label: {
                            Text(String(localized: "Delete automation"))
                                .glassFont(.body)
                                .foregroundStyle(palette.coral)
                                .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(profileStore.profiles.count <= 1)
                        .opacity(profileStore.profiles.count <= 1 ? 0.4 : 1)
                    }
                    Text(profileStore.profiles.count <= 1
                         ? String(localized: "Keep at least one automation.")
                         : String(localized: "Deleting keeps files already written."))
                        .glassFont(.rowSubtitle)
                        .foregroundStyle(palette.muted)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(String(localized: "Rename…", comment: "Action renaming this profile")) {
                        configurationProtection.performConfigurationChange {
                            renameText = profile.name
                            showRename = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel(String(localized: "More"))
            }
        }
        .onAppear {
            contextBindingPeer = AppleContextPhoneClient.shared.boundPeer(profileID: profile.id)
        }
        .navigationDestination(item: $page) { GlassProfilePage(kind: $0, coordinator: coordinator, profile: profile) }
        .navigationDestination(isPresented: $showSchedule) {
            GlassScheduleSheet(profile: profile, entry: entry, entryStore: entryStore) { updated in
                _ = entryStore.upsert(updated)
                schedulingManager.refreshScheduledAutomation()
                onSchedulesChanged()
            }
            .glassTheme()
        }
        .alert(String(localized: "Rename Profile", comment: "Alert title: rename export profile"), isPresented: $showRename) {
            TextField(String(localized: "Profile name", comment: "Placeholder for export profile name"), text: $renameText)
            Button(String(localized: "Save", comment: "Confirm rename")) {
                _ = coordinator.renameProfile(id: profile.id, to: renameText)
            }
            Button(String(localized: "Cancel", comment: "Dismiss rename"), role: .cancel) {}
        }
        .confirmationDialog(
            String(localized: "Delete this profile?", comment: "Confirm deleting an export profile"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Delete “\(profile.name)”", comment: "Destructive action deleting the named export profile"),
                role: .destructive
            ) {
                if coordinator.deleteProfile(id: profile.id) {
                    onSchedulesChanged()
                    dismiss()
                }
            }
            Button(String(localized: "Cancel", comment: "Dismiss delete"), role: .cancel) {}
        } message: {
            Text(String(localized: "Deleting keeps files already written."))
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
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassSectionLabel(title: title).padding(.horizontal, 20)
            content()
        }
    }

    private func requestContextBinding() {
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

    private func bindContextAutomation() {
        let peer = pendingContextPeer
        pendingContextPeer = nil
        configurationProtection.performConfigurationChange {
            do {
                guard let peer, let profile = profileStore.profile(id: profileID), profile.target == .connectedMac else {
                    throw AppleContextPhoneClient.ClientError.profile
                }
                try AppleContextPhoneClient.shared.bind(profileID: profileID, expectedPeerID: peer)
                contextBindingPeer = peer
            } catch {
                contextBindingError = error.localizedDescription
            }
        }
    }

    private func setEnabled(_ isEnabled: Bool, profileID: UUID) {
        configurationProtection.performConfigurationChange {
            entryStore.update(profileID: profileID) { $0.isEnabled = isEnabled }
            AutomationScheduleSwitch.didSwitch(
                isEnabled: isEnabled,
                entries: entryStore.entries,
                schedulingManager: schedulingManager
            )
            onSchedulesChanged()
        }
    }
}

/// The composer's field list: the profile's fields with their frontmatter keys. Checks
/// are staged until Save; unchecked fields stay listed so the change can be undone.
struct ComposerFieldList: View {
    let settings: ExportSettingsSnapshot
    let pending: [String: Bool]
    let onShowMetrics: () -> Void
    let onToggle: (String) -> Void

    @Environment(\.glassPalette) private var palette

    static let visibleRowCount = 6

    private var totalCount: Int {
        HealthMetrics.availableInCurrentBuild
            .filter { !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform }
            .count
    }

    private var fields: [HealthMetricDefinition] {
        let enabled = settings.metricSelection.enabledMetricIDs
        return HealthMetrics.availableInCurrentBuild
            .filter { enabled.contains($0.id) || pending[$0.id] != nil }
            .prefix(Self.visibleRowCount)
            .map { $0 }
    }

    private func isOn(_ field: HealthMetricDefinition) -> Bool {
        pending[field.id] ?? settings.metricSelection.enabledMetricIDs.contains(field.id)
    }

    /// The field's first frontmatter key, renamed if the profile customized it.
    private func key(_ field: HealthMetricDefinition) -> String? {
        guard let canonical = HealthMetricExportMapping.frontmatterKeys(for: field.id).first else { return nil }
        return settings.formatCustomization.frontmatterConfig.fields
            .first { $0.originalKey == canonical }?.outputKey ?? canonical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GlassSectionLabel(title: String(localized: "Fields in this note"))
                Spacer()
                Button(String(localized: "All \(totalCount)"), action: onShowMetrics)
                    .buttonStyle(.plain)
                    .glassFont(.caption)
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: GlassMetrics.touchTarget)
            }
            ForEach(fields, id: \.id) { field in
                let on = isOn(field)
                Rectangle().fill(palette.line).frame(height: 1)
                Button { onToggle(field.id) } label: {
                    HStack(spacing: 12) {
                        Text(field.localizedDisplayName)
                            .glassFont(.body)
                            .foregroundStyle(palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let key = key(field) {
                            Text(verbatim: key)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                        ZStack {
                            Circle()
                                .fill(on ? palette.accent : Color.clear)
                                .overlay { if !on { Circle().strokeBorder(palette.track, lineWidth: 1.5) } }
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.accentInk)
                            }
                        }
                        .frame(width: 24, height: 24)
                    }
                    .frame(minHeight: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Label the Button itself: wrapping it in a separate accessibility
                // element made VoiceOver announce each field twice.
                .accessibilityLabel(field.localizedDisplayName)
                .accessibilityValue(on ? String(localized: "On") : String(localized: "Off"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .glassSurface()
        .accessibilityIdentifier("glass.composer.preview")
    }
}

/// Composer choices staged until Save: field checks and the daily-note switch.
/// Choices made in their own sheets save there, as before.
extension ExportProfile {
    /// This profile showing staged settings, for rows that summarise a composer's draft.
    func withSettings(_ settings: ExportSettingsSnapshot) -> ExportProfile {
        var copy = self
        copy.settings = settings
        return copy
    }
}

struct ComposerDraft: Equatable {
    /// Field checks keyed by metric ID.
    var fields: [String: Bool] = [:]
    var note: Bool?

    var isEmpty: Bool { fields.isEmpty && note == nil }

    func settings(from saved: ExportSettingsSnapshot) -> ExportSettingsSnapshot {
        var settings = saved
        if !fields.isEmpty {
            let state = MetricSelectionState()
            saved.metricSelection.apply(to: state)
            for (metricID, enabled) in fields { state.setMetric(metricID, enabled: enabled) }
            settings.metricSelection = MetricSelectionSnapshot.from(state)
        }
        if let note {
            settings.dailyNoteInjection.enabled = note
            // As the daily-note page does when the note is switched off.
            if !note { settings.dailyNoteInjection.dailyNotesOnly = false }
        }
        return settings
    }

    /// A second toggle back to the saved value unstages the choice.
    mutating func toggleField(_ metricID: String, saved: ExportSettingsSnapshot) {
        let wasOn = saved.metricSelection.enabledMetricIDs.contains(metricID)
        let next = !(fields[metricID] ?? wasOn)
        fields[metricID] = next == wasOn ? nil : next
    }

    mutating func toggleNote(saved: ExportSettingsSnapshot) {
        let wasOn = saved.dailyNoteInjection.enabled
        let next = !(note ?? wasOn)
        note = next == wasOn ? nil : next
    }
}

/// ComposeGlass, ComposeGermanG, ComposeLargeTextG and DuoInnerComposeG.
struct ComposerScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    let profileID: UUID
    let onPreview: (UUID) -> Void
    let onSchedulesChanged: () -> Void
    /// Set when the composer opens on its own (from the Archive) rather than from the
    /// detail: "All settings" then pushes the detail instead of returning to it.
    let onRun: ((UUID) -> Void)?

    @Environment(\.glassPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var showSchedule = false
    @State private var page: GlassProfilePageKind?
    /// Field checks and the note switch, staged until Save.
    @State private var draft = ComposerDraft()

    init(
        coordinator: ExportProfileCoordinator,
        profileID: UUID,
        onPreview: @escaping (UUID) -> Void,
        onSchedulesChanged: @escaping () -> Void,
        onRun: ((UUID) -> Void)? = nil
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.profileID = profileID
        self.onPreview = onPreview
        self.onSchedulesChanged = onSchedulesChanged
        self.onRun = onRun
    }

    var body: some View {
        if let profile = profileStore.profile(id: profileID) {
            content(profile)
        }
    }

    private func content(_ profile: ExportProfile) -> some View {
        let entry = entryStore.entries.first { $0.profileID == profile.id }
        let draftSettings = draft.settings(from: profile.settings)
        let sentence = AutomationFacts(coordinator: coordinator).composerSentence(profile, settings: draftSettings)
        return HStack(alignment: .top, spacing: 0) {
            composerColumn(profile: profile, entry: entry, sentence: sentence, draftSettings: draftSettings)
            if horizontalSizeClass == .regular {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ComposerFilePreview(settings: draftSettings, entry: entry, showsLiveSuffix: true, lineLimit: 18)
                        Text(String(localized: "The preview stays beside the sentence while you edit — no switching screens."))
                            .glassFont(.rowSubtitle)
                            .foregroundStyle(palette.muted)
                            .padding(.horizontal, 4)
                    }
                    .padding(GlassMetrics.screenMargin)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        // ComposeLargeTextG keeps the bare name so the title fits at the largest sizes.
        .navigationTitle(dynamicTypeSize.isAccessibilitySize ? profile.name : String(localized: "\(profile.name) automation"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) { save(profile) }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("glass.composer.save")
            }
        }
        .navigationDestination(item: $page) { GlassProfilePage(kind: $0, coordinator: coordinator, profile: profile) }
        .navigationDestination(isPresented: $showSchedule) {
            GlassScheduleSheet(profile: profile, entry: entry, entryStore: entryStore) { updated in
                _ = entryStore.upsert(updated)
                schedulingManager.refreshScheduledAutomation()
                onSchedulesChanged()
            }
            .glassTheme()
        }
    }

    /// Sheet choices save in their sheets; Save commits the staged field checks and note.
    private func save(_ profile: ExportProfile) {
        guard !draft.isEmpty else {
            dismiss()
            return
        }
        configurationProtection.performConfigurationChange {
            guard let current = profileStore.profile(id: profile.id) else { return }
            coordinator.saveSettings(draft.settings(from: current.settings), for: current)
            draft = ComposerDraft()
            dismiss()
        }
    }

    private func composerColumn(
        profile: ExportProfile,
        entry: ScheduledExportEntry?,
        sentence: AutomationSentence,
        draftSettings: ExportSettingsSnapshot
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if dynamicTypeSize.isAccessibilitySize {
                    listLayout(sentence)
                } else {
                    AutomationSentenceView(sentence: sentence) { handle($0, profile: profile) }
                        // DuoInnerComposeG pads its narrower card by 18.
                        .padding(horizontalSizeClass == .regular ? 18 : 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface()
                }
                if horizontalSizeClass == .regular {
                    // The rows read the staged note, as the sentence does.
                    AutomationSettingsRows(
                        profile: profile.withSettings(draftSettings),
                        entry: entry,
                        includesAllRows: false,
                        onPage: { page = $0 },
                        onSchedule: { showSchedule = true }
                    )
                } else {
                    ComposerFilePreview(settings: draftSettings, entry: entry)
                    ComposerFieldList(
                        settings: profile.settings,
                        pending: draft.fields,
                        onShowMetrics: {
                            configurationProtection.performConfigurationChange { page = .metrics }
                        },
                        onToggle: { metricID in
                            configurationProtection.performConfigurationChange {
                                draft.toggleField(metricID, saved: profile.settings)
                            }
                        }
                    )
                    allSettingsRow(profile)
                }
            }
            .padding(GlassMetrics.screenMargin)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .frame(maxWidth: .infinity)
    }

    /// "All settings": the detail holds every setting. Pushed from the detail, this returns
    /// to it; opened from the Archive, it pushes the detail.
    @ViewBuilder private func allSettingsRow(_ profile: ExportProfile) -> some View {
        if let onRun {
            NavigationLink {
                AutomationDetailScreen(
                    coordinator: coordinator,
                    profileID: profile.id,
                    onRun: onRun,
                    onPreview: onPreview,
                    onSchedulesChanged: onSchedulesChanged,
                    showsComposerLink: false
                )
            } label: { allSettingsLabel }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(localized: "All settings"))
            .accessibilityAddTraits(.isButton)
        } else {
            Button { dismiss() } label: { allSettingsLabel }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(String(localized: "All settings"))
                .accessibilityAddTraits(.isButton)
        }
    }

    private var allSettingsLabel: some View {
        HStack {
            Text(String(localized: "All settings")).glassFont(.body).foregroundStyle(palette.text)
            Spacer(minLength: 8)
            Text(verbatim: String(localized: "Output · format · entries · schedule") + " →")
                .font(.system(size: 14))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 52)
        .glassSurface()
        .contentShape(Rectangle())
    }

    private func listLayout(_ sentence: AutomationSentence) -> some View {
        GlassPanel {
            ForEach(AutomationSentence.Token.allCases, id: \.self) { token in
                Button {
                    if let profile = profileStore.profile(id: profileID) { handle(token, profile: profile) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(for: token)).glassFont(.caption).foregroundStyle(palette.muted)
                        listValue(token, sentence.listValues[token] ?? sentence.values[token] ?? "")
                    }
                    .padding(GlassMetrics.panelPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func listValue(_ token: AutomationSentence.Token, _ value: String) -> some View {
        if AutomationSentenceView.isPathLike(token, value) {
            Text(verbatim: value).fontDesign(.monospaced).fontWeight(.semibold).glassFont(.body).foregroundStyle(palette.accent)
        } else {
            Text(value).fontWeight(.semibold).glassFont(.body).foregroundStyle(palette.accent)
        }
    }

    private static func title(for token: AutomationSentence.Token) -> String {
        switch token {
        case .when: return String(localized: "When")
        case .range: return String(localized: "Dates")
        case .metrics: return String(localized: "Metrics")
        case .where: return String(localized: "Where")
        case .formats: return String(localized: "Formats")
        case .note: return String(localized: "Daily note")
        }
    }

    private func handle(_ token: AutomationSentence.Token, profile: ExportProfile) {
        configurationProtection.performConfigurationChange {
            switch token {
            case .when, .range:
                showSchedule = true
            case .metrics: page = .metrics
            case .where: page = .output
            case .formats: page = .formats
            // ComposeGlass switches the note in place; Save commits it.
            case .note: draft.toggleNote(saved: profile.settings)
            }
        }
    }
}
#endif

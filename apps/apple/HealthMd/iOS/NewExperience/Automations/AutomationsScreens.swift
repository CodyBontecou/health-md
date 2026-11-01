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

    func sentence(_ profile: ExportProfile) -> AutomationSentence {
        .make(profile: profile, entry: entry(profile), destination: destination(profile))
    }

    func statusLine(_ profile: ExportProfile, now: Date = Date()) -> String {
        guard let entry = entry(profile) else { return String(localized: "No schedule") }
        guard entry.isEnabled else { return String(localized: "Paused") }
        guard let next = ScheduleDateMath.calculateNextRunDate(
            schedule: entry.dateMathProjection,
            now: now
        ) else { return String(localized: "Scheduled") }
        return String(localized: "Next · \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
    }
}

/// AutomationsGlass. An automation is an export profile with an optional schedule.
struct AutomationsScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    let historyContent: AnyView
    let onRun: (UUID) -> Void
    let onSchedulesChanged: () -> Void

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var showCreation = false

    init(
        coordinator: ExportProfileCoordinator,
        historyContent: AnyView,
        onRun: @escaping (UUID) -> Void,
        onSchedulesChanged: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.historyContent = historyContent
        self.onRun = onRun
        self.onSchedulesChanged = onSchedulesChanged
    }

    private var facts: AutomationFacts { AutomationFacts(coordinator: coordinator) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
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
                        .accessibilityLabel(String(localized: "New profile"))
                    }
                    Text("Saved exports you can schedule, run from Shortcuts, or call with the CLI.")
                        .glassFont(.body)
                        .foregroundStyle(palette.sec)

                    ForEach(profileStore.profiles) { profile in
                        NavigationLink {
                            AutomationDetailScreen(
                                coordinator: coordinator,
                                profileID: profile.id,
                                onRun: onRun,
                                onSchedulesChanged: onSchedulesChanged
                            )
                        } label: {
                            card(profile)
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        historyContent
                    } label: {
                        GlassPanel {
                            GlassRow(title: String(localized: "Schedule & history")) {
                                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, GlassMetrics.screenMargin)
                .padding(.top, 12)
                .padding(.bottom, GlassMetrics.scrollBottomInset)
            }
            .background(palette.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showCreation) {
            ExportProfileEditorSheet(coordinator: coordinator)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .accessibilityIdentifier("glass.automations")
    }

    private func card(_ profile: ExportProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(profile.name).glassFont(.navTitle).foregroundStyle(palette.text)
            AutomationSentenceView(sentence: facts.sentence(profile), style: .body)
            Text(facts.statusLine(profile)).glassFont(.caption).foregroundStyle(palette.muted)
        }
        .padding(GlassMetrics.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
        .contentShape(Rectangle())
    }
}

/// AutomationDetailG: the hub for one profile. Editing runs through the existing
/// profile editor, so its validation and overlap checks still apply.
struct AutomationDetailScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    let profileID: UUID
    let onRun: (UUID) -> Void
    let onSchedulesChanged: () -> Void

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var showEditor = false
    @State private var showSchedule = false
    @State private var showMetrics = false
    @State private var showFormats = false

    init(
        coordinator: ExportProfileCoordinator,
        profileID: UUID,
        onRun: @escaping (UUID) -> Void,
        onSchedulesChanged: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.profileID = profileID
        self.onRun = onRun
        self.onSchedulesChanged = onSchedulesChanged
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
                VStack(alignment: .leading, spacing: 12) {
                    AutomationSentenceView(sentence: facts.sentence(profile))
                    NavigationLink {
                        ComposerScreen(coordinator: coordinator, profileID: profile.id, onSchedulesChanged: onSchedulesChanged)
                    } label: {
                        Text(verbatim: String(localized: "Edit sentence") + " →")
                            .glassFont(.caption)
                            .foregroundStyle(palette.accent)
                            .frame(minHeight: GlassMetrics.touchTarget)
                    }
                    .buttonStyle(.plain)
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

                GlassPanel {
                    Button {
                        configurationProtection.performConfigurationChange { showMetrics = true }
                    } label: {
                        GlassRow(title: String(localized: "Metrics")) {
                            Text(verbatim: "\(profile.settings.metricSelection.enabledMetricIDs.count)")
                                .glassFont(.rowSubtitle)
                                .foregroundStyle(palette.muted)
                            Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    settingRow(
                        String(localized: "Formats"),
                        value: ExportProfileCardSummary.sortedFormats(profile.settings.exportFormats)
                            .map(\.localizedDisplayName).joined(separator: " · ")
                    ) { showFormats = true }
                    settingRow(String(localized: "All settings"), value: "")
                    settingRow(String(localized: "Output"), value: facts.destination(profile))
                    settingRow(
                        String(localized: "Daily notes"),
                        value: profile.settings.dailyNoteInjection.enabled
                            ? String(localized: "On") : String(localized: "Off")
                    )
                    Button { showSchedule = true } label: {
                        GlassRow(title: String(localized: "Schedule"), subtitle: facts.statusLine(profile)) {
                            Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }

                GlassPanel {
                    Button {
                        UIPasteboard.general.string = profile.id.uuidString
                    } label: {
                        GlassRow(title: String(localized: "Profile ID"), subtitle: profile.id.uuidString) {
                            Image(systemName: "doc.on.doc").foregroundStyle(palette.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    Text(verbatim: "healthmd export --profile \(profile.id.uuidString)")
                        .glassFont(.monoBody)
                        .foregroundStyle(palette.muted)
                        .textSelection(.enabled)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                        .padding(.bottom, 12)
                }

                // Delete, context binding and overlap warnings keep their tested home.
                NavigationLink {
                    ExportProfileDetailView(coordinator: coordinator, profileID: profile.id)
                } label: {
                    GlassPanel {
                        GlassRow(title: String(localized: "More options")) {
                            Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showMetrics) {
            GlassMetricsScreen(coordinator: coordinator, profile: profile)
                .glassTheme()
        }
        .sheet(isPresented: $showFormats) {
            GlassFormatsScreen(coordinator: coordinator, profile: profile)
                .glassTheme()
        }
        .sheet(isPresented: $showEditor) {
            ExportProfileEditorSheet(coordinator: coordinator, editing: profile)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSchedule) {
            GlassScheduleSheet(profile: profile, entry: entry) { updated in
                _ = entryStore.upsert(updated)
                schedulingManager.refreshScheduledAutomation()
                onSchedulesChanged()
            }
            .glassTheme()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func settingRow(_ title: String, value: String, action: (() -> Void)? = nil) -> some View {
        Button {
            configurationProtection.performConfigurationChange {
                if let action { action() } else { showEditor = true }
            }
        } label: {
            GlassRow(title: title) {
                Text(value).glassFont(.rowSubtitle).foregroundStyle(palette.muted).lineLimit(1)
                Image(systemName: "chevron.right").foregroundStyle(palette.muted)
            }
        }
        .buttonStyle(.plain)
    }

    private func setEnabled(_ isEnabled: Bool, profileID: UUID) {
        configurationProtection.performConfigurationChange {
            entryStore.update(profileID: profileID) { $0.isEnabled = isEnabled }
            schedulingManager.refreshScheduledAutomation()
            onSchedulesChanged()
        }
    }
}

/// ComposeGlass, ComposeGermanG and ComposeLargeTextG.
struct ComposerScreen: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    let profileID: UUID
    let onSchedulesChanged: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var showEditor = false
    @State private var showSchedule = false
    @State private var showRange = false

    init(coordinator: ExportProfileCoordinator, profileID: UUID, onSchedulesChanged: @escaping () -> Void) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.profileID = profileID
        self.onSchedulesChanged = onSchedulesChanged
    }

    var body: some View {
        if let profile = profileStore.profile(id: profileID) {
            content(profile)
        }
    }

    private func content(_ profile: ExportProfile) -> some View {
        let entry = entryStore.entries.first { $0.profileID == profile.id }
        let sentence = AutomationFacts(coordinator: coordinator).sentence(profile)
        return ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                if dynamicTypeSize.isAccessibilitySize {
                    listLayout(sentence)
                } else {
                    AutomationSentenceView(sentence: sentence) { handle($0, profile: profile) }
                        .padding(GlassMetrics.panelPadding)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassSurface()
                }
                Button(String(localized: "All settings")) {
                    configurationProtection.performConfigurationChange { showEditor = true }
                }
                .buttonStyle(.plain)
                .glassFont(.caption)
                .foregroundStyle(palette.accent)
                .frame(minHeight: GlassMetrics.touchTarget)
            }
            .padding(GlassMetrics.screenMargin)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            ExportProfileEditorSheet(coordinator: coordinator, editing: profile)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSchedule) {
            GlassScheduleSheet(profile: profile, entry: entry) { updated in
                _ = entryStore.upsert(updated)
                schedulingManager.refreshScheduledAutomation()
                onSchedulesChanged()
            }
            .glassTheme()
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func listLayout(_ sentence: AutomationSentence) -> some View {
        GlassPanel {
            ForEach(AutomationSentence.Token.allCases, id: \.self) { token in
                Button {
                    if let profile = profileStore.profile(id: profileID) { handle(token, profile: profile) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(for: token)).glassFont(.caption).foregroundStyle(palette.muted)
                        Text(sentence.values[token] ?? "").glassFont(.body).foregroundStyle(palette.accent)
                    }
                    .padding(GlassMetrics.panelPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static func title(for token: AutomationSentence.Token) -> String {
        switch token {
        case .when: return String(localized: "When")
        case .range: return String(localized: "Dates")
        case .metrics: return String(localized: "Metrics")
        case .where: return String(localized: "Where")
        case .formats: return String(localized: "Formats")
        case .note: return String(localized: "Daily notes")
        }
    }

    private func handle(_ token: AutomationSentence.Token, profile: ExportProfile) {
        configurationProtection.performConfigurationChange {
            switch token {
            case .when, .range:
                showSchedule = true
            case .metrics, .where, .formats, .note:
                showEditor = true
            }
        }
    }
}
#endif

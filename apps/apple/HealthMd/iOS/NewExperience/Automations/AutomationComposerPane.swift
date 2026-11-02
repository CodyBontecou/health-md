#if os(iOS)
import SwiftUI

/// The "If runs overlap" Queue/Skip choice of one automation, stored per device.
struct ProfileRunOverlapRow: View {
    let profileID: UUID

    @State private var policy: ProfileRunOverlapPolicy?

    var body: some View {
        GlassRow(title: String(localized: "If runs overlap", comment: "Automation detail row choosing what happens when a scheduled run starts while the previous one is still running")) {
            GlassSegmentedControl(
                segments: [
                    .init(value: ProfileRunOverlapPolicy.queue, title: String(localized: "Queue", comment: "Overlap choice: wait for the running export, then run")),
                    .init(value: ProfileRunOverlapPolicy.skip, title: String(localized: "Skip", comment: "Overlap choice: skip the new run while one is running")),
                ],
                selection: Binding(
                    get: { policy ?? ProfileRunOverlapPolicyStore().policy(for: profileID) },
                    set: { newValue in
                        policy = newValue
                        ProfileRunOverlapPolicyStore().setPolicy(newValue, for: profileID)
                    }
                )
            )
            .frame(width: 150)
        }
        .accessibilityIdentifier("export.profiles.overlap-policy")
    }
}

/// iPadAutomationsG's detail pane: the editable sentence, then tomorrow's file beside
/// the settings rows. As in the composer, the note switch stages until Save and the
/// other choices save in their own sheets.
struct AutomationComposerPane: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @ObservedObject private var profileStore: ExportProfileStore
    @ObservedObject private var entryStore: ScheduledExportEntryStore
    let profileID: UUID
    let onRun: (UUID) -> Void
    let onPreview: (UUID) -> Void
    let onSchedulesChanged: () -> Void

    @Environment(\.glassPalette) private var palette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @EnvironmentObject private var schedulingManager: SchedulingManager
    @State private var showSchedule = false
    @State private var page: GlassProfilePageKind?
    /// Staged choices, held by the list so switching automations can offer Save or Discard.
    @Binding var draft: ComposerDraft
    /// The file and the rows sit side by side once the pane can hold both.
    @State private var fitsColumns = true

    /// Two ~280 pt columns plus the gap and the pane's padding.
    static let columnsMinWidth: CGFloat = 600

    init(
        coordinator: ExportProfileCoordinator,
        profileID: UUID,
        draft: Binding<ComposerDraft>,
        onRun: @escaping (UUID) -> Void,
        onPreview: @escaping (UUID) -> Void,
        onSchedulesChanged: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        _profileStore = ObservedObject(wrappedValue: coordinator.profileStore)
        _entryStore = ObservedObject(wrappedValue: coordinator.scheduledEntryStore)
        self.profileID = profileID
        _draft = draft
        self.onRun = onRun
        self.onPreview = onPreview
        self.onSchedulesChanged = onSchedulesChanged
    }

    var body: some View {
        if let profile = profileStore.profile(id: profileID) {
            content(profile)
        }
    }

    private var columnsLayout: AnyLayout {
        fitsColumns && !dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
    }

    private func content(_ profile: ExportProfile) -> some View {
        let entry = entryStore.entries.first { $0.profileID == profile.id }
        let draftSettings = draft.settings(from: profile.settings)
        let sentence = AutomationFacts(coordinator: coordinator).composerSentence(profile, settings: draftSettings)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(profile)

                AutomationSentenceView(sentence: sentence) { handle($0, profile: profile) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("glass.automation.sentence")

                columnsLayout {
                    ComposerFilePreview(settings: draftSettings, entry: entry)
                        .frame(maxWidth: .infinity, alignment: .top)
                    // The rows read the staged note, as the sentence does.
                    AutomationSettingsRows(
                        profile: profile.withSettings(draftSettings),
                        entry: entry,
                        includesAllRows: false,
                        onPage: { page = $0 },
                        onSchedule: { showSchedule = true }
                    )
                    .frame(maxWidth: .infinity, alignment: .top)
                }

                // Below the board's fold: the per-device overlap choice and the full
                // detail (format, entries, CLI, duplicate, pause, delete).
                GlassPanel {
                    ProfileRunOverlapRow(profileID: profile.id)
                    NavigationLink {
                        AutomationDetailScreen(
                            coordinator: coordinator,
                            profileID: profile.id,
                            onRun: onRun,
                            onPreview: onPreview,
                            onSchedulesChanged: onSchedulesChanged,
                            showsComposerLink: false
                        )
                    } label: {
                        GlassRow(title: String(localized: "All settings")) {
                            Image(systemName: "chevron.right").foregroundStyle(palette.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("glass.automation.allSettings")
                }
            }
            .padding(GlassMetrics.panelPadding)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width >= Self.columnsMinWidth } action: { fitsColumns = $0 }
        .background(palette.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("glass.automation.pane")
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

    /// The pane's title row: the automation's name, Run now and Save.
    private func header(_ profile: ExportProfile) -> some View {
        HStack(spacing: 8) {
            Text(profile.name)
                .font(.title2.bold())
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            GlassChip(title: String(localized: "Run now")) { onRun(profile.id) }
            Button { save(profile) } label: {
                Text(String(localized: "Save"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accentInk)
                    .padding(.horizontal, 18)
                    .frame(height: GlassMetrics.touchTarget)
                    .background(Capsule().fill(palette.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // Nothing is staged until a choice changes in place.
            .disabled(draft.isEmpty)
            .opacity(draft.isEmpty ? 0.5 : 1)
            .accessibilityIdentifier("glass.automation.pane.save")
        }
    }

    /// Commits the staged choices; sheet choices have already saved.
    private func save(_ profile: ExportProfile) {
        guard !draft.isEmpty else { return }
        configurationProtection.performConfigurationChange {
            guard let current = profileStore.profile(id: profile.id) else { return }
            coordinator.saveSettings(draft.settings(from: current.settings), for: current)
            draft = ComposerDraft()
        }
    }

    private func handle(_ token: AutomationSentence.Token, profile: ExportProfile) {
        configurationProtection.performConfigurationChange {
            switch token {
            case .when, .range: showSchedule = true
            case .metrics: page = .metrics
            case .where: page = .output
            case .formats: page = .formats
            // As in ComposeGlass, the note switches in place and Save commits it.
            case .note: draft.toggleNote(saved: profile.settings)
            }
        }
    }
}
#endif

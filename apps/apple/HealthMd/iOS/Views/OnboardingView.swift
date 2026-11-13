import SwiftUI

// MARK: - Onboarding v2

/// First-run setup: Welcome → Packs → Apple Health → Folder → First note → Make it daily.
///
/// Goal: the first real file lands in the user's folder in about five taps. Packs
/// replace the full metric list, onboarding configures the existing Default
/// automation (renamed "Daily note") instead of creating a second one, the first
/// note is shown rendered with the raw file behind a toggle, the one free export
/// writes the past 7 days, and the trial is offered only after the user has seen
/// their notes. The flow never traps the user: Health access and the folder can
/// both be skipped and repaired from the app later.
struct OnboardingView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showFolderPicker: Bool
    @ObservedObject var vaultManager: VaultManager
    @ObservedObject private var purchaseManager = PurchaseManager.shared
    @EnvironmentObject var sharedSetupCoordinator: SharedSetupCoordinator
    var services: OnboardingServices = .preview
    let onComplete: () -> Void

    @State private var step: OnboardingStep = .welcome
    @State private var direction: TransitionDirection = .forward
    @State private var packs: Set<OnboardingMetricPack> = OnboardingMetricPack.defaultSelection
    @State private var destination: OnboardingDestination = .folder
    @State private var isRequestingHealthAuthorization = false
    @State private var healthAuthorizationError: String?
    @State private var week = OnboardingWeekState()
    @State private var saveState: OnboardingSaveState = .idle
    @State private var trialState: OnboardingTrialState = .idle
    @State private var endpointEditor: OnboardingEndpointEditorRequest?
    /// Bumped after the endpoint sheet saves or deletes, so the step re-reads it.
    @State private var endpointRevision = 0
    @State private var showDriveDisclosure = false
    @State private var isConnectingDrive = false
    @State private var driveError: String?
    /// Bumped after a Drive connection attempt, so the step re-reads the binding.
    @State private var driveRevision = 0

    private var metricCount: Int { OnboardingMetricPack.metricIDs(for: packs).count }

    /// The free export runs only when there is real data and a writable folder.
    /// Otherwise the step finishes setup and leaves the allowance unused.
    private var canSaveWeek: Bool {
        guard week.hasRealData, purchaseManager.canExport else { return false }
        if destination == .api { return apiEndpoint != nil }
        if usesConnectedDrive { return driveFolder?.isReady == true }
        return vaultManager.vaultURL != nil && !vaultManager.requiresVaultReselection
    }

    /// Google Drive uses the direct Drive connection when this build has it;
    /// otherwise the option falls back to a Drive folder picked in Files.
    private var usesConnectedDrive: Bool { destination == .drive && services.driveAvailable() }

    private var driveFolder: OnboardingDriveFolder? {
        _ = driveRevision
        return services.driveFolder()
    }

    private var apiEndpoint: OnboardingAPIEndpoint? {
        _ = endpointRevision
        return services.apiEndpoint()
    }

    var body: some View {
        ZStack {
            Color.glassAdaptive(\.bg).ignoresSafeArea()

            OnboardingPageLayout(pageID: step.rawValue) {
                if step.showsTopBar {
                    OnboardingTopBar(
                        progress: step.progressIndex,
                        total: OnboardingStep.progressCount,
                        onBack: goBack
                    )
                }
            } content: {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            } footer: {
                footerControls
                    .transition(.opacity)
            }
        }
        .glassTheme()
        .onAppear(perform: restorePacksFromSelection)
        .sheet(item: $endpointEditor, onDismiss: { endpointRevision += 1 }) { request in
            endpointEditorSheet(request)
        }
        .alert(
            GoogleDrivePrivacyDisclosure.title,
            isPresented: $showDriveDisclosure
        ) {
            Button(GoogleDrivePrivacyDisclosure.confirm, action: connectDrive)
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(GoogleDrivePrivacyDisclosure.message)
        }
        .alert(
            String(localized: "Unable to Connect Apple Health"),
            isPresented: Binding(
                get: { healthAuthorizationError != nil },
                set: { if !$0 { healthAuthorizationError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { healthAuthorizationError = nil }
        } message: {
            Text(healthAuthorizationError ?? "")
        }
    }

    // MARK: Content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeStep()
        case .packs:
            OnboardingPacksStep(selection: $packs)
        case .health:
            OnboardingHealthStep(packs: packs, isAuthorized: healthKitManager.isAuthorized)
        case .folder:
            OnboardingFolderStep(
                destination: $destination,
                folderName: vaultManager.vaultURL == nil ? nil : services.folderLabel(),
                onChooseFolder: { showFolderPicker = true },
                previewDates: OnboardingWeekState.defaultDates(),
                apiEndpoint: apiEndpoint,
                onEditAPIEndpoint: { endpointEditor = OnboardingEndpointEditorRequest(endpointID: apiEndpoint?.id) },
                driveAvailable: services.driveAvailable(),
                driveFolder: driveFolder,
                driveError: destination == .drive ? driveError : nil,
                isConnectingDrive: isConnectingDrive,
                onChangeDrive: { showDriveDisclosure = true }
            )
        case .firstNote:
            OnboardingFirstNoteStep(week: $week, healthAuthorized: healthKitManager.isAuthorized)
                .task(id: week.loadID) { await loadWeekIfNeeded() }
        case .daily:
            OnboardingDailyStep(
                savedBanner: savedBanner,
                destinationLabel: services.destinationLabel(),
                trialTimeline: services.trialTimeline(),
                fullAccessIncluded: purchaseManager.isUnlocked
            )
            .task { await services.prepareTrial() }
        }
    }

    @ViewBuilder
    private var footerControls: some View {
        VStack(spacing: Spacing.s3) {
            switch step {
            case .welcome:
                OnboardingPillButton(
                    title: String(localized: "Get started"),
                    trailingSymbol: "arrow.right",
                    action: advance
                )
                Label {
                    Text("No account. Your data stays on your device and in your folders.")
                } icon: {
                    Image(systemName: "lock")
                }
                .glassFont(.caption)
                .foregroundStyle(Color.glassAdaptive(\.muted))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            case .packs:
                OnboardingPacksSummary(packCount: packs.count, metricCount: metricCount)
                OnboardingPillButton(
                    title: String(localized: "Connect Apple Health"),
                    isDisabled: packs.isEmpty,
                    action: confirmPacks
                )

            case .health:
                if healthKitManager.isAuthorized && !isRequestingHealthAuthorization {
                    OnboardingPillButton(title: String(localized: "Continue"), trailingSymbol: "arrow.right", action: advance)
                }
                OnboardingPillButton(
                    title: isRequestingHealthAuthorization
                        ? String(localized: "Connecting…")
                        : String(localized: "Continue to Apple Health"),
                    imageAsset: "AppleHealthIcon",
                    style: healthKitManager.isAuthorized ? .secondary : .primary,
                    isDisabled: isRequestingHealthAuthorization,
                    accessibilityHint: String(localized: "Opens Apple Health permission selection"),
                    action: requestHealthAuthorization
                )
                OnboardingQuietButton(title: String(localized: "Skip for now"), action: advance)

            case .folder:
                if destination == .api && apiEndpoint == nil {
                    OnboardingPillButton(
                        title: String(localized: "Add API endpoint"),
                        trailingSymbol: "plus",
                        action: { endpointEditor = OnboardingEndpointEditorRequest(endpointID: nil) }
                    )
                    OnboardingQuietButton(title: String(localized: "Skip for now"), action: advance)
                } else if usesConnectedDrive && driveFolder == nil {
                    OnboardingPillButton(
                        title: isConnectingDrive
                            ? String(localized: "Connecting…")
                            : String(localized: "Connect Google Drive"),
                        imageAsset: "GoogleDriveLogo",
                        isDisabled: isConnectingDrive,
                        accessibilityHint: String(localized: "Opens Google sign-in and the Drive folder picker"),
                        action: { showDriveDisclosure = true }
                    )
                    OnboardingQuietButton(title: String(localized: "Skip for now"), action: advance)
                } else if destination != .api && !usesConnectedDrive && vaultManager.vaultURL == nil {
                    OnboardingPillButton(
                        title: String(localized: "Choose a folder"),
                        trailingSymbol: "folder.badge.plus",
                        accessibilityHint: String(localized: "Opens the folder picker"),
                        action: { showFolderPicker = true }
                    )
                    OnboardingQuietButton(title: String(localized: "Skip for now"), action: advance)
                } else {
                    OnboardingPillButton(
                        title: String(localized: "Show my notes"),
                        trailingSymbol: "arrow.right",
                        action: confirmDestination
                    )
                }

            case .firstNote:
                OnboardingPillButton(
                    title: saveButtonTitle,
                    leadingSymbol: canSaveWeek ? "square.and.arrow.down" : nil,
                    isDisabled: saveState == .saving || week.isLoading,
                    action: saveWeek
                )
                Text(saveFinePrint)
                    .glassFont(.caption)
                    .foregroundStyle(Color.glassAdaptive(\.muted))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if case .failed(let message) = saveState {
                    Text(message)
                        .glassFont(.caption)
                        .foregroundStyle(Color.glassAdaptive(\.coral))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("onboarding.save.error")
                    OnboardingQuietButton(title: String(localized: "Continue without saving")) {
                        saveState = .idle
                        advance()
                    }
                }

            case .daily:
                if purchaseManager.isUnlocked {
                    OnboardingPillButton(
                        title: String(localized: "Turn on daily notes"),
                        action: { finish(enableSchedule: true) }
                    )
                } else {
                    OnboardingPillButton(
                        title: trialState == .purchasing
                            ? String(localized: "Starting…")
                            : (services.trialEligible()
                                ? String(localized: "Start 7-day free trial")
                                : String(localized: "Subscribe for daily notes")),
                        isDisabled: trialState == .purchasing,
                        action: startTrial
                    )
                    if case .failed(let message) = trialState {
                        Text(message)
                            .glassFont(.caption)
                            .foregroundStyle(Color.glassAdaptive(\.coral))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                OnboardingQuietButton(
                    title: String(localized: "Not now, I'll export manually"),
                    action: { finish(enableSchedule: false) }
                )
                if !purchaseManager.isUnlocked {
                    Text("Cancel anytime in Settings › Apple ID › Subscriptions.")
                        .glassFont(.caption)
                        .foregroundStyle(Color.glassAdaptive(\.muted))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Copy

    private var saveButtonTitle: String {
        if saveState == .saving { return String(localized: "Saving…") }
        guard canSaveWeek else { return String(localized: "Finish setup") }
        let count = week.daysWithData
        if destination == .api, let apiEndpoint {
            return String(localized: "Send \(count) days to \(apiEndpoint.name)")
        }
        return String(localized: "Save \(count) notes to \(services.destinationLabel())")
    }

    private var saveFinePrint: String {
        if destination == .api && apiEndpoint == nil {
            return String(localized: "Add an API endpoint in Automations, then use Run now. Your first export is free.")
        }
        if usesConnectedDrive && driveFolder?.isReady != true {
            return String(localized: "Connect Google Drive in Automations, then use Run now. Your first export is free.")
        }
        if week.hasRealData && !usesConnectedDrive && vaultManager.vaultURL == nil {
            return String(localized: "Choose a folder in Settings, then use Run now. Your first export is free.")
        }
        guard week.hasRealData else {
            return String(localized: "Your free export stays unused until there’s data to write.")
        }
        if !purchaseManager.canExport {
            return String(localized: "Your free export has been used. Your notes appear once you subscribe.")
        }
        if !usesConnectedDrive && vaultManager.requiresVaultReselection {
            return String(localized: "Re-select your folder in Settings, then use Run now.")
        }
        if let range = week.rangeDescription {
            return String(localized: "Includes \(range). Your first export is free.")
        }
        return String(localized: "Your first export is free and includes the past 7 days.")
    }

    private var savedBanner: String {
        switch saveState {
        case .saved(let count):
            if destination == .api {
                return String(localized: "\(count) days sent to \(services.destinationLabel())")
            }
            return String(localized: "\(count) notes saved to \(services.destinationLabel())")
        default:
            return String(localized: "Setup complete, with nothing exported yet")
        }
    }

    // MARK: Navigation

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion: CGFloat = direction == .forward ? 20 : -20
        let removal: CGFloat = direction == .forward ? -12 : 12
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: insertion)),
            removal: .opacity.combined(with: .offset(x: removal))
        )
    }

    private func advance() {
        guard let next = step.next else { return }
        direction = .forward
        move(to: next)
    }

    private func goBack() {
        guard let previous = step.previous else { return }
        direction = .backward
        move(to: previous)
    }

    private func move(to target: OnboardingStep) {
        if reduceMotion {
            step = target
        } else {
            withAnimation(AnimationTimings.standard) { step = target }
        }
    }

    // MARK: Actions

    private func restorePacksFromSelection() {
        // Replaying setup shows what the Default automation already exports.
        let covered = services.coveredPacks()
        if !covered.isEmpty { packs = covered }
    }

    private func confirmPacks() {
        services.applyPacks(packs)
        week.invalidate()
        advance()
    }

    private func requestHealthAuthorization() {
        guard !isRequestingHealthAuthorization else { return }
        isRequestingHealthAuthorization = true
        let metricIDs = OnboardingMetricPack.metricIDs(for: packs)
        Task {
            defer { isRequestingHealthAuthorization = false }
            do {
                let outcome = try await healthKitManager.requestAuthorization(forMetricIDs: metricIDs)
                if outcome == .unavailable {
                    healthAuthorizationError = String(localized: "Apple Health is not available on this device. You can skip this step and connect on a supported device later.")
                    return
                }
                week.invalidate()
                if healthKitManager.isAuthorized { advance() }
            } catch {
                healthAuthorizationError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func endpointEditorSheet(_ request: OnboardingEndpointEditorRequest) -> some View {
        if let id = request.endpointID, let mode = services.apiEndpointEditMode(id) {
            GlassAPIEndpointEditorSheet(
                mode: mode,
                onSave: { services.saveAPIEndpoint($0, id) },
                onDelete: { services.deleteAPIEndpoint(id) }
            )
        } else {
            GlassAPIEndpointEditorSheet(mode: .create) { draft in
                guard services.saveAPIEndpoint(draft, nil) else { return false }
                destination = .api
                return true
            }
        }
    }

    private func connectDrive() {
        guard !isConnectingDrive else { return }
        isConnectingDrive = true
        driveError = nil
        Task {
            let outcome = await services.connectDrive()
            isConnectingDrive = false
            driveRevision += 1
            switch outcome {
            case .connected:
                destination = .drive
            case .cancelled:
                break
            case .failed(let message):
                driveError = message
            }
        }
    }

    private func confirmDestination() {
        services.selectDestination(destination)
        advance()
    }

    private func loadWeekIfNeeded() async {
        guard week.needsLoad else { return }
        let loadID = week.loadID
        week.isLoading = true
        let days = await services.loadWeek(week.dates)
        // Leaving the step cancels the load, and changing packs supersedes it:
        // never keep a partial or outdated week.
        guard !Task.isCancelled, loadID == week.loadID else {
            if loadID == week.loadID { week.isLoading = false }
            return
        }
        week.apply(days)
    }

    private func saveWeek() {
        guard canSaveWeek else {
            saveState = .idle
            advance()
            return
        }
        saveState = .saving
        Task {
            let outcome = await services.saveWeek(week.datesWithData)
            switch outcome {
            case .saved(let count):
                saveState = .saved(count)
                advance()
            case .failed(let message):
                saveState = .failed(message)
            }
        }
    }

    private func startTrial() {
        trialState = .purchasing
        Task {
            switch await services.startTrial() {
            case .started:
                trialState = .idle
                finish(enableSchedule: true)
            case .cancelled:
                trialState = .idle
            case .failed(let message):
                trialState = .failed(message)
            }
        }
    }

    private func finish(enableSchedule: Bool) {
        services.finish(enableSchedule)
        onComplete()
    }
}

// MARK: - Steps & state

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case packs
    case health
    case folder
    case firstNote
    case daily

    static let progressCount = 4

    var showsTopBar: Bool { (1...4).contains(rawValue) }
    /// Packs, Health, Folder and First note are steps 1–4 of the progress dots.
    var progressIndex: Int { max(0, min(rawValue - 1, Self.progressCount - 1)) }
    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    /// Back stops at the first note: after the free export, the trial offer is final.
    var previous: OnboardingStep? {
        self == .daily ? nil : OnboardingStep(rawValue: rawValue - 1)
    }
}

/// The Google Drive folder onboarding's Daily note automation uploads to.
struct OnboardingDriveFolder: Equatable {
    let id: UUID
    let folderLabel: String
    let isReady: Bool
}

enum OnboardingDriveOutcome: Equatable {
    case connected
    case cancelled
    case failed(String)
}

enum OnboardingDestination: String, CaseIterable, Identifiable {
    case folder
    case api
    case drive

    var id: String { rawValue }
}

struct OnboardingEndpointEditorRequest: Identifiable {
    let id = UUID()
    let endpointID: UUID?
}

enum OnboardingSaveState: Equatable {
    case idle
    case saving
    case saved(Int)
    case failed(String)
}

enum OnboardingTrialState: Equatable {
    case idle
    case purchasing
    case failed(String)
}

enum OnboardingSaveOutcome: Equatable {
    case saved(Int)
    case failed(String)
}

enum OnboardingTrialOutcome: Equatable {
    case started
    case cancelled
    case failed(String)
}

private enum TransitionDirection {
    case forward
    case backward
}

/// One day of the first-note preview, rendered from the user's real Health data.
struct OnboardingDayPreview: Identifiable, Equatable {
    struct Chip: Equatable, Hashable { let label: String; let value: String }
    struct Section: Equatable, Hashable { let title: String; let text: String }

    let date: Date
    let fileName: String
    let hasData: Bool
    let sleepMinutes: Double?
    let chips: [Chip]
    let sections: [Section]
    let rawFile: String

    var id: Date { date }
}

struct OnboardingWeekState: Equatable {
    var dates: [Date] = OnboardingWeekState.defaultDates()
    var days: [OnboardingDayPreview] = []
    var selectedIndex: Int = 6
    var isLoading = false
    var showsRaw = false
    private(set) var loadID = 0
    private var loaded = false

    var needsLoad: Bool { !loaded && !isLoading }
    var hasRealData: Bool { days.contains(where: \.hasData) }
    var daysWithData: Int { days.filter(\.hasData).count }
    var datesWithData: [Date] { days.filter(\.hasData).map(\.date) }
    var selectedDay: OnboardingDayPreview? {
        days.indices.contains(selectedIndex) ? days[selectedIndex] : days.last
    }

    var rangeDescription: String? {
        guard let first = dates.first, let last = dates.last else { return nil }
        let style = Date.FormatStyle().month(.abbreviated).day()
        return String(localized: "\(first.formatted(style)) through \(last.formatted(style))")
    }

    mutating func apply(_ previews: [OnboardingDayPreview]) {
        days = previews
        selectedIndex = max(0, previews.count - 1)
        isLoading = false
        loaded = true
    }

    mutating func invalidate() {
        loaded = false
        isLoading = false
        days = []
        dates = Self.defaultDates()
        loadID += 1
    }

    /// The seven complete days ending yesterday, oldest first.
    static func defaultDates(now: Date = Date(), calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (1...7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }
}

/// The app-side work onboarding needs. `ContentView` supplies the live
/// implementation so the flow reuses the real profile, export and purchase paths.
struct OnboardingServices {
    var coveredPacks: @MainActor () -> Set<OnboardingMetricPack>
    var applyPacks: @MainActor (Set<OnboardingMetricPack>) -> Void
    var selectDestination: @MainActor (OnboardingDestination) -> Void
    var destinationLabel: @MainActor () -> String
    /// The chosen local/iCloud folder, independent of the current target.
    var folderLabel: @MainActor () -> String? = { nil }
    /// The saved endpoint bound to the Daily note automation, if any.
    var apiEndpoint: @MainActor () -> OnboardingAPIEndpoint? = { nil }
    var apiEndpointEditMode: @MainActor (UUID) -> GlassAPIEndpointEditorSheet.Mode? = { _ in nil }
    /// Creates (nil id) or edits a saved endpoint and binds it to Daily note.
    var saveAPIEndpoint: @MainActor (APIEndpointDraft, UUID?) -> Bool = { _, _ in false }
    var deleteAPIEndpoint: @MainActor (UUID) -> Void = { _ in }
    /// Whether this build can connect Google Drive directly (PR #138 OAuth + Picker).
    var driveAvailable: @MainActor () -> Bool = { false }
    /// The Drive folder bound to the Daily note automation, if any.
    var driveFolder: @MainActor () -> OnboardingDriveFolder? = { nil }
    /// Shows Google consent and the folder Picker, then binds the folder to Daily note.
    var connectDrive: @MainActor () async -> OnboardingDriveOutcome = { .cancelled }
    var loadWeek: @MainActor ([Date]) async -> [OnboardingDayPreview]
    var saveWeek: @MainActor ([Date]) async -> OnboardingSaveOutcome
    var trialTimeline: @MainActor () -> [String]
    var trialEligible: @MainActor () -> Bool
    var prepareTrial: @MainActor () async -> Void
    var startTrial: @MainActor () async -> OnboardingTrialOutcome
    var finish: @MainActor (_ enableDailySchedule: Bool) -> Void

    /// Inert services for previews and marketing capture.
    static let preview = OnboardingServices(
        coveredPacks: { [] },
        applyPacks: { _ in },
        selectDestination: { _ in },
        destinationLabel: { "My Vault/Health" },
        loadWeek: { dates in dates.map { OnboardingDayPreview.sample(for: $0) } },
        saveWeek: { dates in .saved(dates.count) },
        trialTimeline: { OnboardingServices.defaultTrialTimeline(price: nil) },
        trialEligible: { true },
        prepareTrial: {},
        startTrial: { .cancelled },
        finish: { _ in }
    )

    static func defaultTrialTimeline(price: String?, trialEligible: Bool = true) -> [String] {
        guard trialEligible else {
            return [price.map { String(localized: "Billed \($0) a year. Cancel anytime.") }
                ?? String(localized: "Billed yearly. Cancel anytime.")]
        }
        return [
            String(localized: "Today · Start free trial"),
            String(localized: "Day 5 · Reminder before you're charged"),
            price.map { String(localized: "Day 7 · Billed \($0) unless cancelled") }
                ?? String(localized: "Day 7 · Billed yearly unless cancelled"),
        ]
    }
}

extension OnboardingDayPreview {
    /// Illustrative note shown when Apple Health has no records yet. It is
    /// always labelled as a sample and is never written to the user's folder.
    static func sample(for date: Date) -> OnboardingDayPreview {
        let day = date.formatted(.iso8601.year().month().day())
        return OnboardingDayPreview(
            date: date,
            fileName: "\(day).md",
            hasData: false,
            sleepMinutes: 450,
            chips: [
                Chip(label: "sleep", value: "7h 30m"),
                Chip(label: "hrv", value: "60 ms"),
                Chip(label: "steps", value: "8,000"),
                Chip(label: "resting", value: "58 bpm"),
            ],
            sections: [
                Section(title: String(localized: "Sleep"), text: String(localized: "Bed 10:45 PM, up 6:30 AM. Deep 1h 15m, REM 1h 50m.")),
                Section(title: String(localized: "Activity"), text: String(localized: "40 min exercise, 600 kcal active energy.")),
            ],
            rawFile: """
            ---
            date: \(day)
            type: health-data
            sleep_total_hours: 7.50
            hrv_ms: 60.0
            steps: 8000
            resting_heart_rate: 58
            ---

            # \(day)

            ## Sleep
            - Total: 7h 30m
            """
        )
    }
}

extension OnboardingDayPreview {
    /// Builds a day's preview from the user's real records. The raw file is the
    /// exact Markdown the export would write with the current settings.
    static func make(date: Date, data: HealthData?, settings: AdvancedExportSettings) -> OnboardingDayPreview {
        let fileName = settings.filename(for: date, format: .markdown)
        guard let data, data.hasAnyData else {
            return OnboardingDayPreview(date: date, fileName: fileName, hasData: false, sleepMinutes: nil,
                                        chips: [], sections: [], rawFile: "")
        }
        let time = Date.FormatStyle(date: .omitted, time: .shortened)
        let number = IntegerFormatStyle<Int>.number
        var chips: [Chip] = []
        var sections: [Section] = []

        let sleep = data.sleep
        let sleepMinutes = sleep.totalDuration > 0 ? sleep.totalDuration / 60 : nil
        if let sleepMinutes { chips.append(Chip(label: "sleep", value: OnboardingFirstNoteStep.duration(minutes: sleepMinutes))) }
        if let hrv = data.heart.hrv { chips.append(Chip(label: "hrv", value: "\(Int(hrv.rounded())) ms")) }
        if let steps = data.activity.steps { chips.append(Chip(label: "steps", value: steps.formatted(number))) }
        if let active = data.activity.activeCalories { chips.append(Chip(label: "active", value: "\(Int(active.rounded()).formatted(number)) kcal")) }
        if let resting = data.heart.restingHeartRate { chips.append(Chip(label: "resting", value: "\(Int(resting.rounded())) bpm")) }

        var sleepParts: [String] = []
        if let start = sleep.sessionStart, let end = sleep.sessionEnd {
            sleepParts.append(String(localized: "Bed \(start.formatted(time)), up \(end.formatted(time))."))
        }
        if sleep.deepSleep > 0 || sleep.remSleep > 0 {
            sleepParts.append(String(localized: "Deep \(OnboardingFirstNoteStep.duration(minutes: sleep.deepSleep / 60)), REM \(OnboardingFirstNoteStep.duration(minutes: sleep.remSleep / 60))."))
        }
        if !sleepParts.isEmpty { sections.append(Section(title: String(localized: "Sleep"), text: sleepParts.joined(separator: " "))) }

        var activityParts: [String] = []
        if let exercise = data.activity.exerciseMinutes, exercise > 0 {
            activityParts.append(String(localized: "\(Int(exercise.rounded())) min exercise"))
        }
        if let workout = data.workouts.first {
            let distance = workout.distance.map { String(format: " %.1f km", $0 / 1000) } ?? ""
            let more = data.workouts.count > 1 ? String(localized: " and \(data.workouts.count - 1) more") : ""
            activityParts.append(String(localized: "including a\(distance) \(workout.workoutType.displayName.lowercased())\(more)"))
        }
        if !activityParts.isEmpty {
            sections.append(Section(title: String(localized: "Activity"), text: activityParts.joined(separator: ", ") + "."))
        }

        var heartParts: [String] = []
        if let low = data.heart.heartRateMin, let high = data.heart.heartRateMax {
            heartParts.append(String(localized: "Range \(Int(low.rounded()))–\(Int(high.rounded())) bpm"))
        }
        if let oxygen = data.vitals.bloodOxygenAvg {
            heartParts.append(String(localized: "blood oxygen \(Int((oxygen * 100).rounded()))%"))
        }
        if !heartParts.isEmpty { sections.append(Section(title: String(localized: "Heart"), text: heartParts.joined(separator: ", ") + ".")) }

        if let weight = data.body.weight {
            let fat = data.body.bodyFatPercentage.map { String(localized: ", body fat \(String(format: "%.1f", $0 * 100))%") } ?? ""
            sections.append(Section(title: String(localized: "Body"), text: String(localized: "Weight \(String(format: "%.1f", weight)) kg\(fat).")))
        }
        if let mindful = data.mindfulness.mindfulMinutes, mindful > 0 {
            sections.append(Section(title: String(localized: "Mind"), text: String(localized: "\(Int(mindful.rounded())) mindful minutes.")))
        }
        if let energy = data.nutrition.dietaryEnergy {
            let protein = data.nutrition.protein.map { String(localized: ", \(Int($0.rounded())) g protein") } ?? ""
            sections.append(Section(title: String(localized: "Nutrition"), text: String(localized: "\(Int(energy.rounded()).formatted(number)) kcal\(protein).")))
        }

        return OnboardingDayPreview(
            date: date,
            fileName: fileName,
            hasData: true,
            sleepMinutes: sleepMinutes,
            chips: chips,
            sections: sections,
            rawFile: data.export(format: .markdown, settings: settings)
        )
    }
}

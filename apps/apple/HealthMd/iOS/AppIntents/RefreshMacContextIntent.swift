import AppIntents
import Foundation

@MainActor
final class IPhoneMacContextRefreshCoordinator {
    static let shared = IPhoneMacContextRefreshCoordinator()

    enum Outcome: Equatable {
        case pending(IPhoneContextRefreshStatus)
        case failed(IPhoneContextRefreshStatus)
    }

    private static let receiptDefaultsKey = "shortcuts.macContextRefresh.latestReceipt.v1"
    private weak var syncService: SyncService?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func configure(syncService: SyncService) {
        self.syncService = syncService
    }

    var latestStatus: IPhoneContextRefreshStatus? {
        get {
            guard let data = defaults.data(forKey: Self.receiptDefaultsKey) else { return nil }
            return try? JSONDecoder().decode(IPhoneContextRefreshStatus.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: Self.receiptDefaultsKey)
                return
            }
            defaults.set(data, forKey: Self.receiptDefaultsKey)
        }
    }

    func handle(_ status: IPhoneContextRefreshStatus) {
        guard latestStatus?.jobID == status.jobID || latestStatus == nil else { return }
        latestStatus = status
    }

    func request(
        profileName: String?,
        days: Int,
        allAvailable: Bool,
        now: Date = Date()
    ) -> Outcome {
        let profileStore = ExportProfileStore()
        let profile: ExportProfile?
        let settings: AdvancedExportSettings
        switch ExportIntentRunner.resolveProfile(named: profileName, profileStore: profileStore) {
        case .profile(let resolved):
            guard !SharedSetupV2ExecutionGate().isExecutionBlocked(profileID: resolved.id) else {
                return fail("The selected profile needs destination review before it can run.")
            }
            profile = resolved
            settings = AdvancedExportSettings(snapshot: resolved.settings, userDefaults: .standard)
        case .legacySettings:
            profile = nil
            settings = AdvancedExportSettings()
        case .notFound(let name):
            return fail("No export profile named \(name) exists.")
        case .unavailable:
            return fail("Choose an active export profile before refreshing Mac context.")
        }

        guard let syncService,
              syncService.connectionState == .connected else {
            return fail("No authenticated Mac is connected. Open Health.md on Mac and iPhone, then retry.")
        }
        guard syncService.remoteCapabilities?.supportsIPhoneInitiatedContextRefresh == true,
              syncService.localCapabilities.supportsIPhoneInitiatedContextRefresh else {
            return fail("The connected Mac does not support phone-initiated context refresh. Update Health.md on both devices.")
        }

        let request = Self.makeRequest(
            profile: profile,
            settings: settings,
            days: days,
            allAvailable: allAvailable,
            now: now
        )
        let receipt = IPhoneContextRefreshStatus(
            jobID: request.jobID,
            state: .pending,
            message: "The authenticated Mac context refresh request was sent and is pending durable acceptance."
        )
        latestStatus = receipt
        syncService.send(.iphoneContextRefreshRequest(request))
        return .pending(receipt)
    }

    static func makeRequest(
        profile: ExportProfile?,
        settings: AdvancedExportSettings,
        days: Int,
        allAvailable: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> IPhoneContextRefreshRequest {
        let end = calendar.startOfDay(for: now)
        let boundedDays = min(max(days, 1), 3_650)
        let start = calendar.date(byAdding: .day, value: -(boundedDays - 1), to: end) ?? end
        let detailLevel: CanonicalHealthDataSelection.DetailLevel =
            settings.detailPolicy.includesCanonicalArchive ? .lossless : .summary
        return IPhoneContextRefreshRequest(
            dateSelection: allAvailable ? .allAvailable : .explicitRange,
            dateRangeStart: allAvailable ? end : start,
            dateRangeEnd: end,
            selection: CanonicalHealthDataSelection(
                metricIDs: Array(settings.metricSelection.enabledMetrics),
                sourceIDs: ["apple_health"],
                detailLevel: detailLevel
            ),
            profileID: profile?.id,
            profileName: profile?.name
        )
    }

    private func fail(_ message: String) -> Outcome {
        let status = IPhoneContextRefreshStatus(
            jobID: UUID(),
            state: .failed,
            message: message,
            failureReason: "refresh_preflight_failed"
        )
        latestStatus = status
        return .failed(status)
    }
}

struct RefreshMacContextIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Mac Health Context"
    static var description = IntentDescription(
        "Requests a scoped refresh of the encrypted Health.md context on an authenticated connected Mac. It does not write export files.",
        categoryName: "Health"
    )
    static var openAppWhenRun = false

    @Parameter(
        title: "Profile",
        description: "Export profile whose metric and detail scope should be refreshed. Leave empty to use the active profile."
    )
    var profile: String?

    @Parameter(
        title: "Number of Days",
        description: "Explicit owner-day window ending today. Ignored when All Available History is on.",
        default: 30
    )
    var days: Int

    @Parameter(
        title: "All Available History",
        description: "Ask for all readable authorized history. This fails closed unless OS 27+ verifies full-history authorization for the entire profile scope.",
        default: false
    )
    var allAvailableHistory: Bool

    init() {
        days = 30
        allAvailableHistory = false
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Refresh encrypted Mac context for the selected profile")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = IPhoneMacContextRefreshCoordinator.shared.request(
            profileName: profile,
            days: days,
            allAvailable: allAvailableHistory
        )
        let status: IPhoneContextRefreshStatus
        switch outcome {
        case .pending(let value), .failed(let value): status = value
        }
        return .result(dialog: IntentDialog(stringLiteral: "\(status.message) Job: \(status.jobID.uuidString.lowercased())."))
    }
}

struct GetMacContextRefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Mac Context Refresh Status"
    static var description = IntentDescription(
        "Returns the latest durable status received for a Shortcuts-initiated encrypted Mac context refresh.",
        categoryName: "Health"
    )
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let status = IPhoneMacContextRefreshCoordinator.shared.latestStatus else {
            return .result(dialog: "No Mac context refresh request has been recorded on this iPhone.")
        }
        return .result(dialog: IntentDialog(stringLiteral: "\(status.state.rawValue): \(status.message) Job: \(status.jobID.uuidString.lowercased())."))
    }
}

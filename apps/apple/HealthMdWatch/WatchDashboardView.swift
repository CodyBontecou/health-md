import SwiftUI
import WidgetKit

/// WatchDashboardG colours.
private enum WatchGlass {
    static let accent = Color(red: 0xCD / 255, green: 0xB6 / 255, blue: 0xFF / 255)
    static let label = Color(red: 0xDA / 255, green: 0xD4 / 255, blue: 0xE8 / 255)
    static let hrv = Color(red: 0x5E / 255, green: 0xD3 / 255, blue: 0xB0 / 255)
    static let heart = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x93 / 255)
    static let steps = Color(red: 0xA6 / 255, green: 0xF2 / 255, blue: 0x5F / 255)
    static let oxygen = Color(red: 0x5E / 255, green: 0xD3 / 255, blue: 0xF2 / 255)
    // Softened orange / yellow / blue: the hue families the complications use for move,
    // exercise and stand.
    static let move = Color(red: 0xFF / 255, green: 0x8A / 255, blue: 0x5B / 255)
    static let exercise = Color(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x5C / 255)
    static let stand = Color(red: 0x7F / 255, green: 0xB2 / 255, blue: 0xFF / 255)
    static let line = Color.white.opacity(0.14)
}

private enum WatchHealthAccessState: Equatable {
    case unknown
    case needsAuthorization
    case requested
    case connected
    case unavailable
}

@MainActor
final class WatchDashboardViewModel: ObservableObject {
    @Published var snapshot: WatchHealthSnapshot = .placeholder
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published private var accessState: WatchHealthAccessState = .unknown

    var authorizationButtonTitle: String {
        if isLoading {
            switch accessState {
            case .needsAuthorization, .unknown:
                return "Connecting…"
            case .requested, .connected, .unavailable:
                return "Checking…"
            }
        }

        switch accessState {
        case .unknown, .needsAuthorization:
            return "Connect Health"
        case .requested:
            return "Check Health Access"
        case .connected:
            return "Health Connected"
        case .unavailable:
            return "Health Unavailable"
        }
    }

    var isHealthConnected: Bool {
        accessState == .connected
    }

    var isAuthorizationButtonDisabled: Bool {
        isLoading || accessState == .connected || accessState == .unavailable
    }

    func refresh() async {
        #if DEBUG
        // App Store captures (Debug builds only): launch with `-watch.appStoreFixture YES` to show
        // WatchDashboardG's values as a connected dashboard, without HealthKit or a status line.
        if UserDefaults.standard.bool(forKey: "watch.appStoreFixture") {
            snapshot = .appStoreFixture
            accessState = .connected
            errorMessage = nil
            statusMessage = nil
            isLoading = false
            return
        }
        #endif
        isLoading = true
        errorMessage = nil
        statusMessage = nil

        await updateAuthorizationState()
        let fetchedSnapshot = await WatchHealthSnapshotProvider.fetchToday()
        apply(fetchedSnapshot, emptyDataMessage: statusMessageForCurrentAccessState())

        isLoading = false
    }

    func requestAuthorizationAndRefresh() async {
        isLoading = true
        errorMessage = nil
        statusMessage = accessState == .requested ? "Checking existing Health access…" : "Opening Health access…"

        do {
            let authorizationResult = try await WatchHealthSnapshotProvider.requestAuthorization()
            accessState = .requested
            statusMessage = message(for: authorizationResult)

            let fetchedSnapshot = await WatchHealthSnapshotProvider.fetchToday()
            apply(fetchedSnapshot, emptyDataMessage: message(for: authorizationResult))
            WidgetCenter.shared.reloadAllTimelines()
        } catch WatchHealthSnapshotError.healthDataUnavailable {
            statusMessage = nil
            accessState = .unavailable
            errorMessage = WatchHealthSnapshotError.healthDataUnavailable.localizedDescription
        } catch {
            statusMessage = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func updateAuthorizationState() async {
        do {
            switch try await WatchHealthSnapshotProvider.authorizationStatus() {
            case .shouldRequest:
                accessState = .needsAuthorization
            case .alreadyHandled:
                accessState = .requested
            case .unknown:
                accessState = .unknown
            }
        } catch WatchHealthSnapshotError.healthDataUnavailable {
            accessState = .unavailable
            errorMessage = WatchHealthSnapshotError.healthDataUnavailable.localizedDescription
        } catch {
            accessState = .unknown
            statusMessage = "Unable to check Health access: \(error.localizedDescription)"
        }
    }

    private func apply(_ fetchedSnapshot: WatchHealthSnapshot, emptyDataMessage: String?) {
        snapshot = fetchedSnapshot

        if fetchedSnapshot.hasAnyData {
            WatchHealthSnapshotStore.save(fetchedSnapshot)
            accessState = .connected
            statusMessage = "Connected. Today's Health data is ready for widgets."
        } else if accessState == .requested {
            statusMessage = emptyDataMessage
        }
    }

    private func statusMessageForCurrentAccessState() -> String? {
        switch accessState {
        case .requested:
            return message(for: .alreadyHandled)
        default:
            return statusMessage
        }
    }

    private func message(for authorizationResult: WatchHealthAuthorizationRequestResult) -> String {
        switch authorizationResult {
        case .promptPresented:
            return "Health request completed. If metrics stay blank, check iPhone Health > Sharing > Apps > Health.md."
        case .alreadyHandled:
            return "Health access was already requested. HealthKit won’t show the prompt again; check iPhone Health > Sharing > Apps > Health.md, then Refresh."
        }
    }
}

/// WatchDashboardG: the crystal-heart header over the metric rows (sleep, recovery, then the
/// three activity rings and blood oxygen, as in 3.5). Health access, widget guidance and refresh
/// controls sit below the rows, and the access button only shows until Health is connected.
struct WatchDashboardView: View {
    @StateObject private var viewModel = WatchDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                ForEach(metricRows) { row in
                    WatchMetricRow(row: row)
                }

                footer
                    .padding(.top, 12)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .background(Color.black)
        .task { await viewModel.refresh() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image("HealthCrystalHeart")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            Text(verbatim: "Health.md")
                .font(.system(size: 15, weight: .bold))
        }
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }

    private var metricRows: [WatchMetricRowModel] {
        let snapshot = viewModel.snapshot
        return WatchDashboardMetric.allCases.map { metric in
            WatchMetricRowModel(
                id: metric.id,
                title: metric.titleKey,
                value: metric.value(in: snapshot),
                tint: tint(for: metric)
            )
        }
    }

    private func tint(for metric: WatchDashboardMetric) -> Color {
        switch metric {
        case .sleep: return WatchGlass.accent
        case .heartRateVariability: return WatchGlass.hrv
        case .restingHeartRate: return WatchGlass.heart
        case .steps: return WatchGlass.steps
        case .activeEnergy: return WatchGlass.move
        case .exerciseMinutes: return WatchGlass.exercise
        case .standHours: return WatchGlass.stand
        case .bloodOxygen: return WatchGlass.oxygen
        }
    }

    /// 3.5's header guidance, kept below the rows: once Health is connected, point people at
    /// the Smart Stack and watch-face widgets; before that, ask for access first.
    private var widgetGuidance: LocalizedStringKey {
        viewModel.isHealthConnected
            ? "Add Health.md widgets to your Smart Stack or watch face."
            : "Allow Health access here, then add Health.md widgets to your Smart Stack or watch face."
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(WatchGlass.label)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(WatchGlass.heart)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label {
                Text(widgetGuidance)
            } icon: {
                Image(systemName: "applewatch.watchface")
                    .foregroundStyle(WatchGlass.accent)
            }
            .font(.footnote)
            .foregroundStyle(WatchGlass.label)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("watch.dashboard.widgetGuidance")

            if !viewModel.isHealthConnected {
                Button {
                    Task { await viewModel.requestAuthorizationAndRefresh() }
                } label: {
                    Text(viewModel.authorizationButtonTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(WatchGlass.accent)
                .foregroundStyle(Color.black)
                .disabled(viewModel.isAuthorizationButtonDisabled)
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
    }
}

private struct WatchMetricRowModel: Identifiable {
    let id: String
    let title: String
    let value: String
    let tint: Color
}

private struct WatchMetricRow: View {
    let row: WatchMetricRowModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(row.title))
                .font(.system(size: 13))
                .foregroundStyle(WatchGlass.label)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(row.value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(row.tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) {
            Rectangle().fill(WatchGlass.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.dashboard.metric.\(row.id)")
    }
}

#Preview {
    WatchDashboardView()
}

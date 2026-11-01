import SwiftUI
import WidgetKit

private enum WatchGlass {
    static let accent = Color(red: 0xCD / 255, green: 0xB6 / 255, blue: 0xFF / 255)
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

    var isAuthorizationButtonDisabled: Bool {
        isLoading || accessState == .connected || accessState == .unavailable
    }

    var headerMessage: String {
        switch accessState {
        case .connected:
            return "Health is connected. Add Health.md widgets to your Smart Stack or watch face."
        case .requested:
            return "Health access was already requested for this watch. Use Refresh after changing permissions."
        default:
            return "Allow Health access here, then add Health.md widgets to your Smart Stack or watch face."
        }
    }

    func refresh() async {
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

struct WatchDashboardView: View {
    @StateObject private var viewModel = WatchDashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    metricGrid

                    header

                    if viewModel.isLoading {
                        ProgressView("Updating…")
                            .font(.footnote)
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await viewModel.requestAuthorizationAndRefresh() }
                    } label: {
                        Label(viewModel.authorizationButtonTitle, systemImage: "heart.text.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isAuthorizationButtonDisabled)

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Health.md")
            .task { await viewModel.refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Watch Widgets", systemImage: "applewatch.watchface")
                .font(.headline)
            Text(viewModel.headerMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// WatchDashboardG leads with these; the rest stay reachable below them.
    private var metricRows: [WatchMetricRow] {
        let snapshot = viewModel.snapshot
        let steps = WatchMetricRow(icon: "figure.walk", title: "Steps", value: WatchHealthFormatter.steps(snapshot.steps), tint: .green)
        let active = WatchMetricRow(icon: "flame.fill", title: "Active", value: "\(WatchHealthFormatter.wholeNumber(snapshot.activeEnergyKilocalories)) kcal", tint: .orange)
        let exercise = WatchMetricRow(icon: "timer", title: "Exercise", value: "\(WatchHealthFormatter.wholeNumber(snapshot.exerciseMinutes)) min", tint: .yellow)
        let stand = WatchMetricRow(icon: "figure.stand", title: "Stand", value: WatchHealthFormatter.standHours(snapshot.standHours), tint: .blue)
        let sleep = WatchMetricRow(icon: "bed.double.fill", title: "Sleep", value: WatchHealthFormatter.hours(snapshot.sleepHours), tint: .indigo)
        let resting = WatchMetricRow(icon: "heart.fill", title: "Resting HR", value: WatchHealthFormatter.bpm(snapshot.restingHeartRate), tint: .red)
        let hrv = WatchMetricRow(icon: "waveform.path.ecg", title: "HRV", value: WatchHealthFormatter.milliseconds(snapshot.heartRateVariabilityMS), tint: .cyan)
        let oxygen = WatchMetricRow(icon: "lungs.fill", title: "Blood Oxygen", value: WatchHealthFormatter.percent(snapshot.bloodOxygenPercent), tint: .mint)
        return [sleep, hrv, resting, steps, oxygen, active, exercise, stand]
    }

    private var metricGrid: some View {
        VStack(spacing: 8) {
            ForEach(metricRows, id: \.title) { $0 }
        }
    }
}

private struct WatchMetricRow: View {
    let icon: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WatchGlass.accent)
                .frame(width: 20)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    WatchDashboardView()
}

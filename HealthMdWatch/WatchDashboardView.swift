import SwiftUI
import WidgetKit

@MainActor
final class WatchDashboardViewModel: ObservableObject {
    @Published var snapshot: WatchHealthSnapshot = .placeholder
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var hasRequestedAuthorization = false

    func refresh() async {
        isLoading = true
        errorMessage = nil
        snapshot = await WatchHealthSnapshotProvider.fetchToday()
        if snapshot.hasAnyData {
            WatchHealthSnapshotStore.save(snapshot)
        }
        isLoading = false
    }

    func requestAuthorizationAndRefresh() async {
        isLoading = true
        errorMessage = nil

        do {
            try await WatchHealthSnapshotProvider.requestAuthorization()
            hasRequestedAuthorization = true
            snapshot = await WatchHealthSnapshotProvider.fetchToday()
            if snapshot.hasAnyData {
                WatchHealthSnapshotStore.save(snapshot)
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

struct WatchDashboardView: View {
    @StateObject private var viewModel = WatchDashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await viewModel.requestAuthorizationAndRefresh() }
                    } label: {
                        Label("Connect Health", systemImage: "heart.text.square")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)

                    metricGrid
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
            Text("Allow Health access here, then add Health.md widgets to your Smart Stack or watch face.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metricGrid: some View {
        VStack(spacing: 8) {
            WatchMetricRow(
                icon: "figure.walk",
                title: "Steps",
                value: WatchHealthFormatter.steps(viewModel.snapshot.steps),
                tint: .green
            )
            WatchMetricRow(
                icon: "flame.fill",
                title: "Active",
                value: "\(WatchHealthFormatter.wholeNumber(viewModel.snapshot.activeEnergyKilocalories)) kcal",
                tint: .orange
            )
            WatchMetricRow(
                icon: "timer",
                title: "Exercise",
                value: "\(WatchHealthFormatter.wholeNumber(viewModel.snapshot.exerciseMinutes)) min",
                tint: .yellow
            )
            WatchMetricRow(
                icon: "bed.double.fill",
                title: "Sleep",
                value: WatchHealthFormatter.hours(viewModel.snapshot.sleepHours),
                tint: .indigo
            )
            WatchMetricRow(
                icon: "heart.fill",
                title: "Resting HR",
                value: WatchHealthFormatter.bpm(viewModel.snapshot.restingHeartRate),
                tint: .red
            )
            WatchMetricRow(
                icon: "waveform.path.ecg",
                title: "HRV",
                value: WatchHealthFormatter.milliseconds(viewModel.snapshot.heartRateVariabilityMS),
                tint: .cyan
            )
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
                .foregroundStyle(tint)
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    WatchDashboardView()
}

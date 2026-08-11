#if os(iOS)
import Combine
import Foundation
import SwiftUI

@MainActor
final class CLIExportActivityTracker: ObservableObject {
    static let shared = CLIExportActivityTracker()

    enum Source: Equatable {
        case macApp
        case direct

        var label: String {
            switch self {
            case .macApp: return "Mac CLI"
            case .direct: return "Direct CLI"
            }
        }

        var defaultTargetLabel: String {
            switch self {
            case .macApp: return "Connected Mac"
            case .direct: return "Health.md CLI"
            }
        }
    }

    enum Phase: Equatable {
        case preparing
        case capturing
        case transferring
        case paused
        case completed
        case completedWithWarnings
        case failed
        case cancelled

        var isTerminal: Bool {
            switch self {
            case .completed, .completedWithWarnings, .failed, .cancelled: return true
            case .preparing, .capturing, .transferring, .paused: return false
            }
        }

        var keepsScreenAwake: Bool {
            switch self {
            case .preparing, .capturing, .transferring: return true
            case .paused, .completed, .completedWithWarnings, .failed, .cancelled: return false
            }
        }
    }

    struct Snapshot: Equatable {
        let jobID: UUID
        let source: Source
        let targetLabel: String
        let phase: Phase
        let processedDays: Int
        let totalDays: Int
        let currentDate: String?
        let committedPartitions: Int
        let committedBytes: Int64
        let message: String

        var fractionComplete: Double? {
            if phase == .completed || phase == .completedWithWarnings { return 1 }
            guard totalDays > 0 else { return nil }
            return min(max(Double(processedDays) / Double(totalDays), 0), 1)
        }
    }

    @Published private(set) var snapshot: Snapshot?

    private var dismissalTask: Task<Void, Never>?

    var keepsScreenAwake: Bool {
        snapshot?.phase.keepsScreenAwake == true
    }

    func begin(
        jobID: UUID,
        source: Source,
        totalDays: Int = 0,
        targetLabel: String? = nil,
        message: String
    ) {
        dismissalTask?.cancel()
        publish(Snapshot(
            jobID: jobID,
            source: source,
            targetLabel: targetLabel ?? source.defaultTargetLabel,
            phase: .preparing,
            processedDays: 0,
            totalDays: max(totalDays, 0),
            currentDate: nil,
            committedPartitions: 0,
            committedBytes: 0,
            message: message
        ))
    }

    func update(
        jobID: UUID,
        source: Source,
        targetLabel: String? = nil,
        phase: Phase,
        processedDays: Int,
        totalDays: Int,
        currentDate: String?,
        committedPartitions: Int = 0,
        committedBytes: Int64 = 0,
        message: String
    ) {
        dismissalTask?.cancel()
        guard snapshot == nil
                || snapshot?.jobID == jobID
                || snapshot?.phase.isTerminal == true else { return }
        let existingTarget = snapshot?.jobID == jobID ? snapshot?.targetLabel : nil
        publish(Snapshot(
            jobID: jobID,
            source: source,
            targetLabel: targetLabel ?? existingTarget ?? source.defaultTargetLabel,
            phase: phase,
            processedDays: max(processedDays, 0),
            totalDays: max(totalDays, 0),
            currentDate: currentDate,
            committedPartitions: max(committedPartitions, 0),
            committedBytes: max(committedBytes, 0),
            message: message
        ))
    }

    func updateMac(_ progress: MacExportProgress) {
        guard snapshot?.jobID == progress.jobID,
              snapshot?.source == .macApp else { return }
        let phase: Phase
        switch progress.phase {
        case .receiving, .validating, .exporting, .writing:
            phase = .transferring
        case .completed:
            phase = .completed
        case .failed:
            phase = .failed
        case .cancelled:
            phase = .cancelled
        }
        update(
            jobID: progress.jobID,
            source: .macApp,
            phase: phase,
            processedDays: progress.processedDays,
            totalDays: progress.totalDays,
            currentDate: progress.currentDate.map(Self.dateFormatter.string(from:)),
            message: progress.message
        )
        if phase.isTerminal {
            finish(jobID: progress.jobID, phase: phase, message: progress.message)
        }
    }

    func updateConnected(_ progress: ConnectedCorpusProgressSnapshot) {
        let phase: Phase
        switch progress.state {
        case .preparing:
            phase = .capturing
        case .transferring, .finalizing:
            phase = .transferring
        case .paused:
            phase = .paused
        case .completed:
            phase = .completed
        case .partialSuccess:
            phase = .completedWithWarnings
        case .failed, .expired:
            phase = .failed
        case .cancelled:
            phase = .cancelled
        }
        let message = progress.message ?? defaultMessage(for: phase)
        update(
            jobID: progress.jobID,
            source: .macApp,
            phase: phase,
            processedDays: progress.processedDays,
            totalDays: progress.totalDays,
            currentDate: progress.currentDate.map(Self.dateFormatter.string(from:)),
            committedPartitions: progress.committedPartitionCount,
            committedBytes: progress.committedBytes,
            message: message
        )
        if phase.isTerminal {
            finish(jobID: progress.jobID, phase: phase, message: message)
        }
    }

    func finish(jobID: UUID, phase: Phase, message: String) {
        guard phase.isTerminal,
              let current = snapshot,
              current.jobID == jobID else { return }
        publish(Snapshot(
            jobID: current.jobID,
            source: current.source,
            targetLabel: current.targetLabel,
            phase: phase,
            processedDays: phase == .completed || phase == .completedWithWarnings
                ? max(current.processedDays, current.totalDays)
                : current.processedDays,
            totalDays: current.totalDays,
            currentDate: current.currentDate,
            committedPartitions: current.committedPartitions,
            committedBytes: current.committedBytes,
            message: message
        ))
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  self?.snapshot?.jobID == jobID,
                  self?.snapshot?.phase == phase else { return }
            self?.snapshot = nil
        }
    }

    func setMessage(jobID: UUID, phase: Phase? = nil, message: String) {
        guard let current = snapshot, current.jobID == jobID else { return }
        update(
            jobID: current.jobID,
            source: current.source,
            phase: phase ?? current.phase,
            processedDays: current.processedDays,
            totalDays: current.totalDays,
            currentDate: current.currentDate,
            committedPartitions: current.committedPartitions,
            committedBytes: current.committedBytes,
            message: message
        )
    }

    func clear(jobID: UUID? = nil) {
        guard jobID == nil || snapshot?.jobID == jobID else { return }
        let dismissedJobID = snapshot?.jobID
        dismissalTask?.cancel()
        dismissalTask = nil
        snapshot = nil
        if let dismissedJobID {
            CLIExportLiveActivityController.shared.dismiss(jobID: dismissedJobID)
        }
    }

    private func publish(_ newSnapshot: Snapshot) {
        snapshot = newSnapshot
        CLIExportLiveActivityController.shared.present(newSnapshot)
    }

    private func defaultMessage(for phase: Phase) -> String {
        switch phase {
        case .preparing: return "Preparing the CLI export…"
        case .capturing: return "Reading the requested Apple Health data…"
        case .transferring: return "Sending the export to the CLI…"
        case .paused: return "CLI export paused. Reconnect the same Mac to resume."
        case .completed: return "CLI export completed."
        case .completedWithWarnings: return "CLI export completed with missing data."
        case .failed: return "CLI export failed."
        case .cancelled: return "CLI export cancelled."
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

struct CLIExportActivityBanner: View {
    let snapshot: CLIExportActivityTracker.Snapshot

    var body: some View {
        ExportActivityBanner(
            title: title,
            systemImage: phaseIcon,
            tint: phaseColor,
            sourceLabel: snapshot.source.label,
            targetLabel: snapshot.targetLabel,
            message: snapshot.message,
            progress: snapshot.fractionComplete,
            showsIndeterminateProgress: !snapshot.phase.isTerminal && snapshot.phase != .paused,
            progressAccessibilityLabel: snapshot.fractionComplete == nil
                ? String(localized: "CLI export in progress")
                : String(localized: "CLI export progress"),
            details: details,
            trailingText: snapshot.phase.keepsScreenAwake
                ? String(localized: "Keep Health.md open")
                : nil,
            accessibilityIdentifier: AccessibilityID.CLI.exportActivity
        )
    }

    private var details: [ExportActivityBannerDetail] {
        var details: [ExportActivityBannerDetail] = []
        if snapshot.totalDays > 0 {
            details.append(ExportActivityBannerDetail(
                text: "\(min(snapshot.processedDays, snapshot.totalDays)) of \(snapshot.totalDays) days",
                systemImage: "calendar"
            ))
        }
        if snapshot.committedBytes > 0 {
            details.append(ExportActivityBannerDetail(
                text: ByteCountFormatter.string(
                    fromByteCount: snapshot.committedBytes,
                    countStyle: .file
                ),
                systemImage: "arrow.up.doc"
            ))
        }
        return details
    }

    private var title: String {
        switch snapshot.phase {
        case .preparing: return "CLI export starting"
        case .capturing: return "CLI export in progress"
        case .transferring: return "Sending CLI export"
        case .paused: return "CLI export paused"
        case .completed, .completedWithWarnings: return "CLI export completed"
        case .failed: return "CLI export failed"
        case .cancelled: return "CLI export cancelled"
        }
    }

    private var phaseIcon: String {
        switch snapshot.phase {
        case .preparing, .capturing: return "waveform.path.ecg"
        case .transferring: return "arrow.up.doc.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .completedWithWarnings: return "exclamationmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .failed, .cancelled: return Color.error
        case .completed: return Color.success
        case .completedWithWarnings, .paused: return Color.warning
        case .preparing, .capturing, .transferring: return Color.accent
        }
    }
}
#endif

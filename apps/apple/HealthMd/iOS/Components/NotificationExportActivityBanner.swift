#if os(iOS)
import Combine
import Foundation
import SwiftUI

@MainActor
final class NotificationExportActivityTracker: ObservableObject {
    static let shared = NotificationExportActivityTracker()

    enum Source: Equatable {
        case scheduled
        case shortcut

        var label: String {
            switch self {
            case .scheduled: return "Scheduled"
            case .shortcut: return "Shortcut Retry"
            }
        }

        var operationLabel: String {
            switch self {
            case .scheduled: return "Scheduled export"
            case .shortcut: return "Shortcut export"
            }
        }
    }

    enum Phase: Equatable {
        case preparing
        case capturing
        case transferring
        case completed
        case completedWithWarnings
        case failed

        var isTerminal: Bool {
            switch self {
            case .completed, .completedWithWarnings, .failed: return true
            case .preparing, .capturing, .transferring: return false
            }
        }

        var keepsScreenAwake: Bool { !isTerminal }
    }

    struct Snapshot: Equatable {
        let operationID: UUID
        let source: Source
        let targetLabel: String
        let phase: Phase
        let processedDays: Int
        let totalDays: Int
        let message: String

        var fractionComplete: Double? {
            if phase == .completed || phase == .completedWithWarnings { return 1 }
            guard totalDays > 0 else { return nil }
            return min(max(Double(processedDays) / Double(totalDays), 0), 1)
        }
    }

    @Published private(set) var snapshot: Snapshot?

    private var dismissalTask: Task<Void, Never>?
    private var handledResultTimestamp: Date?

    var keepsScreenAwake: Bool {
        snapshot?.phase.keepsScreenAwake == true
    }

    func begin(
        operationID: UUID,
        source: Source,
        targetLabel: String,
        totalDays: Int,
        message: String
    ) {
        guard snapshot == nil
                || snapshot?.operationID == operationID
                || snapshot?.phase.isTerminal == true else { return }
        dismissalTask?.cancel()
        handledResultTimestamp = nil
        snapshot = Snapshot(
            operationID: operationID,
            source: source,
            targetLabel: targetLabel,
            phase: .preparing,
            processedDays: 0,
            totalDays: max(totalDays, 0),
            message: message
        )
    }

    func update(
        operationID: UUID,
        phase: Phase,
        processedDays: Int,
        totalDays: Int,
        message: String
    ) {
        guard let current = snapshot,
              current.operationID == operationID,
              !current.phase.isTerminal else { return }
        dismissalTask?.cancel()
        snapshot = Snapshot(
            operationID: current.operationID,
            source: current.source,
            targetLabel: current.targetLabel,
            phase: phase,
            processedDays: max(processedDays, 0),
            totalDays: max(totalDays, 0),
            message: message
        )
    }

    func finish(with result: NotificationExportResult) {
        guard let current = snapshot, !current.phase.isTerminal else { return }
        let phase: Phase
        switch result.status {
        case .success, .dailyNotesCompleted, .noExportNeeded:
            phase = .completed
        case .partialSuccess:
            phase = .completedWithWarnings
        case .failure:
            phase = .failed
        }

        handledResultTimestamp = result.timestamp
        snapshot = Snapshot(
            operationID: current.operationID,
            source: current.source,
            targetLabel: current.targetLabel,
            phase: phase,
            processedDays: phase == .completed || phase == .completedWithWarnings
                ? max(current.processedDays, current.totalDays)
                : current.processedDays,
            totalDays: current.totalDays,
            message: result.message
        )

        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled,
                  self?.snapshot?.operationID == current.operationID,
                  self?.snapshot?.phase == phase else { return }
            self?.snapshot = nil
        }
    }

    func handles(_ result: NotificationExportResult) -> Bool {
        handledResultTimestamp == result.timestamp
    }

    func clear() {
        dismissalTask?.cancel()
        dismissalTask = nil
        handledResultTimestamp = nil
        snapshot = nil
    }
}

struct NotificationExportActivityBanner: View {
    let snapshot: NotificationExportActivityTracker.Snapshot

    var body: some View {
        ExportActivityBanner(
            title: title,
            systemImage: phaseIcon,
            tint: phaseColor,
            sourceLabel: snapshot.source.label,
            targetLabel: snapshot.targetLabel,
            message: snapshot.message,
            progress: snapshot.fractionComplete,
            showsIndeterminateProgress: !snapshot.phase.isTerminal,
            progressAccessibilityLabel: snapshot.fractionComplete == nil
                ? String(localized: "Notification export in progress")
                : String(localized: "Notification export progress"),
            details: details,
            trailingText: snapshot.phase.keepsScreenAwake
                ? String(localized: "Keep Health.md open")
                : nil,
            accessibilityIdentifier: AccessibilityID.Notification.exportActivity
        )
    }

    private var details: [ExportActivityBannerDetail] {
        guard snapshot.totalDays > 0 else { return [] }
        return [ExportActivityBannerDetail(
            text: "\(min(snapshot.processedDays, snapshot.totalDays)) of \(snapshot.totalDays) days",
            systemImage: "calendar"
        )]
    }

    private var title: String {
        switch snapshot.phase {
        case .preparing: return "\(snapshot.source.operationLabel) starting"
        case .capturing: return "\(snapshot.source.operationLabel) in progress"
        case .transferring: return "Sending \(snapshot.source.operationLabel.lowercased())"
        case .completed, .completedWithWarnings: return "\(snapshot.source.operationLabel) completed"
        case .failed: return "\(snapshot.source.operationLabel) failed"
        }
    }

    private var phaseIcon: String {
        switch snapshot.phase {
        case .preparing, .capturing: return "waveform.path.ecg"
        case .transferring: return "arrow.up.doc.fill"
        case .completed: return "checkmark.circle.fill"
        case .completedWithWarnings: return "exclamationmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var phaseColor: Color {
        switch snapshot.phase {
        case .failed: return Color.error
        case .completed: return Color.success
        case .completedWithWarnings: return Color.warning
        case .preparing, .capturing, .transferring: return Color.accent
        }
    }
}
#endif

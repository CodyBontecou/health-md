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
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                Image(systemName: phaseIcon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(phaseColor)
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Spacer(minLength: Spacing.s2)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(snapshot.source.label)
                        .font(.caption2.weight(.semibold))
                    Text(snapshot.targetLabel)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.bgSecondary))
                .privacySensitive()
            }

            Text(snapshot.message)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let progress = snapshot.fractionComplete {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(phaseColor)
                    .accessibilityLabel("Notification export progress")
                    .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            } else if !snapshot.phase.isTerminal {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(phaseColor)
                    .accessibilityLabel("Notification export in progress")
            }

            HStack(spacing: Spacing.s3) {
                if snapshot.totalDays > 0 {
                    Label(
                        "\(min(snapshot.processedDays, snapshot.totalDays)) of \(snapshot.totalDays) days",
                        systemImage: "calendar"
                    )
                }
                Spacer(minLength: 0)
                if snapshot.phase.keepsScreenAwake {
                    Text("Keep Health.md open")
                }
            }
            .font(.caption2)
            .foregroundStyle(Color.textMuted)
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s2)
        .background(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .fill(Color.bgPrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GeistRadius.md, style: .continuous)
                .strokeBorder(phaseColor.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.Notification.exportActivity)
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

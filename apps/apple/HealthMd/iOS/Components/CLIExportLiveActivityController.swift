#if os(iOS)
import ActivityKit
import Foundation

@MainActor
final class CLIExportLiveActivityController {
    static let shared = CLIExportLiveActivityController()

    private var currentActivity: Activity<CLIExportActivityAttributes>?
    private var pendingUpdateTask: Task<Void, Never>?
    private var pendingUpdateID: UUID?
    private var latestSnapshot: CLIExportActivityTracker.Snapshot?

    func present(_ snapshot: CLIExportActivityTracker.Snapshot) {
        guard !TestMode.isUnitTesting else { return }

        if let currentActivity, currentActivity.attributes.jobID != snapshot.jobID {
            pendingUpdateTask?.cancel()
            pendingUpdateTask = nil
            pendingUpdateID = nil
            self.currentActivity = nil
        }
        latestSnapshot = snapshot

        let state = contentState(for: snapshot)
        let content = ActivityContent(state: state, staleDate: nil)
        let activity = matchingActivity(for: snapshot.jobID)
            ?? requestActivity(for: snapshot, content: content)

        guard let activity else { return }
        if state.isTerminal {
            pendingUpdateTask?.cancel()
            pendingUpdateTask = nil
            pendingUpdateID = nil
            latestSnapshot = nil
            currentActivity = nil
            Task {
                await activity.end(
                    content,
                    dismissalPolicy: .after(Date().addingTimeInterval(15))
                )
            }
        } else {
            currentActivity = activity
            scheduleUpdate(for: activity)
        }
    }

    func dismiss(jobID: UUID) {
        guard !TestMode.isUnitTesting else { return }
        let activities = Activity<CLIExportActivityAttributes>.activities.filter {
            $0.attributes.jobID == jobID
        }
        if currentActivity?.attributes.jobID == jobID {
            pendingUpdateTask?.cancel()
            pendingUpdateTask = nil
            pendingUpdateID = nil
            latestSnapshot = nil
            currentActivity = nil
        }
        for activity in activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Removes a Live Activity left behind by a terminated app process. A
    /// reconnect or durable resume calls `present` again with the same job ID.
    func reconcile(with snapshot: CLIExportActivityTracker.Snapshot?) {
        guard !TestMode.isUnitTesting else { return }
        guard let snapshot else {
            pendingUpdateTask?.cancel()
            pendingUpdateTask = nil
            pendingUpdateID = nil
            latestSnapshot = nil
            currentActivity = nil
            for activity in Activity<CLIExportActivityAttributes>.activities {
                Task {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
            return
        }
        present(snapshot)
    }

    private func scheduleUpdate(
        for activity: Activity<CLIExportActivityAttributes>
    ) {
        guard pendingUpdateTask == nil else { return }
        let updateID = UUID()
        pendingUpdateID = updateID
        pendingUpdateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled,
                  let self,
                  self.pendingUpdateID == updateID,
                  let snapshot = self.latestSnapshot,
                  snapshot.jobID == activity.attributes.jobID,
                  !snapshot.phase.isTerminal else {
                if self?.pendingUpdateID == updateID {
                    self?.pendingUpdateTask = nil
                    self?.pendingUpdateID = nil
                }
                return
            }
            self.pendingUpdateTask = nil
            self.pendingUpdateID = nil
            let content = ActivityContent(
                state: self.contentState(for: snapshot),
                staleDate: nil
            )
            await activity.update(content)
        }
    }

    private func matchingActivity(
        for jobID: UUID
    ) -> Activity<CLIExportActivityAttributes>? {
        if let currentActivity, currentActivity.attributes.jobID == jobID {
            return currentActivity
        }

        let activities = Activity<CLIExportActivityAttributes>.activities
        let matching = activities.first { $0.attributes.jobID == jobID }
        for activity in activities where activity.attributes.jobID != jobID {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        return matching
    }

    private func requestActivity(
        for snapshot: CLIExportActivityTracker.Snapshot,
        content: ActivityContent<CLIExportActivityAttributes.ContentState>
    ) -> Activity<CLIExportActivityAttributes>? {
        guard !snapshot.phase.isTerminal,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        let attributes = CLIExportActivityAttributes(
            jobID: snapshot.jobID,
            sourceLabel: Self.bounded(snapshot.source.label, length: 32),
            targetLabel: Self.bounded(snapshot.targetLabel, length: 48)
        )
        return try? Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil
        )
    }

    private func contentState(
        for snapshot: CLIExportActivityTracker.Snapshot
    ) -> CLIExportActivityAttributes.ContentState {
        CLIExportActivityAttributes.ContentState(
            phase: liveActivityPhase(for: snapshot.phase),
            processedDays: max(snapshot.processedDays, 0),
            totalDays: max(snapshot.totalDays, 0),
            committedPartitions: max(snapshot.committedPartitions, 0),
            committedBytes: max(snapshot.committedBytes, 0),
            message: Self.bounded(snapshot.message, length: 160)
        )
    }

    private func liveActivityPhase(
        for phase: CLIExportActivityTracker.Phase
    ) -> CLIExportActivityAttributes.ContentState.Phase {
        switch phase {
        case .preparing: return .preparing
        case .capturing: return .capturing
        case .transferring: return .transferring
        case .paused: return .paused
        case .completed: return .completed
        case .completedWithWarnings: return .completedWithWarnings
        case .failed: return .failed
        case .cancelled: return .cancelled
        }
    }

    private static func bounded(_ value: String, length: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return String(singleLine.prefix(length))
    }
}
#endif

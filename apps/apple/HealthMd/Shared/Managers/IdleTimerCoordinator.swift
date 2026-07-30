import Foundation

#if os(iOS)
import SwiftUI
import UIKit
#endif

/// Coordinates process-wide idle-timer assertions without letting one activity
/// re-enable sleep while another activity is still running.
@MainActor
final class IdleTimerCoordinator {
    static let shared: IdleTimerCoordinator = {
        #if os(iOS)
        IdleTimerCoordinator { isDisabled in
            UIApplication.shared.isIdleTimerDisabled = isDisabled
        }
        #elseif os(macOS)
        var processActivity: NSObjectProtocol?
        return IdleTimerCoordinator { isDisabled in
            if isDisabled, processActivity == nil {
                processActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
                    reason: "Health.md export in progress"
                )
            } else if !isDisabled, let activity = processActivity {
                ProcessInfo.processInfo.endActivity(activity)
                processActivity = nil
            }
        }
        #else
        IdleTimerCoordinator { _ in }
        #endif
    }()

    private let setIdleTimerDisabled: (Bool) -> Void
    private var activeActivityIDs: Set<UUID> = []
    private(set) var isIdleTimerDisabled = false

    init(setIdleTimerDisabled: @escaping (Bool) -> Void) {
        self.setIdleTimerDisabled = setIdleTimerDisabled
    }

    // Final ownership is sufficient; avoid Swift 6.2+'s crashing isolated-deinit
    // path for synchronous iOS callers (swiftlang/swift#85663).
    nonisolated deinit {}

    func beginActivity(_ activityID: UUID) {
        guard activeActivityIDs.insert(activityID).inserted else { return }
        updateIdleTimer()
    }

    func endActivity(_ activityID: UUID) {
        guard activeActivityIDs.remove(activityID) != nil else { return }
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        let shouldDisable = !activeActivityIDs.isEmpty
        guard shouldDisable != isIdleTimerDisabled else { return }
        isIdleTimerDisabled = shouldDisable
        setIdleTimerDisabled(shouldDisable)
    }
}

#if os(iOS)
private struct KeepScreenAwakeModifier: ViewModifier {
    let isActive: Bool
    @State private var activityID = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                updateActivity(isActive: isActive)
            }
            .onChange(of: isActive) { _, newValue in
                updateActivity(isActive: newValue)
            }
            .onDisappear {
                IdleTimerCoordinator.shared.endActivity(activityID)
            }
    }

    private func updateActivity(isActive: Bool) {
        if isActive {
            IdleTimerCoordinator.shared.beginActivity(activityID)
        } else {
            IdleTimerCoordinator.shared.endActivity(activityID)
        }
    }
}

extension View {
    /// Keeps the display awake while `isActive` without overriding another
    /// in-progress activity that also requires the display.
    func keepsScreenAwake(while isActive: Bool) -> some View {
        modifier(KeepScreenAwakeModifier(isActive: isActive))
    }
}
#endif

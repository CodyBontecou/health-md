#if os(iOS)
import ActivityKit
import Foundation

struct CLIExportActivityAttributes: ActivityAttributes, Hashable {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case preparing
            case capturing
            case transferring
            case paused
            case completed
            case completedWithWarnings
            case failed
            case cancelled
        }

        let phase: Phase
        let processedDays: Int
        let totalDays: Int
        let committedPartitions: Int
        let committedBytes: Int64
        let message: String

        var fractionComplete: Double? {
            if phase == .completed || phase == .completedWithWarnings { return 1 }
            guard totalDays > 0 else { return nil }
            return min(max(Double(processedDays) / Double(totalDays), 0), 1)
        }

        var isTerminal: Bool {
            switch phase {
            case .completed, .completedWithWarnings, .failed, .cancelled: return true
            case .preparing, .capturing, .transferring, .paused: return false
            }
        }
    }

    let jobID: UUID
    let sourceLabel: String
    let targetLabel: String
}
#endif

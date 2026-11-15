import Foundation

/// Static, health-detail-free handoff entry point. Not an export instruction.
/// Never infer an account, destination, date or selection from URL components.
enum CloudRepairLink {
    static let rawValue = "healthmd://cloud/requests"

    static func matches(_ url: URL) -> Bool {
        url.absoluteString == rawValue
    }
}

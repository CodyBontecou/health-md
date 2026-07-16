import Foundation

/// Produces diagnostics safe for unified logging. HealthKit localized descriptions,
/// userInfo, record names, filenames, payload bytes, and URLs are deliberately excluded.
enum HealthKitSafeLogging {
    static func queryFailureDescriptor(objectTypeIdentifier: String, error: NSError) -> String {
        "object_type=\(objectTypeIdentifier) domain=\(error.domain) code=\(error.code)"
    }
}

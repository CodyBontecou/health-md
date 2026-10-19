import XCTest
@testable import HealthMd

@MainActor
func syntheticScheduledAPIDestination(
    url: String = "https://api.example.com/synthetic-exports",
    authorization: String? = "Bearer synthetic-test-credential"
) -> APIExportDestinationSnapshot {
    APIExportDestinationSnapshot(
        endpointURL: URL(string: url)!,
        authorizationHeaderValue: authorization,
        displayName: "Synthetic API",
        redactedEndpointDescription: APIExportSettings.redactedEndpointDescription(for: url)
    )
}

/// Deterministic suspension seam for preparation/checkpoint races; no OS notifications.
@MainActor
final class SuspendingRecoveryNotificationScheduler: ExportNotificationScheduling {
    let base = InspectableExportNotificationScheduler()
    var afterSchedule: ((PendingExportRequest) async throws -> Void)?
    var afterImmediate: ((PendingExportRequest) async throws -> Void)?
    var fallbackDelay: TimeInterval { base.fallbackDelay }

    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {
        try await base.schedulePendingExportNotification(for: request)
        try await afterSchedule?(request)
    }

    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {
        try await base.sendImmediatePendingExportNotification(for: request)
        try await afterImmediate?(request)
    }

    func cancelPendingExportNotification(id: UUID) {
        base.cancelPendingExportNotification(id: id)
    }

    func cancelArmedPendingExportNotification(id: UUID) {
        base.cancelArmedPendingExportNotification(id: id)
    }
}

@MainActor
final class ScheduledAPIEndpointIdentityTests: XCTestCase {
    func testIdentityBindsExactURLCredentialAndProfileBindingWithoutPersistingThem() throws {
        let binding = UUID()
        let destination = syntheticScheduledAPIDestination(url: "https://api.example.com/ingest?private=synthetic")
        let identity = ScheduledAPIEndpointIdentity(destination: destination, bindingID: binding)
        XCTAssertTrue(identity.matches(destination, bindingID: binding))
        XCTAssertFalse(identity.matches(destination, bindingID: UUID()))
        XCTAssertFalse(identity.matches(syntheticScheduledAPIDestination(url: "https://other.example.com/ingest"), bindingID: binding))
        XCTAssertFalse(identity.matches(syntheticScheduledAPIDestination(url: destination.endpointURL.absoluteString, authorization: "Bearer rotated-synthetic"), bindingID: binding))
        let encoded = try JSONEncoder().encode(identity)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains("example.com"))
        XCTAssertFalse(text.contains("synthetic"))
        let decoded = try JSONDecoder().decode(ScheduledAPIEndpointIdentity.self, from: encoded)
        XCTAssertEqual(decoded, identity)
        XCTAssertNotEqual(identity.fingerprint, ScheduledAPIEndpointIdentity(destination: destination, bindingID: binding).fingerprint)
    }
}

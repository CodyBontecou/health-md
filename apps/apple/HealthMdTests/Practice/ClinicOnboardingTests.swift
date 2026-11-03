import XCTest
@testable import HealthMd

@MainActor
final class ClinicOnboardingTests: XCTestCase {
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testAcceptAddsSeparateFullProfileAndDisabledSchedule() throws {
        let suite = "clinic-synthetic-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let snapshot = ExportSettingsSnapshot.from(settings, calendarTimeZoneIdentifier: "Etc/UTC")
        let profiles = ExportProfileStore(userDefaults: defaults)
        let existing = profiles.add(name: "Existing synthetic profile", settings: snapshot, target: .localIPhoneFolder)
        let schedules = ScheduledExportEntryStore(userDefaults: defaults)
        let endpointID = UUID()
        let endpoint = APIExportDestinationSnapshot(endpointURL: try XCTUnwrap(URL(string: "https://practice.invalid/synthetic")),
            authorizationHeaderValue: "synthetic", displayName: "Synthetic", redactedEndpointDescription: "Synthetic")
        let onboarding = ClinicNativeOnboarding(profiles: profiles, schedules: schedules, store: try ClinicPrivateStore(root: root),
            destination: { $0 == endpointID ? endpoint : nil }, enabled: { true })
        let review = ClinicSetupReview(clinicID: "clinic_synthetic", clinicName: "Synthetic clinic", setupID: "setup_synthetic", subjectID: "subject_synthetic", deviceID: "device_synthetic",
            connectionID: "connection_synthetic", revision: "revision_synthetic", name: "Clinic synthetic profile",
            settings: snapshot, endpointID: endpointID, weekly: false, hour: 12, expiresAt: Date().addingTimeInterval(300))
        let digest = try onboarding.preview(review)
        XCTAssertEqual(profiles.profiles.count, 1)
        XCTAssertThrowsError(try onboarding.accept(digest: "wrong", authorize: { _ in }))
        let approval = try onboarding.accept(digest: digest, authorize: { _ in })
        XCTAssertEqual(profiles.profiles.count, 2)
        XCTAssertEqual(profiles.activeProfileID, existing.id)
        XCTAssertEqual(profiles.profiles.first(where: { $0.id == approval.profileID })?.settings, snapshot)
        XCTAssertEqual(schedules.entry(profileID: approval.profileID)?.isEnabled, false)
        XCTAssertEqual(schedules.entry(profileID: approval.profileID)?.preferredHour, 12)
    }

    func testDestinationCredentialRotationInvalidatesReviewedSetup() throws {
        let suite = "clinic-synthetic-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = AdvancedExportSettings(userDefaults: defaults); Self.retainedSettings.append(settings)
        let profiles = ExportProfileStore(userDefaults: defaults)
        let endpointID = UUID(); var rotated = false
        let onboarding = ClinicNativeOnboarding(profiles: profiles, schedules: ScheduledExportEntryStore(userDefaults: defaults),
            store: try ClinicPrivateStore(root: root), destination: { _ in
                APIExportDestinationSnapshot(endpointURL: URL(string: "https://practice.invalid/synthetic")!,
                    authorizationHeaderValue: rotated ? "rotated_synthetic" : "synthetic", displayName: "Synthetic", redactedEndpointDescription: "Synthetic")
            }, enabled: { true })
        let digest = try onboarding.preview(ClinicSetupReview(clinicID: "clinic_synthetic", clinicName: "Synthetic clinic", setupID: "setup_synthetic", subjectID: "subject_synthetic", deviceID: "device_synthetic",
            connectionID: "connection_synthetic", revision: "revision_synthetic", name: "Synthetic", settings: .from(settings, calendarTimeZoneIdentifier: "Etc/UTC"),
            endpointID: endpointID, weekly: true, hour: 9, expiresAt: Date().addingTimeInterval(300)))
        rotated = true
        XCTAssertThrowsError(try onboarding.accept(digest: digest, authorize: { _ in }))
        XCTAssertTrue(profiles.profiles.isEmpty)
    }
}

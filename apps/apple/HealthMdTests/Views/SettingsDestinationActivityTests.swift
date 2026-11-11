import XCTest
@testable import HealthMd

@MainActor
final class SettingsDestinationActivityTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(
        at offset: TimeInterval,
        target: ExportTargetSelection?,
        success: Bool = true,
        source: ExportSource = .manual,
        operation: ExportHistoryOperationDetails.Kind? = nil
    ) -> ExportHistoryEntry {
        ExportHistoryEntry(
            timestamp: base.addingTimeInterval(offset),
            source: source,
            success: success,
            dateRangeStart: base,
            dateRangeEnd: base,
            successCount: 1,
            totalCount: 1,
            exportTarget: target,
            operationDetails: operation.map {
                ExportHistoryOperationDetails(
                    kind: $0,
                    requestID: UUID(),
                    dateSelection: "exact_range",
                    settingsPolicy: "requested_dates_only",
                    failedDayCount: 0
                )
            }
        )
    }

    func testLastSuccessMatchesTargetAndIgnoresFailures() {
        let history = [
            entry(at: 10, target: .apiEndpoint),
            entry(at: 30, target: .apiEndpoint, success: false),
            entry(at: 20, target: .localIPhoneFolder),
        ]
        XCTAssertEqual(
            SettingsDestinationActivity.lastSuccess(to: .apiEndpoint, in: history),
            base.addingTimeInterval(10)
        )
        XCTAssertNil(SettingsDestinationActivity.lastSuccess(to: .agentDataGateway, in: history))
    }

    func testUntargetedLegacyEntriesCountAsFolderWritesExceptMacAgentRuns() {
        let history = [
            entry(at: 5, target: nil),
            entry(at: 50, target: nil, source: .macAgent),
        ]
        XCTAssertEqual(
            SettingsDestinationActivity.lastSuccess(to: .localIPhoneFolder, in: history),
            base.addingTimeInterval(5)
        )
        XCTAssertNil(SettingsDestinationActivity.lastSuccess(to: .connectedMac, in: history))
    }

    func testLastDirectCLIRequestIgnoresGatewayAccounting() {
        let history = [
            entry(at: 10, target: .localIPhoneFolder, operation: .rawExport),
            entry(at: 40, target: .agentDataGateway, operation: .agentDataGatewayUpload),
            entry(at: 60, target: .localIPhoneFolder),
        ]
        XCTAssertEqual(
            SettingsDestinationActivity.lastDirectCLIRequest(in: history),
            base.addingTimeInterval(10)
        )
    }

    func testProfilesUsingDefaultFolderMatchNilOrSamePath() {
        let settings = ExportSettingsSnapshot.from(AdvancedExportSettings(userDefaults: isolatedDefaults()))
        let same = SavedVaultDestination(name: "Vault", standardizedPath: "/vault", bookmarkData: Data([1]))
        let other = SavedVaultDestination(name: "Other", standardizedPath: "/other", bookmarkData: Data([2]))
        let profiles = [
            ExportProfile(name: "Daily", settings: settings, target: .localIPhoneFolder),
            ExportProfile(name: "Bound", settings: settings, target: .localIPhoneFolder, folderVaultID: same.id),
            ExportProfile(name: "Elsewhere", settings: settings, target: .localIPhoneFolder, folderVaultID: other.id),
            ExportProfile(name: "API", settings: settings, target: .apiEndpoint),
        ]
        XCTAssertEqual(
            SettingsDestinationActivity.profilesUsingDefaultFolder(
                profiles: profiles,
                savedFolders: [same, other],
                defaultFolderPath: "/vault"
            ),
            ["Daily", "Bound"]
        )
    }

    func testHTTPStatusText() {
        XCTAssertEqual(SettingsDestinationActivity.httpStatusText(200), "200 OK")
        XCTAssertEqual(SettingsDestinationActivity.httpStatusText(405), "405 Method Not Allowed")
        XCTAssertEqual(SettingsDestinationActivity.httpStatusText(599), "HTTP 599")
    }

    func testRelativeDayTextUsesCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale = Locale(identifier: "en_US")
        let now = base
        XCTAssertEqual(
            SettingsDestinationActivity.relativeDayText(now.addingTimeInterval(-60), now: now, calendar: calendar, locale: locale),
            "today"
        )
        XCTAssertEqual(
            SettingsDestinationActivity.relativeDayText(now.addingTimeInterval(-86_400), now: now, calendar: calendar, locale: locale),
            "yesterday"
        )
    }

    func testAuthorizationHeaderMatchesAPIExportSettings() {
        XCTAssertNil(APIEndpointConnectionTester.authorizationHeaderValue(for: "  "))
        XCTAssertEqual(APIEndpointConnectionTester.authorizationHeaderValue(for: "abc"), "Bearer abc")
        XCTAssertEqual(APIEndpointConnectionTester.authorizationHeaderValue(for: "Basic xyz"), "Basic xyz")
    }

    func testDestinationNamesTrimAndClear() {
        let names = DestinationNameStore(defaults: isolatedDefaults())
        names.apiEndpointName = "  Agent feed "
        XCTAssertEqual(names.apiEndpointName, "Agent feed")
        names.apiEndpointName = ""
        XCTAssertEqual(names.apiEndpointName, "")
        XCTAssertNil(names.defaults.object(forKey: DestinationNameStore.apiEndpointKey))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SettingsDestinationActivityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}

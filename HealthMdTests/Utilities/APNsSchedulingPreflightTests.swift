//
//  APNsSchedulingPreflightTests.swift
//  HealthMdTests
//
//  Repo-level release guard for ISO-154. These tests validate the
//  production APNs + scheduled export contract that must hold before
//  submitting Health.md to App Store Connect.
//

import Foundation
import XCTest

final class APNsSchedulingPreflightTests: XCTestCase {

    private static let projectRoot: URL = {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // Utilities/
            .deletingLastPathComponent()  // HealthMdTests/
            .deletingLastPathComponent()  // app/
    }()

    func testProductionAPNsEntitlementIsConfiguredForIOSRelease() throws {
        let entitlements = try plistDictionary("HealthMd/HealthMd.entitlements")

        XCTAssertEqual(
            entitlements["aps-environment"] as? String,
            "production",
            "HealthMd/HealthMd.entitlements must use production APNs before release; sandbox/development tokens break server-driven scheduled exports."
        )
    }

    func testSilentPushAndBackgroundTaskInfoPlistConfiguration() throws {
        let info = try plistDictionary("HealthMd/Info.plist")
        let backgroundModes = try XCTUnwrap(
            info["UIBackgroundModes"] as? [String],
            "HealthMd/Info.plist must define UIBackgroundModes for silent push delivery."
        )
        XCTAssertTrue(
            backgroundModes.contains("remote-notification"),
            "UIBackgroundModes must include remote-notification so scheduled export APNs payloads can wake the app."
        )

        let permittedIdentifiers = try XCTUnwrap(
            info["BGTaskSchedulerPermittedIdentifiers"] as? [String],
            "HealthMd/Info.plist must list BGTaskSchedulerPermittedIdentifiers."
        )
        let schedulingSource = try source("HealthMd/iOS/SchedulingManager.swift")
        let identifier = try capture(
            in: schedulingSource,
            pattern: #"static\s+let\s+backgroundTaskIdentifier\s*=\s*"([^"]+)""#,
            description: "SchedulingManager.backgroundTaskIdentifier"
        )
        XCTAssertTrue(
            permittedIdentifiers.contains(identifier),
            "BGTaskSchedulerPermittedIdentifiers must include SchedulingManager.backgroundTaskIdentifier (\(identifier))."
        )
    }

    func testSchedulingManagerMirrorsEnabledSchedulesToAPNsBridge() throws {
        let schedulingSource = try source("HealthMd/iOS/SchedulingManager.swift")

        try assertSource(
            schedulingSource,
            relativePath: "HealthMd/iOS/SchedulingManager.swift",
            contains: [
                "await PushRegistrationManager.shared.registerForRemoteNotificationsIfNeeded()",
                "PushRegistrationManager.shared.syncSchedule(schedule)",
            ]
        )
    }

    func testAppDelegateForwardsAPNsTokenAndSilentScheduledExportPushes() throws {
        let appDelegateSource = try source("HealthMd/iOS/HealthMdApp.swift")

        try assertSource(
            appDelegateSource,
            relativePath: "HealthMd/iOS/HealthMdApp.swift",
            contains: [
                "didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data",
                "PushRegistrationManager.shared.submitDeviceToken(deviceToken)",
                "didReceiveRemoteNotification userInfo: [AnyHashable: Any]",
                "fetchCompletionHandler completionHandler",
                "userInfo[\"type\"] as? String == \"scheduled-export\"",
                "performSilentPushExport(fireDate: fireDate)",
            ]
        )
    }

    func testPushRegistrationBridgeKeepsWorkerRegistrationAndScheduleContract() throws {
        let pushRegistrationSource = try source("HealthMd/Shared/Managers/PushRegistrationManager.swift")

        try assertSource(
            pushRegistrationSource,
            relativePath: "HealthMd/Shared/Managers/PushRegistrationManager.swift",
            contains: [
                "URL(string: \"https://healthmd-receipt-verifier.costream.workers.dev\")",
                "postJSON(path: \"/devices/register\", body: body, label: \"register\")",
                "postJSON(path: \"/schedules/upsert\", body: body, label: \"schedule\")",
                "let userId: String",
                "let platform: String",
                "let apnsToken: String",
                "let bundleId: String",
                "let timezone: String",
                "let isEnabled: Bool",
                "let frequency: String",
                "let hour: Int",
                "let minute: Int",
                "let weekday: Int?",
                "return \"daily\"",
                "return \"weekly\"",
            ]
        )
    }

    func testReleasePreflightScriptDocsAndWorkflowWiringExist() throws {
        let scriptURL = projectFile("scripts/check-apns-scheduling-preflight.sh")
        XCTAssertTrue(
            FileManager.default.isExecutableFile(atPath: scriptURL.path),
            "scripts/check-apns-scheduling-preflight.sh must exist and be executable so release jobs can fail fast."
        )

        let docs = try source("docs/testing/apns-scheduling-preflight.md")
        try assertSource(
            docs,
            relativePath: "docs/testing/apns-scheduling-preflight.md",
            contains: [
                "scripts/check-apns-scheduling-preflight.sh",
                "HealthMd/HealthMd.entitlements",
                "remote-notification",
                "PushRegistrationManager",
            ]
        )

        let releaseWorkflow = try source(".github/workflows/release-ios.yml")
        let preflightRange = try XCTUnwrap(
            releaseWorkflow.range(of: "scripts/check-apns-scheduling-preflight.sh"),
            "release-ios.yml must run the APNs scheduling preflight."
        )
        let ascSubmitRange = try XCTUnwrap(
            releaseWorkflow.range(of: "asc review submissions-submit"),
            "release-ios.yml must still contain the App Store review submission step."
        )
        XCTAssertLessThan(
            preflightRange.lowerBound,
            ascSubmitRange.lowerBound,
            "APNs scheduling preflight must run before App Store submission."
        )
    }

    private func projectFile(_ relativePath: String) -> URL {
        Self.projectRoot.appendingPathComponent(relativePath)
    }

    private func plistDictionary(_ relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: projectFile(relativePath))
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try XCTUnwrap(object as? [String: Any], "\(relativePath) must be a plist dictionary.")
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: projectFile(relativePath), encoding: .utf8)
    }

    private func capture(in source: String, pattern: String, description: String) throws -> String {
        let regex = try NSRegularExpression(pattern: pattern)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let match = try XCTUnwrap(
            regex.firstMatch(in: source, range: fullRange),
            "Expected to find \(description) in source."
        )
        let captureRange = try XCTUnwrap(
            Range(match.range(at: 1), in: source),
            "Expected to capture \(description) from source."
        )
        return String(source[captureRange])
    }

    private func assertSource(_ source: String, relativePath: String, contains snippets: [String]) throws {
        for snippet in snippets {
            XCTAssertTrue(
                source.contains(snippet),
                "\(relativePath) must contain required APNs scheduling preflight snippet: \(snippet)"
            )
        }
    }
}

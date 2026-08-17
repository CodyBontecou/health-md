import CryptoKit
import Foundation
import HealthMdCoreRust
import XCTest
@testable import HealthMd

@MainActor
final class HealthMdSemanticInputAdapterTests: XCTestCase {
    func testExactTimestampPreservesNanosecondsNullableOffsetAndNegativeEpoch() throws {
        let kathmandu = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        let timestamp = try HealthMdSemanticInputAdapter.exactTimestamp(
            Date(timeIntervalSince1970: -0.25),
            sourceUTCOffsetSeconds: nil,
            calendarTimeZone: kathmandu
        )
        let negativeZero = try HealthMdSemanticInputAdapter.binary64(-0.0, unitID: "ratio_0_1")

        XCTAssertEqual(timestamp["epoch_seconds"] as? String, "-1")
        XCTAssertEqual(timestamp["nanoseconds"] as? Int, 750_000_000)
        XCTAssertTrue(timestamp["source_utc_offset_seconds"] is NSNull)
        XCTAssertEqual(timestamp["calendar_utc_offset_seconds"] as? Int, 19_800)
        let number = try XCTUnwrap(negativeZero["number"] as? [String: Any])
        XCTAssertEqual(number["bits"] as? String, "8000000000000000")
        XCTAssertThrowsError(
            try HealthMdSemanticInputAdapter.exactTimestamp(
                Date(timeIntervalSince1970: 9_223_372_036_854_775_808.0),
                calendarTimeZone: kathmandu
            )
        )
    }

    func testCapturedHealthDataProcessesThroughOnePackagedRustSession() throws {
        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let selection = MetricSelectionState()
        selection.enabledMetrics = ["blood_oxygen", "body_fat", "sleep_bedtime"]
        for invalidTimeZone in ["not/an-iana-zone", "+05:00"] {
            XCTAssertThrowsError(try HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionID: "bad-timezone",
                selection: selection,
                registry: registry,
                customization: FormatCustomization(),
                calendarTimeZoneIdentifier: invalidTimeZone,
                retainPlatformExtensions: false,
                rollupPeriods: []
            ))
        }
        let customization = FormatCustomization()
        customization.timeFormat = .hour12WithSeconds
        let configuration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: "apple-adapter-test",
            selection: selection,
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York",
            retainPlatformExtensions: true,
            rollupPeriods: [.range]
        )
        var data = HealthData(
            date: Date(timeIntervalSince1970: 1_767_225_600),
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "America/New_York")
        )
        data.sleep.sessionStart = data.date.addingTimeInterval(3_600)
        data.vitals.bloodOxygenAvg = 0.975
        data.vitals.bloodPressureSystolicAvg = 120
        data.vitals.bloodPressureDiastolicAvg = 80
        data.body.bodyFatPercentage = 0.2
        data.healthKitRecordArchive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2025-12-31",
                intervalStart: Date(timeIntervalSince1970: 1_767_225_600),
                intervalEnd: Date(timeIntervalSince1970: 1_767_312_000),
                calendarTimeZoneIdentifier: "America/New_York"
            ),
            externalRecords: [
                HealthKitExternalRecord(
                    externalIdentifier: "stable-native-healthkit-identity",
                    externalIdentityKind: .characteristicSingleton,
                    objectTypeIdentifier: "synthetic.test.record",
                    recordKind: .characteristic,
                    selectedMetricIDs: ["blood_oxygen"],
                    fields: [:]
                ),
            ]
        )
        let encoded = try HealthMdSemanticInputAdapter.batch(
            sessionID: "apple-adapter-test",
            batchIndex: 0,
            finalBatch: true,
            healthData: [data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York"
        )
        var nextDayData = HealthData(
            date: data.date.addingTimeInterval(86_400),
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "America/New_York")
        )
        nextDayData.sleep = data.sleep
        nextDayData.vitals = data.vitals
        nextDayData.body = data.body
        nextDayData.healthKitRecordArchive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-01-01",
                intervalStart: Date(timeIntervalSince1970: 1_767_312_000),
                intervalEnd: Date(timeIntervalSince1970: 1_767_398_400),
                calendarTimeZoneIdentifier: "America/New_York"
            ),
            externalRecords: data.healthKitRecordArchive?.externalRecords ?? []
        )
        let multiDay = try HealthMdSemanticInputAdapter.batch(
            sessionID: "multi-day-identity",
            batchIndex: 0,
            finalBatch: true,
            healthData: [data, nextDayData],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York"
        )
        XCTAssertEqual(multiDay.retainedExtensionTokens.count, 2)
        XCTAssertEqual(Set(multiDay.retainedExtensionTokens).count, 2)
        let incrementallyBounded = try HealthMdSemanticInputAdapter.boundedBatches(
            sessionID: "multi-day-identity",
            healthData: [nextDayData, data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York"
        )
        let boundedLocations: [String: HealthMdSemanticInputAdapter.ExtensionLocation] =
            incrementallyBounded.reduce(into: [:]) {
            $0.merge($1.extensionLocations) { first, _ in first }
        }
        XCTAssertEqual(Set(boundedLocations.keys), Set(multiDay.extensionLocations.keys))
        for (token, originalLocation) in multiDay.extensionLocations {
            XCTAssertEqual(boundedLocations[token]?.dayIndex, 1 - originalLocation.dayIndex)
            XCTAssertEqual(boundedLocations[token]?.collection, originalLocation.collection)
            XCTAssertEqual(boundedLocations[token]?.recordIndex, originalLocation.recordIndex)
        }
        XCTAssertThrowsError(try HealthMdSemanticInputAdapter.batch(
            sessionID: "ordinal-overflow",
            batchIndex: 0,
            finalBatch: true,
            healthData: [data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York",
            startingSourceOrdinal: .max
        ))
        let rechunked = try HealthMdSemanticInputAdapter.batch(
            sessionID: "apple-adapter-rechunked",
            batchIndex: 7,
            finalBatch: true,
            healthData: [data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York"
        )
        let bounded = try HealthMdSemanticInputAdapter.boundedBatches(
            sessionID: "apple-adapter-bounded",
            healthData: [data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "America/New_York"
        )
        XCTAssertEqual(bounded.count, 1)
        XCTAssertLessThanOrEqual(bounded[0].data.count, 1_048_576)
        let originalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded.data) as? [String: Any]
        )
        let rechunkedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: rechunked.data) as? [String: Any]
        )
        let originalIDs = (originalObject["records"] as? [[String: Any]])?.compactMap {
            $0["record_id"] as? String
        }
        let originalRecords = originalObject["records"] as? [[String: Any]]
        let rechunkedIDs = (rechunkedObject["records"] as? [[String: Any]])?.compactMap {
            $0["record_id"] as? String
        }
        XCTAssertEqual(originalIDs, rechunkedIDs)
        let bloodPressureRecords = originalRecords?.filter {
            (($0["output_key"] as? String) ?? "").contains("blood_pressure")
        }
        XCTAssertGreaterThanOrEqual(bloodPressureRecords?.count ?? 0, 2)
        XCTAssertTrue(bloodPressureRecords?.allSatisfy {
            ($0["selection_ids"] as? [String])?.count == 2
        } == true)
        XCTAssertEqual(encoded.retainedExtensionTokens.count, 1)
        XCTAssertEqual(encoded.retainedExtensionTokens, rechunked.retainedExtensionTokens)

        let session = try service.semanticSession(configuration: configuration)
        let result = try session.process(batch: encoded.data)
        let text = try XCTUnwrap(String(data: result, encoding: .utf8))

        XCTAssertTrue(text.contains("\"state\":\"completed\""))
        XCTAssertTrue(text.contains("\"blood_oxygen\""))
        XCTAssertTrue(text.contains("\"body_fat_percent\""))
        XCTAssertTrue(text.contains("\"time_of_day_minute\""))
        XCTAssertTrue(text.contains("apple.healthkit_archive"))
        XCTAssertFalse(text.contains("\"steps\""))

        let disabledCustomization = FormatCustomization()
        if let index = disabledCustomization.frontmatterConfig.fields.firstIndex(where: {
            $0.originalKey == "body_fat_percent"
        }) {
            disabledCustomization.frontmatterConfig.fields[index].isEnabled = false
        }
        let disabledConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: "apple-adapter-test",
            selection: selection,
            registry: registry,
            customization: disabledCustomization,
            calendarTimeZoneIdentifier: "America/New_York",
            retainPlatformExtensions: false,
            rollupPeriods: [.range]
        )
        let disabledSession = try service.semanticSession(configuration: disabledConfiguration)
        let disabledResult = try disabledSession.process(batch: encoded.data)
        let disabledText = String(decoding: disabledResult, as: UTF8.self)
        XCTAssertFalse(disabledText.contains("\"body_fat_percent\""))
        XCTAssertFalse(disabledText.contains("apple.healthkit_archive"))
    }

    func testSharedDifferentialFixtureMatchesExactResultHashes() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("packages/contracts/semantic-input/v1/fixtures/differential-v1.json")
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        let cases = try XCTUnwrap(object["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 3)

        for fixtureCase in cases {
            let configuration = try HealthMdSemanticInputAdapter.canonicalJSON(
                try XCTUnwrap(fixtureCase["config"])
            )
            let batches = try XCTUnwrap(fixtureCase["batches"] as? [Any])
            let expected = try XCTUnwrap(fixtureCase["expected_result_sha256"] as? String)
            let session = try HealthMdCoreService().semanticSession(configuration: configuration)
            var result = Data()
            for batch in batches {
                result = try session.process(batch: HealthMdSemanticInputAdapter.canonicalJSON(batch))
            }
            XCTAssertEqual(
                SHA256.hash(data: result).map { String(format: "%02x", $0) }.joined(),
                expected,
                fixtureCase["id"] as? String ?? "semantic fixture"
            )
        }
    }

    func testSessionCancellationAndShadowDifferencesAreHealthFree() throws {
        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let selection = MetricSelectionState()
        selection.enabledMetrics = ["steps"]
        let configuration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: "apple-cancel-test",
            selection: selection,
            registry: registry,
            customization: FormatCustomization(),
            calendarTimeZoneIdentifier: "UTC",
            retainPlatformExtensions: false,
            rollupPeriods: []
        )
        let session = try service.semanticSession(configuration: configuration)
        session.cancel()
        let cancelled = try session.process(batch: Data("private-health-value".utf8))
        XCTAssertTrue(String(decoding: cancelled, as: UTF8.self).contains("\"state\":\"cancelled\""))
        XCTAssertThrowsError(try session.process(batch: Data("{}".utf8))) { error in
            XCTAssertEqual(error as? HealthMdCoreServiceError, .semanticSessionTerminal)
        }

        let paths = HealthMdSemanticShadowComparator.differences(
            legacy: Data("{\"days\":[{\"value\":1}]}".utf8),
            rust: Data("{\"days\":[{\"value\":2}]}".utf8)
        )
        XCTAssertEqual(paths, ["/days/0/value"])
        XCTAssertFalse(paths.joined().contains("private-health-value"))
    }
}

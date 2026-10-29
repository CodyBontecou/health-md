import Foundation
import HealthMdCoreRust
import XCTest
@testable import HealthMd

@MainActor
final class APIEndpointExportEngineTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation state that
    // is unsafe during test teardown on some macOS runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testDenseBloodPressurePairsStayOutsideAPIHandoffWithoutFabricatingSummaries() async throws {
        let zone = TimeZone.gmt
        let date = try XCTUnwrap(days(count: 1).first)
        let samples = (0..<2_000).map { index in BloodPressureSample(
            correlationUUID: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)),
            systolic: 120.125.nextUp, diastolic: 80.875.nextDown,
            startDate: date.addingTimeInterval(Double(index) + 0.125), endDate: date.addingTimeInterval(Double(index) + (index == 0 ? 0.125 : 0.875)),
            sourceRevision: HealthKitSourceRevision(name: "Synthetic cuff", bundleIdentifier: "example.synthetic.bp"),
            device: HealthKitDeviceProvenance(model: "Synthetic"), metadata: ["synthetic": "api-pair-\(index)"]) }
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 0), vitals: VitalsData(bloodPressureSamples: samples))
        let expected = try XCTUnwrap((try JSONSerialization.jsonObject(with: day.toJSONDataThrowing(captureContext: context)) as? [String: Any])?["vitals"] as? [String: Any])
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .detailedTimeSeries
        settings.metricSelection.enabledMetrics = ["blood_pressure_systolic", "blood_pressure_diastolic"]
        let resolution = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false, fetchHealthData: { _, _, _ in day },
            coreExecutor: APIRecordingCoreExecutor(events: APIEngineEventRecorder(), requireAggregateOnlyConfiguration: true))
        guard case .prepared(let operation) = resolution else { return XCTFail("Expected native paired-record composition") }
        let batch = try XCTUnwrap(operation.batches.first)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        let vitals = try XCTUnwrap(record["vitals"] as? [String: Any])
        XCTAssertEqual(vitals["bloodPressureSamples"] as? NSArray, expected["bloodPressureSamples"] as? NSArray)
        XCTAssertEqual((vitals["bloodPressureSamples"] as? NSArray)?.count, 2_000)
        XCTAssertNil(vitals["bloodPressureSystolic"])
        XCTAssertNil(vitals["bloodPressureDiastolic"])
        try batch.bodyArtifact.validateIntegrity()
        let index = try XCTUnwrap(settings.formatCustomization.frontmatterConfig.fields.firstIndex { $0.originalKey == "blood_pressure_systolic" })
        settings.formatCustomization.frontmatterConfig.fields[index].isEnabled = false
        do {
            _ = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false, fetchHealthData: { _, _, _ in day })
            XCTFail("API composition must not bypass disabled paired-output authority")
        } catch { XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .rustPlanningFailed) }
        settings.metricSelection.enabledMetrics = ["steps"]
        let filtered = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false, fetchHealthData: { _, _, _ in day })
        guard case .prepared(let filteredOperation) = filtered else { return XCTFail("Unselected paired source must not block API steps") }
        XCTAssertEqual(filteredOperation.batches.count, 1)
        for batch in filteredOperation.batches {
            XCTAssertFalse(String(decoding: batch.body, as: UTF8.self).contains("bloodPressureSamples"))
        }


    }

    func testDenseSleepStagesRemainOutsideAPIRenderInputAndKeepOriginalSessionClocks() async throws {
        let zone = TimeZone.gmt
        let date = try XCTUnwrap(days(count: 1).first)
        let start = date.addingTimeInterval(-3600 + 0.125), end = start.addingTimeInterval(30_000)
        let stages = (0..<2_000).map { index in SleepStageSample(stage: "core",
            startDate: start.addingTimeInterval(Double(index) * 15), endDate: start.addingTimeInterval(Double(index + 1) * 15),
            metadata: ["synthetic": "api-stage-\(index)"]) }
        let day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: 30_000, coreSleep: 30_000, sessionStart: start, sessionEnd: end, stages: stages))
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .detailedTimeSeries
        settings.metricSelection.enabledMetrics = ["sleep_total", "sleep_core", "sleep_bedtime", "sleep_wake"]
        let resolution = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false, fetchHealthData: { _, _, _ in day },
            coreExecutor: APIRecordingCoreExecutor(events: APIEngineEventRecorder(), requireAggregateOnlyConfiguration: true))
        guard case .prepared(let operation) = resolution else { return XCTFail("Expected file-backed stage composition") }
        let batch = try XCTUnwrap(operation.batches.first)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        let sleep = try XCTUnwrap(record["sleep"] as? [String: Any])
        let values = try XCTUnwrap(sleep["sleepStages"] as? [[String: Any]])
        XCTAssertEqual(values.count, 2_000)
        XCTAssertEqual(values.first?["startDate"] as? String, CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: start))
        XCTAssertEqual(values.last?["endDate"] as? String, CanonicalRFC3339UTC.stringPreservingReferencePrecision(from: end))
        XCTAssertEqual((values.last?["metadata"] as? [String: String])?["synthetic"], "api-stage-1999")
        try batch.bodyArtifact.validateIntegrity()
    }

    func testDenseSelectedQuantityOnlyDayKeepsAllFiveFamiliesOutsideAPICoreInput() async throws {
        let zone = TimeZone.gmt
        let date = try XCTUnwrap(days(count: 1).first)
        func samples(_ value: Double) -> [TimeSample] {
            (0..<2_000).map { TimeSample(timestamp: date.addingTimeInterval(Double($0) + 0.125),
                value: value, metadata: ["synthetic": "quantity-\($0)"]) }
        }
        var day = HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
        day.heart.heartRateSamples = samples(72.125.nextUp)
        day.heart.hrvSamples = samples(31.875.nextUp)
        day.vitals.bloodOxygenSamples = samples(0.97125.nextUp)
        day.vitals.bloodGlucoseSamples = samples(101.875.nextUp)
        day.vitals.respiratoryRateSamples = samples(16.125.nextUp)
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .detailedTimeSeries
        settings.metricSelection.enabledMetrics = ["heart_rate_avg", "hrv", "blood_oxygen", "blood_glucose", "respiratory_rate"]
        let resolution = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false,
            fetchHealthData: { _, _, _ in day },
            coreExecutor: APIRecordingCoreExecutor(events: APIEngineEventRecorder(), requireAggregateOnlyConfiguration: true))
        guard case .prepared(let operation) = resolution else { return XCTFail("Expected dense native quantities") }
        let batch = try XCTUnwrap(operation.batches.first)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        XCTAssertTrue((record["summary"] as? [String: Any])?.isEmpty == true)
        for (category, field, value) in [("heart", "heartRateSamples", 72.125.nextUp), ("heart", "hrvSamples", 31.875.nextUp),
            ("vitals", "bloodOxygenSamples", 0.97125.nextUp), ("vitals", "bloodGlucoseSamples", 101.875.nextUp),
            ("vitals", "respiratoryRateSamples", 16.125.nextUp)] {
            let values = try XCTUnwrap((record[category] as? [String: Any])?[field] as? [[String: Any]])
            XCTAssertEqual(values.count, 2_000)
            XCTAssertEqual((values.last?["value"] as? Double)?.bitPattern, value.bitPattern)
            XCTAssertEqual((values.last?["metadata"] as? [String: String])?["synthetic"], "quantity-1999")
        }
        try batch.bodyArtifact.validateIntegrity()
    }

    func testNativeConnectedSourcesRejectWrongDateOrUnknownSchemaBeforePreparing() async throws {
        let zone = TimeZone.gmt
        let date = try XCTUnwrap(days(count: 1).first)
        for invalid in ["owner", "date", "schema", "version"] {
            var external = ExternalDailyRecord(provider: .oura,
                date: APIExportClient.dayString(from: date, timeZone: zone), payloads: [
                    ExternalProviderPayload(name: "synthetic", endpoint: "https://synthetic.invalid/source", statusCode: 200,
                        data: .object(["records": .array([.object(["id": .number(1)])])]))
                ])
            switch invalid {
            case "owner": external.date = "1900-01-01"
            case "date": external.date = "2026-02-30"
            case "schema": external.schema = "unknown.source"
            default: external.schemaVersion = 999
            }
            let settings = makeSettings()
            settings.exportTimeZoneOverride = zone
            settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
            settings.executionSleepCaptureContextIsFrozen = true
            settings.metricSelection.enabledMetrics = ["steps"]
            do {
                _ = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
                    destination: destination, calendarTimeZone: zone, connectedAppsEnabled: true,
                    fetchHealthData: { date, _, _ in HealthData(date: date,
                        timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                        activity: ActivityData(steps: 42)) }, fetchExternalDailyRecords: { _ in [external] })
                XCTFail("Unbound native source must reject: \(invalid)")
            } catch {
                XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .invalidPreparedPlan)
            }
        }
    }

    func testLargeConnectedProviderSourceFactsReachFinalBodyWithoutEnteringCoreConfiguration() async throws {
        let zone = TimeZone.gmt
        let date = try XCTUnwrap(days(count: 1).first)
        let padding = String(repeating: "synthetic-source-", count: 600_000)
        for provider in [ExternalIntegrationProvider.whoop, .oura] {
            let external = ExternalDailyRecord(provider: provider,
                date: APIExportClient.dayString(from: date, timeZone: zone), payloads: [
                    ExternalProviderPayload(name: "cycles", endpoint: "https://synthetic.invalid/cycles", statusCode: 200,
                        data: .object(["records": .array([.object(["id": .string("synthetic-cycle"),
                            "start": .string("2026-07-01T00:00:00Z"),
                            "score": .object(["strain": .number(12.875.nextUp)])])]),
                            "synthetic_source": .string(padding)]))
                ])
            let settings = makeSettings()
            settings.exportTimeZoneOverride = zone
            settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
            settings.executionSleepCaptureContextIsFrozen = true
            settings.detailPolicy = .summary
            settings.metricSelection.enabledMetrics = ["steps"]
            let events = APIEngineEventRecorder()
            let resolution = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: true,
                fetchHealthData: { date, _, _ in HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                    activity: ActivityData(steps: 42)) }, fetchExternalDailyRecords: { _ in [external] },
                coreExecutor: APIRecordingCoreExecutor(events: events, requireAggregateOnlyConfiguration: true))
            guard case .prepared(let operation) = resolution else { return XCTFail("Expected native connected source composition") }
            XCTAssertEqual(operation.batches.count, 1)
            let batch = try XCTUnwrap(operation.batches.first)
            XCTAssertGreaterThan(batch.bodyByteCount, UInt64(APIEndpointExportRunner.defaultMaxBatchPayloadBytes))
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
            XCTAssertEqual(root["external_record_count"] as? Int, 1)
            let sidecar = try XCTUnwrap((root["external_records"] as? [[String: Any]])?.first)
            let payload = try XCTUnwrap((sidecar["payloads"] as? [[String: Any]])?.first)
            let source = try XCTUnwrap(payload["data"] as? [String: Any])
            XCTAssertEqual(source["synthetic_source"] as? String, padding)
            let cycle = try XCTUnwrap((source["records"] as? [[String: Any]])?.first)
            XCTAssertEqual(((cycle["score"] as? [String: Any])?["strain"] as? Double)?.bitPattern, 12.875.nextUp.bitPattern)
            let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
            XCTAssertEqual(record["providers"] != nil, provider == .whoop)
            try batch.bodyArtifact.validateIntegrity()
            XCTAssertEqual(operation.selectedPlan.artifacts.first?.sha256, batch.bodyArtifact.descriptor.sha256)
            var uploads = 0
            let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { prepared, _ in
                uploads += 1
                XCTAssertEqual(prepared.bodyArtifact.descriptor, batch.bodyArtifact.descriptor)
                XCTAssertEqual(prepared.externalRecordPayloadCount, 1)
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
            XCTAssertEqual(uploads, 1)
            XCTAssertEqual(result.successCount, 1)
            XCTAssertTrue(result.didCompleteAllRequestedDates)
        }
    }

    func testMorningConnectedCaptureKeepsTypedPartialProviderAndIndependentSidecar() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(days(count: 1).first)
        let owner = APIExportClient.dayString(from: date, timeZone: zone)
        let external = ExternalDailyRecord(provider: .whoop, date: owner, payloads: [
            ExternalProviderPayload(name: "cycles", endpoint: "https://synthetic.invalid/cycles", statusCode: 200,
                data: .object(["records": .array([.object(["id": .string("provider-cycle"),
                    "start": .string("2026-07-01T23:30:00-07:00"), "end": .null,
                    "score": .object(["strain": .number(12.875.nextUp)])])])])),
            ExternalProviderPayload(name: "recovery", endpoint: "https://synthetic.invalid/recovery", statusCode: 403,
                error: "synthetic permission failure")
        ])
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .summary
        settings.metricSelection.enabledMetrics = ["steps"]
        var fetches = 0
        let resolution = try await APIEndpointExportRunner.prepare(dates: [date], settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: true,
            fetchHealthData: { date, _, _ in HealthData(date: date,
                timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                activity: ActivityData(steps: 42)) }, fetchExternalDailyRecords: { _ in
                    fetches += 1
                    return [external]
                })
        guard case .prepared(let operation) = resolution else { return XCTFail("Expected connected capture") }
        XCTAssertEqual(fetches, 1)
        let batch = try XCTUnwrap(operation.batches.first)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        let expected = try XCTUnwrap(HealthProviderSections.normalized(from: [external]))
        XCTAssertEqual(record["providers"] as? NSDictionary, try expected.foundationJSONObject() as NSDictionary)
        let provider = try XCTUnwrap((record["providers"] as? [String: Any])?["whoop"] as? [String: Any])
        XCTAssertEqual(provider["capture_status"] as? String, "partial")
        let cycle = try XCTUnwrap((provider["cycles"] as? [[String: Any]])?.first)
        XCTAssertEqual(cycle["start_time"] as? String, "2026-07-02T06:30:00.000000000Z")
        XCTAssertTrue(cycle["end_time"] is NSNull)
        XCTAssertEqual((cycle["strain_score"] as? Double)?.bitPattern, 12.875.nextUp.bitPattern)
        XCTAssertEqual(root["external_record_count"] as? Int, 1)
        XCTAssertEqual(batch.externalRecords, [external])
    }

    func testMorningAPIRejectsUnknownTypedProviderVersion() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.metricSelection.enabledMetrics = ["steps"]
        var providers = try XCTUnwrap(ExportFixtures.whoopDay.providers)
        providers.whoop?.schemaVersion = 999
        do {
            _ = try await APIEndpointExportRunner.prepare(dates: days(count: 1), settings: settings,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false,
                fetchHealthData: { date, _, _ in HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                    activity: ActivityData(steps: 42), providers: providers) })
            XCTFail("Unknown provider authority must reject before commit")
        } catch {
            XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .rustPlanningFailed)
        }
    }

    func testMorningAPIKeepsTypedWHOOPFactsIndependentOfAppleSleepAttribution() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let provider = try XCTUnwrap(ExportFixtures.whoopDay.providers)
        for connected in [false, true] {
            let settings = makeSettings()
            settings.exportTimeZoneOverride = zone
            settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
            settings.executionSleepCaptureContextIsFrozen = true
            settings.detailPolicy = .summary
            settings.metricSelection.enabledMetrics = ["steps"]
            let resolution = try await APIEndpointExportRunner.prepare(dates: days(count: 1), settings: settings,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: connected,
                fetchHealthData: { date, _, _ in HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                    activity: ActivityData(steps: 42), providers: provider) })
            guard case .prepared(let operation) = resolution else { return XCTFail("Expected typed provider composition") }
            let batch = try XCTUnwrap(operation.batches.first)
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
            let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
            XCTAssertEqual(record["providers"] as? NSDictionary, try provider.foundationJSONObject() as NSDictionary)
            XCTAssertEqual(root["schema_version"] as? Int, connected ? 2 : 1)
            XCTAssertEqual(root["daily_record_schema_profile"] as? String, "apple-v11")
            let summary = try XCTUnwrap(record["summary"] as? [String: Any])
            XCTAssertNil(summary["providers"])
            try batch.bodyArtifact.validateIntegrity()
            XCTAssertEqual(operation.selectedPlan.artifacts.first?.sha256, batch.bodyArtifact.descriptor.sha256)
        }
    }

    func testMorningSourceSingletonKeepsFullDiagnosticBeyondBatchTarget() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .summary
        settings.metricSelection.enabledMetrics = ["steps"]
        let message = "begin-" + String(repeating: "x", count: 9 * 1024 * 1024) + "-end"
        let resolution = try await APIEndpointExportRunner.prepare(dates: days(count: 1), settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in HealthData(date: date,
                timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                activity: ActivityData(steps: 42), partialFailures: [ExportPartialFailure(date: date,
                    dataType: "sleep", dateRangeDescription: "synthetic", errorDescription: message)]) })
        guard case .prepared(let operation) = resolution else { return XCTFail("Expected file-backed source body") }
        XCTAssertEqual(operation.batches.count, 1)
        let batch = try XCTUnwrap(operation.batches.first)
        XCTAssertGreaterThan(batch.bodyByteCount, UInt64(APIEndpointExportRunner.defaultMaxBatchPayloadBytes))
        try batch.bodyArtifact.validateIntegrity()
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        let record = try XCTUnwrap((root["records"] as? [[String: Any]])?.first)
        let diagnostics = try XCTUnwrap(record["diagnostics"] as? [String: Any])
        let failure = try XCTUnwrap((diagnostics["partial_failures"] as? [[String: Any]])?.first)
        XCTAssertEqual(failure["error_description"] as? String, message)
        XCTAssertEqual(operation.selectedPlan.artifacts.first?.sha256, batch.bodyArtifact.descriptor.sha256)
    }

    func testMorningSourceArchiveRejectsConflictingOwnerBeforeCommit() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .archiveOnly
        do {
            _ = try await APIEndpointExportRunner.prepare(dates: days(count: 1), settings: settings,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false,
                fetchHealthData: { date, _, _ in HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                    healthKitRecordArchive: HealthKitRecordArchive(captureStatus: .complete,
                        dailyOwnership: HealthKitDailyOwnershipMetadata(ownerDate: "1900-01-01",
                            intervalStart: date, intervalEnd: date.addingTimeInterval(86400),
                            calendarTimeZoneIdentifier: zone.identifier)), healthKitRecordCaptureStatus: .complete) })
            XCTFail("Conflicting native source ownership must reject the whole operation")
        } catch {
            XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .rustPlanningFailed)
        }
    }

    func testMorningSourceBodiesRebatchByFinalBytesAndKeepFailuresAndExactNativeFacts() async throws {
        let dates = days(count: 4)
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let large = String(repeating: "x", count: 5 * 1024 * 1024)
        for connected in [false, true] {
            let settings = makeSettings()
            settings.exportTimeZoneOverride = zone
            settings.executionSleepCaptureContext = context
            settings.executionSleepCaptureContextIsFrozen = true
            settings.detailPolicy = .lossless
            settings.metricSelection.enabledMetrics = ["steps", "active_energy"]
            settings.formatCustomization.unitPreference = .imperial
            let resolution = try await APIEndpointExportRunner.prepare(dates: dates, settings: settings,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: connected,
                fetchHealthData: { date, _, _ in
                    guard let index = dates.firstIndex(of: date), index != 1 else {
                        return HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
                    }
                    let owner = HealthKitDailyOwnershipMetadata.ownerDate(for: date,
                        calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier)
                    let archive: HealthKitRecordArchive? = index == 0 || index == 2 ? HealthKitRecordArchive(captureStatus: .complete,
                        dailyOwnership: HealthKitDailyOwnershipMetadata(ownerDate: owner, intervalStart: date,
                            intervalEnd: date.addingTimeInterval(86400), calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier),
                        records: [HealthKitRecord(originalUUID: UUID(), objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
                            recordKind: .quantity, selectedMetricIDs: ["steps"], includedBecause: .selectedMetric,
                            startDate: date, endDate: date, sourceRevision: HealthKitSourceRevision(name: "Synthetic", bundleIdentifier: "com.example.synthetic"),
                            metadata: ["large": .string(large), "exact": .unsignedInteger(.max)],
                            payload: .quantity(HealthKitQuantityPayload(value: 42, unit: "count")))]) : nil
                    return HealthData(date: date,
                        timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                        activity: ActivityData(steps: 42, activeCalories: 123.875.nextUp),
                        partialFailures: index == 2 ? [ExportPartialFailure(date: date, dataType: "sleep",
                            dateRangeDescription: owner, errorDescription: "synthetic missing sleep")] : [],
                        healthKitRecordArchive: archive)
                })
            guard case .prepared(let operation) = resolution else { return XCTFail("Native source work must keep explicit successor authority") }
            XCTAssertEqual(operation.batches.map { $0.requestedDates.count }, [2, 2])
            XCTAssertEqual(operation.batches.map { $0.records.count }, [1, 2])
            XCTAssertEqual(operation.selectedPlan.artifacts.count, 2)
            for (index, batch) in operation.batches.enumerated() {
                XCTAssertGreaterThan(batch.bodyByteCount, 5 * 1024 * 1024)
                XCTAssertLessThan(batch.bodyByteCount, 8 * 1024 * 1024)
                XCTAssertEqual(operation.selectedPlan.artifacts[index].sha256, batch.bodyArtifact.descriptor.sha256)
                let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
                XCTAssertEqual(envelope["schema_version"] as? Int, connected ? 2 : 1)
                XCTAssertEqual(envelope["daily_record_schema_profile"] as? String, "apple-v11")
                let records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
                for record in records {
                    let summary = try XCTUnwrap(record["summary"] as? [String: Any])
                    let activity = try XCTUnwrap(summary["activity"] as? [String: Any])
                    XCTAssertEqual((activity["active_calories"] as? Double)?.bitPattern, 123.875.nextUp.bitPattern)
                    XCTAssertEqual(record["unit_system"] as? String, "metric")
                }
                XCTAssertTrue(String(decoding: batch.body, as: UTF8.self).contains("18446744073709551615"))
            }
            settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
            settings.detailPolicy = .summary
            var sends = 0
            let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
                sends += 1
                try batch.bodyArtifact.validateIntegrity()
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
            XCTAssertEqual(sends, 2)
            XCTAssertEqual(result.successCount, 3)
            XCTAssertEqual(result.failedDateDetails.count, 1)
            XCTAssertEqual(result.partialFailures.count, 1)
            XCTAssertTrue(result.didCompleteAllRequestedDates)
        }
    }

    func testPreparedSourceBodyMutationRejectsWholeOperationBeforeFirstUpload() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let settings = makeSettings()
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.executionSleepCaptureContextIsFrozen = true
        settings.exportTimeZoneOverride = zone
        settings.detailPolicy = .summary
        let dates = days(count: 2)
        let resolution = try await APIEndpointExportRunner.prepare(dates: dates, settings: settings,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in HealthData(date: date,
                timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                activity: ActivityData(steps: 1), partialFailures: [ExportPartialFailure(date: date,
                    dataType: "sleep", dateRangeDescription: "one day", errorDescription: "synthetic")]) }, maxBatchDaySpan: 1)
        guard case .prepared(let operation) = resolution else { return XCTFail("Expected source-composed operation") }
        let last = try XCTUnwrap(operation.batches.last)
        try Data(repeating: 0x78, count: Int(last.bodyByteCount)).write(to: last.bodyArtifact.url)
        var sends = 0
        let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { _, _ in
            sends += 1
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertTrue(result.isFailure)
    }

    func testMorningEndsAPIComposesPartialFailuresIntoFinalBody() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .summary
        settings.metricSelection.enabledMetrics = ["steps"]
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings,
            calendarTimeZone: zone, surface: .apiEndpoint)
        let frozen = snapshot.makeAdvancedExportSettings()
        Self.retainedSettings.append(frozen)
        let day = HealthData(date: ExportFixtures.referenceDate,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 42), partialFailures: [ExportPartialFailure(
                date: ExportFixtures.referenceDate, dataType: "sleep", dateRangeDescription: "synthetic day",
                errorDescription: "synthetic missing source")])
        let optional = try await APIEndpointExportRunner.preparePreview(records: [day], settings: frozen,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false)
        let operation = try XCTUnwrap(optional)
        let batch = try XCTUnwrap(operation.batches.first)
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        XCTAssertEqual(envelope["daily_record_schema_version"] as? Int, 11)
        XCTAssertEqual(envelope["daily_record_schema_profile"] as? String, "apple-v11")
        let record = try XCTUnwrap((envelope["records"] as? [[String: Any]])?.first)
        let failure = try XCTUnwrap(((record["diagnostics"] as? [String: Any])?["partial_failures"] as? [[String: Any]])?.first)
        XCTAssertEqual(failure["data_type"] as? String, "sleep")
        XCTAssertEqual(failure["error_description"] as? String, "synthetic missing source")
        XCTAssertEqual(operation.selectedPlan.artifacts.first?.sha256, batch.bodyArtifact.descriptor.sha256)
        XCTAssertNotNil(operation.selectedPlan.artifacts.first?.fileArtifact)
        XCTAssertNil(operation.nativePlan)
        XCTAssertEqual((record["time_context"] as? [String: String])?["sleep_day_attribution"], "morning_ends")
    }

    func testMorningEndsAPIComposesCanonicalArchiveIntoFinalBody() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.detailPolicy = .archiveOnly
        settings.metricSelection.enabledMetrics = ["steps"]
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings,
            calendarTimeZone: zone, surface: .apiEndpoint)
        let frozen = snapshot.makeAdvancedExportSettings()
        Self.retainedSettings.append(frozen)
        let date = ExportFixtures.referenceDate
        let archive = HealthKitRecordArchive(captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: HealthKitDailyOwnershipMetadata.ownerDate(for: date, calendarTimeZoneIdentifier: zone.identifier),
                intervalStart: date, intervalEnd: date.addingTimeInterval(86400), calendarTimeZoneIdentifier: zone.identifier))
        let day = HealthData(date: date,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            healthKitRecordArchive: archive, healthKitRecordCaptureStatus: .complete)
        let optional = try await APIEndpointExportRunner.preparePreview(records: [day], settings: frozen,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false)
        let operation = try XCTUnwrap(optional)
        let batch = try XCTUnwrap(operation.batches.first)
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
        let record = try XCTUnwrap((envelope["records"] as? [[String: Any]])?.first)
        let actual = try XCTUnwrap(record["healthkit_record_archive"] as? NSDictionary)
        XCTAssertEqual(actual, try JSONSerialization.jsonObject(with: HealthKitRecordArchiveSerializer.data(for: archive)) as? NSDictionary)
        XCTAssertEqual(record["raw_capture_status"] as? String, "complete")
        XCTAssertEqual(envelope["daily_record_schema_profile"] as? String, "apple-v11")
        var sends = 0
        let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { sent, _ in
            sends += 1
            XCTAssertEqual(sent.bodyArtifact.descriptor, batch.bodyArtifact.descriptor)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(result.successCount, 1)
    }

    func testMorningEndsAPISelectsV11BeforeCaptureAndKeepsNativeRecordsAndFailedBatchAuthority() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let first = try XCTUnwrap(formatter.date(from: "2026-11-01T04:00:00Z"))
        let second = try XCTUnwrap(formatter.date(from: "2026-11-02T05:00:00Z"))
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z")).addingTimeInterval(0.125)
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T06:30:00Z")).addingTimeInterval(0.125)
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let settings = makeSettings()
        settings.exportTimeZoneOverride = zone
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        settings.formatCustomization.unitPreference = .imperial
        settings.metricSelection.enabledMetrics = ["steps", "sleep_total", "workouts"]
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings,
            calendarTimeZone: zone, surface: .apiEndpoint)
        XCTAssertEqual(snapshot.appleExportEnginePin?.profile, AppleExportEnginePin.wakeDateProfileID)
        let frozen = snapshot.makeAdvancedExportSettings()
        Self.retainedSettings.append(frozen)
        // Changes to the original device-side settings cannot alter accepted API work.
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Europe/Berlin")!, sleepDayAttribution: .nightBegins)
        settings.exportTimeZoneOverride = TimeZone(identifier: "Europe/Berlin")
        let workout = WorkoutData(workoutType: .running, startTime: start, duration: 1800.5,
            calories: 123.25, distance: 1500.125)
        var populated = HealthData(date: first,
            timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
            activity: ActivityData(steps: 17), workouts: [workout])
        populated.sleep = SleepData(totalDuration: 3600, sessionStart: start, sessionEnd: end)
        var captures = 0
        let events = APIEngineEventRecorder()
        let resolution: APIEndpointExportRunner.PreparationResolution
        do {
        resolution = try await APIEndpointExportRunner.prepare(dates: [first, second], settings: frozen,
            destination: destination, calendarTimeZone: zone, connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                captures += 1
                XCTAssertEqual(frozen.executionSleepCaptureContext, context)
                return date == first ? populated : HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds))
            }, maxBatchDaySpan: 1, coreExecutor: APIRecordingCoreExecutor(events: events), identitySource: identitySource)
        } catch {
            let phases = await events.values()
            XCTFail("API boundary phases: \(phases)")
            throw error
        }
        guard case .prepared(let operation) = resolution else { return XCTFail("Morning ends API must not fall back") }
        XCTAssertEqual(captures, 2)
        let phases = await events.values()
        XCTAssertEqual(phases.filter { $0 == "semantic" }.count, 1)
        XCTAssertEqual(phases.filter { $0 == "render" }.count, 1)
        XCTAssertEqual(operation.authority, .rust)
        XCTAssertNil(operation.nativePlan)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.rustPlan))
        XCTAssertEqual(operation.pin, snapshot.appleExportEnginePin)
        XCTAssertEqual(operation.batches.count, 2)
        for (index, batch) in operation.batches.enumerated() {
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: batch.body) as? [String: Any])
            XCTAssertEqual(root["schema_version"] as? Int, 1)
            XCTAssertEqual(root["daily_record_schema_version"] as? Int, 11)
            XCTAssertEqual(root["daily_record_schema_profile"] as? String, "apple-v11")
            let clock = try XCTUnwrap(root["daily_record_time_context"] as? [String: String])
            XCTAssertEqual(clock["calendar_timezone"], zone.identifier)
            XCTAssertEqual(clock["sleep_day_attribution"], "morning_ends")
            let records = try XCTUnwrap(root["records"] as? [[String: Any]])
            XCTAssertEqual(records.count, index == 0 ? 1 : 0)
            if let record = records.first {
                let nativeWorkouts = try XCTUnwrap(record["workouts"] as? [[String: Any]])
                XCTAssertEqual(nativeWorkouts.first?["id"] as? String, workout.id.uuidString)
                let summary = try XCTUnwrap(record["summary"] as? [String: [String: Any]])
                XCTAssertEqual(summary["activity"]?["steps"] as? Int, 17)
                XCTAssertEqual(summary["sleep"]?["sleep_total_hours"] as? Double, 1)
            }
        }
    }

    func testMorningEndsAPIRejectsMissingOrContradictoryAuthorityBeforeCapture() async throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let valid = AppleSleepCaptureContext(timeZone: utc, sleepDayAttribution: .morningEnds)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        object.removeValue(forKey: "exportProfileID")
        let draft = try JSONDecoder().decode(AppleSleepCaptureContext.self,
            from: JSONSerialization.data(withJSONObject: object))
        let service = HealthMdCoreService()
        let historical = try AppleExportEnginePin(engine: .shadow, calendarTimeZoneIdentifier: "UTC",
            buildInfo: service.buildInfo(), registrySnapshot: service.metricRegistry(profile: .appleHealthDataV8))
        let cases: [(AppleSleepCaptureContext, AppleExportEnginePin?, Bool)] = [
            (draft, nil, false), (valid, historical, true), (valid, nil, true),
            (AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Europe/Berlin")!, sleepDayAttribution: .morningEnds), nil, false),
        ]
        for (context, pin, frozen) in cases {
            let settings = makeSettings()
            settings.executionSleepCaptureContext = context
            settings.executionSleepCaptureContextIsFrozen = true
            settings.executionAppleExportEnginePin = pin
            settings.executionAppleExportEngineAuthorityIsFrozen = frozen
            var captures = 0
            do {
                _ = try await APIEndpointExportRunner.prepare(dates: days(count: 1), settings: settings,
                    destination: destination, calendarTimeZone: utc, connectedAppsEnabled: false,
                    fetchHealthData: { date, _, _ in captures += 1; return self.record(date: date, steps: 1) })
                XCTFail("Incompatible API authority must reject before capture")
            } catch {
                XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .rustPlanningFailed)
            }
            XCTAssertEqual(captures, 0)
        }
    }

    func testMorningEndsV2EnvelopeAndFailureOnlyOperationKeepProfileBeforeCommit() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = days(count: 1)[0]
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        for failureOnly in [false, true] {
            let settings = makeSettings()
            settings.executionSleepCaptureContext = context
            settings.executionSleepCaptureContextIsFrozen = true
            let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings, calendarTimeZone: zone, surface: .apiEndpoint)
            let frozen = snapshot.makeAdvancedExportSettings()
            Self.retainedSettings.append(frozen)
            let identity = AppleExportOperationIdentitySource(makeRequestID: { "api-v11-v2-\(failureOnly)" },
                makeSessionID: { "api-v11-session-\(failureOnly)" }, now: { Date(timeIntervalSince1970: 1_751_328_000.125) })
            let resolution = try await APIEndpointExportRunner.prepare(dates: [date], settings: frozen,
                destination: destination, calendarTimeZone: zone, connectedAppsEnabled: true,
                fetchHealthData: { date, _, _ in HealthData(date: date,
                    timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                    activity: failureOnly ? ActivityData() : ActivityData(steps: 3)) }, identitySource: identity)
            guard case .prepared(let operation) = resolution else { return XCTFail("A v11 API cannot downgrade") }
            XCTAssertNil(operation.nativePlan)
            let body = try XCTUnwrap(operation.batches.first).body
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(root["schema_version"] as? Int, 2)
            XCTAssertEqual(root["daily_record_schema_version"] as? Int, 11)
            XCTAssertEqual(root["daily_record_schema_profile"] as? String, "apple-v11")
            XCTAssertEqual(root["external_record_schema"] as? String, ExternalDailyRecord.schema)
            XCTAssertEqual(root["external_record_count"] as? Int, 0)
            XCTAssertEqual((root["records"] as? [Any])?.count, failureOnly ? 0 : 1)
            var uploaded: [Data] = []
            let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
                uploaded.append(batch.body)
                return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
            }
            XCTAssertEqual(uploaded, failureOnly ? [] : [body])
            XCTAssertEqual(result.successCount, failureOnly ? 0 : 1)
        }
    }

    func testMorningEndsExportDispatcherDoesNotFallBackWithAnExternalFetcherOrFrozenNilPin() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        for frozenNilPin in [false, true] {
            let settings = makeSettings()
            settings.executionAppleExportEngineAuthorityIsFrozen = frozenNilPin
            var captures = 0
            var uploads: [Data] = []
            let result = await AppleSleepCaptureContext.pinned.withValue(context) {
                await APIEndpointExportRunner.exportEngineAware(dates: days(count: 1), settings: settings,
                    destination: destination, calendarTimeZone: zone, connectedAppsEnabled: true,
                    fetchHealthData: { date, _, _ in
                        captures += 1
                        return HealthData(date: date, timeContext: ExportTimeContext(timeZone: zone, sleepDayAttribution: .morningEnds),
                            activity: ActivityData(steps: 3))
                    }, fetchExternalDailyRecords: { _ in [] }, upload: { batch, _ in
                        uploads.append(batch.body)
                        return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
                    }, maxBatchDaySpan: 7, maxBatchPayloadBytes: APIEndpointExportRunner.defaultMaxBatchPayloadBytes,
                    policyResolver: AppleExportEnginePolicyResolver(injectedOverride: "legacy", userDefaults: nil, environment: [:]),
                    coreExecutor: SystemAppleLooseDailyCoreExecutor(), identitySource: identitySource,
                    comparisonOptions: NativeExportComparisonOptions(), diagnosticSink: { _ in }, onProgress: nil)
            }
            XCTAssertEqual(captures, frozenNilPin ? 0 : 1)
            XCTAssertEqual(uploads.count, frozenNilPin ? 0 : 1)
            XCTAssertEqual(result.successCount, frozenNilPin ? 0 : 1)
            if let body = uploads.first {
                let root = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(root["schema_version"] as? Int, 2)
                XCTAssertEqual(root["daily_record_schema_version"] as? Int, 11)
                XCTAssertEqual(root["daily_record_schema_profile"] as? String, "apple-v11")
            }
        }
    }

    func testShadowCapturesEachOwnerOnceAndCompletesEveryPlanBeforeUpload() async throws {
        let dates = days(count: 8)
        let settings = makeSettings()
        let events = APIEngineEventRecorder()
        var captureCounts: [Date: Int] = [:]
        var uploadBodies: [Data] = []

        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            maxBatchDaySpan: 3,
            fetchHealthData: { date, _, _ in
                captureCounts[date, default: 0] += 1
                await events.record("capture")
                return self.record(date: date, steps: 1_000)
            },
            coreExecutor: APIRecordingCoreExecutor(events: events)
        )

        XCTAssertEqual(captureCounts.count, dates.count)
        XCTAssertTrue(captureCounts.values.allSatisfy { $0 == 1 })
        XCTAssertEqual(operation.batches.map(\.requestedDates.count), [3, 3, 2])
        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)
        XCTAssertEqual(Set(operation.batches.map(\.exportedAt)), [fixedExportedAt])
        let eventsBeforeCommit = await events.values()
        XCTAssertFalse(eventsBeforeCommit.contains("upload"))

        _ = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            await events.record("upload")
            uploadBodies.append(batch.body)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }

        XCTAssertEqual(uploadBodies, try XCTUnwrap(operation.nativePlan).artifacts.map(\.inlineData))
        let values = await events.values()
        let firstUpload = try XCTUnwrap(values.firstIndex(of: "upload"))
        XCTAssertFalse(values[firstUpload...].contains("capture"))
        XCTAssertFalse(values[firstUpload...].contains("semantic"))
        XCTAssertFalse(values[firstUpload...].contains("render"))
    }

    func testExactV1NativeAndRustFixtureIncludesFailureOnlyDayAndFullRange() async throws {
        let dates = days(count: 2)
        let settings = makeSettings()
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                if date == dates[1] {
                    return HealthData(
                        date: date,
                        timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                    )
                }
                return self.record(date: date, steps: 1_234)
            }
        )

        let rustPlan = try XCTUnwrap(operation.rustPlan)
        XCTAssertEqual(rustPlan, operation.nativePlan)
        XCTAssertEqual(operation.batches.count, 1)
        let batch = try XCTUnwrap(operation.batches.first)
        let frozenSettings = operation.settingsSnapshot.makeAdvancedExportSettings()
        let expected = try APIExportClient.makePayload(
            records: batch.records,
            failedDateDetails: batch.failedDateDetails,
            settings: frozenSettings,
            dateRangeStart: dates[0],
            dateRangeEnd: dates[1],
            exportedAt: fixedExportedAt,
            connectedAppsEnabled: false
        )
        XCTAssertEqual(batch.body, expected)

        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: batch.body) as? [String: Any]
        )
        XCTAssertEqual(envelope["schema_version"] as? Int, 1)
        XCTAssertEqual(envelope["record_count"] as? Int, 1)
        XCTAssertEqual((envelope["failed_date_details"] as? [Any])?.count, 1)
        XCTAssertEqual((envelope["date_range"] as? [String: String]), [
            "start": "2026-07-01",
            "end": "2026-07-02",
        ])
    }

    func testExactV2NativeAndRustFixtureIncludesExternalJSONAndUnescapedSlashes() async throws {
        let dates = days(count: 2)
        let settings = makeSettings()
        let external = externalRecord(ownerDate: "2026-07-01")
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            connectedAppsEnabled: true,
            fetchHealthData: { date, _, _ in
                if date == dates[1] {
                    return HealthData(
                        date: date,
                        timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                    )
                }
                return self.record(date: date, steps: 9_876)
            },
            fetchExternalDailyRecords: { date in
                date == dates[0] ? [external] : []
            }
        )

        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        let batch = try XCTUnwrap(operation.batches.first)
        let frozenSettings = operation.settingsSnapshot.makeAdvancedExportSettings()
        let expected = try APIExportClient.makePayload(
            records: batch.records,
            failedDateDetails: batch.failedDateDetails,
            externalRecords: batch.externalRecords,
            settings: frozenSettings,
            dateRangeStart: dates[0],
            dateRangeEnd: dates[1],
            exportedAt: fixedExportedAt,
            connectedAppsEnabled: true
        )
        XCTAssertEqual(batch.body, expected)
        let text = String(decoding: batch.body, as: UTF8.self)
        XCTAssertTrue(text.contains("https://api.example.com/provider/path"))
        XCTAssertFalse(text.contains(#"https:\/\/api.example.com"#))

        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: batch.body) as? [String: Any]
        )
        XCTAssertEqual(envelope["schema_version"] as? Int, 2)
        XCTAssertEqual(envelope["external_record_count"] as? Int, 1)
        XCTAssertEqual((envelope["failed_date_details"] as? [Any])?.count, 1)
    }

    func testShadowCommitsNativeOnlyAndNeverCommitsMismatchingRustCandidate() async throws {
        let diagnostics = APIEngineDiagnosticRecorder()
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 1),
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in self.record(date: date, steps: 42) },
            coreExecutor: APIMutatingCoreExecutor(),
            diagnosticSink: { await diagnostics.record($0) }
        )
        let rustPlan = try XCTUnwrap(operation.rustPlan)
        XCTAssertNotEqual(operation.nativePlan, rustPlan)
        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)

        var uploaded: [Data] = []
        _ = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            uploaded.append(batch.body)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(uploaded, try XCTUnwrap(operation.nativePlan).artifacts.map(\.inlineData))
        XCTAssertFalse(uploaded.contains(rustPlan.artifacts[0].inlineData))

        let recorded = await diagnostics.values()
        XCTAssertTrue(recorded.contains {
            if case .planMismatch = $0 { return true }
            return false
        })
    }

    func testUnsupportedRustAPIFallsBackBeforeCaptureAndPersistedPinFailsClosed() async throws {
        let dates = days(count: 2)
        var captures = 0
        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "rust",
            userDefaults: nil,
            environment: [:]
        )
        let newResolution = try await APIEndpointExportRunner.prepare(
            dates: dates,
            settings: makeSettings(),
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                captures += 1
                return self.record(date: date, steps: 77)
            },
            policyResolver: resolver,
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
        )
        guard case .legacy = newResolution else {
            return XCTFail("Unsupported new Rust API work must resolve wholly to legacy")
        }
        XCTAssertEqual(captures, 0)

        let pin = try makeSyntheticAppleExportEnginePin(
            engine: .rust,
            calendarTimeZoneIdentifier: "UTC"
        )
        let pinnedSettings = ExportSettingsSnapshot.from(
            makeSettings(),
            appleExportEnginePin: pin,
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "UTC"
        ).makeAdvancedExportSettings()
        do {
            _ = try await APIEndpointExportRunner.prepare(
                dates: dates,
                settings: pinnedSettings,
                destination: destination,
                calendarTimeZone: TimeZone(identifier: "UTC")!,
                connectedAppsEnabled: false,
                fetchHealthData: { date, _, _ in
                    captures += 1
                    return self.record(date: date, steps: 77)
                },
                policyResolver: resolver,
                coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
            )
            XCTFail("Persisted unsupported Rust API authority must fail closed")
        } catch {
            XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .rustPlanningFailed)
        }
        XCTAssertEqual(captures, 0)
    }

    func testEncodedLimitPlansSingletonsIncludingFailureOnlyDays() async throws {
        let dates = days(count: 3)
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: makeSettings(),
            maxBatchPayloadBytes: 1,
            fetchHealthData: { date, _, _ in
                if date == dates[1] {
                    return HealthData(
                        date: date,
                        timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                    )
                }
                return self.record(date: date, steps: 500)
            }
        )

        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        XCTAssertEqual(operation.batches.map(\.requestedDates.count), [1, 1, 1])
        XCTAssertEqual(operation.batches.map(\.records.count), [1, 0, 1])
        XCTAssertTrue(operation.batches.allSatisfy { $0.body.count > 1 })
    }

    func testPreparedRetryReusesExactBodiesWithoutCaptureOrRerender() async throws {
        let events = APIEngineEventRecorder()
        var captures = 0
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 2),
            settings: makeSettings(),
            maxBatchDaySpan: 1,
            fetchHealthData: { date, _, _ in
                captures += 1
                return self.record(date: date, steps: 321)
            },
            coreExecutor: APIRecordingCoreExecutor(events: events)
        )
        var firstAttempt: [Data] = []
        let firstResult = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            firstAttempt.append(batch.body)
            throw APIExportClientError.serverRejected(statusCode: 503, body: "private")
        }
        XCTAssertEqual(firstResult.successCount, 0)

        var retry: [Data] = []
        let retryResult = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            retry.append(batch.body)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(retryResult.successCount, 2)
        XCTAssertEqual(firstAttempt[0], retry[0])
        XCTAssertEqual(retry, operation.selectedPlan.artifacts.map(\.inlineData))
        XCTAssertEqual(captures, 2)
        let recordedEvents = await events.values()
        XCTAssertEqual(recordedEvents.filter { $0 == "semantic" }.count, 1)
        XCTAssertEqual(recordedEvents.filter { $0 == "render" }.count, 1)
    }

    func testCommitBarrierLocksBeforeFirstUploadAndFailureCannotFallback() async throws {
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 1),
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in self.record(date: date, steps: 808) },
            coreExecutor: APIMutatingCoreExecutor()
        )
        let barrier = ExportCommitBarrier()
        var bodies: [Data] = []
        let result = await APIEndpointExportRunner.commitPreparedOperation(
            operation,
            upload: { batch, _ in
                let stateDuringUpload = await barrier.state
                XCTAssertEqual(stateDuringUpload, .committing)
                bodies.append(batch.body)
                throw APIExportClientError.serverRejected(statusCode: 500, body: "private")
            },
            barrier: barrier
        )

        let finalBarrierState = await barrier.state
        XCTAssertEqual(finalBarrierState, .failed)
        XCTAssertEqual(bodies, operation.selectedPlan.artifacts.map(\.inlineData))
        XCTAssertEqual(bodies, try XCTUnwrap(operation.nativePlan).artifacts.map(\.inlineData))
        XCTAssertNotEqual(bodies, try XCTUnwrap(operation.rustPlan).artifacts.map(\.inlineData))
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .apiUploadFailed)
    }

    func testShadowFailureDiagnosticIsTypedAndHealthFree() async throws {
        let sensitive = "steps=654321;2026-07-01;https://private.example/path;Bearer secret"
        let diagnostics = APIEngineDiagnosticRecorder()
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 1),
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in self.record(date: date, steps: 654_321) },
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: sensitive),
            diagnosticSink: { await diagnostics.record($0) }
        )

        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)
        XCTAssertNil(operation.rustPlan)
        let recorded = await diagnostics.values()
        XCTAssertEqual(recorded.count, 1)
        guard case .rustRenderFailed(let diagnostic) = try XCTUnwrap(recorded.first) else {
            return XCTFail("Expected typed Rust failure")
        }
        XCTAssertEqual(diagnostic.kind, .rustRenderFailed)
        let description = String(describing: recorded)
        for forbidden in ["654321", "2026-07-01", "private.example", "Bearer", "secret"] {
            XCTAssertFalse(description.contains(forbidden))
        }
    }

    func testSettingsTimezoneClockAndDestinationAreFrozenOnce() async throws {
        let dates = days(count: 2)
        let settings = makeSettings()
        let originalDestination = destination
        var seenSelections: [Set<String>] = []
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            fetchHealthData: { date, _, selection in
                seenSelections.append(selection.enabledMetrics)
                if date == dates[0] {
                    settings.metricSelection.enabledMetrics = []
                    settings.exportTimeZoneOverride = TimeZone(identifier: "America/New_York")
                }
                return self.record(date: date, steps: 100)
            }
        )

        XCTAssertEqual(seenSelections, [Set(["steps"]), Set(["steps"])])
        XCTAssertEqual(operation.destination, originalDestination)
        XCTAssertEqual(operation.pin.calendarTimeZoneIdentifier, "UTC")
        XCTAssertEqual(operation.settingsSnapshot.calendarTimeZoneIdentifier, "UTC")
        XCTAssertEqual(Set(operation.batches.map(\.exportedAt)), [fixedExportedAt])
    }

    func testFrozenLegacySnapshotDoesNotInheritCurrentRustDefaultOrCapture() async throws {
        let frozenLegacy = ExportSettingsSnapshot.from(
            makeSettings(),
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "UTC"
        ).makeAdvancedExportSettings()
        var captureCount = 0

        let resolution = try await APIEndpointExportRunner.prepare(
            dates: days(count: 1),
            settings: frozenLegacy,
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                captureCount += 1
                return self.record(date: date, steps: 10)
            },
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
        )

        guard case .legacy = resolution else {
            return XCTFail("Frozen nil authority must remain legacy")
        }
        XCTAssertEqual(captureCount, 0)
    }

    func testPreparedPreviewReusesCapturedRecordsAndExactAuthoritativeBodySizes() async throws {
        let dates = days(count: 3)
        let records = dates.enumerated().map { index, date in
            record(date: date, steps: 1_000 + index)
        }
        let preparedPreview = try await APIEndpointExportRunner.preparePreview(
            records: Array(records.reversed()),
            settings: makeSettings(),
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: true,
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: identitySource
        )
        let operation = try XCTUnwrap(preparedPreview)

        XCTAssertEqual(operation.authority, ExportEngineMode.shadow)
        XCTAssertEqual(operation.normalizedDates, dates)
        XCTAssertTrue(operation.batches.allSatisfy(\.externalRecords.isEmpty))
        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.rustPlan))
        let samples = ExportPreviewView.apiPayloadSizeSamples(operation)
        XCTAssertEqual(samples.count, dates.count)
        XCTAssertEqual(
            samples.reduce(0) { $0 + $1.aggregateByteCount },
            operation.batches.reduce(0) { $0 + $1.body.count }
        )
    }

    func testPreparedPreviewExplicitLegacyDoesNotFetchProvidersOrLoadCore() async throws {
        let settings = ExportSettingsSnapshot.from(
            makeSettings(),
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "UTC"
        ).makeAdvancedExportSettings()
        var externalFetchCount = 0
        let operation = try await APIEndpointExportRunner.preparePreview(
            records: [record(date: days(count: 1)[0], steps: 10)],
            settings: settings,
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: true,
            fetchExternalDailyRecords: { _ in
                externalFetchCount += 1
                return []
            },
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
        )

        XCTAssertNil(operation)
        XCTAssertEqual(externalFetchCount, 0)
    }

    func testPreparePathPerformsNoUploadAndAllEmptyPlanRemainsDestinationFree() async throws {
        let dates = days(count: 2)
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in
                HealthData(
                    date: date,
                    timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                )
            }
        )
        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        XCTAssertEqual(operation.batches.count, 1)
        XCTAssertTrue(operation.batches[0].records.isEmpty)

        var uploadCount = 0
        let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { _, _ in
            uploadCount += 1
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.count, 2)
    }

    private var destination: APIExportDestinationSnapshot {
        APIExportDestinationSnapshot(
            endpointURL: URL(string: "https://api.example.com/healthmd")!,
            authorizationHeaderValue: "Bearer frozen-token",
            displayName: "api.example.com",
            redactedEndpointDescription: "https://api.example.com/healthmd"
        )
    }

    private var fixedExportedAt: Date {
        Date(timeIntervalSince1970: 1_751_328_000.125)
    }

    private var identitySource: AppleExportOperationIdentitySource {
        AppleExportOperationIdentitySource(
            makeRequestID: { "api-m6-request" },
            makeSessionID: { "api-m6-session" },
            now: { Date(timeIntervalSince1970: 1_751_328_000.125) }
        )
    }

    private func preparedOperation(
        mode: ExportEngineMode,
        dates: [Date],
        settings: AdvancedExportSettings,
        connectedAppsEnabled: Bool = false,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan,
        maxBatchPayloadBytes: Int = APIEndpointExportRunner.defaultMaxBatchPayloadBytes,
        fetchHealthData: @escaping APIEndpointExportRunner.HealthDataFetcher,
        fetchExternalDailyRecords: APIEndpointExportRunner.ExternalDailyRecordFetcher? = nil,
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(),
        diagnosticSink: @escaping APIEndpointExportRunner.EngineDiagnosticSink = { _ in }
    ) async throws -> APIEndpointExportRunner.PreparedOperation {
        let resolution = try await APIEndpointExportRunner.prepare(
            dates: dates,
            settings: settings,
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: connectedAppsEnabled,
            fetchHealthData: fetchHealthData,
            fetchExternalDailyRecords: fetchExternalDailyRecords,
            maxBatchDaySpan: maxBatchDaySpan,
            maxBatchPayloadBytes: maxBatchPayloadBytes,
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: mode.rawValue,
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: coreExecutor,
            identitySource: identitySource,
            comparisonOptions: NativeExportComparisonOptions(
                includeFirstDifferingByteOffset: false
            ),
            diagnosticSink: diagnosticSink
        )
        guard case .prepared(let operation) = resolution else {
            throw XCTSkip("Internal engine override is unavailable")
        }
        return operation
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suite = "APIEndpointExportEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")
        Self.retainedSettings.append(settings)
        return settings
    }

    private func days(count: Int) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private func record(date: Date, steps: Int) -> HealthData {
        HealthData(
            date: date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            activity: ActivityData(steps: steps)
        )
    }

    private func externalRecord(ownerDate: String) -> ExternalDailyRecord {
        ExternalDailyRecord(
            provider: .whoop,
            date: ownerDate,
            payloads: [ExternalProviderPayload(
                name: "fixture",
                endpoint: "https://api.example.com/provider/path",
                statusCode: 200,
                data: .object([
                    "source_url": .string("https://api.example.com/provider/path"),
                    "records": .array([.object(["id": .number(1)])]),
                ])
            )]
        )
    }
}

private actor APIEngineDiagnosticRecorder {
    private var diagnostics: [ShadowExportDiagnostic] = []
    func record(_ diagnostic: ShadowExportDiagnostic) { diagnostics.append(diagnostic) }
    func values() -> [ShadowExportDiagnostic] { diagnostics }
}

private actor APIEngineEventRecorder {
    private var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func values() -> [String] { events }
}

nonisolated private struct APIRecordingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    let events: APIEngineEventRecorder
    var requireAggregateOnlyConfiguration = false
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        await events.record("context")
        return try await base.loadContext()
    }

    func loadContext(profile: CoreMetricRegistryProfile, expectedRegistryVersion: UInt32) async throws -> AppleLooseDailyCoreContext {
        await events.record("profile-context")
        return try await base.loadContext(profile: profile, expectedRegistryVersion: expectedRegistryVersion)
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        await events.record("semantic")
        do {
            let result = try await base.processSemantic(configuration: configuration, batches: batches)
            await events.record("semantic-completed")
            return result
        } catch {
            await events.record("semantic-failure: \(error)")
            throw error
        }
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        if requireAggregateOnlyConfiguration {
            XCTAssertLessThan(configuration.count, 64 * 1024)
            XCTAssertTrue(batches.allSatisfy { $0.count < 64 * 1024 })
            let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: configuration) as? [String: Any])
            let api = try XCTUnwrap(root["api"] as? [String: Any])
            XCTAssertEqual((api["external_records"] as? [Any])?.count, 0)
        }
        if let directory = ProcessInfo.processInfo.environment["HEALTHMD_API_V11_FIXTURE_DIR"],
           let config = try JSONSerialization.jsonObject(with: configuration) as? [String: Any],
           config["profile"] as? String == AppleExportEnginePin.wakeDateProfileID {
            let root = URL(fileURLWithPath: directory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try configuration.write(to: root.appendingPathComponent("config.json"))
            try semanticResult.write(to: root.appendingPathComponent("semantic.json"))
            for (index, batch) in batches.enumerated() {
                try batch.write(to: root.appendingPathComponent("batch-\(index).json"))
            }
        }
        await events.record("render")
        do {
            let result = try await base.render(configuration: configuration, semanticResult: semanticResult, batches: batches)
            await events.record("render-completed")
            return result
        } catch {
            await events.record("render-failure: \(error)")
            throw error
        }
    }
}

nonisolated private struct APIMutatingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        try await base.loadContext()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        try await base.processSemantic(configuration: configuration, batches: batches)
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        let plan = try await base.render(
            configuration: configuration,
            semanticResult: semanticResult,
            batches: batches
        )
        guard let changedIndex = plan.items.firstIndex(where: { $0.writeMode == .apiPost }) else {
            return plan
        }
        let first = plan.items[changedIndex]
        let changed = first.content + Data(" ".utf8)
        let digest = NativeExportArtifact.sha256(of: changed)
        let replacement = CoreArtifactPlanItem(
            artifactId: NativeExportArtifactPlan.artifactID(
                requestID: plan.requestId,
                sessionID: plan.sessionId,
                profile: plan.profile,
                relativePath: first.relativePath,
                mediaType: first.mediaType,
                writeMode: first.writeMode,
                contentSHA256: digest
            ),
            relativePath: first.relativePath,
            mediaType: first.mediaType,
            writeMode: first.writeMode,
            content: changed,
            byteCount: UInt64(changed.count),
            sha256: digest
        )
        var items = plan.items
        items[changedIndex] = replacement
        return CoreArtifactPlan(
            schema: plan.schema,
            artifactPlanVersion: plan.artifactPlanVersion,
            requestId: plan.requestId,
            sessionId: plan.sessionId,
            profile: plan.profile,
            items: items,
            totalByteCount: plan.totalByteCount + 1
        )
    }
}

nonisolated private struct APIEngineSensitiveError: Error, Sendable {
    let value: String
}

nonisolated private struct APIFailingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    let sensitiveValue: String
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        try await base.loadContext()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        throw APIEngineSensitiveError(value: sensitiveValue)
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        throw APIEngineSensitiveError(value: sensitiveValue)
    }
}

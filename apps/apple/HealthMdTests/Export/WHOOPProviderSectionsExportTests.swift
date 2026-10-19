import XCTest
@testable import HealthMd

final class WHOOPProviderSectionsExportTests: XCTestCase {
    func testCycleStepsPreserveZeroAndExactCountsWithoutChangingDailySteps() throws {
        for count in [0, 1, Int(Int32.max)] {
            let (data, native) = try cycleExport([.number(Double(count))])
            let text = try data.toJSONThrowing(outputFormatting: [.sortedKeys])
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let providers = try XCTUnwrap(root["providers"] as? [String: Any])
            let whoop = try XCTUnwrap(providers["whoop"] as? [String: Any])
            let cycles = try XCTUnwrap(whoop["cycles"] as? [[String: Any]])
            XCTAssertEqual(whoop["schema_version"] as? Int, 2)
            XCTAssertEqual(cycles.first?["step_count"] as? Int, count)
            XCTAssertEqual((root["activity"] as? [String: Any])?["steps"] as? Int, 1)
            XCTAssertEqual(data.activity.steps, 1)
            XCTAssertTrue(data.toObsidianBases().contains("whoop_cycle_step_count: \(count)\n"))
            XCTAssertTrue(data.toMarkdown().contains("Steps (cycle)"))
            XCTAssertTrue(try data.toCSVThrowing().contains("WHOOP Cycle,Physiological-Cycle Steps,\(count),count,"))
            let nativeText = String(decoding: try JSONEncoder().encode(native), as: UTF8.self)
            XCTAssertTrue(nativeText.contains("\"step_count\":\(count)"))
        }
    }

    func testCycleStepsMissingNullAndInvalidValuesRemainUnavailable() throws {
        let values: [JSONValue?] = [nil, .null, .number(-1), .number(1.5),
                                  .number(Double(Int32.max) + 1), .bool(false), .string("100")]
        for value in values {
            let (data, _) = try cycleExport([value])
            let text = try data.toJSONThrowing()
            XCTAssertFalse(text.contains("\"step_count\""))
            XCTAssertFalse(data.toObsidianBases().contains("whoop_cycle_step_count:"))
            XCTAssertFalse(try data.toCSVThrowing().contains("Physiological-Cycle Steps,"))
            XCTAssertEqual(data.activity.steps, 1)
        }
    }

    func testMultiplePhysiologicalCyclesKeepCountsWithoutAFalseDailyTotal() throws {
        let (data, _) = try cycleExport([.number(0), .number(9_876)])
        let text = try data.toJSONThrowing()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        let whoop = try XCTUnwrap((root["providers"] as? [String: Any])?["whoop"] as? [String: Any])
        let cycles = try XCTUnwrap(whoop["cycles"] as? [[String: Any]])
        XCTAssertEqual(cycles.compactMap { $0["step_count"] as? Int }, [0, 9_876])
        XCTAssertFalse(data.toObsidianBases().contains("whoop_cycle_step_count:"))
        XCTAssertEqual(data.activity.steps, 1)
        XCTAssertTrue(data.toMarkdown().contains("Steps (cycle)"))
        XCTAssertTrue(try data.toCSVThrowing().contains("WHOOP Cycle,Cycle Record,"))
    }

    private func cycleExport(_ counts: [JSONValue?]) throws -> (HealthData, ExternalDailyRecord) {
        let cycles: [JSONValue] = counts.enumerated().map { index, count in
            var object: [String: JSONValue] = [
                "id": .number(Double(index + 1)),
                "start": .string("2026-03-14T17:00:00Z"),
                "end": index == 0 ? .string("2026-03-15T08:00:00Z") : .null,
                "timezone_offset": .string("Z")
            ]
            if let count { object["step_count"] = count }
            return .object(object)
        }
        let record = ExternalDailyRecord(
            provider: .whoop, date: "2026-03-15", fetchedAt: ExportFixtures.referenceDate,
            payloads: [ExternalProviderPayload(
                name: "cycles", endpoint: "https://redacted.invalid/cycle", statusCode: 200,
                data: .object(["records": .array(cycles)])
            )]
        )
        var data = ExportFixtures.whoopDay
        data.providers = try XCTUnwrap(HealthProviderSections.normalized(from: [record], whoopResources: [.cycles]))
        return (data, record)
    }

    func testHistoricalWHOOPV1DecodesAndSelectionDoesNotUpgradeItsGrammar() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let bytes = try Data(contentsOf: root.appendingPathComponent(
            "packages/contracts/proposals/provider-sections-v1/fixtures/whoop-complete.providers.json"
        ))
        let decoded = try JSONDecoder().decode(HealthProviderSections.self, from: bytes)
        let old = try XCTUnwrap(decoded.whoop)
        XCTAssertEqual(old.schemaVersion, 1)
        XCTAssertNil(old.cycles.first?.stepCount)
        let selected = try XCTUnwrap(old.selectingResources([.cycles]))
        XCTAssertEqual(selected.schemaVersion, 1)
        XCTAssertNil(selected.cycles.first?.stepCount)
        let original = try JSONSerialization.jsonObject(with: bytes) as? NSDictionary
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? NSDictionary
        XCTAssertEqual(encoded, original)
    }

    func testWHOOPV2SnapshotRoundTripsAndDisabledCyclesDoNotRetainSteps() throws {
        let (data, _) = try cycleExport([.number(0)])
        let decoded = try JSONDecoder().decode(HealthData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded.providers?.whoop?.schemaVersion, 2)
        XCTAssertEqual(decoded.providers?.whoop?.cycles.first?.stepCount, 0)
        let selected = try XCTUnwrap(decoded.providers?.whoop?.selectingResources([.recovery]))
        XCTAssertTrue(selected.cycles.isEmpty)
        XCTAssertFalse(selected.flatScalars.contains { $0.definition.key == "whoop_cycle_step_count" })
        var providerOnly = decoded
        providerOnly.activity = ActivityData()
        XCTAssertFalse(providerOnly.hasAnyData)
    }

    func testTypedCycleStepsAreNotLegalInWHOOPV1AndUnknownVersionsAreRejected() throws {
        let (data, _) = try cycleExport([.number(0)])
        let bytes = try JSONEncoder().encode(try XCTUnwrap(data.providers))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        for version in [1, 3] {
            var object = original
            var whoop = try XCTUnwrap(object["whoop"] as? [String: Any])
            whoop["schema_version"] = version
            object["whoop"] = whoop
            XCTAssertThrowsError(try JSONDecoder().decode(
                HealthProviderSections.self, from: JSONSerialization.data(withJSONObject: object)
            ))
        }
    }

    func testFoundationJSONNumbersZeroAndOneRemainNumbersDuringNormalization() throws {
        let decoded = try JSONSerialization.jsonObject(with: Data(#"{"records":[{"id":1,"start":"2026-03-15T09:00:00Z","step_count":1,"score":{"strain":0}}]}"#.utf8))
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            payloads: [
                ExternalProviderPayload(
                    name: "cycles",
                    endpoint: "https://redacted.invalid/cycles",
                    statusCode: 200,
                    data: JSONValue(any: decoded)
                )
            ]
        )

        let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record])?.whoop)
        XCTAssertEqual(whoop.cycles.first?.id, "1")
        XCTAssertEqual(whoop.cycles.first?.strainScore, 0)
        XCTAssertEqual(whoop.cycles.first?.stepCount, 1)
        XCTAssertEqual(whoop.resources.first { $0.resource == .cycles }?.status, .success)
    }

    func testCompleteNormalizationPreservesTypedSemanticsAndDeterministicOrdering() throws {
        let whoop = try XCTUnwrap(ExportFixtures.whoopDay.providers?.whoop)

        XCTAssertEqual(whoop.schema, "healthmd.provider.whoop_daily")
        XCTAssertEqual(whoop.schemaVersion, 2)
        XCTAssertEqual(whoop.captureStatus, .complete)
        XCTAssertEqual(whoop.resources.map(\.resource), [.cycles, .recovery, .sleep, .workouts, .body])
        XCTAssertEqual(whoop.resources.map(\.recordCount), [1, 1, 1, 1, 1])
        XCTAssertTrue(whoop.recordCountsAreValid)
        XCTAssertEqual(whoop.cycles.first?.id, "101")
        XCTAssertEqual(whoop.recoveries.first?.cycleID, "101")
        XCTAssertEqual(whoop.recoveries.first?.sleepID, "202")
        XCTAssertEqual(whoop.sleep.first?.id, "202")
        XCTAssertEqual(whoop.sleep.first?.cycleID, "101")
        XCTAssertEqual(whoop.sleep.first?.totalSleepMilliseconds, 24_300_750)
        XCTAssertEqual(whoop.sleep.first?.lightSleepMilliseconds, 12_600_125)
        XCTAssertEqual(whoop.sleep.first?.recentNapAdjustmentMilliseconds, -900_000)
        XCTAssertEqual(whoop.workouts.first?.sportName, "running")

        let first = try ExportFixtures.whoopDay.toJSONThrowing(outputFormatting: [.sortedKeys])
        let second = try ExportFixtures.whoopDay.toJSONThrowing(outputFormatting: [.sortedKeys])
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.contains("sport_id"))
        XCTAssertTrue(first.contains("\"sport_name\":\"running\""))
    }

    func testDocumentedWorkoutZoneDurationsPreserveEveryZoneAndExactMilliseconds() throws {
        let whoop = try workoutSection(score: ["zone_durations": .object([
            "zone_zero_milli": .number(0),
            "zone_one_milli": .number(600_001),
            "zone_two_milli": .number(900_002),
            "zone_three_milli": .number(1_800_003),
            "zone_four_milli": .number(400_004),
            "zone_five_milli": .number(250_005)
        ])])
        let zones = try XCTUnwrap(whoop.workouts.first?.zoneDurations)
        XCTAssertEqual(zones.zoneZeroMilliseconds, 0)
        XCTAssertEqual(zones.zoneOneMilliseconds, 600_001)
        XCTAssertEqual(zones.zoneTwoMilliseconds, 900_002)
        XCTAssertEqual(zones.zoneThreeMilliseconds, 1_800_003)
        XCTAssertEqual(zones.zoneFourMilliseconds, 400_004)
        XCTAssertEqual(zones.zoneFiveMilliseconds, 250_005)
        XCTAssertEqual(whoop.captureStatus, .complete)
        XCTAssertTrue(whoop.recordCountsAreValid)
    }

    func testLegacyWorkoutZoneDurationStillDecodesWhenCanonicalKeyIsAbsent() throws {
        let whoop = try workoutSection(score: ["zone_duration": .object([
            "zone_zero_milli": .number(0), "zone_one_milli": .number(600_001)
        ])])
        XCTAssertEqual(whoop.workouts.first?.zoneDurations?.zoneZeroMilliseconds, 0)
        XCTAssertEqual(whoop.workouts.first?.zoneDurations?.zoneOneMilliseconds, 600_001)
    }

    func testCanonicalWorkoutZoneKeyWinsWithoutBlendingLegacyValues() throws {
        let whoop = try workoutSection(score: [
            "zone_durations": .object(["zone_zero_milli": .number(0)]),
            "zone_duration": .object([
                "zone_zero_milli": .number(42), "zone_one_milli": .number(600_001)
            ])
        ])
        XCTAssertEqual(whoop.workouts.first?.zoneDurations?.zoneZeroMilliseconds, 0)
        XCTAssertNil(whoop.workouts.first?.zoneDurations?.zoneOneMilliseconds)
    }

    func testCanonicalNullEmptyOrMalformedZonesDoNotResurrectLegacyData() throws {
        let canonicalValues: [JSONValue] = [.null, .object([:]), .array([]), .string("invalid")]
        for value in canonicalValues {
            let whoop = try workoutSection(score: [
                "zone_durations": value,
                "zone_duration": .object(["zone_zero_milli": .number(42)])
            ])
            XCTAssertNil(whoop.workouts.first?.zoneDurations)
        }
    }

    private func workoutSection(score: [String: JSONValue]) throws -> WHOOPDailyProviderSection {
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            fetchedAt: ExportFixtures.referenceDate,
            payloads: [ExternalProviderPayload(
                name: "workouts",
                endpoint: "https://redacted.invalid/workout",
                statusCode: 200,
                fetchedAt: ExportFixtures.referenceDate,
                data: .object(["records": .array([.object([
                    "id": .string("synthetic-workout"),
                    "start": .string("2026-03-15T16:00:00Z"),
                    "end": .string("2026-03-15T17:00:00Z"),
                    "sport_name": .string("running"),
                    "score_state": .string("SCORED"),
                    "score": .object(score)
                ])])])
            )]
        )
        return try XCTUnwrap(HealthProviderSections.normalized(
            from: [record], whoopResources: [.workouts]
        )?.whoop)
    }

    func testSuccessfulEmptyCaptureIsCompleteAndDoesNotMakeProviderOnlyDayExportable() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_773_556_800)
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            fetchedAt: fetchedAt,
            payloads: ["cycles", "recovery", "sleep", "workouts"].map {
                ExternalProviderPayload(
                    name: $0,
                    endpoint: "https://redacted.invalid/\($0)",
                    statusCode: 200,
                    fetchedAt: fetchedAt,
                    data: .object(["records": .array([])])
                )
            }
        )
        let providers = try XCTUnwrap(HealthProviderSections.normalized(from: [record]))
        let whoop = try XCTUnwrap(providers.whoop)
        XCTAssertEqual(whoop.captureStatus, .complete)
        XCTAssertEqual(whoop.resources.map(\.recordCount), [0, 0, 0, 0])
        XCTAssertTrue(whoop.recordCountsAreValid)
        XCTAssertFalse(record.shouldExport, "Successful-empty typed capture does not create a native sidecar")

        var providerOnly = HealthData(date: ExportFixtures.referenceDate, timeContext: ExportFixtures.timeContext)
        providerOnly.providers = providers
        XCTAssertFalse(providerOnly.hasAnyData, "WHOOP-only days remain non-exportable")
    }

    func testTypedCollectionRetentionStopsAtTenThousandWithSafeFailure() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_773_556_800)
        let records: [JSONValue] = (0..<10_001).map { index in
            .object([
                "id": .string(String(index)),
                "start": .string("2026-03-15T09:00:00Z")
            ])
        }
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            fetchedAt: fetchedAt,
            payloads: [
                ExternalProviderPayload(
                    name: "cycles",
                    endpoint: "https://redacted.invalid/cycles",
                    statusCode: 200,
                    fetchedAt: fetchedAt,
                    data: .object(["records": .array(records)])
                )
            ]
        )

        let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record])?.whoop)
        XCTAssertEqual(whoop.cycles.count, 10_000)
        let cycleResult = try XCTUnwrap(whoop.resources.first { $0.resource == .cycles })
        XCTAssertEqual(cycleResult.status, .failure)
        XCTAssertEqual(cycleResult.recordCount, 10_000)
        XCTAssertEqual(cycleResult.error?.code, "record_limit_reached")
        XCTAssertFalse(cycleResult.error?.retryable ?? true)
        XCTAssertEqual(
            whoop.warnings.filter { $0.code == "record_limit_reached" && $0.resource == .cycles }.count,
            1
        )
        XCTAssertTrue(whoop.recordCountsAreValid)
    }

    func testPartialCaptureKeepsSuccessfulSiblingsAndUsesSafeErrors() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_773_556_800)
        let record = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-03-15",
            fetchedAt: fetchedAt,
            payloads: [
                ExternalProviderPayload(
                    name: "cycles",
                    endpoint: "https://api.prod.whoop.com/developer/v2/cycle?nextToken=secret-cursor",
                    statusCode: 200,
                    fetchedAt: fetchedAt,
                    data: .object(["records": .array([.object([
                        "id": .number(9),
                        "start": .string("2026-03-15T09:00:00Z")
                    ])])])
                ),
                ExternalProviderPayload(
                    name: "recovery",
                    endpoint: "https://api.prod.whoop.com/developer/v2/recovery",
                    statusCode: 403,
                    fetchedAt: fetchedAt,
                    data: .object(["email": .string("private@example.invalid")]),
                    error: "WHOOP permission read:recovery is missing. raw-body-token"
                ),
                ExternalProviderPayload(
                    name: "sleep",
                    endpoint: "https://api.prod.whoop.com/developer/v2/activity/sleep",
                    statusCode: 429,
                    fetchedAt: fetchedAt,
                    error: "WHOOP rate limit reached. Try again in about 37 seconds."
                ),
                ExternalProviderPayload(
                    name: "workouts",
                    endpoint: "https://api.prod.whoop.com/developer/v2/activity/workout",
                    statusCode: 200,
                    fetchedAt: fetchedAt,
                    data: .object(["records": .array([])])
                )
            ],
            warnings: ["Authorization: Bearer secret-token https://private.invalid raw error body"]
        )

        let whoop = try XCTUnwrap(HealthProviderSections.normalized(from: [record])?.whoop)
        XCTAssertEqual(whoop.captureStatus, .partial)
        XCTAssertEqual(whoop.cycles.map(\.id), ["9"])
        XCTAssertEqual(whoop.resources.first { $0.resource == .cycles }?.recordCount, 1)
        XCTAssertEqual(whoop.resources.first { $0.resource == .recovery }?.status, .skipped)
        XCTAssertEqual(whoop.resources.first { $0.resource == .recovery }?.error?.code, "missing_scope")
        XCTAssertEqual(whoop.resources.first { $0.resource == .sleep }?.error?.code, "rate_limited")
        XCTAssertEqual(whoop.resources.first { $0.resource == .sleep }?.error?.retryAfterSeconds, 37)
        XCTAssertEqual(whoop.resources.first { $0.resource == .workouts }?.status, .success)
        XCTAssertTrue(whoop.recordCountsAreValid)

        let encoded = try JSONEncoder().encode(HealthProviderSections(whoop: whoop))
        let text = String(decoding: encoded, as: UTF8.self)
        for forbidden in ["secret-token", "secret-cursor", "private@example.invalid", "private.invalid", "raw-body-token", "Authorization", "endpoint", "headers", "cursor"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), "Leaked \(forbidden)")
        }
    }

    func testAmbiguousRecordScalarsAreOmittedButRepeatedRecordsRemainStructured() throws {
        let original = try XCTUnwrap(ExportFixtures.whoopDay.providers?.whoop)
        let duplicate = try XCTUnwrap(original.recoveries.first)
        let whoop = WHOOPDailyProviderSection(
            captureStatus: original.captureStatus,
            fetchedAt: original.fetchedAt,
            resources: original.resources.map {
                $0.resource == .recovery
                    ? WHOOPResourceResult(resource: .recovery, status: .success, recordCount: 2, error: nil)
                    : $0
            },
            cycles: original.cycles,
            recoveries: [duplicate, duplicate],
            sleep: original.sleep,
            workouts: original.workouts,
            body: original.body,
            warnings: original.warnings
        )
        var data = ExportFixtures.whoopDay
        data.providers = HealthProviderSections(whoop: whoop)

        let bases = data.toObsidianBases()
        XCTAssertFalse(bases.contains("whoop_recovery_score_percent:"))
        XCTAssertFalse(bases.contains("whoop_hrv_rmssd_ms:"))
        XCTAssertTrue(bases.contains("whoop_capture_status: complete"))

        let json = try data.toJSONThrowing()
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let providers = try XCTUnwrap(root["providers"] as? [String: Any])
        let object = try XCTUnwrap(providers["whoop"] as? [String: Any])
        XCTAssertEqual((object["recoveries"] as? [Any])?.count, 2)

        let markdown = data.toMarkdown()
        XCTAssertEqual(markdown.components(separatedBy: "| 101 | 202 |").count - 1, 2)
        let csv = try data.toCSVThrowing()
        XCTAssertEqual(csv.components(separatedBy: "WHOOP Recovery,Recovery Record").count - 1, 2)
    }

    func testAllTraditionalFormatsExposeWHOOPWithoutUsingFetchTimeAsMeasurementTime() throws {
        let data = ExportFixtures.whoopDay
        let whoop = try XCTUnwrap(data.providers?.whoop)
        let fetchedAt = try XCTUnwrap(whoop.fetchedAt)

        let json = try data.toJSONThrowing()
        XCTAssertTrue(json.contains("\"providers\""))
        XCTAssertTrue(json.contains("\"healthmd.provider.whoop_daily\""))
        XCTAssertTrue(json.contains("\"hrv_rmssd_ms\""))

        let markdown = data.toMarkdown()
        XCTAssertTrue(markdown.contains("## WHOOP"))
        XCTAssertTrue(markdown.contains("HRV (RMSSD)"))
        XCTAssertFalse(markdown.contains(fetchedAt))

        let bases = data.toObsidianBases()
        XCTAssertTrue(bases.contains("schema_version: 10"))
        XCTAssertTrue(bases.contains("whoop_capture_status: complete"))
        XCTAssertTrue(bases.contains("whoop_hrv_rmssd_ms: 54.3"))

        let csv = try data.toCSVThrowing()
        XCTAssertTrue(csv.hasPrefix("Date,Category,Metric,Value,Unit,Timestamp\n"))
        XCTAssertTrue(csv.contains("WHOOP Recovery,HRV (RMSSD),54.3,ms,"))
        XCTAssertTrue(csv.contains("WHOOP Sleep,Sleep Record,"))
        XCTAssertTrue(csv.contains("WHOOP Workout,Workout Record,"))
        XCTAssertTrue(csv.contains("WHOOP Body,Body Snapshot,"))
        let bodyRows = csv.split(separator: "\n").filter { $0.contains("WHOOP Body") }
        XCTAssertTrue(bodyRows.allSatisfy { $0.hasSuffix(",") })
        let recoveryRows = csv.split(separator: "\n").filter { $0.contains("WHOOP Recovery") }
        XCTAssertTrue(recoveryRows.allSatisfy { $0.hasSuffix(",") })
        XCTAssertFalse(csv.contains(",\(fetchedAt)"))
    }

    func testProviderFlatDictionaryHasNoRollupsAndRMSSDIsNotSDNN() {
        let entries = HealthMetricDataDictionary.entries(includeProviderEntries: true)
            .filter { $0.metricId == "provider.whoop" }
        XCTAssertEqual(entries.count, WHOOPFlatMetricDefinition.all.count)
        XCTAssertTrue(entries.allSatisfy { $0.rollup.periods.isEmpty && $0.rollup.primary == "none" })
        let hrv = entries.first { $0.canonicalKey == "whoop_hrv_rmssd_ms" }
        XCTAssertEqual(hrv?.displayName, "WHOOP HRV (RMSSD)")
        XCTAssertFalse(entries.contains { $0.canonicalKey == "hrv_ms" || $0.displayName.localizedCaseInsensitiveContains("SDNN") })
    }

    func testHistoricalProviderFreeHealthDataStillDecodes() throws {
        let legacy = """
        {
          "date": 1773532800,
          "timeContext": {"calendarTimeZoneIdentifier":"UTC"},
          "activity": {"steps": 123},
          "healthKitRecordCaptureStatus": "legacyUnavailable"
        }
        """
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HealthData.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.providers)
        XCTAssertEqual(decoded.activity.steps, 123)
    }
}

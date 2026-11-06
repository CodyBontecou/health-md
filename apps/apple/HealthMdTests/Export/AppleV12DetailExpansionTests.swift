import XCTest
import HealthKit
@testable import HealthMd

/// apple-v12: the Night begins successor selected only by explicit per-category Detailed
/// overrides. apple-v8 and apple-v11 bytes must never change.
final class AppleV12DetailExpansionTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private var activityDetailed: AppleExportDetailPolicy {
        AppleExportDetailPolicy.summary.settingCompatibilityDetail(.detailed, for: .activity)
    }

    // MARK: - Policy selection

    func testUniformPresetsNeverSelectAppleV12() {
        for policy in [AppleExportDetailPolicy.summary, .detailedTimeSeries, .archiveOnly, .lossless] {
            XCTAssertFalse(policy.selectsAppleV12)
            XCTAssertFalse(policy.requiresAppleV12PeerSupport)
            for group in ExportDetailGroup.allCases {
                XCTAssertFalse(policy.includesDetailSamples(for: group, sleepDayAttribution: nil))
            }
        }
    }

    func testExplicitDetailedExpansionOverrideSelectsAppleV12() {
        for group in ExportDetailGroup.appleV12ExpansionGroups {
            let policy = AppleExportDetailPolicy.summary.settingCompatibilityDetail(.detailed, for: group)
            XCTAssertTrue(policy.selectsAppleV12, "\(group)")
            XCTAssertTrue(policy.includesDetailSamples(for: group, sleepDayAttribution: nil))
            XCTAssertTrue(policy.requiresAppleV12PeerSupport)
        }
        XCTAssertEqual(ExportDetailGroup.appleV12ExpansionGroups,
                       [.activity, .nutrition, .mobility, .reproductiveHealth, .mindfulness, .body, .vitals])
    }

    func testSleepHeartAndWorkoutOverridesStayAppleV8() {
        for group in [ExportDetailGroup.sleep, .heart, .workouts] {
            let policy = AppleExportDetailPolicy.detailedTimeSeries.settingCompatibilityDetail(.detailed, for: group)
            XCTAssertFalse(policy.selectsAppleV12, "\(group)")
            XCTAssertFalse(policy.requiresAppleV12PeerSupport)
        }
        // A Summary override on an expansion group selects nothing new either.
        let summaryOverride = AppleExportDetailPolicy.detailedTimeSeries.settingCompatibilityDetail(.summary, for: .activity)
        XCTAssertFalse(summaryOverride.selectsAppleV12)
        XCTAssertTrue(summaryOverride.requiresAppleV12PeerSupport, "older per-group peers cannot decode activity")
    }

    func testOtherGroupsFollowTheirResolvedDetailOnceAppleV12IsSelected() {
        let policy = AppleExportDetailPolicy.detailedTimeSeries
            .settingCompatibilityDetail(.detailed, for: .vitals)
            .settingCompatibilityDetail(.summary, for: .nutrition)
        XCTAssertTrue(policy.includesDetailSamples(for: .vitals, sleepDayAttribution: .nightBegins))
        XCTAssertTrue(policy.includesDetailSamples(for: .activity, sleepDayAttribution: nil), "default resolves Detailed")
        XCTAssertFalse(policy.includesDetailSamples(for: .nutrition, sleepDayAttribution: nil))
        XCTAssertFalse(policy.includesDetailSamples(for: .heart, sleepDayAttribution: nil), "heart has no detailSamples")
    }

    func testMorningEndsKeepsAppleV11WithoutExpansion() {
        XCTAssertTrue(activityDetailed.selectsAppleV12)
        XCTAssertFalse(activityDetailed.selectsAppleV12(sleepDayAttribution: .morningEnds))
        XCTAssertFalse(activityDetailed.includesDetailSamples(for: .activity, sleepDayAttribution: .morningEnds))

        var record = ExportFixtures.appleV12DetailDay
        record = HealthData(date: record.date,
                            timeContext: ExportTimeContext(timeZone: utc, sleepDayAttribution: .morningEnds),
                            activity: record.activity, compatibilityDetailProfile: .appleV12)
        XCTAssertFalse(record.exportsAppleV12DetailExpansion)
        XCTAssertNil(record.exportSnapshot(customization: FormatCustomization()).detailExpansion)

        let sanitized = ConnectedExportDetailPolicy.sanitized(record, detailPolicy: activityDetailed)
        XCTAssertNil(sanitized.compatibilityDetailProfile)
        XCTAssertTrue(sanitized.activity.detailSamples.isEmpty)
    }

    // MARK: - Sanitizer

    func testSanitizerKeepsOnlyResolvedDetailedGroupsAndMarksTheProfile() {
        let source = ExportFixtures.appleV12DetailDay
        let sanitized = ConnectedExportDetailPolicy.sanitized(source, detailPolicy: activityDetailed)
        XCTAssertEqual(sanitized.compatibilityDetailProfile, .appleV12)
        XCTAssertEqual(sanitized.activity.detailSamples, source.activity.detailSamples)
        for group in ExportDetailGroup.appleV12ExpansionGroups where group != .activity {
            XCTAssertTrue(sanitized.detailSamples(for: group).isEmpty, "\(group)")
        }

        for policy in [AppleExportDetailPolicy.summary, .detailedTimeSeries, .lossless] {
            let v8 = ConnectedExportDetailPolicy.sanitized(source, detailPolicy: policy)
            XCTAssertNil(v8.compatibilityDetailProfile)
            for group in ExportDetailGroup.appleV12ExpansionGroups {
                XCTAssertTrue(v8.detailSamples(for: group).isEmpty)
            }
        }
    }

    // MARK: - Writers

    func testAppleV8BytesAreUnchangedByCapturedSamplesWithoutTheProfile() throws {
        let config = FormatCustomization()
        // Captured samples without the profile marker (an unsanitized or v8 path) render the
        // apple-v8 projection byte-for-byte.
        let v8 = ExportFixtures.appleV12DetailDay.withoutDetailExpansion()
        var unmarked = ExportFixtures.appleV12DetailDay
        unmarked.compatibilityDetailProfile = nil
        XCTAssertEqual(try unmarked.toJSONThrowing(customization: config), try v8.toJSONThrowing(customization: config))
        XCTAssertEqual(unmarked.toCSV(customization: config), v8.toCSV(customization: config))
        XCTAssertEqual(unmarked.toMarkdown(customization: config), v8.toMarkdown(customization: config))
        XCTAssertEqual(unmarked.toObsidianBases(customization: config), v8.toObsidianBases(customization: config))
        let json = try v8.toJSONThrowing(customization: config)
        XCTAssertFalse(json.contains("detailSamples"))
        XCTAssertFalse(json.contains("schema_profile"))
        XCTAssertTrue(json.contains("\"schema_version\" : 8"))
    }

    func testJSONEmitsAppleV12HeaderAndExactDetailSamples() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(ExportFixtures.appleV12DetailDay.toJSONThrowing(customization: FormatCustomization()).utf8)
        ) as? [String: Any])
        XCTAssertEqual(json["schema"] as? String, "healthmd.health_data")
        XCTAssertEqual(json["schema_version"] as? Int, 12)
        XCTAssertEqual(json["schema_profile"] as? String, "apple-v12")

        let activity = try XCTUnwrap(json["activity"] as? [String: Any])
        XCTAssertEqual(activity["steps"] as? Int, 12500, "daily summaries are unchanged")
        let samples = try XCTUnwrap(activity["detailSamples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0] as NSDictionary, [
            "metric": "steps",
            "healthKitType": "HKQuantityTypeIdentifierStepCount",
            "timestamp": "2026-03-15T08:00:00.000000000Z",
            "endDate": "2026-03-15T08:15:00.000000000Z",
            "value": 1200,
            "unit": "count",
            "sourceUUID": "00000000-0000-0000-0000-0000000000A1",
            "source": "com.apple.health",
        ] as NSDictionary)
        XCTAssertEqual(samples[1] as NSDictionary, [
            "metric": "stand_hours",
            "healthKitType": "HKCategoryTypeIdentifierAppleStandHour",
            "timestamp": "2026-03-15T09:00:00.000000000Z",
            "endDate": "2026-03-15T10:00:00.000000000Z",
            "categoryValue": "stood",
            "sourceUUID": "00000000-0000-0000-0000-0000000000A1",
            "source": "com.apple.health",
        ] as NSDictionary)

        let vitals = try XCTUnwrap((json["vitals"] as? [String: Any])?["detailSamples"] as? [[String: Any]])
        XCTAssertEqual(vitals.first?["unit"] as? String, "degC")
        XCTAssertNil(vitals.first?["sourceUUID"])
        XCTAssertNil(vitals.first?["source"])
        for key in ["body", "nutrition", "mindfulness", "mobility", "reproductiveHealth"] {
            XCTAssertEqual(((json[key] as? [String: Any])?["detailSamples"] as? [Any])?.count, 1, key)
        }
        XCTAssertNil((json["heart"] as? [String: Any])?["detailSamples"])
    }

    func testJSONCreatesTheCategoryObjectForSamplesWithoutASummary() throws {
        var day = HealthData(date: ExportFixtures.referenceDate, timeContext: ExportFixtures.timeContext)
        day.body.detailSamples = ExportFixtures.appleV12DetailDay.body.detailSamples
        day.compatibilityDetailProfile = .appleV12
        let json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(day.toJSONThrowing(customization: FormatCustomization()).utf8)
        ) as? [String: Any])
        XCTAssertEqual((json["body"] as? [String: Any])?.keys.sorted(), ["detailSamples"])
    }

    func testCSVEmitsOneRowPerSampleAfterTheAppleV8Rows() throws {
        let config = FormatCustomization()
        let day = ExportFixtures.appleV12DetailDay
        let date = day.exportSnapshot(customization: config).dateString
        let csv = day.toCSV(customization: config)
        let lines = csv.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("\(date),Metadata,schema_version,12,,"))
        XCTAssertTrue(lines.contains("\(date),Metadata,schema_profile,apple-v12,,"))
        XCTAssertFalse(lines.contains("\(date),Metadata,schema_version,8,,"))

        let detailRows = lines.filter { $0.contains("Detail Sample,") }
        XCTAssertEqual(detailRows, [
            "\(date),Activity,Steps Detail Sample,1200,count,2026-03-15T08:00:00.000000000Z",
            "\(date),Activity,Stand Hour Detail Sample,stood,category,2026-03-15T09:00:00.000000000Z",
            "\(date),Vitals,Body Temperature Detail Sample,36.6,degC,2026-03-15T07:00:00.000000000Z",
            "\(date),Body,Weight Detail Sample,75,kg,2026-03-15T07:30:00.000000000Z",
            "\(date),Nutrition,Water Detail Sample,0.5,L,2026-03-15T12:00:00.000000000Z",
            "\(date),Mindfulness,Mindful Session Detail Sample,not_applicable,category,2026-03-15T06:00:00.000000000Z",
            "\(date),Mobility,Walking Speed Detail Sample,1.4,m/s,2026-03-15T10:00:00.000000000Z",
            "\(date),Reproductive Health,Menstrual Flow Detail Sample,medium,category,2026-03-15T00:00:00.000000000Z",
        ])
        // Apart from the identity rows, every apple-v8 row is unchanged and precedes the samples.
        let v8Lines = day.withoutDetailExpansion().toCSV(customization: config).components(separatedBy: "\n")
        let firstDetail = try XCTUnwrap(lines.firstIndex { $0.contains("Detail Sample,") })
        var successorPrefix = Array(lines[..<firstDetail])
        successorPrefix.removeAll { $0 == "\(date),Metadata,schema_profile,apple-v12,," }
        successorPrefix = successorPrefix.map {
            $0 == "\(date),Metadata,schema_version,12,," ? "\(date),Metadata,schema_version,8,," : $0
        }
        XCTAssertEqual(successorPrefix, Array(v8Lines.dropLast()))
    }

    func testMarkdownAndBasesDeclareAppleV12AndMarkdownAddsCollapsedTables() {
        let config = FormatCustomization()
        let day = ExportFixtures.appleV12DetailDay
        let markdown = day.toMarkdown(customization: config)
        let frontmatter = markdown.components(separatedBy: "\n---")[0]
        XCTAssertTrue(frontmatter.contains("\nschema_version: 12\n"))
        XCTAssertTrue(frontmatter.contains("\nschema_profile: apple-v12\n"))
        XCTAssertTrue(markdown.contains(" Detail Samples\n"))
        XCTAssertTrue(markdown.contains("<summary>Activity Detail Samples (2 samples)</summary>"))
        XCTAssertTrue(markdown.contains("| Start | End | Metric | Value | Unit | Source |"))
        XCTAssertTrue(markdown.contains("| Steps | 1200.0 | count | com.apple.health |"))
        XCTAssertTrue(markdown.contains("| Stand Hour | stood |  | com.apple.health |"))

        let bases = day.toObsidianBases(customization: config)
        XCTAssertTrue(bases.contains("\nschema_version: 12\n"))
        XCTAssertTrue(bases.contains("\nschema_profile: apple-v12\n"))
        XCTAssertFalse(bases.contains("Detail Samples"))
    }

    // MARK: - Model compatibility

    func testOlderPayloadsDecodeAndAppleV8PayloadsEncodeWithoutNewKeys() throws {
        let activity = try JSONDecoder().decode(ActivityData.self, from: Data(#"{"steps":5}"#.utf8))
        XCTAssertEqual(activity.steps, 5)
        XCTAssertTrue(activity.detailSamples.isEmpty)
        let vitals = try JSONDecoder().decode(VitalsData.self, from: Data(#"{"respiratoryRateAvg":14}"#.utf8))
        XCTAssertTrue(vitals.detailSamples.isEmpty)
        let mindfulness = try JSONDecoder().decode(MindfulnessData.self, from: Data(#"{"mindfulSessions":1}"#.utf8))
        XCTAssertTrue(mindfulness.detailSamples.isEmpty)

        let v8 = String(decoding: try JSONEncoder().encode(ExportFixtures.fullDay), as: UTF8.self)
        XCTAssertFalse(v8.contains("detailSamples"))
        XCTAssertFalse(v8.contains("compatibilityDetailProfile"))

        let encoded = try JSONEncoder().encode(ExportFixtures.appleV12DetailDay)
        let decoded = try JSONDecoder().decode(HealthData.self, from: encoded)
        XCTAssertEqual(decoded.compatibilityDetailProfile, .appleV12)
        for group in ExportDetailGroup.appleV12ExpansionGroups {
            XCTAssertEqual(decoded.detailSamples(for: group), ExportFixtures.appleV12DetailDay.detailSamples(for: group))
        }
    }

    func testMetricSelectionDropsSamplesForDeselectedMetrics() {
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.toggleMetric("steps")
        selection.toggleMetric("mindful_minutes")
        let filtered = ExportFixtures.appleV12DetailDay.filtered(by: selection)
        XCTAssertEqual(filtered.activity.detailSamples.map(\.metric), ["steps"])
        XCTAssertEqual(filtered.mindfulness.detailSamples.map(\.metric), ["mindful_sessions"],
                       "either mindful metric retains the session sample")
        XCTAssertTrue(filtered.body.detailSamples.isEmpty)
        XCTAssertTrue(filtered.vitals.detailSamples.isEmpty)
        XCTAssertEqual(filtered.compatibilityDetailProfile, .appleV12)
    }

    @MainActor
    func testCatalogUnitsAndCategoryValuesMatchHealthKitSummaries() {
        let adapter = SystemHealthStoreAdapter()
        let definitions = Dictionary(uniqueKeysWithValues: HealthMetrics.all.map { ($0.id, $0) })
        for entry in AppleDetailSampleCatalog.entries {
            XCTAssertEqual(definitions[entry.metricID]?.healthKitIdentifier, entry.healthKitType, entry.metricID)
            for metricID in entry.selectionMetricIDs {
                XCTAssertEqual(definitions[metricID]?.healthKitIdentifier, entry.healthKitType, metricID)
            }
            if let unit = entry.unit {
                XCTAssertEqual(
                    adapter.unitMap[HKQuantityTypeIdentifier(rawValue: entry.healthKitType)]?.unitString,
                    unit,
                    entry.metricID
                )
            }
        }
        func value(_ type: String, _ raw: Int) -> String {
            AppleDetailSampleCatalog.categoryValueString(healthKitType: "HKCategoryTypeIdentifier\(type)", rawValue: raw)
        }
        XCTAssertEqual(value("AppleStandHour", HKCategoryValueAppleStandHour.stood.rawValue), "stood")
        XCTAssertEqual(value("AppleStandHour", HKCategoryValueAppleStandHour.idle.rawValue), "idle")
        XCTAssertEqual(value("MenstrualFlow", HKCategoryValueMenstrualFlow.heavy.rawValue), "heavy")
        XCTAssertEqual(value("MenstrualFlow", HKCategoryValueMenstrualFlow.none.rawValue), "none")
        XCTAssertEqual(value("OvulationTestResult", HKCategoryValueOvulationTestResult.luteinizingHormoneSurge.rawValue), "positive")
        XCTAssertEqual(value("CervicalMucusQuality", HKCategoryValueCervicalMucusQuality.eggWhite.rawValue), "egg_white")
        XCTAssertEqual(value("MindfulSession", HKCategoryValue.notApplicable.rawValue), "not_applicable")
        XCTAssertEqual(value("MindfulSession", 9), "raw_9")
    }

    // MARK: - Capture

    @MainActor
    func testCaptureReadsStartOwnedSourceSamplesOnlyForAppleV12() async throws {
        let store = FakeHealthStore()
        let day = ExportFixtures.referenceDate
        let uuid = UUID()
        store.quantitySampleResults[HKQuantityTypeIdentifier.stepCount.rawValue] = [
            QuantitySampleValue(uuid: UUID(), value: 9, startDate: day.addingTimeInterval(-60),
                                endDate: day.addingTimeInterval(60), sourceBundleIdentifier: "previous.day"),
            QuantitySampleValue(uuid: uuid, value: 120, startDate: day.addingTimeInterval(3600),
                                endDate: day.addingTimeInterval(3900), sourceBundleIdentifier: "com.apple.health"),
            QuantitySampleValue(uuid: uuid, value: 120, startDate: day.addingTimeInterval(3600),
                                endDate: day.addingTimeInterval(3900), sourceBundleIdentifier: "com.apple.health"),
        ]
        store.categorySampleResults[HKCategoryTypeIdentifier.mindfulSession.rawValue] = [
            CategorySampleValue(value: 0, startDate: day.addingTimeInterval(7200), endDate: day.addingTimeInterval(7800),
                                uuid: uuid, sourceBundleIdentifier: "com.example.meditate"),
        ]
        let sut = makeManager(store: store)
        let policy = activityDetailed.settingCompatibilityDetail(.detailed, for: .mindfulness)

        let data = try await sut.fetchHealthData(for: day, detailPolicy: policy, timeZone: utc)
        XCTAssertEqual(data.compatibilityDetailProfile, .appleV12)
        let expected = DetailSample(metric: "steps", healthKitType: "HKQuantityTypeIdentifierStepCount",
                                    startDate: day.addingTimeInterval(3600), endDate: day.addingTimeInterval(3900),
                                    value: 120, unit: "count", sourceUUID: uuid, source: "com.apple.health")
        XCTAssertEqual(data.activity.detailSamples, [expected, expected], "one entry per sample; no dedupe")
        XCTAssertEqual(data.mindfulness.detailSamples, [DetailSample(
            metric: "mindful_sessions", healthKitType: "HKCategoryTypeIdentifierMindfulSession",
            startDate: day.addingTimeInterval(7200), endDate: day.addingTimeInterval(7800),
            categoryValue: "not_applicable", sourceUUID: uuid, source: "com.example.meditate"
        )])
        XCTAssertTrue(data.body.detailSamples.isEmpty)

        let presetStore = FakeHealthStore()
        presetStore.quantitySampleResults = store.quantitySampleResults
        let preset = try await makeManager(store: presetStore)
            .fetchHealthData(for: day, detailPolicy: .lossless, timeZone: utc)
        XCTAssertNil(preset.compatibilityDetailProfile)
        XCTAssertTrue(preset.activity.detailSamples.isEmpty)
        XCTAssertFalse(presetStore.quantitySampleQueries.contains { $0.identifier == HKQuantityTypeIdentifier.stepCount.rawValue })
    }

    @MainActor
    func testCaptureDetailFailureIsPartialAndCancellationPropagates() async throws {
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 100
        store.errorsForQuantitySamples[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "test", code: 1)
        let data = try await makeManager(store: store)
            .fetchHealthData(for: ExportFixtures.referenceDate, detailPolicy: activityDetailed, timeZone: utc)
        XCTAssertEqual(data.activity.steps, 100, "summary survives a detail failure")
        XCTAssertTrue(data.partialFailures.contains { $0.dataType == "activity detail samples" })

        let cancelling = FakeHealthStore()
        cancelling.errorsForQuantitySamples[HKQuantityTypeIdentifier.stepCount.rawValue] = CancellationError()
        do {
            _ = try await makeManager(store: cancelling)
                .fetchHealthData(for: ExportFixtures.referenceDate, detailPolicy: activityDetailed, timeZone: utc)
            XCTFail("cancellation must propagate")
        } catch is CancellationError {}
    }

    // MARK: - Connected peers and strict receivers

    func testPeersWithoutAppleV12SupportAreRefused() throws {
        let current = SyncPeerCapabilities.current(platform: .macOS, installationID: UUID())
        XCTAssertTrue(current.supportsAppleV12DetailExpansion)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        object.removeValue(forKey: "supportsAppleV12DetailExpansion")
        let perGroupOnly = try JSONDecoder().decode(SyncPeerCapabilities.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(perGroupOnly.supportsPerGroupExportDetail)
        XCTAssertFalse(perGroupOnly.supportsAppleV12DetailExpansion)

        let bodySummary = AppleExportDetailPolicy.detailedTimeSeries.settingCompatibilityDetail(.summary, for: .body)
        let sleepOnly = AppleExportDetailPolicy.summary.settingCompatibilityDetail(.detailed, for: .sleep)
        XCTAssertTrue(current.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: activityDetailed))
        XCTAssertFalse(perGroupOnly.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: activityDetailed))
        XCTAssertFalse(perGroupOnly.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: bodySummary))
        XCTAssertTrue(perGroupOnly.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false, detailPolicy: sleepOnly))
    }

    func testStrictReceiversAcceptAppleV12AndStillRejectUnknownIdentities() throws {
        XCTAssertTrue(AppleDetailExpansionSchema.isAcceptedNightBeginsDailyIdentity(schemaVersion: 8, schemaProfile: nil))
        XCTAssertTrue(AppleDetailExpansionSchema.isAcceptedNightBeginsDailyIdentity(schemaVersion: 12, schemaProfile: "apple-v12"))
        for (version, profile) in [(12, nil), (8, "apple-v12"), (11, "apple-v11"), (13, "apple-v12"), (9, nil)] as [(Int, String?)] {
            XCTAssertFalse(AppleDetailExpansionSchema.isAcceptedNightBeginsDailyIdentity(schemaVersion: version, schemaProfile: profile))
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let v12URL = directory.appendingPathComponent("v12.json")
        try Data(ExportFixtures.appleV12DetailDay.toJSONThrowing(customization: FormatCustomization()).utf8).write(to: v12URL)
        let compact = try CanonicalDailyJSONStream.compactValidated(sourceURL: v12URL, expectsLosslessArchive: false)
        compact.remove()

        let unknownURL = directory.appendingPathComponent("v13.json")
        try Data(#"{"schema":"healthmd.health_data","schema_version":13,"schema_profile":"apple-v12"}"#.utf8).write(to: unknownURL)
        XCTAssertThrowsError(try CanonicalDailyJSONStream.compactValidated(sourceURL: unknownURL, expectsLosslessArchive: false))
        let unprofiledURL = directory.appendingPathComponent("v12-bare.json")
        try Data(#"{"schema":"healthmd.health_data","schema_version":12}"#.utf8).write(to: unprofiledURL)
        XCTAssertThrowsError(try CanonicalDailyJSONStream.compactValidated(sourceURL: unprofiledURL, expectsLosslessArchive: false))
    }

    @MainActor
    func testAPIEnvelopeDeclaresAppleV12RecordsAndRefusesMixedBatches() throws {
        let suite = "healthmd.tests.apple-v12.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.exportTimeZoneOverride = utc
        let day = ExportFixtures.referenceDate

        let payload = try APIExportClient.makePayload(
            records: [ExportFixtures.appleV12DetailDay], failedDateDetails: [], settings: settings,
            dateRangeStart: day, dateRangeEnd: day, exportedAt: day, connectedAppsEnabled: false
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["daily_record_schema_version"] as? Int, 12)
        XCTAssertEqual(object["daily_record_schema_profile"] as? String, "apple-v12")
        let record = try XCTUnwrap((object["records"] as? [[String: Any]])?.first)
        XCTAssertEqual(record["schema_version"] as? Int, 12)

        let v8Payload = try APIExportClient.makePayload(
            records: [ExportFixtures.fullDay], failedDateDetails: [], settings: settings,
            dateRangeStart: day, dateRangeEnd: day, exportedAt: day, connectedAppsEnabled: false
        )
        let v8 = try XCTUnwrap(JSONSerialization.jsonObject(with: v8Payload) as? [String: Any])
        XCTAssertEqual(v8["daily_record_schema_version"] as? Int, 8)
        XCTAssertNil(v8["daily_record_schema_profile"])

        XCTAssertThrowsError(try APIExportClient.makePayload(
            records: [ExportFixtures.appleV12DetailDay, ExportFixtures.fullDay], failedDateDetails: [],
            settings: settings, dateRangeStart: day, dateRangeEnd: day, exportedAt: day, connectedAppsEnabled: false
        ))
    }

    func testDailyNotesKeepTheAppleV8Grammar() {
        let note = ExportFixtures.appleV12DetailDay.withoutDetailExpansion()
        XCTAssertNil(note.compatibilityDetailProfile)
        XCTAssertFalse(note.toMarkdown(includeMetadata: false).contains("Detail Samples"))
    }

    @MainActor
    private func makeManager(store: FakeHealthStore) -> HealthKitManager {
        let suiteName = "AppleV12DetailExpansionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: "healthKit.authorizationRequested")
        return HealthKitManager(store: store, userDefaults: defaults)
    }
}

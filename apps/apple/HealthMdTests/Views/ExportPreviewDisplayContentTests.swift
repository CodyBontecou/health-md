import XCTest
@testable import HealthMd

final class ExportPreviewDisplayContentTests: XCTestCase {

    // Retain nested observation state through host-test teardown; see docs/testing/lifecycle-audit.md.
    @MainActor private static var retainedPreviewSettings: [AdvancedExportSettings] = []
    @MainActor private static var retainedPreviewConfigurations: [ExportPreviewOperationConfiguration] = []

    @MainActor
    func testAcceptedMorningPreviewDistinguishesFreshProfileFromDurableNilPin() async throws {
        let suite = "MorningPreviewAuthority.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        for captureWasFrozen in [false, true] {
            let source = AdvancedExportSettings(userDefaults: defaults)
            Self.retainedPreviewSettings.append(source)
            source.exportFormats = [.markdown]
            source.detailPolicy = .lossless
            source.generateRangeSummary = true
            source.executionAppleExportEngineAuthorityIsFrozen = true
            source.executionAppleExportEnginePin = nil
            source.executionSleepCaptureContext = captureWasFrozen ? context : nil
            source.executionSleepCaptureContextIsFrozen = captureWasFrozen

            let accepted = try AcceptedExternalProviderFileCapture(settings: source,
                context: context, healthSubfolder: "", includesProviders: false, providers: nil)
            let settings = accepted.snapshot.makeAdvancedExportSettings()
            Self.retainedPreviewSettings.append(settings)
            XCTAssertTrue(settings.executionSleepCaptureContextIsFrozen,
                "Accepting capture freezes selection, independently of durable renderer authority")
            settings.executionSleepCaptureContextIsFrozen = captureWasFrozen
            let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings,
                healthSubfolder: accepted.snapshot.healthSubfolder, calendarTimeZone: zone, surface: .preview)
            XCTAssertEqual(snapshot.sleepCaptureContext, context)
            XCTAssertEqual(snapshot.detailPolicy, .lossless)
            XCTAssertTrue(snapshot.generateRangeSummary)
            if captureWasFrozen {
                XCTAssertNil(snapshot.appleExportEnginePin,
                    "A durable nil pin must never acquire successor authority during replay")
                XCTAssertThrowsError(try snapshot.recoveredSleepCaptureContext())
            } else {
                XCTAssertTrue(snapshot.appleExportEnginePin?.hasExplicitWakeDateContracts == true,
                    "A live profile with a nil engine pin must still admit a fresh Morning preview")
                XCTAssertEqual(try snapshot.recoveredSleepCaptureContext(), context)
            }
        }
    }

    @MainActor
    func testAcceptedPreviewKeepsCaptureScopeAndDestinationPathsAcrossLivePreferenceMutation() async throws {
        let suite = "FrozenPreviewConfiguration.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedPreviewSettings.append(source)
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        source.executionSleepCaptureContext = context
        source.executionSleepCaptureContextIsFrozen = true
        source.exportTimeZoneOverride = zone
        source.exportFormats = [.json, .csv]
        source.detailPolicy = .lossless
        source.organizeFormatsIntoFolders = true
        source.folderStructure = "yyyy/MM"
        source.dailyNoteInjection.folderPath = "Daily/Accepted"
        source.generateRangeSummary = false
        source.archiveExportFiles = false
        source.metricSelection.enabledMetrics = ["steps"]
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(source,
            healthSubfolder: "Accepted/Health", calendarTimeZone: zone, surface: .preview)
        XCTAssertTrue(snapshot.appleExportEnginePin?.hasExplicitWakeDateContracts == true)
        let root = URL(fileURLWithPath: "/tmp/AcceptedPreviewVault", isDirectory: true)
        let configuration = ExportPreviewOperationConfiguration(snapshot: snapshot,
            destinationRootName: "AcceptedVault", vaultURL: root)
        Self.retainedPreviewConfigurations.append(configuration)
        let date = ExportFixtures.referenceDate
        let folder = configuration.aggregateFolderPath(for: date, format: .json)
        let summaryFolder = configuration.aggregateSummaryFolderPath(for: date)
        let rollupFolder = configuration.rollupFolderPath(for: .range, format: .json)
        let noteFolder = configuration.dailyNoteFolderPath(for: date)
        let noteURL = configuration.dailyNoteURL(for: date)
        XCTAssertTrue(folder.hasPrefix("AcceptedVault/Accepted/Health/"))
        XCTAssertTrue(noteFolder.contains("Daily/Accepted"))
        var callbacks = 0
        _ = await configuration.fetchRecord(for: date) { receivedDate, accepted in
            callbacks += 1
            source.exportFormats = [.markdown]
            source.detailPolicy = .summary
            source.metricSelection.enabledMetrics = ["sleep_total"]
            source.exportTimeZoneOverride = TimeZone(identifier: "America/Los_Angeles")!
            source.executionSleepCaptureContext = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
            source.folderStructure = "Changed"
            source.organizeFormatsIntoFolders = false
            source.dailyNoteInjection.folderPath = "Daily/Changed"
            await Task.yield()
            XCTAssertEqual(receivedDate, date)
            XCTAssertEqual(accepted.exportFormats, [.json, .csv])
            XCTAssertEqual(accepted.detailPolicy, .lossless)
            XCTAssertEqual(accepted.calendarTimeZoneIdentifier, zone.identifier)
            XCTAssertEqual(try? accepted.recoveredSleepCaptureContext(), context)
            let captured = accepted.makeAdvancedExportSettings()
            Self.retainedPreviewSettings.append(captured)
            XCTAssertEqual(captured.metricSelection.enabledMetrics, ["steps"])
            XCTAssertEqual(captured.exportTimeZoneOverride, zone)
            return nil
        }
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(configuration.scope.maximumRenderedDates, 1)
        XCTAssertEqual(Set(configuration.scope.formats), [.json, .csv])
        XCTAssertFalse(configuration.scope.includesSupplementalFiles)
        XCTAssertEqual(configuration.aggregateFolderPath(for: date, format: .json), folder)
        XCTAssertEqual(configuration.aggregateSummaryFolderPath(for: date), summaryFolder)
        XCTAssertEqual(configuration.rollupFolderPath(for: .range, format: .json), rollupFolder)
        XCTAssertEqual(configuration.dailyNoteFolderPath(for: date), noteFolder)
        XCTAssertEqual(configuration.dailyNoteURL(for: date), noteURL)
        XCTAssertTrue(configuration.matchesVault(root))
        XCTAssertFalse(configuration.matchesVault(URL(fileURLWithPath: "/tmp/ReboundVault")))
        XCTAssertFalse(configuration.matchesVault(nil))
    }

    @MainActor
    func testMorningPreviewFreezesSuccessorBeforeSyntheticCaptureAndNeverUsesHistoricalWriter() async throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Kathmandu"))
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 2)))
        let suite = "MorningPreviewTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = Set(ExportFormat.allCases)
        settings.metricSelection.selectAll()
        settings.detailPolicy = .summary
        settings.generateRangeSummary = true
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.executionSleepCaptureContext = context
        settings.executionSleepCaptureContextIsFrozen = true
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings,
            healthSubfolder: "", calendarTimeZone: zone, surface: .preview)
        XCTAssertEqual(try snapshot.recoveredSleepCaptureContext(), context)
        XCTAssertEqual(snapshot.appleExportEnginePin?.registryVersion, 3)
        XCTAssertEqual(snapshot.operationRollupPeriods, [.range])
        let record = await AppleSleepCaptureContext.pinned.withValue(context) {
            UITestHealthKitFixtures.exportPreviewHealthData(for: date, includeGranularData: false)
        }
        XCTAssertEqual(record.timeContext.sleepDayAttribution, .morningEnds)
        XCTAssertEqual(record.sleep.sessionEnd.map { calendar.startOfDay(for: $0) }, date)
        XCTAssertEqual(record.sleep.sessionStart.map { calendar.startOfDay(for: $0) },
            calendar.date(byAdding: .day, value: -1, to: date))
        let planned = try await AppleLooseDailyExportPreviewPlanner.artifacts(
            healthData: record, settingsSnapshot: snapshot, planner: AppleLooseDailyExportPlanner())
        let artifacts = try XCTUnwrap(planned)
        XCTAssertEqual(Set(artifacts.map(\.format)), Set(ExportFormat.allCases))
        for format in ExportFormat.allCases {
            var singleFormat = snapshot
            singleFormat.exportFormats = [format]
            let single = try await AppleLooseDailyExportPreviewPlanner.artifacts(
                healthData: record, settingsSnapshot: singleFormat, planner: AppleLooseDailyExportPlanner())
            XCTAssertEqual(single?.map(\.format), [format], "Selecting \(format) alone must keep complete attestation")
        }
        for artifact in artifacts {
            XCTAssertEqual(artifact.preview.omittedByteCount, 0)
            XCTAssertTrue(artifact.preview.head.contains("apple-v11"))
        }
        let json = try XCTUnwrap(artifacts.first { $0.format == .json })
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.preview.head.utf8)) as? [String: Any])
        XCTAssertEqual(object["schema_version"] as? Int, 11)
        let range = try HealthRollupRangeRequest(ownerDateIdentifiers: ["2026-07-02"],
            calendarTimeZoneIdentifier: zone.identifier)
        let rollups = try await AppleLooseDailyExportPreviewPlanner.rangeArtifacts(
            healthData: [record], requestedRange: range, settingsSnapshot: snapshot,
            planner: AppleLooseDailyExportPlanner())
        XCTAssertEqual(Set(rollups.map(\.format)), Set(ExportFormat.allCases))
        XCTAssertTrue(rollups.allSatisfy { $0.kind == .rollup })
        XCTAssertEqual(snapshot.operationRollupPeriods, [.range], "Daily preview must not erase range output authority")
        for artifact in rollups {
            XCTAssertTrue(String(decoding: artifact.artifact.inlineData, as: UTF8.self).contains("morning_ends"))
        }
    }

    @MainActor
    func testFilePreviewIncludesTypedWHOOPCaptureInRenderedJSON() async throws {
        let date = Date(timeIntervalSince1970: 1_773_556_800)
        var fetchCount = 0
        let record = await ExportPreviewView.fetchPreviewRecord(
            for: date,
            targetType: .localFile,
            connectedAppsEnabled: true,
            writesExternalProviderSidecars: true,
            fetchHealthData: { HealthData(date: $0, activity: ActivityData(steps: 1)) },
            fetchExternalDailyRecords: { requestedDate in
                XCTAssertEqual(requestedDate, date)
                fetchCount += 1
                return [ExternalDailyRecord(
                    provider: .whoop,
                    date: "2026-03-15",
                    payloads: ["cycles", "recovery", "sleep", "workouts"].map {
                        ExternalProviderPayload(
                            name: $0,
                            endpoint: "https://redacted.invalid/\($0)",
                            statusCode: 200,
                            data: .object(["records": .array([])])
                        )
                    }
                )]
            }
        )
        let enriched = try XCTUnwrap(record)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(enriched.providers?.whoop?.captureStatus, .complete)
        let json = try enriched.toJSONThrowing(outputFormatting: [.sortedKeys])
        XCTAssertTrue(json.contains("healthmd.provider.whoop_daily"))
        XCTAssertEqual(enriched.activity.steps, 1)
    }

    @MainActor
    func testPreviewSkipsProviderFetchWhenPolicyExcludesIt() async {
        let cases: [(ExportPreviewTargetType, Bool, Bool, Bool)] = [
            (.apiEndpoint, true, true, true),
            (.agentDataGateway, true, true, true),
            (.localFile, false, true, true),
            (.localFile, true, false, true),
            (.localFile, true, true, false)
        ]
        for (target, enabled, writesProviders, hasHealthData) in cases {
            var fetchCount = 0
            _ = await ExportPreviewView.fetchPreviewRecord(
                for: Date(timeIntervalSince1970: 0),
                targetType: target,
                connectedAppsEnabled: enabled,
                writesExternalProviderSidecars: writesProviders,
                fetchHealthData: { HealthData(date: $0, activity: hasHealthData ? ActivityData(steps: 1) : ActivityData()) },
                fetchExternalDailyRecords: { _ in fetchCount += 1; return [] }
            )
            XCTAssertEqual(fetchCount, 0, "Unexpected provider fetch for \(target)")
        }
    }

    func testLosslessPreviewScopeShowsAllFourSelectedFormatsForOneDate() {
        let scope = ExportPreviewScope.make(
            selectedFormats: [.markdown, .json, .csv, .obsidianBases],
            losslessEnabled: true
        )

        XCTAssertEqual(scope.maximumRenderedDates, 1)
        XCTAssertEqual(scope.formats, [.csv, .json, .markdown, .obsidianBases])
        XCTAssertFalse(scope.includesSupplementalFiles)
    }

    func testLosslessPreviewScopeShowsEverySelectedFormat() {
        let scope = ExportPreviewScope.make(
            selectedFormats: [.csv, .json],
            losslessEnabled: true
        )

        XCTAssertEqual(scope.formats, [.csv, .json])
    }

    func testStandardPreviewScopePreservesExistingBehavior() {
        let scope = ExportPreviewScope.make(
            selectedFormats: [.markdown, .json, .csv, .obsidianBases],
            losslessEnabled: false
        )

        XCTAssertEqual(scope.maximumRenderedDates, 5)
        XCTAssertEqual(scope.formats, [.csv, .json, .markdown, .obsidianBases])
        XCTAssertTrue(scope.includesSupplementalFiles)
    }

    func testSmallContentRendersUnchanged() {
        let content = "{\"steps\":12500}"

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 128,
            headBytes: 96,
            tailBytes: 32
        )

        XCTAssertEqual(display.text, content)
        XCTAssertEqual(display.originalByteCount, content.utf8.count)
        XCTAssertEqual(display.omittedByteCount, 0)
        XCTAssertFalse(display.isTruncated)
    }

    func testEmptyContentUsesPlaceholder() {
        let display = ExportPreviewDisplayContent.make(from: "")

        XCTAssertEqual(display.text, "(empty file)")
        XCTAssertEqual(display.originalByteCount, 0)
        XCTAssertFalse(display.isTruncated)
    }

    func testLargeContentKeepsHeadAndTailWithTruncationMarker() {
        let content = String(repeating: "a", count: 1_000)
            + "CENTER_SENTINEL"
            + String(repeating: "z", count: 1_000)

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 24,
            headBytes: 10,
            tailBytes: 8
        )

        XCTAssertTrue(display.isTruncated)
        XCTAssertEqual(display.originalByteCount, content.utf8.count)
        XCTAssertTrue(display.text.hasPrefix(String(repeating: "a", count: 10)))
        XCTAssertTrue(display.text.hasSuffix(String(repeating: "z", count: 8)))
        XCTAssertTrue(display.text.contains("Preview truncated"))
        XCTAssertFalse(display.text.contains("CENTER_SENTINEL"))
        XCTAssertLessThan(display.text.utf8.count, content.utf8.count)
    }

    func testTruncationDoesNotSplitMultibyteCharacters() {
        let content = String(repeating: "é", count: 80)
            + "middle"
            + String(repeating: "🙂", count: 80)

        let display = ExportPreviewDisplayContent.make(
            from: content,
            maximumRenderedBytes: 32,
            headBytes: 9,
            tailBytes: 11
        )

        XCTAssertTrue(display.isTruncated)
        XCTAssertTrue(display.text.hasPrefix(String(repeating: "é", count: 4)))
        XCTAssertTrue(display.text.hasSuffix(String(repeating: "🙂", count: 2)))
        XCTAssertTrue(display.text.contains("Preview truncated"))
    }

    func testPermissionGuidanceRecognizesAuthorizationNotDetermined() throws {
        let failure = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 0),
            dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBiologicalSex",
            dateRangeDescription: "2026-07-15",
            errorDescription: "Authorization is not determined"
        )

        let guidance = try XCTUnwrap(ExportPermissionGuidance(failure: failure))

        XCTAssertEqual(guidance.healthDataName, "Biological Sex")
        XCTAssertTrue(guidance.iOSInstructions.contains("Request Access"))
        XCTAssertTrue(guidance.iOSInstructions.contains("do not appear"))
        XCTAssertTrue(guidance.iOSInstructions.contains("Biological Sex"))
    }

    func testPermissionGuidanceRecognizesAuthorizationMessageWithoutIs() {
        let failure = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 0),
            dataType: "HealthKit specialized record HKActivitySummaryTypeIdentifier",
            dateRangeDescription: "2026-07-15",
            errorDescription: "Authorization not determined"
        )

        XCTAssertEqual(
            ExportPermissionGuidance(failure: failure)?.healthDataName,
            "Activity Summary Rings and Goals"
        )
    }

    func testPermissionGuidanceIgnoresUnrelatedWarnings() {
        let failure = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 0),
            dataType: "Daily Note",
            dateRangeDescription: "2026-07-15",
            errorDescription: "Daily note not found"
        )

        XCTAssertNil(ExportPermissionGuidance(failure: failure))
    }

    func testPartialExportNoticeOffersPermissionRecovery() throws {
        let failures = [
            ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBiologicalSex",
                dateRangeDescription: "2026-07-15",
                errorDescription: "Authorization is not determined"
            ),
            ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "HealthKit specialized record HKCharacteristicTypeIdentifierBloodType",
                dateRangeDescription: "2026-07-15",
                errorDescription: "Authorization not determined"
            )
        ]
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            partialFailures: failures
        )

        let notice = try XCTUnwrap(PartialExportNotice(result: result))
        let guidance = try XCTUnwrap(notice.permissionGuidance)

        XCTAssertEqual(notice.issueCount, 2)
        XCTAssertTrue(notice.toastMessage.contains("Health permissions need attention"))
        XCTAssertTrue(guidance.healthDataName.contains("Biological Sex"))
        XCTAssertTrue(guidance.healthDataName.contains("Blood Type"))
        XCTAssertTrue(
            notice.permissionAlertMessage(instructions: guidance.iOSInstructions)
                .contains("some health data was skipped")
        )
    }

    func testLargePermissionSetUsesCompactGuidance() throws {
        let identifiers = [
            "HKActivitySummaryTypeIdentifier",
            "HKCharacteristicTypeIdentifierBiologicalSex",
            "HKCharacteristicTypeIdentifierBloodType",
            "HKCharacteristicTypeIdentifierDateOfBirth"
        ]
        let failures = identifiers.map { identifier in
            ExportPartialFailure(
                date: Date(timeIntervalSince1970: 0),
                dataType: "HealthKit specialized record \(identifier)",
                dateRangeDescription: "2026-07-15",
                errorDescription: "Authorization is not determined"
            )
        }

        let guidance = try XCTUnwrap(ExportPermissionGuidance(failures: failures))

        XCTAssertEqual(guidance.healthDataCount, 4)
        XCTAssertEqual(guidance.healthDataName, "4 additional health data types")
        XCTAssertTrue(guidance.iOSInstructions.contains("additional data types you want to export"))
        XCTAssertFalse(guidance.iOSInstructions.contains("Activity Summary Rings and Goals,"))
    }

    func testPartialExportNoticeSummarizesNonPermissionIssues() throws {
        let failedDate = FailedDateDetail(
            date: Date(timeIntervalSince1970: 0),
            reason: .fileWriteError
        )
        let result = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 2,
            failedDateDetails: [failedDate]
        )

        let notice = try XCTUnwrap(PartialExportNotice(result: result))

        XCTAssertNil(notice.permissionGuidance)
        XCTAssertEqual(notice.issueCount, 1)
        XCTAssertTrue(notice.toastMessage.contains("1 issue"))
        XCTAssertTrue(notice.genericAlertMessage.contains("File write failed"))
    }
}

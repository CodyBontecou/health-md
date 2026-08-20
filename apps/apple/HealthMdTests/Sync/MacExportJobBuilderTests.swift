import XCTest
@testable import HealthMd

@MainActor
final class MacExportJobBuilderTests: XCTestCase {
    func testNewConnectedOperationPinsOnlyPureRustRangeSummaryBeforeCapture() async throws {
        let settings = makeSettings()
        settings.writeMode = .overwrite
        settings.includeGranularData = false
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "rust",
            userDefaults: nil,
            environment: [:]
        )

        let supported = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            hasNativeOnlyCompanionAction: false,
            policyResolver: resolver
        )
        XCTAssertTrue(supported.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(supported.appleExportEnginePin)

        settings.generateRangeSummary = true
        let rollup = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            hasNativeOnlyCompanionAction: false,
            policyResolver: resolver
        )
        XCTAssertTrue(rollup.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(rollup.appleExportEnginePin)

        settings.summaryOnlyExport = true
        let corpusRollup = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            hasNativeOnlyCompanionAction: false,
            operationSurface: .connectedReceivedRangeWithoutSideEffects,
            policyResolver: resolver
        )
        XCTAssertTrue(corpusRollup.appleExportEngineAuthorityIsFrozen)
        XCTAssertEqual(corpusRollup.appleExportEnginePin?.engine, .rust)

        settings.generateRangeSummary = false
        settings.summaryOnlyExport = false
        let providerSidecar = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            hasNativeOnlyCompanionAction: true,
            policyResolver: resolver
        )
        XCTAssertTrue(providerSidecar.appleExportEngineAuthorityIsFrozen)
        XCTAssertNil(providerSidecar.appleExportEnginePin)
    }

    func testCorpusProtocolV3AloneAdmitsConnectedRangeAuthority() {
        XCTAssertEqual(
            MacExportStreamingJobBuilder.connectedOperationSurface(protocolVersion: 2),
            .connectedReceivedFilesWithoutSideEffects
        )
        XCTAssertEqual(
            MacExportStreamingJobBuilder.connectedOperationSurface(
                protocolVersion: ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion
            ),
            .connectedReceivedRangeWithoutSideEffects
        )
    }

    func testBuild_fetchesEachDateUsingIncludeGranularDataSetting() async throws {
        let settings = makeSettings()
        settings.includeGranularData = true
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        var requestedGranularFlags: [Bool] = []

        let job = try await MacExportJobBuilder.build(
            jobID: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
            sourceDeviceName: "Test iPhone",
            startDate: start,
            endDate: end,
            settings: settings,
            healthSubfolder: "2. Areas/Health",
            destinationDisplayName: "MacVault",
            fetchHealthData: { date, includeGranularData in
                requestedGranularFlags.append(includeGranularData)
                var data = HealthData(date: date)
                data.activity.steps = 123
                return data
            }
        )

        XCTAssertEqual(requestedGranularFlags, [true, true])
        XCTAssertTrue(job.settingsSnapshot.includeGranularData)
        XCTAssertEqual(job.settingsSnapshot.healthSubfolder, "2. Areas/Health")
        XCTAssertEqual(job.records.count, 2)
        XCTAssertEqual(job.requestedTarget?.kind, .connectedMac)
        XCTAssertEqual(job.requestedTarget?.destinationDisplayName, "MacVault")
    }

    func testBuild_reportsDayProgressOnlyAfterCaptureCompletes() async throws {
        let settings = makeSettings()
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        var events: [String] = []

        _ = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: start,
            endDate: end,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { date, _ in
                events.append("captured")
                return HealthData(date: date, activity: ActivityData(steps: 1))
            },
            onProgress: { processed, _, _ in
                events.append("progress-\(processed)")
            }
        )

        XCTAssertEqual(events, [
            "captured", "progress-1",
            "captured", "progress-2"
        ])
    }

    func testBuild_summaryOnlyNeverFetchesGranularArchivesDespiteSavedToggle() async throws {
        let settings = makeSettings()
        settings.includeGranularData = true
        settings.generateRangeSummary = true
        settings.summaryOnlyExport = true
        let date = Self.day(2026, 5, 12)
        var requestedGranularFlags: [Bool] = []

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: date,
            endDate: date,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { requestedDate, includeGranularData in
                requestedGranularFlags.append(includeGranularData)
                let dayStart = Calendar.current.startOfDay(for: requestedDate)
                var data = HealthData(
                    date: requestedDate,
                    healthKitRecordArchive: HealthKitRecordArchive(
                        captureStatus: .complete,
                        dailyOwnership: HealthKitDailyOwnershipMetadata(
                            ownerDate: "2026-05-12",
                            intervalStart: dayStart,
                            intervalEnd: Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!,
                            calendarTimeZoneIdentifier: TimeZone.current.identifier
                        )
                    ),
                    healthKitRecordCaptureStatus: .complete
                )
                data.sleep.stages = [SleepStageSample(
                    stage: "core",
                    startDate: dayStart,
                    endDate: dayStart.addingTimeInterval(600)
                )]
                data.heart.heartRateSamples = [TimeSample(timestamp: dayStart, value: 60)]
                data.workouts = [WorkoutData(
                    workoutType: .running,
                    startTime: dayStart,
                    duration: 600,
                    calories: 100,
                    distance: 1_000,
                    route: [RoutePoint(
                        timestamp: dayStart,
                        latitude: 1,
                        longitude: 2,
                        altitudeMeters: nil,
                        speedMps: nil,
                        courseDegrees: nil,
                        horizontalAccuracyMeters: nil
                    )],
                    timeSeries: WorkoutTimeSeries(heartRate: [
                        TimeSeriesSample(timestamp: dayStart, value: 120)
                    ])
                )]
                return data
            }
        )
        let metadata = MacExportStreamingJobBuilder.metadata(
            startDate: date,
            endDate: date,
            settings: settings,
            destinationDisplayName: "MacVault"
        )

        XCTAssertTrue(job.settingsSnapshot.includeGranularData, "The saved toggle remains represented")
        XCTAssertTrue(job.settingsSnapshot.summaryOnlyExport)
        XCTAssertFalse(ConnectedExportGranularMode.isEnabled(for: job.settingsSnapshot))
        XCTAssertFalse(requestedGranularFlags.isEmpty)
        XCTAssertTrue(requestedGranularFlags.allSatisfy { !$0 })
        XCTAssertFalse(MacExportStreamingJobBuilder.shouldIncludeGranularData(
            for: date,
            metadata: metadata,
            settings: settings
        ), "The request-handler streaming path must use the same effective mode")
        XCTAssertTrue(job.records.allSatisfy { $0.healthKitRecordArchive == nil })
        XCTAssertTrue(job.records.allSatisfy { $0.sleep.stages.isEmpty })
        XCTAssertTrue(job.records.allSatisfy { $0.heart.heartRateSamples.isEmpty })
        XCTAssertTrue(job.records.allSatisfy { record in
            record.workouts.allSatisfy {
                $0.route.isEmpty && $0.timeSeries.isEmpty && $0.laps.isEmpty && $0.splits.isEmpty
            }
        })
    }

    func testBuild_dailyNotesOnlyUsesSummaryCaptureAndSkipsProviderSidecars() async throws {
        let settings = makeSettings()
        settings.exportFormats = []
        settings.includeGranularData = true
        settings.generateRangeSummary = true
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        let date = Self.day(2026, 5, 12)
        var requestedGranularFlags: [Bool] = []
        var externalFetchCount = 0

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: date,
            endDate: date,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { requestedDate, includeGranularData in
                requestedGranularFlags.append(includeGranularData)
                var data = HealthData(date: requestedDate)
                data.activity.steps = 123
                return data
            },
            fetchExternalDailyRecords: { _ in
                externalFetchCount += 1
                return []
            }
        )

        XCTAssertEqual(requestedGranularFlags, [false])
        XCTAssertEqual(externalFetchCount, 0)
        XCTAssertEqual(job.records.count, 1)
        XCTAssertTrue(job.externalDailyRecords.isEmpty)
        XCTAssertTrue(job.settingsSnapshot.dailyNotesOnlyModeEnabled)
        XCTAssertTrue(job.settingsSnapshot.hasFileDestinationOutput)
    }

    func testStreamingMetadataAndChunksUseTransferDatesWithOneBasedSequences() async throws {
        let settings = makeSettings()
        settings.generateRangeSummary = true
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)

        let metadata = MacExportStreamingJobBuilder.metadata(
            startDate: start,
            endDate: end,
            settings: settings,
            healthSubfolder: "2. Areas/Health",
            destinationDisplayName: "MacVault"
        )
        let chunks = MacExportStreamingJobBuilder.chunks(for: metadata.transferDates, chunkSize: 3)

        XCTAssertEqual(metadata.totalRequestedDays, 2)
        XCTAssertEqual(metadata.totalTransferDays, 2)
        XCTAssertEqual(metadata.transferDates.first, Calendar.current.startOfDay(for: start))
        XCTAssertEqual(metadata.transferDates.last, Calendar.current.startOfDay(for: end))
        XCTAssertEqual(metadata.requestedTarget.destinationDisplayName, "MacVault")
        XCTAssertEqual(metadata.settingsSnapshot.healthSubfolder, "2. Areas/Health")
        XCTAssertEqual(chunks.map(\.sequence), [1])
        XCTAssertEqual(chunks.map { $0.dates.count }, [2])
    }

    func testMetadataUsesFrozenNonCurrentCalendarForRequestedDayOwnership() async throws {
        let settings = makeSettings()
        settings.includeGranularData = true
        settings.exportTimeZoneOverride = TimeZone(identifier: "Pacific/Kiritimati")!
        let instant = ISO8601DateFormatter().date(from: "2026-05-12T12:00:00Z")!

        let metadata = await MacExportStreamingJobBuilder.metadataForNewOperation(
            startDate: instant,
            endDate: instant,
            requestedDates: [instant],
            settings: settings,
            destinationDisplayName: "MacVault",
            enforceConnectedOperationGate: true,
            hasNativeOnlyCompanionAction: true
        )
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = settings.exportTimeZoneOverride!
        let frozenDay = sourceCalendar.startOfDay(for: instant)

        XCTAssertEqual(metadata.settingsSnapshot.calendarTimeZoneIdentifier, "Pacific/Kiritimati")
        XCTAssertEqual(metadata.requestedDates, [frozenDay])
        XCTAssertEqual(metadata.requestedDays, [frozenDay])
        XCTAssertEqual(metadata.transferDates, [frozenDay])
        XCTAssertTrue(MacExportStreamingJobBuilder.shouldIncludeGranularData(
            for: instant,
            metadata: metadata,
            settings: settings
        ))
    }

    func testBuild_rangeV9UsesRequestedRecordsWithoutGranularDuplication() async throws {
        let settings = makeSettings()
        settings.includeGranularData = true
        settings.generateRangeSummary = true
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        var requestedDates: [Date] = []
        var requestedGranularFlags: [Bool] = []
        var externalRequestedDates: [Date] = []

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: start,
            endDate: end,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { date, includeGranularData in
                requestedDates.append(Calendar.current.startOfDay(for: date))
                requestedGranularFlags.append(includeGranularData)
                var data = HealthData(date: date)
                data.activity.steps = 123
                return data
            },
            fetchExternalDailyRecords: { date in
                externalRequestedDates.append(Calendar.current.startOfDay(for: date))
                return [ExternalDailyRecord(
                    provider: .withings,
                    date: ExternalProviderAPIClient.dayString(date),
                    payloads: [ExternalProviderPayload(
                        name: "daily_activity",
                        endpoint: "https://wbsapi.withings.net/v2/measure",
                        statusCode: 200,
                        data: .object(["steps": .number(123)])
                    )]
                )]
            }
        )

        XCTAssertEqual(job.records.count, 2)
        XCTAssertEqual(requestedDates.first, Calendar.current.startOfDay(for: start))
        XCTAssertEqual(requestedDates.last, Calendar.current.startOfDay(for: end))
        XCTAssertEqual(requestedGranularFlags.filter { $0 }.count, 2)
        XCTAssertTrue(requestedGranularFlags.filter { !$0 }.isEmpty)
        XCTAssertEqual(externalRequestedDates, [
            Calendar.current.startOfDay(for: start),
            Calendar.current.startOfDay(for: end)
        ])
        XCTAssertEqual(job.externalDailyRecords.count, 2)
        XCTAssertEqual(job.dateRangeStart, Calendar.current.startOfDay(for: start))
        XCTAssertEqual(job.dateRangeEnd, Calendar.current.startOfDay(for: end))
    }

    func testBuild_noncontiguousRequestedDatesDoesNotReinsertCompletedMiddleDay() async throws {
        let settings = makeSettings()
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        let first = Self.day(2026, 5, 10)
        let completedMiddle = Self.day(2026, 5, 11)
        let last = Self.day(2026, 5, 12)
        var fetchedDates: [Date] = []

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: first,
            endDate: last,
            requestedDates: [first, last],
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { requestedDate, _ in
                fetchedDates.append(requestedDate)
                return HealthData(date: requestedDate, activity: ActivityData(steps: 123))
            }
        )

        let expected = [first, last].map { Calendar.current.startOfDay(for: $0) }
        XCTAssertEqual(job.requestedDates, expected)
        XCTAssertEqual(fetchedDates, expected)
        XCTAssertFalse(fetchedDates.contains(Calendar.current.startOfDay(for: completedMiddle)))
    }

    func testBuild_carriesTypedSuccessfulEmptyWHOOPWithLocalRenderingParity() async throws {
        let settings = makeSettings()
        settings.exportFormats = [.json]
        let date = Self.day(2026, 5, 12)
        let fetchedAt = Date(timeIntervalSince1970: 1_778_544_000)
        let providerRecord = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-05-12",
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
        var local = HealthData(date: date, activity: ActivityData(steps: 123))
        local.providers = HealthProviderSections.normalized(from: [providerRecord])

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: date,
            endDate: date,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { requestedDate, _ in
                HealthData(date: requestedDate, activity: ActivityData(steps: 123))
            },
            fetchExternalDailyRecords: { _ in [providerRecord] }
        )

        let connected = try XCTUnwrap(job.records.first)
        XCTAssertEqual(connected.providers?.whoop?.captureStatus, .complete)
        XCTAssertTrue(job.externalDailyRecords.isEmpty)
        XCTAssertEqual(
            try connected.exportThrowing(format: .json, settings: settings),
            try local.exportThrowing(format: .json, settings: settings)
        )
    }

    func testBuild_providerOnlyDayDoesNotFetchOrTransferExternalRecords() async throws {
        let settings = makeSettings()
        let date = Self.day(2026, 5, 12)
        var externalFetchCount = 0

        let job = try await MacExportJobBuilder.build(
            sourceDeviceName: "Test iPhone",
            startDate: date,
            endDate: date,
            settings: settings,
            destinationDisplayName: "MacVault",
            fetchHealthData: { requestedDate, _ in HealthData(date: requestedDate) },
            fetchExternalDailyRecords: { requestedDate in
                externalFetchCount += 1
                return [ExternalDailyRecord(
                    provider: .whoop,
                    date: ExternalProviderAPIClient.dayString(requestedDate),
                    payloads: [ExternalProviderPayload(
                        name: "cycles",
                        endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                        statusCode: 200,
                        data: .object(["records": .array([.object(["id": .number(1)])])])
                    )]
                )]
            }
        )

        XCTAssertEqual(job.records.count, 1)
        XCTAssertTrue(job.externalDailyRecords.isEmpty)
        XCTAssertEqual(externalFetchCount, 0)
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "MacExportJobBuilderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown]
        return settings
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }
}

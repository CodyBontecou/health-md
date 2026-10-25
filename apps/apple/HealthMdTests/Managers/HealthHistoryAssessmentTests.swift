import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class HealthHistoryAssessmentTests: XCTestCase {
    private let steps = HKQuantityTypeIdentifier.stepCount.rawValue
    private let heart = HKQuantityTypeIdentifier.heartRate.rawValue
    private let boundary = Date(timeIntervalSince1970: 1_800_000_000)

    private func scope(_ metrics: Set<String> = ["steps"], start: Date? = nil,
                       allAvailable: Bool = false, profile: UUID? = nil) -> HealthHistoryScope {
        HealthHistoryScope(metricIDs: metrics, startDate: start ?? boundary.addingTimeInterval(-86400),
                           endDate: boundary.addingTimeInterval(86400), timeZoneIdentifier: "America/Los_Angeles",
                           allAvailable: allAvailable, profileID: profile)
    }

    private func manager(_ store: FakeHealthStore) -> HealthKitManager {
        HealthKitManager(store: store, userDefaults: UserDefaults(suiteName: "HealthHistoryAssessmentTests")!)
    }

    func testMixedBoundariesAndOmissionsRemainPerTypeUnknown() async {
        let store = FakeHealthStore()
        store.historyOutcome = .boundaries([steps: boundary, heart: boundary.addingTimeInterval(3600), "outside": .distantPast])
        let sut = manager(store)
        let request = scope(["steps", "heart_rate_avg", "sleep_total"])
        let result = await sut.assessHistoryAccess(scope: request)
        XCTAssertEqual(result.scope, request)
        XCTAssertEqual(result.access(for: steps), .limited(sampleEndBoundary: boundary))
        XCTAssertEqual(result.access(for: heart), .limited(sampleEndBoundary: boundary.addingTimeInterval(3600)))
        XCTAssertEqual(result.access(for: HKCategoryTypeIdentifier.sleepAnalysis.rawValue), .unknown)
        XCTAssertEqual(result.access(for: "outside"), .unassessed(reason: "outside_selected_scope"))
        XCTAssertEqual(Set(store.historyRequestedIdentifiers), [steps, heart, HKCategoryTypeIdentifier.sleepAnalysis.rawValue])
        XCTAssertTrue(result.hasIntersectingLimit)
        XCTAssertTrue(result.hasUnverifiedHistory)
    }

    func testFullSelectedDeniedAndLimitedWithoutDateAllRemainUnknown() async {
        for _ in ["full_selected", "denied", "limited_no_known_date"] {
            let store = FakeHealthStore()
            store.historyOutcome = .boundaries([:])
            let result = await manager(store).assessHistoryAccess(scope: scope())
            XCTAssertEqual(result.access(for: steps), .unknown)
            XCTAssertFalse(result.hasIntersectingLimit)
            XCTAssertTrue(result.needsWarning)
        }
    }

    func testEmptySuccessfulReadDoesNotEstablishHistoryAuthorization() async {
        let store = FakeHealthStore()
        let sut = manager(store)
        let discovery = await sut.discoverEarliestHealthDataDate(enabledMetricIDs: ["steps"])
        let result = await sut.assessHistoryAccess(scope: scope())
        XCTAssertTrue(discovery.isQueryComplete)
        XCTAssertNil(discovery.earliestDate)
        XCTAssertEqual(result.access(for: steps), .unknown)
    }

    func testAssessmentFailurePreservesReadableSiblingAndQueryCompletion() async {
        let store = FakeHealthStore()
        store.earliestSampleDates[steps] = boundary.addingTimeInterval(-86400)
        store.historyOutcomesByIdentifier[heart] = .failure
        store.historyOutcomesByIdentifier[steps] = .boundaries([steps: boundary])
        let sut = manager(store)
        let discovery = await sut.discoverEarliestHealthDataDate(enabledMetricIDs: ["steps", "heart_rate_avg"])
        let result = await sut.assessHistoryAccess(scope: scope(["steps", "heart_rate_avg"]))
        XCTAssertTrue(discovery.isQueryComplete)
        XCTAssertEqual(discovery.earliestDate, boundary.addingTimeInterval(-86400))
        XCTAssertEqual(result.access(for: heart), .assessmentFailed)
        XCTAssertEqual(result.access(for: steps), .limited(sampleEndBoundary: boundary))
    }

    func testReadFailureDoesNotReplaceSuccessfulAssessmentWithDenied() async {
        let store = FakeHealthStore()
        store.errorsForEarliestSampleDates[steps] = NSError(domain: "synthetic", code: 1)
        store.historyOutcome = .boundaries([steps: boundary])
        let sut = manager(store)
        let discovery = await sut.discoverEarliestHealthDataDate(enabledMetricIDs: ["steps"])
        let result = await sut.assessHistoryAccess(scope: scope())
        XCTAssertFalse(discovery.isQueryComplete)
        XCTAssertEqual(result.access(for: steps), .limited(sampleEndBoundary: boundary))
    }

    func testOlderRuntimeAssessmentUnavailableIsNotHealthDataUnavailable() async {
        let store = FakeHealthStore()
        store.historyOutcome = .unavailable
        store.earliestSampleDates[steps] = boundary
        let sut = manager(store)
        let result = await sut.assessHistoryAccess(scope: scope())
        let discovery = await sut.discoverEarliestHealthDataDate(enabledMetricIDs: ["steps"])
        XCTAssertEqual(result.access(for: steps), .apiUnavailable)
        XCTAssertEqual(discovery.earliestDate, boundary)
        XCTAssertTrue(result.needsWarning)
    }

    func testDependenciesSpecialTypesSnapshotsAndUnresolvedMetricsAreExplicit() async {
        let store = FakeHealthStore()
        let result = await manager(store).assessHistoryAccess(scope: scope([
            "stand_time", "blood_pressure_systolic", "medications", "vision_prescriptions", "date_of_birth", "unknown_metric"
        ]))
        let stand = result.types.first { $0.id == HealthKitRecordCatalog.appleStandHourIdentifier }
        XCTAssertEqual(stand?.dependencyMetricIDs, ["stand_time"])
        XCTAssertEqual(stand?.dependencyReasons, ["appleStandHourCompatibility"])
        XCTAssertEqual(result.access(for: HealthKitRecordCatalog.bloodPressureCorrelationIdentifier),
                       .unassessed(reason: "special_api_eligibility_unverified"))
        XCTAssertEqual(result.access(for: HealthKitRecordCatalog.dateOfBirthIdentifier),
                       .unassessed(reason: "snapshot_or_non_sample_api"))
        XCTAssertEqual(result.access(for: "metric:unknown_metric"), .unassessed(reason: "unresolved_selected_metric"))
        XCTAssertFalse(store.historyRequestedIdentifiers.contains(HealthKitRecordCatalog.bloodPressureCorrelationIdentifier))
        XCTAssertFalse(store.historyRequestedIdentifiers.contains(HealthKitRecordCatalog.medicationDoseEventIdentifier))
        XCTAssertFalse(store.historyRequestedIdentifiers.contains(HealthKitRecordCatalog.visionPrescriptionIdentifier))
    }

    func testBoundedRangeIntersectionBeforeAtAndAfterEndBoundaryIsDisclosureOnly() async {
        let store = FakeHealthStore()
        store.historyOutcome = .boundaries([steps: boundary])
        let sut = manager(store)
        for (start, warns) in [(boundary.addingTimeInterval(-1), true), (boundary, false), (boundary.addingTimeInterval(1), false)] {
            let result = await sut.assessHistoryAccess(scope: scope(start: start))
            XCTAssertEqual(result.hasIntersectingLimit, warns)
            XCTAssertEqual(result.scope.startDate, start)
            XCTAssertEqual(result.access(for: steps), .limited(sampleEndBoundary: boundary))
        }
        let allTime = await sut.assessHistoryAccess(scope: scope(start: boundary.addingTimeInterval(1), allAvailable: true))
        XCTAssertTrue(allTime.hasIntersectingLimit)
    }

    func testAssessmentDoesNotClampEarlierStartsOrMutateSampleIdentity() async throws {
        let store = FakeHealthStore()
        let sleep = HKCategoryTypeIdentifier.sleepAnalysis.rawValue
        let source = HealthKitSourceRevision(name: "Synthetic", bundleIdentifier: "test.history")
        let records = [heart, sleep].flatMap { identifier in
            [-1.0, 0.0, 1.0].map { delta in
                HealthKitRecord(
                    originalUUID: UUID(), objectTypeIdentifier: identifier,
                    recordKind: identifier == heart ? .quantity : .category,
                    selectedMetricIDs: identifier == heart ? ["heart_rate_avg"] : ["sleep_total"],
                    includedBecause: .selectedMetric,
                    startDate: boundary.addingTimeInterval(-100), endDate: boundary.addingTimeInterval(delta),
                    sourceRevision: source,
                    payload: identifier == heart ? .quantity(HealthKitQuantityPayload(value: 72, unit: "count/min"))
                        : .category(HealthKitCategoryPayload(rawValue: 1, symbolicValue: nil))
                )
            }
        }
        store.quantityRecordResults[heart] = records.filter { $0.objectTypeIdentifier == heart }
        store.categoryRecordResults[sleep] = records.filter { $0.objectTypeIdentifier == sleep }
        store.historyOutcome = .boundaries([heart: boundary, sleep: boundary])
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.enabledMetrics = ["heart_rate_avg", "sleep_total"]
        let sut = manager(store)
        let before = try await sut.fetchHealthData(for: boundary, detailPolicy: .archiveOnly,
                                                  metricSelection: selection, timeZone: TimeZone(secondsFromGMT: 0))
        _ = await sut.assessHistoryAccess(scope: scope(selection.enabledMetrics))
        let after = try await sut.fetchHealthData(for: boundary, detailPolicy: .archiveOnly,
                                                 metricSelection: selection, timeZone: TimeZone(secondsFromGMT: 0))
        let retained = try XCTUnwrap(after.healthKitRecordArchive).records
        XCTAssertEqual(retained.count, 6)
        XCTAssertEqual(retained, try XCTUnwrap(before.healthKitRecordArchive).records)
        XCTAssertEqual(Set(retained.map(\.originalUUID)), Set(records.map(\.originalUUID)))
        for record in retained {
            let original = try XCTUnwrap(records.first { $0.originalUUID == record.originalUUID })
            XCTAssertEqual(record.startDate, original.startDate)
            XCTAssertEqual(record.endDate, original.endDate)
        }
        XCTAssertEqual(after.date, before.date)
        // Native capture non-clamping proof, not OS filtering at equality/device sleep proof.
    }

    func testPermissionChangesReassessWithoutRelabelingPriorEvidence() async {
        let store = FakeHealthStore()
        let sut = manager(store)
        store.historyOutcome = .boundaries([steps: boundary])
        let first = await sut.assessHistoryAccess(scope: scope())
        store.historyOutcome = .boundaries([:])
        let second = await sut.assessHistoryAccess(scope: scope())
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.access(for: steps), .limited(sampleEndBoundary: boundary))
        XCTAssertEqual(second.access(for: steps), .unknown)
    }

    func testSameScopeExecutionEvidenceOverridesUnknownPreviewAndInverse() async {
        let store = FakeHealthStore()
        let sut = manager(store)
        let request = scope()
        for (previewOutcome, executionOutcome) in [
            (HealthHistoryQueryOutcome.boundaries([:]), HealthHistoryQueryOutcome.boundaries([steps: boundary])),
            (.boundaries([steps: boundary]), .boundaries([:]))
        ] {
            store.historyOutcome = previewOutcome
            let preview = await sut.assessHistoryAccess(scope: request)
            store.historyOutcome = executionOutcome
            let execution = await HealthHistoryAssessmentCoordinator().assess(scope: request, isCurrent: { true }) {
                await sut.assessHistoryAccess(scope: request)
            }
            let displayed = HealthHistoryAssessment.displayed(preview: preview, execution: execution, scope: request)
            XCTAssertEqual(displayed?.id, execution?.id)
            XCTAssertEqual(displayed?.access(for: steps), execution?.access(for: steps))
            let changedScope = scope(["heart_rate_avg"])
            XCTAssertNil(HealthHistoryAssessment.displayed(preview: preview, execution: execution, scope: changedScope))
            XCTAssertEqual(HealthHistoryAssessment.displayed(preview: preview, execution: nil, scope: request)?.id, preview.id)
        }
    }

    func testBoundaryDisplayUsesFrozenTimeZoneAcrossCivilDay() async {
        let date = ISO8601DateFormatter().date(from: "2027-01-01T00:30:00Z")!
        let store = FakeHealthStore()
        store.historyOutcome = .boundaries([steps: date])
        let west = await manager(store).assessHistoryAccess(scope: scope())
        let eastScope = HealthHistoryScope(metricIDs: ["steps"], startDate: west.scope.startDate,
            endDate: west.scope.endDate, timeZoneIdentifier: "Pacific/Kiritimati", allAvailable: false, profileID: nil)
        let east = await manager(store).assessHistoryAccess(scope: eastScope)
        XCTAssertNotEqual(west.boundaryDescription(date), east.boundaryDescription(date))
        XCTAssertTrue(west.boundaryDescription(date).contains("America/Los_Angeles"))
        XCTAssertTrue(east.boundaryDescription(date).contains("Pacific/Kiritimati"))
    }

    func testProductionCoordinatorRejectsLatePreviewAfterNewerRequestAndABA() async {
        let sut = manager(FakeHealthStore())
        let originalScope = scope()
        let coordinator = HealthHistoryAssessmentCoordinator()
        var pending: CheckedContinuation<HealthHistoryAssessment, Never>?
        let oldTask = Task {
            await coordinator.assess(scope: originalScope, isCurrent: { true }) {
                await withCheckedContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        coordinator.invalidate() // A → B
        let latest = await coordinator.assess(scope: originalScope, isCurrent: { true }) {
            await sut.assessHistoryAccess(scope: originalScope) // B → A, still a new request
        }
        let oldResult = await sut.assessHistoryAccess(scope: originalScope)
        pending?.resume(returning: oldResult)
        let obsolete = await oldTask.value
        XCTAssertNil(obsolete)
        XCTAssertNotNil(latest)
    }

    func testProductionCoordinatorRejectsChangedExecutionSettingsScopeAndProfileBeforeCapture() async {
        let store = FakeHealthStore()
        let sut = manager(store)
        let defaults = UserDefaults(suiteName: "HistoryExecutionSettings")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let coordinator = HealthHistoryAssessmentCoordinator()
        let initial = HealthHistoryExecutionSelection(scope: scope(), settings: ExportSettingsSnapshot.from(settings),
                                                     target: .localIPhoneFolder, preset: .custom)
        var changedSettings = initial.settings
        changedSettings.includeMetadata.toggle()
        for changed in [
            HealthHistoryExecutionSelection(scope: initial.scope, settings: changedSettings, target: initial.target, preset: .custom),
            HealthHistoryExecutionSelection(scope: scope(["heart_rate_avg"]), settings: initial.settings, target: initial.target, preset: .custom),
            HealthHistoryExecutionSelection(scope: scope(profile: UUID()), settings: initial.settings, target: initial.target, preset: .custom),
            HealthHistoryExecutionSelection(scope: initial.scope, settings: initial.settings, target: .connectedMac, preset: .custom),
            HealthHistoryExecutionSelection(scope: initial.scope, settings: initial.settings, target: initial.target, preset: .today)
        ] {
            var current = initial
            var captures = 0
            var pending: CheckedContinuation<HealthHistoryAssessment, Never>?
            let requestID = coordinator.beginRequest()
            let task = Task {
                let result = await coordinator.assess(requestID: requestID, scope: initial.scope,
                    isCurrent: { current == initial }) {
                    await withCheckedContinuation { pending = $0 }
                }
                if result != nil { captures += 1 }
            }
            while pending == nil { await Task.yield() }
            current = changed
            pending?.resume(returning: await sut.assessHistoryAccess(scope: initial.scope))
            await task.value
            XCTAssertEqual(captures, 0)
        }
        let changed = HealthHistoryExecutionSelection(scope: initial.scope, settings: changedSettings,
                                                     target: initial.target, preset: initial.preset)
        XCTAssertNotEqual(changed, initial)
        let staleRequest = coordinator.beginRequest()
        coordinator.invalidate() // Permission/ABA event before the async task starts.
        var assessmentCalls = 0
        let result = await coordinator.assess(requestID: staleRequest, scope: initial.scope, isCurrent: { true }) {
            assessmentCalls += 1
            return await sut.assessHistoryAccess(scope: initial.scope)
        }
        XCTAssertNil(result)
        XCTAssertEqual(assessmentCalls, 0)
    }

    func testProductionCoordinatorUnchangedSelectionAllowsCapture() async {
        let sut = manager(FakeHealthStore())
        let defaults = UserDefaults(suiteName: "HistoryUnchangedSettings")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let selection = HealthHistoryExecutionSelection(scope: scope(), settings: ExportSettingsSnapshot.from(settings),
                                                       target: .localIPhoneFolder, preset: .custom)
        let coordinator = HealthHistoryAssessmentCoordinator()
        let requestID = coordinator.beginRequest()
        var captures = 0
        let result = await coordinator.assess(requestID: requestID, scope: selection.scope,
            isCurrent: { selection.settings == ExportSettingsSnapshot.from(settings) }) {
            await sut.assessHistoryAccess(scope: selection.scope)
        }
        if result != nil { captures += 1 }
        XCTAssertEqual(captures, 1)
        XCTAssertEqual(result?.scope, selection.scope)
    }

    func testResolvedExportRequestKeepsOriginAndExactCaptureScopeWithoutPreferenceWrites() async throws {
        let suite = "HistoryResolvedRequest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let origin = HealthHistoryExecutionSelection(scope: scope(allAvailable: true, profile: UUID()),
            settings: ExportSettingsSnapshot.from(settings), target: .localIPhoneFolder,
            preset: .allTime, localDestinationURL: URL(fileURLWithPath: "/tmp/history-original"))
        let before = defaults.persistentDomain(forName: suite) as NSDictionary?
        let coordinator = HealthHistoryAssessmentCoordinator()
        let request = coordinator.beginExportRequest(selection: origin)
        let range = ExportDateRange(startDate: boundary.addingTimeInterval(-86400 * 30),
                                    endDate: boundary.addingTimeInterval(86400 * 2))
        let admitted = await coordinator.resolveExportRequest(request, liveSelection: { origin }) { range }
        let resolved = try XCTUnwrap(admitted)
        XCTAssertEqual(resolved.id, request.id)
        XCTAssertEqual(resolved.originatingSelection, origin)
        XCTAssertNotEqual(resolved.selection, origin, "Equatable must retain the actual capture bounds")
        XCTAssertEqual(resolved.selection.scope.startDate, range.startDate)
        XCTAssertEqual(resolved.selection.scope.endDate, range.endDate)
        XCTAssertEqual(resolved.selection.scope.profileID, origin.scope.profileID)
        XCTAssertEqual(resolved.selection.scope.metricIDs, origin.scope.metricIDs)
        XCTAssertEqual(resolved.selection.scope.timeZoneIdentifier, origin.scope.timeZoneIdentifier)
        XCTAssertEqual(resolved.selection.settings, origin.settings)
        XCTAssertEqual(resolved.selection.localDestinationURL, origin.localDestinationURL)
        XCTAssertTrue(coordinator.isCurrent(resolved, liveSelection: origin))
        XCTAssertEqual(before, defaults.persistentDomain(forName: suite) as NSDictionary?)
    }

    func testResolvedBoundsDriveScaleAssessmentAndExecutionDisclosure() async throws {
        let suite = "HistoryResolvedAdmission.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let origin = HealthHistoryExecutionSelection(scope: scope(allAvailable: true),
            settings: ExportSettingsSnapshot.from(AdvancedExportSettings(userDefaults: defaults)),
            target: .localIPhoneFolder, preset: .allTime)
        let coordinator = HealthHistoryAssessmentCoordinator()
        let request = coordinator.beginExportRequest(selection: origin)
        XCTAssertEqual(request.scaleVerdict, .proceed, "Original UI dates are only a few days")
        let resolved = try XCTUnwrap(request.resolvingAllTime(ExportDateRange(
            startDate: boundary.addingTimeInterval(-86400 * 366), endDate: boundary)))
        guard case .confirm(let scale) = resolved.scaleVerdict else {
            return XCTFail("Freshly discovered historical coverage must require scale confirmation")
        }
        XCTAssertGreaterThan(scale.dayCount, ExportScaleGuard.confirmationDayThreshold)
        XCTAssertEqual(request.dateRangeRequest, resolved.dateRangeRequest,
                       "Discovery identity remains the original UI selection")
        let assessment = await coordinator.assess(requestID: resolved.id, scope: resolved.selection.scope,
            isCurrent: { coordinator.isCurrent(resolved, liveSelection: origin) }) {
                HealthHistoryAssessment(id: UUID(), assessedAt: self.boundary,
                    scope: resolved.selection.scope, types: [])
            }
        let execution = try XCTUnwrap(assessment)
        let preview = HealthHistoryAssessment(id: UUID(), assessedAt: boundary, scope: origin.scope, types: [])
        XCTAssertEqual(execution.scope.startDate, resolved.selection.scope.startDate)
        XCTAssertEqual(execution.scope.endDate, resolved.selection.scope.endDate)
        XCTAssertEqual(HealthHistoryAssessment.displayed(preview: preview, execution: execution,
            scope: origin.scope, executionScope: resolved.selection.scope)?.id, execution.id)
        XCTAssertEqual(HealthHistoryAssessment.displayed(preview: preview, execution: execution,
            scope: origin.scope)?.id, preview.id, "Execution bounds cannot silently replace preview scope")
        XCTAssertEqual(request.originatingSelection, origin)
    }

    func testResolvedRequestRejectsInvalidBoundsAndNonAllTimeSelection() throws {
        let suite = "HistoryInvalidResolvedAdmission.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ExportSettingsSnapshot.from(AdvancedExportSettings(userDefaults: defaults))
        let origin = HealthHistoryExecutionSelection(scope: scope(allAvailable: true),
            settings: settings, target: .localIPhoneFolder, preset: .allTime)
        let request = HealthHistoryExportRequest(id: UUID(), selection: origin)
        XCTAssertNil(request.resolvingAllTime(ExportDateRange(startDate: boundary,
            endDate: boundary.addingTimeInterval(-1))))
        XCTAssertNil(request.resolvingAllTime(ExportDateRange(
            startDate: Date(timeIntervalSinceReferenceDate: .infinity), endDate: boundary)))
        XCTAssertNil(request.resolvingAllTime(ExportDateRange(startDate: boundary,
            endDate: Date(timeIntervalSinceReferenceDate: .nan))))
        let bounded = HealthHistoryExportRequest(id: UUID(), selection: HealthHistoryExecutionSelection(
            scope: scope(), settings: settings, target: .localIPhoneFolder, preset: .custom))
        XCTAssertNil(bounded.resolvingAllTime(ExportDateRange(startDate: boundary, endDate: boundary)))
    }

    func testResolvedExportRequestRejectsChangesBeforeConfirmationOrAssessment() async throws {
        let defaults = UserDefaults(suiteName: "HistoryResolvedChanged")!
        defer { defaults.removePersistentDomain(forName: "HistoryResolvedChanged") }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let origin = HealthHistoryExecutionSelection(scope: scope(allAvailable: true),
            settings: ExportSettingsSnapshot.from(settings), target: .localIPhoneFolder, preset: .allTime,
            localDestinationURL: URL(fileURLWithPath: "/tmp/history-original"))
        var altered = origin.settings
        altered.includeMetadata.toggle()
        let changed = [
            HealthHistoryExecutionSelection(scope: origin.scope, settings: altered, target: origin.target, preset: origin.preset, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: scope(["heart_rate_avg"], allAvailable: true), settings: origin.settings, target: origin.target, preset: origin.preset, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: scope(allAvailable: true, profile: UUID()), settings: origin.settings, target: origin.target, preset: origin.preset, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: scope(start: origin.scope.startDate.addingTimeInterval(3600), allAvailable: true),
                settings: origin.settings, target: origin.target, preset: origin.preset, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: HealthHistoryScope(metricIDs: origin.scope.metricIDs,
                startDate: origin.scope.startDate, endDate: origin.scope.endDate, timeZoneIdentifier: "UTC",
                allAvailable: true, profileID: origin.scope.profileID, rangeSemantics: origin.scope.rangeSemantics),
                settings: origin.settings, target: origin.target, preset: origin.preset, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: origin.scope, settings: origin.settings, target: origin.target,
                preset: .custom, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: origin.scope, settings: origin.settings, target: .connectedMac, preset: origin.preset, localDestinationURL: origin.localDestinationURL),
            HealthHistoryExecutionSelection(scope: origin.scope, settings: origin.settings, target: origin.target, preset: origin.preset,
                localDestinationURL: URL(fileURLWithPath: "/tmp/history-replaced"))
        ]
        let coordinator = HealthHistoryAssessmentCoordinator()
        for live in changed {
            let discovering = coordinator.beginExportRequest(selection: origin)
            var current = origin
            let admission = await coordinator.resolveExportRequest(discovering, liveSelection: { current }) {
                await Task.yield()
                current = live
                return ExportDateRange(startDate: self.boundary.addingTimeInterval(-86400 * 30),
                                       endDate: self.boundary)
            }
            XCTAssertNil(admission, "Every origin field must remain current across discovery")
            let request = coordinator.beginExportRequest(selection: origin)
            let resolved = try XCTUnwrap(request.resolvingAllTime(ExportDateRange(
                startDate: boundary.addingTimeInterval(-86400 * 30), endDate: boundary)))
            var calls = 0
            let assessment = await coordinator.assess(requestID: resolved.id, scope: resolved.selection.scope,
                isCurrent: { coordinator.isCurrent(resolved, liveSelection: live) }) {
                    calls += 1
                    return HealthHistoryAssessment(id: UUID(), assessedAt: self.boundary,
                        scope: resolved.selection.scope, types: [])
                }
            XCTAssertNil(assessment)
            XCTAssertEqual(calls, 0, "Changed confirmation requests must not begin assessment")
        }
    }

    func testResolvedExportRequestRejectsABAAndStaleCancellation() async {
        let defaults = UserDefaults(suiteName: "HistoryResolvedABA")!
        defer { defaults.removePersistentDomain(forName: "HistoryResolvedABA") }
        let origin = HealthHistoryExecutionSelection(scope: scope(allAvailable: true),
            settings: ExportSettingsSnapshot.from(AdvancedExportSettings(userDefaults: defaults)),
            target: .localIPhoneFolder, preset: .allTime)
        let coordinator = HealthHistoryAssessmentCoordinator()
        let old = coordinator.beginExportRequest(selection: origin)
        coordinator.invalidate() // The UI changed away and back during discovery/confirmation.
        XCTAssertFalse(coordinator.isCurrent(old, liveSelection: origin))
        let current = coordinator.beginExportRequest(selection: origin)
        coordinator.invalidate(old)
        XCTAssertTrue(coordinator.isCurrent(current, liveSelection: origin))
        let admission = await coordinator.resolveExportRequest(current, liveSelection: { origin }) {
            await Task.yield()
            coordinator.invalidate() // Away-and-back is equal by value, but has a new revision.
            return ExportDateRange(startDate: self.boundary.addingTimeInterval(-86400 * 30),
                                   endDate: self.boundary)
        }
        XCTAssertNil(admission)
    }

    func testFrozenCaptureSettingsRetainMetricScopeEngineAuthorityAndCalendar() {
        let defaults = UserDefaults(suiteName: "HistoryFrozenCaptureSettings")!
        let live = AdvancedExportSettings(userDefaults: defaults)
        live.metricSelection.enabledMetrics = ["steps"]
        live.executionAppleExportEngineAuthorityIsFrozen = false
        let snapshot = ExportSettingsSnapshot.from(live, appleExportEngineAuthorityIsFrozen: false)
        let selection = HealthHistoryExecutionSelection(scope: scope(), settings: snapshot,
                                                       target: .localIPhoneFolder, preset: .custom)
        live.metricSelection.enabledMetrics = ["heart_rate_avg"]
        let frozen = selection.makeCaptureSettings()
        XCTAssertEqual(frozen.metricSelection.enabledMetrics, ["steps"])
        XCTAssertEqual(frozen.exportTimeZoneOverride?.identifier, selection.scope.timeZoneIdentifier)
        XCTAssertEqual(frozen.executionAppleExportEnginePin, snapshot.appleExportEnginePin)
        XCTAssertEqual(frozen.executionAppleExportEngineAuthorityIsFrozen, snapshot.appleExportEngineAuthorityIsFrozen)
        XCTAssertFalse(frozen.executionAppleExportEngineAuthorityIsFrozen, "History assessment must not freeze/repin M3 authority differently")
        XCTAssertEqual(selection.scope.startDate, scope().startDate)
        XCTAssertEqual(selection.scope.endDate, scope().endDate)
    }

    func testContinueUnverifiedIsNotAnEmptySuccessfulAssessmentOrFullHistory() {
        let store = FakeHealthStore()
        let sut = manager(store)
        let request = scope(["steps", "stand_time"])
        let result = sut.historyAssessmentNotCompleted(scope: request)
        XCTAssertEqual(result.scope, request)
        XCTAssertEqual(result.evidenceSource, "assessment_not_completed")
        XCTAssertEqual(result.access(for: steps), .unassessed(reason: "assessment_not_completed"))
        XCTAssertEqual(result.types.first { $0.id == HealthKitRecordCatalog.appleStandHourIdentifier }?.dependencyMetricIDs, ["stand_time"])
        XCTAssertTrue(result.warningMessage.contains("did not finish"))
        XCTAssertTrue(result.needsWarning)
        XCTAssertTrue(store.historyRequestedIdentifiers.isEmpty)
    }

    func testProductionCoordinatorCancelledAssessmentCannotStartCapture() async {
        let request = scope()
        let sut = manager(FakeHealthStore())
        let coordinator = HealthHistoryAssessmentCoordinator()
        var pending: CheckedContinuation<HealthHistoryAssessment, Never>?
        let task = Task {
            await coordinator.assess(scope: request, isCurrent: { true }) {
                await withCheckedContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        task.cancel()
        pending?.resume(returning: await sut.assessHistoryAccess(scope: request))
        let result = await task.value
        XCTAssertNil(result)
    }

    func testOwnerDateDisclosureUsesFrozenCalendarWithoutChangingRequestedDates() async {
        let store = FakeHealthStore()
        let day = ISO8601DateFormatter().date(from: "2027-01-01T20:00:00Z")!
        let endBoundary = ISO8601DateFormatter().date(from: "2027-01-01T18:00:00Z")!
        store.historyOutcome = .boundaries([steps: endBoundary])
        let request = HealthHistoryScope(metricIDs: ["steps"], startDate: day, endDate: day,
            timeZoneIdentifier: "America/Los_Angeles", allAvailable: false, profileID: nil, rangeSemantics: .ownerDates)
        let result = await manager(store).assessHistoryAccess(scope: request)
        XCTAssertTrue(result.hasIntersectingLimit, "Capture includes the earlier hours of the requested owner day")
        XCTAssertEqual(result.scope.startDate, day)
        XCTAssertEqual(result.scope.endDate, day)
        XCTAssertEqual(result.scope.sampleQueryStart, ISO8601DateFormatter().date(from: "2027-01-01T08:00:00Z"))
    }

    func testStaleRevisionScopeProfileAndTimeZoneCannotPublishPreview() async {
        let result = await manager(FakeHealthStore()).assessHistoryAccess(scope: scope())
        var revision = HealthHistoryAssessmentRevision()
        let token = revision.id
        XCTAssertTrue(revision.accepts(token, assessment: result, scope: scope()))
        XCTAssertFalse(revision.accepts(token, assessment: result, scope: scope(["heart_rate_avg"])))
        XCTAssertFalse(revision.accepts(token, assessment: result, scope: scope(profile: UUID())))
        let utc = HealthHistoryScope(metricIDs: ["steps"], startDate: result.scope.startDate,
                                    endDate: result.scope.endDate, timeZoneIdentifier: "UTC", allAvailable: false, profileID: nil)
        XCTAssertFalse(revision.accepts(token, assessment: result, scope: utc))
        revision.invalidate() // permission change, preset edit, or A → B → A
        XCTAssertFalse(revision.accepts(token, assessment: result, scope: scope()))
    }
}

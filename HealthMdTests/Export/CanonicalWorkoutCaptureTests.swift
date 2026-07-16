import XCTest
import HealthKit
@testable import HealthMd

final class CanonicalWorkoutCaptureTests: XCTestCase {
    private static let workoutUUID = UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
    private static let routeUUID1 = UUID(uuidString: "91000000-0000-0000-0000-000000000002")!
    private static let routeUUID2 = UUID(uuidString: "91000000-0000-0000-0000-000000000003")!
    private static let sampleUUID = UUID(uuidString: "91000000-0000-0000-0000-000000000004")!
    private static let source = HealthKitSourceRevision(
        name: "Apple Watch",
        bundleIdentifier: "com.apple.health.910",
        version: "26.0",
        productType: "Watch9,1",
        operatingSystemVersion: HealthKitOperatingSystemVersion(
            majorVersion: 26,
            minorVersion: 0,
            patchVersion: 1
        )
    )
    private static let device = HealthKitDeviceProvenance(
        name: "Apple Watch",
        manufacturer: "Apple Inc.",
        model: "Watch",
        hardwareVersion: "Watch9,1",
        firmwareVersion: "26.0",
        softwareVersion: "26.0.1",
        localIdentifier: "canonical-watch",
        udiDeviceIdentifier: "canonical-udi"
    )
    private static let customization: FormatCustomization = {
        let customization = FormatCustomization()
        customization.unitPreference = .metric
        return customization
    }()

    @MainActor
    func testPausedWorkoutUsesStableHealthKitIdentityAndActualEndAcrossExports() async throws {
        let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let actualEnd = dayStart.addingTimeInterval(50 * 60)
        let store = FakeHealthStore()
        store.workoutResults = [WorkoutValue(
            sourceUUID: Self.workoutUUID,
            activityType: HKWorkoutActivityType.running.rawValue,
            duration: 40 * 60,
            startDate: dayStart,
            endDate: actualEnd,
            sourceRevision: Self.source,
            device: Self.device,
            isIndoor: false,
            metadata: ["fixture": "paused"],
            totalEnergyBurned: 410.25,
            totalDistance: 8_001.125
        )]
        store.workoutRecordResult = HealthKitWorkoutRecordQueryResult(records: [
            Self.workoutRecord(dayStart: dayStart, actualEnd: actualEnd)
        ])
        let manager = makeManager(store: store)
        let selection = workoutSelection()

        let first = try await manager.fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: selection
        )
        let second = try await manager.fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: selection
        )

        let firstWorkout = try XCTUnwrap(first.workouts.first)
        XCTAssertEqual(firstWorkout.id, Self.workoutUUID)
        XCTAssertEqual(firstWorkout.sourceUUID, Self.workoutUUID)
        XCTAssertEqual(firstWorkout.duration, 40 * 60)
        XCTAssertEqual(firstWorkout.actualEndDate, actualEnd)
        XCTAssertEqual(firstWorkout.endTime, actualEnd)
        XCTAssertEqual(firstWorkout.sourceRevision, Self.source)
        XCTAssertEqual(firstWorkout.device, Self.device)
        XCTAssertEqual(second.workouts.first?.id, Self.workoutUUID)
        XCTAssertEqual(store.workoutRecordQueries.count, 2)

        let json = try parseJSON(first.toJSON(customization: Self.customization))
        let workoutJSON = try XCTUnwrap((json["workouts"] as? [[String: Any]])?.first)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        XCTAssertEqual(workoutJSON["endTimeISO"] as? String, formatter.string(from: actualEnd))
        XCTAssertEqual(workoutJSON["duration"] as? Double, 40 * 60)
    }

    @MainActor
    func testCanonicalWorkoutGraphMergesAssociatedSamplesByUUIDAndFulfillsWorkoutAndRoutesOnce() async throws {
        let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let actualEnd = dayStart.addingTimeInterval(50 * 60)
        let store = FakeHealthStore()
        let workout = Self.workoutRecord(dayStart: dayStart, actualEnd: actualEnd)
        let route1 = Self.routeRecord(
            uuid: Self.routeUUID1,
            dayStart: dayStart,
            pointOffset: 10,
            simulated: false
        )
        let route2 = Self.routeRecord(
            uuid: Self.routeUUID2,
            dayStart: dayStart,
            pointOffset: 20,
            simulated: true
        )
        let associatedSample = Self.quantityRecord(
            dayStart: dayStart,
            relationships: [HealthKitRecordRelationship(
                targetUUID: Self.workoutUUID,
                role: "workout",
                kind: "associated_with"
            )]
        )
        store.workoutRecordResult = HealthKitWorkoutRecordQueryResult(
            records: [workout, route1, route2, associatedSample]
        )
        // The generic dependency query sees the same HKQuantitySample. It must
        // merge only by UUID and retain the specialized workout relationship.
        store.quantityRecordResults[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] = [
            Self.quantityRecord(dayStart: dayStart)
        ]

        let data = try await makeManager(store: store).fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: workoutSelection()
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)

        XCTAssertEqual(store.workoutRecordQueries.count, 1)
        XCTAssertEqual(archive.captureStatus, .complete)
        XCTAssertEqual(archive.records.filter { $0.originalUUID == Self.sampleUUID }.count, 1)
        let mergedSample = try XCTUnwrap(archive.records.first { $0.originalUUID == Self.sampleUUID })
        XCTAssertTrue(mergedSample.relationships.contains { $0.targetUUID == Self.workoutUUID })
        XCTAssertEqual(archive.records.filter { $0.recordKind == .workoutRoute }.count, 2)

        let workoutResult = try XCTUnwrap(archive.queryResults.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.workoutTypeIdentifier
        })
        let routeResult = try XCTUnwrap(archive.queryResults.first {
            $0.objectTypeIdentifier == HealthKitRecordCatalog.workoutRouteTypeIdentifier
                && $0.operation == "queryWorkoutRecords"
        })
        XCTAssertEqual(workoutResult.status, .success)
        XCTAssertEqual(workoutResult.recordCount, 1)
        XCTAssertEqual(routeResult.status, .success)
        XCTAssertEqual(routeResult.recordCount, 2)
        XCTAssertFalse(archive.queryResults.contains { $0.status == .unsupported })

        let exported = try parseJSON(HealthKitRecordArchiveSerializer.string(for: archive))
        let records = try XCTUnwrap(exported["records"] as? [[String: Any]])
        let exportedWorkout = try XCTUnwrap(records.first {
            $0["original_uuid"] as? String == Self.workoutUUID.uuidString
        })
        let payload = try XCTUnwrap(exportedWorkout["payload"] as? [String: Any])
        let fields = try XCTUnwrap(payload["fields"] as? [String: Any])
        XCTAssertEqual(((fields["durationSeconds"] as? [String: Any])?["value"] as? NSNumber)?.doubleValue, 2_400)
        let events = try XCTUnwrap((fields["events"] as? [String: Any])?["value"] as? [[String: Any]])
        XCTAssertEqual(events.count, 9, "all known fixture event types plus a future raw type must survive")
        XCTAssertEqual(
            ((events.last?["value"] as? [String: Any])?["typeRawValue"] as? [String: Any])?["value"] as? Int,
            9_999
        )
        let activities = try XCTUnwrap((fields["activities"] as? [String: Any])?["value"] as? [[String: Any]])
        XCTAssertEqual(activities.count, 1)
        let activityValue = try XCTUnwrap(activities.first?["value"] as? [String: Any])
        XCTAssertEqual((activityValue["originalUUID"] as? [String: Any])?["value"] as? String,
                       "91000000-0000-0000-0000-000000000099")
        XCTAssertNotNil(activityValue["allStatistics"])

        let exportedRoutes = records.filter { $0["record_kind"] as? String == "workout_route" }
        XCTAssertEqual(exportedRoutes.count, 2)
        let routePayload = try XCTUnwrap(exportedRoutes.first?["payload"] as? [String: Any])
        let routeFields = try XCTUnwrap(routePayload["fields"] as? [String: Any])
        let locations = try XCTUnwrap((routeFields["locations"] as? [String: Any])?["value"] as? [[String: Any]])
        let location = try XCTUnwrap(locations.first?["value"] as? [String: Any])
        for key in [
            "timestamp", "latitude", "longitude", "altitudeMeters",
            "ellipsoidalAltitudeMeters", "horizontalAccuracyMeters",
            "verticalAccuracyMeters", "courseDegrees", "courseAccuracyDegrees",
            "speedMetersPerSecond", "speedAccuracyMetersPerSecond", "floorLevel",
            "sourceInformation"
        ] {
            XCTAssertNotNil(location[key], "canonical route location missing \(key)")
        }
    }

    @MainActor
    func testWorkoutChildFailureIsExplicitAndDoesNotDropSuccessfulGraph() async throws {
        let dayStart = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let actualEnd = dayStart.addingTimeInterval(50 * 60)
        let store = FakeHealthStore()
        let childFailure = HealthKitQueryResult(
            identifier: "\(Self.workoutUUID.uuidString):route:\(Self.routeUUID2.uuidString):locations",
            objectTypeIdentifier: HealthKitRecordCatalog.workoutRouteTypeIdentifier,
            operation: "queryWorkoutRouteLocations",
            metricIDs: ["workouts"],
            metricAttribution: HealthKitMetricAttribution(dependencyMetricIDs: ["workouts"]),
            interval: HealthKitQueryInterval(startDate: dayStart, endDate: actualEnd),
            status: .failure,
            recordCount: 0,
            error: HealthKitQueryError(
                domain: "CanonicalWorkoutFixture",
                code: 72,
                description: "Second route locations unavailable",
                isRecoverable: true
            ),
            statusDescription: "workout_uuid=\(Self.workoutUUID.uuidString) child_uuid=\(Self.routeUUID2.uuidString)"
        )
        store.workoutRecordResult = HealthKitWorkoutRecordQueryResult(
            records: [
                Self.workoutRecord(dayStart: dayStart, actualEnd: actualEnd),
                Self.routeRecord(uuid: Self.routeUUID1, dayStart: dayStart, pointOffset: 10, simulated: false),
                Self.routeRecord(uuid: Self.routeUUID2, dayStart: dayStart, pointOffset: 20, simulated: true),
            ],
            childQueryFailures: [childFailure],
            integrityWarnings: [HealthKitRecordIntegrityWarning(
                code: "fixture_warning",
                message: "A non-fatal canonical fixture warning",
                metricIDs: ["workouts"],
                recordUUIDs: [Self.workoutUUID]
            )]
        )

        let data = try await makeManager(store: store).fetchHealthData(
            for: dayStart,
            includeGranularData: true,
            metricSelection: workoutSelection()
        )
        let archive = try XCTUnwrap(data.healthKitRecordArchive)
        XCTAssertEqual(archive.captureStatus, .partial)
        XCTAssertEqual(archive.records.filter { $0.recordKind == .workout }.count, 1)
        XCTAssertEqual(archive.records.filter { $0.recordKind == .workoutRoute }.count, 2)
        XCTAssertEqual(archive.integrityWarnings.map(\.code), ["fixture_warning"])
        let failed = try XCTUnwrap(archive.queryResults.first {
            $0.operation == "queryWorkoutRouteLocations"
        })
        XCTAssertEqual(failed.error?.domain, "CanonicalWorkoutFixture")
        XCTAssertEqual(failed.error?.code, 72)
        XCTAssertEqual(data.partialFailures.filter {
            $0.dataType.contains("HealthKit workout child")
        }.count, 1)
    }

    func testWorkoutDataNewAndLegacyCodableRemainCompatible() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let actualEnd = start.addingTimeInterval(3_000)
        let workout = WorkoutData(
            id: Self.workoutUUID,
            sourceUUID: Self.workoutUUID,
            workoutType: .running,
            healthKitActivityType: "running",
            healthKitActivityTypeRawValue: HKWorkoutActivityType.running.rawValue,
            startTime: start,
            actualEndDate: actualEnd,
            sourceRevision: Self.source,
            device: Self.device,
            duration: 2_400,
            calories: 410.25,
            distance: 8_001.125
        )
        let decoded = try JSONDecoder().decode(
            WorkoutData.self,
            from: JSONEncoder().encode(workout)
        )
        XCTAssertEqual(decoded.id, Self.workoutUUID)
        XCTAssertEqual(decoded.sourceUUID, Self.workoutUUID)
        XCTAssertEqual(decoded.actualEndDate, actualEnd)
        XCTAssertEqual(decoded.endTime, actualEnd)
        XCTAssertEqual(decoded.sourceRevision, Self.source)
        XCTAssertEqual(decoded.device, Self.device)

        let legacyJSON = #"{"id":"91000000-0000-0000-0000-000000000001","workoutType":"running","startTime":0,"duration":2400}"#
        let legacy = try JSONDecoder().decode(WorkoutData.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(legacy.sourceUUID)
        XCTAssertNil(legacy.actualEndDate)
        XCTAssertNil(legacy.sourceRevision)
        XCTAssertNil(legacy.device)
        XCTAssertEqual(legacy.endTime, Date(timeIntervalSinceReferenceDate: 2_400))
    }

    @MainActor
    private func makeManager(store: FakeHealthStore) -> HealthKitManager {
        let suite = "CanonicalWorkoutCaptureTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return HealthKitManager(store: store, userDefaults: defaults)
    }

    @MainActor
    private func workoutSelection() -> MetricSelectionState {
        let selection = MetricSelectionState()
        selection.deselectAll()
        selection.enabledMetrics = ["workouts"]
        return selection
    }

    private static func workoutRecord(dayStart: Date, actualEnd: Date) -> HealthKitRecord {
        let eventRawValues = [1, 2, 3, 4, 5, 6, 7, 8, 9_999]
        let events: [HealthKitMetadataValue] = eventRawValues.enumerated().map { index, rawValue in
            let start = dayStart.addingTimeInterval(Double(index * 60))
            return .dictionary([
                "typeRawValue": .signedInteger(Int64(rawValue)),
                "typeSymbolicValue": rawValue == 9_999 ? .null : .string("event-\(rawValue)"),
                "dateInterval": .dictionary([
                    "startDate": .date(start),
                    "endDate": .date(start.addingTimeInterval(Double(index))),
                    "durationSeconds": .floatingPoint(Double(index)),
                ]),
                "metadata": .dictionary(["raw": .signedInteger(Int64(rawValue))]),
            ])
        }
        let statistics: HealthKitMetadataValue = .dictionary([
            HKQuantityTypeIdentifier.activeEnergyBurned.rawValue: .dictionary([
                "quantityTypeIdentifier": .string(HKQuantityTypeIdentifier.activeEnergyBurned.rawValue),
                "canonicalUnit": .string("kcal"),
                "sum": .quantity(HealthKitMetadataQuantity(value: 410.25, unit: "kcal", rawDescription: "410.25 kcal")),
                "average": .quantity(HealthKitMetadataQuantity(value: 5.125, unit: "kcal", rawDescription: "5.125 kcal")),
                "minimum": .quantity(HealthKitMetadataQuantity(value: 0.125, unit: "kcal", rawDescription: "0.125 kcal")),
                "maximum": .quantity(HealthKitMetadataQuantity(value: 9.875, unit: "kcal", rawDescription: "9.875 kcal")),
                "mostRecent": .quantity(HealthKitMetadataQuantity(value: 1.75, unit: "kcal", rawDescription: "1.75 kcal")),
                "duration": .quantity(HealthKitMetadataQuantity(value: 2_400.5, unit: "s", rawDescription: "2400.5 s")),
            ])
        ])
        let activity: HealthKitMetadataValue = .dictionary([
            "originalUUID": .string("91000000-0000-0000-0000-000000000099"),
            "workoutConfiguration": .dictionary([
                "activityTypeRawValue": .unsignedInteger(UInt64(HKWorkoutActivityType.running.rawValue)),
                "activityTypeSymbolicValue": .string("running"),
                "locationTypeRawValue": .signedInteger(3),
                "locationTypeSymbolicValue": .string("outdoor"),
            ]),
            "startDate": .date(dayStart),
            "endDate": .date(actualEnd),
            "durationSeconds": .floatingPoint(2_400),
            "metadata": .dictionary(["segment": .string("main")]),
            "events": .array(events),
            "allStatistics": statistics,
        ])
        return HealthKitRecord(
            originalUUID: Self.workoutUUID,
            objectTypeIdentifier: HealthKitRecordCatalog.workoutTypeIdentifier,
            recordKind: .workout,
            selectedMetricIDs: ["workouts"],
            includedBecause: .selectedMetric,
            startDate: dayStart,
            endDate: actualEnd,
            hasUndeterminedDuration: true,
            sourceRevision: Self.source,
            device: Self.device,
            metadata: [
                HKMetadataKeyIndoorWorkout: .bool(false),
                "typed": .unsignedInteger(UInt64.max),
            ],
            payload: .structured(kind: "workout", fields: [
                "activityTypeRawValue": .unsignedInteger(UInt64(HKWorkoutActivityType.running.rawValue)),
                "activityTypeSymbolicValue": .string("running"),
                "durationSeconds": .floatingPoint(2_400),
                "isIndoor": .bool(false),
                "events": .array(events),
                "activities": .array([activity]),
                "allStatistics": statistics,
                "totalEnergyBurned": .quantity(HealthKitMetadataQuantity(value: 410.25, unit: "kcal", rawDescription: "410.25 kcal")),
                "totalDistance": .quantity(HealthKitMetadataQuantity(value: 8_001.125, unit: "m", rawDescription: "8001.125 m")),
            ]),
            relationships: [
                HealthKitRecordRelationship(targetUUID: Self.routeUUID1, role: "workout_route", kind: "contains"),
                HealthKitRecordRelationship(targetUUID: Self.routeUUID2, role: "workout_route", kind: "contains"),
                HealthKitRecordRelationship(targetUUID: Self.sampleUUID, role: "quantity_sample", kind: "contains"),
            ]
        )
    }

    private static func routeRecord(
        uuid: UUID,
        dayStart: Date,
        pointOffset: TimeInterval,
        simulated: Bool
    ) -> HealthKitRecord {
        let timestamp = dayStart.addingTimeInterval(pointOffset)
        let location: HealthKitMetadataValue = .dictionary([
            "index": .unsignedInteger(0),
            "timestamp": .date(timestamp),
            "latitude": .floatingPoint(21.306944123456),
            "longitude": .floatingPoint(-157.858333654321),
            "altitudeMeters": .floatingPoint(12.3456789),
            "ellipsoidalAltitudeMeters": .floatingPoint(34.5678912),
            "horizontalAccuracyMeters": .floatingPoint(1.2345678),
            "verticalAccuracyMeters": .floatingPoint(2.3456789),
            "courseDegrees": .floatingPoint(123.456789),
            "courseAccuracyDegrees": .floatingPoint(3.4567891),
            "speedMetersPerSecond": .floatingPoint(4.5678912),
            "speedAccuracyMetersPerSecond": .floatingPoint(0.1234567),
            "floorLevel": .signedInteger(-1),
            "sourceInformation": .dictionary([
                "isSimulatedBySoftware": .bool(simulated),
                "isProducedByAccessory": .bool(!simulated),
            ]),
        ])
        return HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: HealthKitRecordCatalog.workoutRouteTypeIdentifier,
            recordKind: .workoutRoute,
            selectedMetricIDs: ["workouts"],
            includedBecause: .relationshipDependency,
            startDate: timestamp,
            endDate: timestamp.addingTimeInterval(30),
            sourceRevision: Self.source,
            device: Self.device,
            metadata: ["route": .string(uuid.uuidString)],
            payload: .structured(kind: "workoutRoute", fields: [
                "locationCount": .unsignedInteger(1),
                "locations": .array([location]),
            ]),
            relationships: [HealthKitRecordRelationship(
                targetUUID: Self.workoutUUID,
                role: "workout",
                kind: "associated_with"
            )]
        )
    }

    private static func quantityRecord(
        dayStart: Date,
        relationships: [HealthKitRecordRelationship] = []
    ) -> HealthKitRecord {
        HealthKitRecord(
            originalUUID: Self.sampleUUID,
            objectTypeIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
            recordKind: .quantity,
            selectedMetricIDs: ["workouts"],
            includedBecause: .relationshipDependency,
            startDate: dayStart.addingTimeInterval(30),
            endDate: dayStart.addingTimeInterval(60),
            sourceRevision: Self.source,
            device: Self.device,
            metadata: ["sample": .string("associated")],
            payload: .quantity(HealthKitQuantityPayload(value: 5.125, unit: "kcal")),
            relationships: relationships
        )
    }

    private func parseJSON(_ string: String) throws -> [String: Any] {
        let data = try XCTUnwrap(string.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

//
//  IndividualEntryDocumentationTests.swift
//  HealthMdTests
//
//  Generates and guards the committed Individual Entry Tracking reference.
//  Every example is rendered by the production extractor, filename builder,
//  and preview renderer from fixed synthetic UTC fixtures.
//

import XCTest
import HealthKit
@testable import HealthMd

@MainActor
final class IndividualEntryDocumentationTests: XCTestCase {
    func testGeneratedIndividualEntryDocumentationHasNoDrift() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        defer { NSTimeZone.default = previousTimeZone }

        let artifacts = try IndividualEntryDocumentationGenerator.artifacts()
        XCTAssertEqual(artifacts.count, 9)
        XCTAssertTrue(artifacts.values.allSatisfy { !$0.contains("...") })
        XCTAssertTrue(artifacts.values.allSatisfy { !$0.contains("…") })

        if let outputBasename = try Self.updateOutputBasename() {
            try Self.stage(artifacts, outputBasename: outputBasename)
            return
        }

        let root = Self.generatedDocumentationDirectory
        let expectedPaths = Set(artifacts.keys)
        let actualPaths = try Self.relativeFilePaths(in: root)
        XCTAssertEqual(actualPaths, expectedPaths, """
        Generated Individual Entry Tracking artifact set drifted.
        Run scripts/generated-individual-entry-docs.sh update and review the result.
        """)

        for path in artifacts.keys.sorted() {
            let committedURL = root.appendingPathComponent(path)
            let committed = try String(contentsOf: committedURL, encoding: .utf8)
            XCTAssertEqual(committed, artifacts[path], """
            Generated Individual Entry Tracking documentation drifted at \(path).
            Run scripts/generated-individual-entry-docs.sh update and review the result.
            """)
        }
    }

    private static var generatedDocumentationDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Documentation
            .deletingLastPathComponent() // HealthMdTests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("docs/reference/generated/individual", isDirectory: true)
    }

    private static var updateMarkerURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(".update-generated-individual-entry-docs")
    }

    private static func updateOutputBasename() throws -> String? {
        if let basename = ProcessInfo.processInfo.environment["GENERATED_INDIVIDUAL_ENTRY_DOCS_OUTPUT_BASENAME"] {
            return basename
        }
        guard FileManager.default.fileExists(atPath: updateMarkerURL.path) else { return nil }
        return try String(contentsOf: updateMarkerURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stage(
        _ artifacts: [String: String],
        outputBasename: String
    ) throws {
        guard outputBasename.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw DocumentationGenerationError.invalidOutputBasename(outputBasename)
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(outputBasename, isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: root)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        for path in artifacts.keys.sorted() {
            let outputURL = root.appendingPathComponent(path)
            try fileManager.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try artifacts[path]!.write(to: outputURL, atomically: true, encoding: .utf8)
        }
        try String(artifacts.count).write(
            to: root.appendingPathComponent(".complete"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func relativeFilePaths(in root: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return Set(try FileManager.default.contentsOfDirectory(atPath: root.path).filter {
            !$0.hasPrefix(".")
        })
    }
}

private enum DocumentationGenerationError: Error {
    case invalidOutputBasename(String)
    case missingSample(String)
    case unexpectedSampleCount(Int)
    case missingMetricDefinition(String)
    case missingCollisionOutput
}

@MainActor
private enum IndividualEntryDocumentationGenerator {
    // STATIC RETENTION JUSTIFICATION: these ObservableObject fixtures are immutable
    // after one-time setup. Retention avoids the macOS 26 / Swift 6 reentrant
    // main-actor deinit crash described in docs/testing/lifecycle-audit.md.
    private static let trackingSettings: IndividualTrackingSettings = {
        let settings = IndividualTrackingSettings()
        settings.globalEnabled = true
        for metricID in [
            "weight",
            "symptom_headache",
            "state_of_mind_entries",
            "blood_pressure_systolic",
            "blood_pressure_diastolic",
            "medications",
            "workouts",
            "blood_glucose"
        ] {
            settings.setTrackIndividually(metricID, enabled: true)
        }
        return settings
    }()

    private static let formatSettings: FormatCustomization = {
        let settings = FormatCustomization()
        settings.unitPreference = .metric
        return settings
    }()

    private static let exporter = IndividualEntryExporter()
    private static let dayStart = utcDate("2026-07-14T00:00:00.000Z")
    private static let quantityDate = utcDate("2026-07-14T09:15:30.125Z")
    private static let categoryDate = utcDate("2026-07-14T09:16:31.250Z")
    private static let stateOfMindDate = utcDate("2026-07-14T09:17:32.375Z")
    private static let bloodPressureDate = utcDate("2026-07-14T09:18:33.500Z")
    private static let medicationDate = utcDate("2026-07-14T09:19:34.625Z")
    private static let workoutDate = utcDate("2026-07-14T09:20:35.750Z")

    private static let quantityUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
    private static let categoryUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000002")!
    private static let stateOfMindUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000003")!
    private static let bloodPressureUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000004")!
    private static let systolicUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000005")!
    private static let diastolicUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000006")!
    private static let medicationUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000007")!
    private static let workoutUUID = UUID(uuidString: "71000000-0000-0000-0000-000000000008")!

    private static let sourceRevision = HealthKitSourceRevision(
        name: "Health.md Documentation Fixture",
        bundleIdentifier: "tech.isolated.healthmd.documentation-fixture",
        version: "1.0.0",
        productType: "FixtureDevice1,1",
        operatingSystemVersion: HealthKitOperatingSystemVersion(
            majorVersion: 1,
            minorVersion: 0,
            patchVersion: 0
        )
    )

    private static let device = HealthKitDeviceProvenance(
        name: "Synthetic Fixture Device",
        manufacturer: "Health.md",
        model: "Documentation Model",
        hardwareVersion: "1",
        firmwareVersion: "1.0",
        softwareVersion: "1.0",
        localIdentifier: "fixture-device",
        udiDeviceIdentifier: "fixture-udi"
    )

    static func artifacts() throws -> [String: String] {
        let extracted = exporter.extractIndividualSamples(
            from: canonicalHealthData(),
            settings: trackingSettings
        )
        guard extracted.count == 6 else {
            throw DocumentationGenerationError.unexpectedSampleCount(extracted.count)
        }

        let canonicalSpecifications: [(path: String, uuid: UUID, label: String)] = [
            ("quantity.md", quantityUUID, "Canonical quantity"),
            ("category.md", categoryUUID, "Canonical category"),
            ("state-of-mind.md", stateOfMindUUID, "Canonical State of Mind"),
            ("blood-pressure.md", bloodPressureUUID, "Canonical blood-pressure correlation"),
            ("medication-dose.md", medicationUUID, "Canonical medication dose"),
            ("workout.md", workoutUUID, "Canonical detailed workout")
        ]

        var artifacts: [String: String] = [:]
        var inventoryInputs: [(document: String, content: String)] = []
        for specification in canonicalSpecifications {
            guard let sample = extracted.first(where: { $0.originalUUID == specification.uuid }) else {
                throw DocumentationGenerationError.missingSample(specification.label)
            }
            let content = exporter.previewEntryContent(for: sample, formatSettings: formatSettings) + "\n"
            artifacts[specification.path] = content
            inventoryInputs.append((specification.path, content))
        }

        let fallback = try fallbackDocumentation()
        artifacts["legacy-daily-aggregate.md"] = fallback.document
        inventoryInputs.append(("summary-only", fallback.summaryPreview))
        inventoryInputs.append(("legacy-aggregate", fallback.legacyPreview))

        artifacts["filename-path-matrix.md"] = try filenamePathMatrix(samples: extracted)
        artifacts["frontmatter-fields.md"] = frontmatterInventory(inventoryInputs)
        return artifacts
    }

    private static func canonicalHealthData() -> HealthData {
        let quantity = record(
            uuid: quantityUUID,
            identifier: HKQuantityTypeIdentifier.bodyMass.rawValue,
            kind: .quantity,
            directMetricIDs: ["weight"],
            start: quantityDate,
            end: quantityDate.addingTimeInterval(4.875),
            payload: .quantity(.init(value: 72.375, unit: "kg"))
        )
        let category = record(
            uuid: categoryUUID,
            identifier: "HKCategoryTypeIdentifierHeadache",
            kind: .category,
            directMetricIDs: ["symptom_headache"],
            start: categoryDate,
            end: categoryDate.addingTimeInterval(300),
            payload: .category(.init(rawValue: 2, symbolicValue: "moderate"))
        )
        let stateOfMind = record(
            uuid: stateOfMindUUID,
            identifier: HealthKitRecordCatalog.stateOfMindIdentifier,
            kind: .stateOfMind,
            directMetricIDs: ["state_of_mind_entries"],
            start: stateOfMindDate,
            end: stateOfMindDate.addingTimeInterval(30),
            payload: .structured(kind: "stateOfMind", fields: [
                "kind": enumValue(rawValue: 1, symbolicValue: "Daily Mood"),
                "valence": .floatingPoint(0.625),
                "valenceClassification": enumValue(rawValue: 2, symbolicValue: "Pleasant"),
                "labels": .array([
                    enumValue(rawValue: 3, symbolicValue: "Calm"),
                    enumValue(rawValue: 4, symbolicValue: "Content")
                ]),
                "associations": .array([
                    enumValue(rawValue: 5, symbolicValue: "Exercise")
                ])
            ])
        )
        let bloodPressure = record(
            uuid: bloodPressureUUID,
            identifier: HealthKitRecordCatalog.bloodPressureCorrelationIdentifier,
            kind: .correlation,
            directMetricIDs: ["blood_pressure_systolic", "blood_pressure_diastolic"],
            start: bloodPressureDate,
            end: bloodPressureDate.addingTimeInterval(2.5),
            payload: .correlation(componentUUIDs: [systolicUUID, diastolicUUID]),
            relationships: [
                HealthKitRecordRelationship(targetUUID: systolicUUID, role: "systolic", kind: "component"),
                HealthKitRecordRelationship(targetUUID: diastolicUUID, role: "diastolic", kind: "component")
            ]
        )
        let systolic = record(
            uuid: systolicUUID,
            identifier: HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
            kind: .quantity,
            dependencyMetricIDs: ["blood_pressure_systolic", "blood_pressure_diastolic"],
            start: bloodPressureDate,
            end: bloodPressureDate.addingTimeInterval(1),
            payload: .quantity(.init(value: 122.5, unit: "mmHg")),
            relationships: [
                HealthKitRecordRelationship(targetUUID: bloodPressureUUID, role: "parent", kind: "correlation")
            ]
        )
        let diastolic = record(
            uuid: diastolicUUID,
            identifier: HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue,
            kind: .quantity,
            dependencyMetricIDs: ["blood_pressure_systolic", "blood_pressure_diastolic"],
            start: bloodPressureDate,
            end: bloodPressureDate.addingTimeInterval(1),
            payload: .quantity(.init(value: 78.25, unit: "mmHg")),
            relationships: [
                HealthKitRecordRelationship(targetUUID: bloodPressureUUID, role: "parent", kind: "correlation")
            ]
        )
        let medication = record(
            uuid: medicationUUID,
            identifier: HealthKitRecordCatalog.medicationDoseEventIdentifier,
            kind: .medicationDoseEvent,
            directMetricIDs: ["medications"],
            start: medicationDate,
            end: medicationDate.addingTimeInterval(45),
            payload: .structured(kind: "medicationDoseEvent", fields: [
                "medicationConceptIdentifier": .string("fixture-medication-concept"),
                "medicationName": .string("Synthetic Fixture Medication"),
                "doseQuantity": .floatingPoint(1.5),
                "scheduledDoseQuantity": .floatingPoint(2),
                "unit": .string("tablet"),
                "scheduledDate": .date(medicationDate.addingTimeInterval(-300)),
                "logStatus": enumValue(rawValue: 1, symbolicValue: "taken"),
                "scheduleType": enumValue(rawValue: 2, symbolicValue: "scheduled")
            ])
        )
        let workout = record(
            uuid: workoutUUID,
            identifier: HealthKitRecordCatalog.workoutTypeIdentifier,
            kind: .workout,
            directMetricIDs: ["workouts"],
            start: workoutDate,
            end: workoutDate.addingTimeInterval(600),
            payload: .structured(kind: "workout", fields: [
                "activityTypeRawValue": .unsignedInteger(13),
                "activityTypeSymbolicValue": .string("Cycling"),
                "durationSeconds": .floatingPoint(600),
                "isIndoor": .bool(false),
                "allStatistics": .dictionary([
                    "activeEnergyBurned": .quantity(.init(
                        value: 90,
                        unit: "kcal",
                        rawDescription: "90 kcal"
                    )),
                    "distanceCycling": .quantity(.init(
                        value: 3_200,
                        unit: "m",
                        rawDescription: "3200 m"
                    )),
                    "heartRateAverage": .quantity(.init(
                        value: 150,
                        unit: "count/min",
                        rawDescription: "150 count/min"
                    ))
                ])
            ])
        )

        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-07-14",
                intervalStart: dayStart,
                intervalEnd: dayStart.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            records: [
                quantity,
                category,
                stateOfMind,
                bloodPressure,
                systolic,
                diastolic,
                medication,
                workout
            ]
        )
        var data = HealthData(date: dayStart, healthKitRecordArchive: archive)
        data.workouts = [workoutPresentation()]
        return data
    }

    private static func record(
        uuid: UUID,
        identifier: String,
        kind: HealthKitRecordKind,
        directMetricIDs: [String] = [],
        dependencyMetricIDs: [String] = [],
        start: Date,
        end: Date,
        payload: HealthKitRecordPayload,
        relationships: [HealthKitRecordRelationship] = []
    ) -> HealthKitRecord {
        let attribution = HealthKitMetricAttribution(
            directMetricIDs: directMetricIDs,
            dependencyMetricIDs: dependencyMetricIDs
        )
        return HealthKitRecord(
            originalUUID: uuid,
            objectTypeIdentifier: identifier,
            recordKind: kind,
            selectedMetricIDs: attribution.metricIDs,
            includedBecause: directMetricIDs.isEmpty ? .relationshipDependency : .selectedMetric,
            metricAttribution: attribution,
            startDate: start,
            endDate: end,
            sourceRevision: sourceRevision,
            device: device,
            metadata: [
                "fixture": .bool(true),
                "fixturePurpose": .string("Deterministic Individual Entry Tracking documentation")
            ],
            payload: payload,
            relationships: relationships
        )
    }

    private static func enumValue(rawValue: Int64, symbolicValue: String) -> HealthKitMetadataValue {
        .dictionary([
            "rawValue": .signedInteger(rawValue),
            "symbolicValue": .string(symbolicValue)
        ])
    }

    private static func workoutPresentation() -> WorkoutData {
        func sample(_ offset: TimeInterval, _ value: Double) -> TimeSeriesSample {
            TimeSeriesSample(timestamp: workoutDate.addingTimeInterval(offset), value: value)
        }

        let firstLap = WorkoutLap(
            startDate: workoutDate,
            endDate: workoutDate.addingTimeInterval(300),
            duration: 300,
            distanceMeters: 1_600
        )
        let secondLap = WorkoutLap(
            startDate: workoutDate.addingTimeInterval(300),
            endDate: workoutDate.addingTimeInterval(600),
            duration: 300,
            distanceMeters: 1_600
        )
        let firstSplit = WorkoutSplit(
            index: 1,
            startDate: workoutDate,
            duration: 300,
            distanceMeters: 1_600,
            avgHeartRate: 145
        )
        let secondSplit = WorkoutSplit(
            index: 2,
            startDate: workoutDate.addingTimeInterval(300),
            duration: 300,
            distanceMeters: 1_600,
            avgHeartRate: 155
        )
        let offsets: [TimeInterval] = [0, 120, 240, 360, 480]

        return WorkoutData(
            id: workoutUUID,
            sourceUUID: workoutUUID,
            workoutType: .cycling,
            healthKitActivityType: "cycling",
            healthKitActivityTypeRawValue: 13,
            startTime: workoutDate,
            actualEndDate: workoutDate.addingTimeInterval(600),
            sourceRevision: sourceRevision,
            device: device,
            isIndoor: false,
            metadata: ["Fixture": "Synthetic documentation workout"],
            duration: 600,
            calories: 90,
            distance: 3_200,
            avgHeartRate: 150,
            maxHeartRate: 180,
            minHeartRate: 110,
            avgCyclingCadence: 84,
            avgPower: 210,
            maxPower: 280,
            elevationGainMeters: 24,
            elevationLossMeters: 18,
            laps: [firstLap, secondLap],
            splits: [firstSplit, secondSplit],
            route: [
                RoutePoint(
                    timestamp: workoutDate,
                    latitude: 0,
                    longitude: 0,
                    altitudeMeters: 10,
                    speedMps: 5,
                    courseDegrees: 90,
                    horizontalAccuracyMeters: 3
                ),
                RoutePoint(
                    timestamp: workoutDate.addingTimeInterval(600),
                    latitude: 0.001,
                    longitude: 0.001,
                    altitudeMeters: 16,
                    speedMps: 5.5,
                    courseDegrees: 95,
                    horizontalAccuracyMeters: 3
                )
            ],
            timeSeries: WorkoutTimeSeries(
                heartRate: zip(offsets, [110.0, 135, 150, 165, 180]).map(sample),
                speed: zip(offsets, [4.8, 5.0, 5.2, 5.4, 5.6]).map(sample),
                power: zip(offsets, [170.0, 190, 210, 230, 250]).map(sample),
                cadence: zip(offsets, [78.0, 81, 84, 87, 90]).map(sample),
                strideLength: zip(offsets, [1.0, 1.1, 1.2, 1.3, 1.4]).map(sample),
                groundContactTime: zip(offsets, [260.0, 255, 250, 245, 240]).map(sample),
                verticalOscillation: zip(offsets, [7.0, 7.2, 7.4, 7.6, 7.8]).map(sample),
                altitude: zip(offsets, [10.0, 12, 14, 16, 18]).map(sample)
            )
        )
    }

    private static func fallbackDocumentation() throws -> (
        document: String,
        summaryPreview: String,
        legacyPreview: String
    ) {
        var summaryOnly = HealthData(
            date: dayStart,
            healthKitRecordCaptureStatus: .notRequested
        )
        summaryOnly.body.weight = 70.25
        let summarySamples = exporter.extractIndividualSamples(
            from: summaryOnly,
            settings: trackingSettings
        )
        guard summarySamples.count == 1, let summary = summarySamples.first else {
            throw DocumentationGenerationError.missingSample("summary-only aggregate")
        }
        let summaryPreview = exporter.previewEntryContent(
            for: summary,
            formatSettings: formatSettings
        )

        var legacy = HealthData(
            date: dayStart,
            healthKitRecordCaptureStatus: .legacyUnavailable
        )
        legacy.body.weight = 71.5
        let legacySamples = exporter.extractIndividualSamples(
            from: legacy,
            settings: trackingSettings
        )
        guard legacySamples.count == 1, let legacySample = legacySamples.first else {
            throw DocumentationGenerationError.missingSample("legacy aggregate")
        }
        let legacyPreview = exporter.previewEntryContent(
            for: legacySample,
            formatSettings: formatSettings
        )

        var partial = HealthData(
            date: dayStart,
            healthKitRecordCaptureStatus: .partial
        )
        partial.body.weight = 73
        let partialCount = exporter.extractIndividualSamples(
            from: partial,
            settings: trackingSettings
        ).count

        let document = """
        # Summary-only and legacy aggregate fallback

        This generated note uses fixed synthetic values. It records the compatibility boundary enforced by `IndividualEntryExporter.extractIndividualSamples`.

        | Capture state | Canonical archive present | Extracted entries | Result |
        |---|---:|---:|---|
        | `not_requested` | no | \(summarySamples.count) | A daily aggregate is emitted with `entry_kind: daily_aggregate`. |
        | `legacy_unavailable` | no | \(legacySamples.count) | A daily aggregate is emitted with `entry_kind: daily_aggregate`. |
        | `partial` | no | \(partialCount) | No aggregate is substituted for requested canonical capture. |

        Summary-only exports and legacy records may use aggregate fallback because source-event identity is unavailable by design. When canonical capture was requested, an empty, failed, unsupported, skipped, or partial canonical query is not replaced by a daily summary that could look like a source event.

        ## Summary-only generated entry

        ```markdown
        \(summaryPreview)
        ```

        ## Legacy generated entry

        ```markdown
        \(legacyPreview)
        ```
        """ + "\n"

        return (document, summaryPreview, legacyPreview)
    }

    private static func filenamePathMatrix(samples: [IndividualHealthSample]) throws -> String {
        let canonicalLabels: [UUID: String] = [
            quantityUUID: "canonical quantity",
            categoryUUID: "canonical category",
            stateOfMindUUID: "canonical State of Mind",
            bloodPressureUUID: "canonical blood-pressure correlation",
            medicationUUID: "canonical medication dose",
            workoutUUID: "canonical workout"
        ]
        var canonicalRows: [String] = []
        for sample in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard let uuid = sample.originalUUID, let label = canonicalLabels[uuid] else { continue }
            let definition = metricDefinition(for: sample)
            let folder = trackingSettings.folderPath(for: definition)
            let filename = exporter.filename(for: sample, settings: trackingSettings)
            canonicalRows.append("| \(label) | `\(sample.metricId)` | `\(folder)/\(filename)` | UUID suffix from canonical source identity |")
        }

        let collisionDate = utcDate("2026-07-14T09:15:15.000Z")
        var collisionData = HealthData(
            date: dayStart,
            healthKitRecordCaptureStatus: .legacyUnavailable
        )
        collisionData.vitals.bloodGlucoseSamples = [
            TimeSample(timestamp: collisionDate, value: 101, metadata: ["source": "Synthetic Fixture Sensor"]),
            TimeSample(timestamp: collisionDate, value: 102, metadata: ["source": "Synthetic Fixture Sensor"]),
            TimeSample(timestamp: collisionDate, value: 103, metadata: ["source": "Synthetic Fixture Sensor"])
        ]
        let collisionSamples = exporter.extractIndividualSamples(
            from: collisionData,
            settings: trackingSettings
        )
        guard collisionSamples.count == 3, let firstCollision = collisionSamples.first else {
            throw DocumentationGenerationError.missingSample("legacy same-minute collision fixtures")
        }
        let requestedFilename = exporter.filename(
            for: firstCollision,
            settings: trackingSettings
        )
        let collisionFolder = trackingSettings.folderPath(for: metricDefinition(for: firstCollision))
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-individual-doc-collision-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.removeItem(at: temporaryRoot)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        _ = try exporter.exportIndividualEntries(
            samples: collisionSamples,
            to: temporaryRoot,
            settings: trackingSettings,
            formatSettings: formatSettings
        )
        let collisionDirectory = temporaryRoot.appendingPathComponent(collisionFolder)
        let resolvedNames = try FileManager.default.contentsOfDirectory(atPath: collisionDirectory.path)
            .filter { $0.hasSuffix(".md") }
            .sorted()
        guard resolvedNames.count == 3 else {
            throw DocumentationGenerationError.missingCollisionOutput
        }
        let behaviors = [
            "base path reserved by the first sample",
            "seconds and milliseconds suffix resolves the same-minute collision",
            "numeric suffix resolves an identical timestamp suffix collision"
        ]
        let collisionRows = zip(resolvedNames, behaviors).map { name, behavior in
            "| legacy compatibility collision | `blood_glucose` | `\(collisionFolder)/\(requestedFilename)` | `\(collisionFolder)/\(name)` | \(behavior) |"
        }

        return """
        # Individual entry filename and path matrix

        All paths below were generated with the production `IndividualTrackingSettings.folderPath`, `IndividualEntryExporter.filename`, and file export collision resolver. Dates and UUIDs are fixed synthetic fixtures in UTC.

        ## Canonical UUID-backed paths

        | Fixture | Metric | Generated relative path | Identity behavior |
        |---|---|---|---|
        \(canonicalRows.joined(separator: "\n"))

        Canonical filenames always include the lowercased original HealthKit UUID. Re-exporting the same canonical record therefore resolves to the same path, and distinct records in the same minute remain distinct without order-dependent suffixes.

        ## UUID-free compatibility collisions

        | Fixture | Metric | Filename requested for every sample | Resolved relative path | Collision behavior |
        |---|---|---|---|---|
        \(collisionRows.joined(separator: "\n"))

        UUID-free compatibility entries keep the configured minute-precision base filename for the first sample. Later collisions receive the production seconds-and-milliseconds suffix, followed by a numeric suffix only when that suffix is also reserved during the export run.
        """ + "\n"
    }

    private static func metricDefinition(for sample: IndividualHealthSample) -> HealthMetricDefinition {
        HealthMetrics.all.first(where: { $0.id == sample.metricId }) ?? HealthMetricDefinition(
            id: sample.metricId,
            name: sample.metricName,
            category: sample.category,
            unit: sample.unit,
            healthKitIdentifier: nil,
            metricType: .quantity,
            aggregation: .mostRecent
        )
    }

    private static func frontmatterInventory(
        _ documents: [(document: String, content: String)]
    ) -> String {
        var inventory: [String: (types: Set<String>, documents: Set<String>)] = [:]
        for document in documents {
            for observation in frontmatterObservations(document.content) {
                inventory[observation.path, default: ([], [])].types.insert(observation.type)
                inventory[observation.path, default: ([], [])].documents.insert(document.document)
            }
        }

        let rows = inventory.keys.sorted().map { path -> String in
            let entry = inventory[path]!
            return "| `\(path)` | `\(entry.types.sorted().joined(separator: " | "))` | \(entry.documents.sorted().map { "`\($0)`" }.joined(separator: ", ")) |"
        }

        return """
        # Generated frontmatter field and type inventory

        This inventory is derived from the complete generated frontmatter, including nested workout objects and arrays. Types describe the YAML representation emitted by `IndividualEntryExporter.previewEntryContent` for fixed synthetic fixtures.

        | Field path | Observed YAML type | Generated documents |
        |---|---|---|
        \(rows.joined(separator: "\n"))
        """ + "\n"
    }

    private static func frontmatterObservations(
        _ content: String
    ) -> [(path: String, type: String)] {
        let lines = content.components(separatedBy: "\n")
        guard lines.first == "---" else { return [] }

        var observations: [(String, String)] = []
        var containers: [(indent: Int, path: String)] = []
        for line in lines.dropFirst() {
            if line == "---" { break }
            let indent = line.prefix(while: { $0 == " " }).count
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            while let last = containers.last, last.indent >= indent {
                containers.removeLast()
            }

            if trimmed == "-" || trimmed.hasPrefix("- ") {
                guard let parent = containers.last else { continue }
                let item = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                if item.isEmpty {
                    observations.append((parent.path, "array<object>"))
                    containers.append((indent, parent.path + "[]"))
                    continue
                }
                guard let separator = item.firstIndex(of: ":") else {
                    observations.append((parent.path, "array<\(yamlType(of: item))>"))
                    continue
                }

                observations.append((parent.path, "array<object>"))
                containers.append((indent, parent.path + "[]"))
                let key = String(item[..<separator])
                let value = String(item[item.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                let path = parent.path + "[]." + key
                if value.isEmpty {
                    observations.append((path, "object"))
                    containers.append((indent + 1, path))
                } else {
                    observations.append((path, yamlType(of: value)))
                }
                continue
            }

            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            if let parent = containers.last {
                observations.append((parent.path, "object"))
            }
            let key = String(trimmed[..<separator])
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            let prefix = containers.last?.path
            let path = [prefix, key].compactMap { $0 }.joined(separator: ".")
            if value.isEmpty {
                containers.append((indent, path))
            } else if value == "[]" {
                observations.append((path, "array"))
            } else {
                observations.append((path, yamlType(of: value)))
            }
        }

        var merged: [String: Set<String>] = [:]
        for observation in observations {
            merged[observation.0, default: []].insert(observation.1)
        }
        return merged.keys.sorted().map { path in
            (path, merged[path]!.sorted().joined(separator: " | "))
        }
    }

    private static func yamlType(of scalar: String) -> String {
        if scalar.hasPrefix("\"") || scalar.hasPrefix("'") { return "string" }
        if scalar == "true" || scalar == "false" { return "boolean" }
        if scalar == "null" || scalar == "~" { return "null" }
        if scalar.range(of: #"^-?[0-9]+$"#, options: .regularExpression) != nil { return "integer" }
        if scalar.range(of: #"^-?(?:[0-9]+\.[0-9]+|[0-9]+[eE][+-]?[0-9]+)$"#, options: .regularExpression) != nil {
            return "number"
        }
        if scalar.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil {
            return "date"
        }
        if scalar.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T"#, options: .regularExpression) != nil {
            return "timestamp"
        }
        return "string"
    }

    private static func utcDate(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: value)!
    }
}

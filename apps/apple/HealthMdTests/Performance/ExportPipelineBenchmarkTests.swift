import Darwin
import XCTest
@testable import HealthMd

@MainActor
final class ExportPipelineBenchmarkTests: XCTestCase {
    func testRepresentativeOneThirtyAndYearSerializationBaselines() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HEALTHMD_RUN_EXPORT_BENCHMARKS"] == "1",
            "Set HEALTHMD_RUN_EXPORT_BENCHMARKS=1 in the test action to run export baselines."
        )

        let suiteName = "ExportPipelineBenchmarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = Set(ExportFormat.allCases)

        let calendar = Calendar(identifier: .gregorian)
        let endDate = calendar.startOfDay(for: Date())
        let records = (0..<365).map { offset in
            representativeRecord(
                date: calendar.date(byAdding: .day, value: offset - 364, to: endDate)!
            )
        }

        for dayCount in [1, 30, 365] {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            var outputBytes = 0
            var outputFiles = 0
            for record in records.suffix(dayCount) {
                let prepared = record.preparedExport(settings: settings)
                for format in ExportFormat.allCases {
                    let content = try prepared.content(format: format, settings: settings)
                    outputBytes += content.utf8.count
                    outputFiles += 1
                }
            }
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            let elapsedMilliseconds = Double(elapsedNanoseconds) / 1_000_000
            let report: [String: Any] = [
                "days": dayCount,
                "elapsed_ms": (elapsedMilliseconds * 100).rounded() / 100,
                "output_bytes": outputBytes,
                "output_files": outputFiles,
                "formats": ExportFormat.allCases.count
            ]
            let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("HEALTHMD_EXPORT_BENCHMARK \(String(decoding: reportData, as: UTF8.self))")

            XCTAssertEqual(outputFiles, dayCount * ExportFormat.allCases.count)
            XCTAssertGreaterThan(outputBytes, dayCount * 100)
        }
    }

    func testDenseLosslessSerializationAndPreparationBaseline() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HEALTHMD_RUN_EXPORT_BENCHMARKS"] == "1",
            "Set HEALTHMD_RUN_EXPORT_BENCHMARKS=1 in the test action to run export baselines."
        )

        let suiteName = "ExportPipelineBenchmarkTests.lossless.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json, .csv]

        var record = ExportFixtures.losslessDay
        let sourceArchive = try XCTUnwrap(record.healthKitRecordArchive)
        let repeatedRecords = (0..<256).flatMap { _ in sourceArchive.records }
        record.healthKitRecordArchive = HealthKitRecordArchive(
            captureStatus: sourceArchive.captureStatus,
            dailyOwnership: sourceArchive.dailyOwnership,
            records: repeatedRecords,
            externalRecords: sourceArchive.externalRecords,
            queryManifest: sourceArchive.queryManifest,
            integrityWarnings: sourceArchive.integrityWarnings,
            medicationInventoryRecords: sourceArchive.medicationInventoryRecords
        )
        let selectedRecord = record.filtered(by: settings.metricSelection)

        for (mode, prepare) in [
            ("regular", { selectedRecord.preparedExport(settings: settings) }),
            ("selection_applied", {
                selectedRecord.preparedExportAssumingSelectionApplied(settings: settings)
            })
        ] {
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let prepared = prepare()
            var outputBytes = 0
            for format in [ExportFormat.json, .csv] {
                outputBytes += try prepared.content(format: format, settings: settings).utf8.count
            }
            let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
            let report: [String: Any] = [
                "mode": mode,
                "records": repeatedRecords.count,
                "elapsed_ms": (Double(elapsedNanoseconds) / 10_000).rounded() / 100,
                "output_bytes": outputBytes
            ]
            let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print("HEALTHMD_LOSSLESS_EXPORT_BENCHMARK \(String(decoding: reportData, as: UTF8.self))")
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportPipelineBenchmarkTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let prepared = selectedRecord.preparedExportAssumingSelectionApplied(settings: settings)
        var outputBytes: UInt64 = 0
        for format in [ExportFormat.json, .csv] {
            let artifact = try prepared.renderArtifact(format: format, in: directory)
            outputBytes += artifact.descriptor.byteCount
        }
        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt
        let streamingReport: [String: Any] = [
            "mode": "selection_applied_streaming_files",
            "records": repeatedRecords.count,
            "elapsed_ms": (Double(elapsedNanoseconds) / 10_000).rounded() / 100,
            "output_bytes": outputBytes
        ]
        let reportData = try JSONSerialization.data(
            withJSONObject: streamingReport,
            options: [.sortedKeys]
        )
        print("HEALTHMD_LOSSLESS_EXPORT_BENCHMARK \(String(decoding: reportData, as: UTF8.self))")
    }

    func testDenseConnectedApplicationItemEncodingBaseline() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HEALTHMD_RUN_EXPORT_BENCHMARKS"] == "1",
            "Set HEALTHMD_RUN_EXPORT_BENCHMARKS=1 in the test action to run export baselines."
        )
        var record = ExportFixtures.losslessDay
        let sourceArchive = try XCTUnwrap(record.healthKitRecordArchive)
        let repeatedRecords = (0..<256).flatMap { _ in sourceArchive.records }
        record.healthKitRecordArchive = HealthKitRecordArchive(
            captureStatus: sourceArchive.captureStatus,
            dailyOwnership: sourceArchive.dailyOwnership,
            records: repeatedRecords,
            externalRecords: sourceArchive.externalRecords,
            queryManifest: sourceArchive.queryManifest,
            integrityWarnings: sourceArchive.integrityWarnings,
            medicationInventoryRecords: sourceArchive.medicationInventoryRecords
        )
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: record.date,
            isRequestedDate: true,
            record: record,
            externalDailyRecords: [],
            failure: nil
        )
        let baseline = Self.currentResidentBytes()
        let sampler = ResidentSampler()
        sampler.start()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let file = try ConnectedCorpusApplicationItemCodec.encode(
            payload,
            kind: .macHealthDay
        )
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        sampler.stop()
        defer { file.remove() }
        let decoded = try ConnectedCorpusApplicationItemCodec.decode(
            ConnectedCorpusHealthDayPayload.self,
            from: file.url,
            expectedKind: .macHealthDay
        )
        XCTAssertEqual(decoded.record?.healthKitRecordArchive?.records.count, repeatedRecords.count)
        let report: [String: Any] = [
            "records": repeatedRecords.count,
            "elapsed_ms": (elapsed * 100).rounded() / 100,
            "output_bytes": file.totalBytes,
            "rss_delta_bytes": sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("HEALTHMD_CITEM_BENCHMARK \(String(decoding: data, as: UTF8.self))")
        XCTAssertLessThan(elapsed, 60_000)
    }

    func testPhysicalConnectedApplicationItemReplayBaseline() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["HEALTHMD_PHYSICAL_CITEM_REPLAY_PATH"] else {
            throw XCTSkip("Set HEALTHMD_PHYSICAL_CITEM_REPLAY_PATH to a private captured .citem file.")
        }
        let expectedJSONPath = try XCTUnwrap(
            environment["HEALTHMD_PHYSICAL_CITEM_EXPECTED_JSON"],
            "Physical CITEM replay requires the exact expected JSON artifact."
        )
        let expectedCSVPath = try XCTUnwrap(
            environment["HEALTHMD_PHYSICAL_CITEM_EXPECTED_CSV"],
            "Physical CITEM replay requires the exact expected CSV artifact."
        )
        let expectedByFormat: [ExportFormat: ConnectedTransferPreparedFile] = [
            .json: try ConnectedTransferFile.inspect(URL(fileURLWithPath: expectedJSONPath)),
            .csv: try ConnectedTransferFile.inspect(URL(fileURLWithPath: expectedCSVPath)),
        ]
        let source = URL(fileURLWithPath: path)
        let payload = try ConnectedCorpusApplicationItemCodec.decode(
            ConnectedCorpusHealthDayPayload.self,
            from: source,
            expectedKind: .macHealthDay
        )
        let record = try XCTUnwrap(payload.record)
        let sourceFile = try ConnectedTransferFile.inspect(source)
        let encodeBaseline = Self.currentResidentBytes()
        let encodeSampler = ResidentSampler()
        encodeSampler.start()
        let encodeStartedAt = DispatchTime.now().uptimeNanoseconds
        let encoded = try ConnectedCorpusApplicationItemCodec.encode(
            payload,
            kind: .macHealthDay
        )
        let encodeElapsed = Double(
            DispatchTime.now().uptimeNanoseconds - encodeStartedAt
        ) / 1_000_000
        encodeSampler.stop()
        defer { encoded.remove() }
        XCTAssertEqual(encoded.totalBytes, sourceFile.totalBytes)
        XCTAssertEqual(encoded.sha256, sourceFile.sha256)
        let encodeReport: [String: Any] = [
            "elapsed_ms": (encodeElapsed * 100).rounded() / 100,
            "output_bytes": encoded.totalBytes,
            "rss_delta_bytes": encodeSampler.peakBytes > encodeBaseline
                ? encodeSampler.peakBytes - encodeBaseline : 0,
        ]
        let encodeReportData = try JSONSerialization.data(
            withJSONObject: encodeReport,
            options: [.sortedKeys]
        )
        print("HEALTHMD_PHYSICAL_CITEM_ENCODE \(String(decoding: encodeReportData, as: UTF8.self))")

        let suiteName = "ExportPipelineBenchmarkTests.replay.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json, .csv]
        settings.includeGranularData = true
        settings.includeMetadata = true
        settings.summaryOnlyExport = true
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(
            "HealthMdCITEMReplay-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: output) }
        let prepared = record.preparedExportAssumingSelectionApplied(settings: settings)
        var measurements: [[String: Any]] = []
        for format in [ExportFormat.csv, .json] {
            let baseline = Self.currentResidentBytes()
            let sampler = ResidentSampler()
            sampler.start()
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let artifact = try prepared.renderArtifact(format: format, in: output)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
            sampler.stop()
            measurements.append([
                "format": format.rawValue,
                "elapsed_ms": (elapsed * 100).rounded() / 100,
                "output_bytes": artifact.descriptor.byteCount,
                "rss_delta_bytes": sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0,
            ])
            XCTAssertGreaterThan(artifact.descriptor.byteCount, 0)
            let expected = try XCTUnwrap(expectedByFormat[format])
            XCTAssertEqual(artifact.descriptor.byteCount, UInt64(expected.totalBytes))
            XCTAssertEqual(artifact.descriptor.sha256, expected.sha256)
        }
        let report = try JSONSerialization.data(withJSONObject: measurements, options: [.sortedKeys])
        print("HEALTHMD_PHYSICAL_CITEM_REPLAY \(String(decoding: report, as: UTF8.self))")
    }

    func testFileBackedAttachmentStreamingMemoryBaseline() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["HEALTHMD_RUN_EXPORT_BENCHMARKS"] == "1",
            "Set HEALTHMD_RUN_EXPORT_BENCHMARKS=1 in the test action to run export baselines."
        )
        let byteCount = 32 * 1_024 * 1_024
        let chunk = Data(repeating: 0x5a, count: 128 * 1_024)
        let source = try ExportArtifactIO.renderTemporary(
            prefix: "attachment-memory-source",
            mediaType: "application/octet-stream"
        ) { sink in
            for _ in 0..<(byteCount / chunk.count) { try sink.write(chunk) }
        }
        let blob = HealthKitFileBackedBlob(artifact: source)
        let external = ClinicalDocumentVisionHealthKitRecordMapper.attachment(
            HealthKitAttachmentValue(
                identifier: UUID(uuidString: "20000000-0000-0000-0000-000000000099")!,
                filename: "benchmark.bin",
                uniformTypeIdentifier: "public.data",
                byteCount: Int64(byteCount),
                creationDate: ExportFixtures.referenceDate,
                data: nil,
                fileBackedData: blob,
                sha256: blob.sha256
            ),
            parentUUID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            parentObjectTypeIdentifier: "HKClinicalRecord",
            selectedMetricIDs: ["clinical_records"]
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-03-15",
                intervalStart: ExportFixtures.referenceDate,
                intervalEnd: ExportFixtures.referenceDate.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            externalRecords: [external]
        )
        let record = HealthData(
            date: ExportFixtures.referenceDate,
            timeContext: ExportFixtures.timeContext,
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )
        let suiteName = "ExportPipelineBenchmarkTests.attachment.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let prepared = record.preparedExportAssumingSelectionApplied(settings: settings)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ExportPipelineAttachmentBenchmark-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        var outputBytes: UInt64 = 0
        var peakOverhead: UInt64 = 0
        var formatOverheads: [String: UInt64] = [:]
        for format in [ExportFormat.json, .csv] {
            let baseline = Self.currentResidentBytes()
            let sampler = ResidentSampler()
            sampler.start()
            let artifact = try prepared.renderArtifact(format: format, in: directory)
            sampler.stop()
            outputBytes += artifact.descriptor.byteCount
            let overhead = sampler.peakBytes > baseline ? sampler.peakBytes - baseline : 0
            peakOverhead = max(peakOverhead, overhead)
            formatOverheads[format.rawValue] = overhead
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
        let report: [String: Any] = [
            "attachment_bytes": byteCount,
            "elapsed_ms": (Double(elapsed) / 10_000).rounded() / 100,
            "output_bytes": outputBytes,
            "peak_rss_delta_bytes": peakOverhead,
            "format_rss_delta_bytes": formatOverheads
        ]
        let reportData = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("HEALTHMD_FILE_BACKED_ATTACHMENT_BENCHMARK \(String(decoding: reportData, as: UTF8.self))")
        XCTAssertLessThan(peakOverhead, UInt64(48 * 1_024 * 1_024))
    }

    private func representativeRecord(date: Date) -> HealthData {
        let heartRateSamples = (0..<288).map { index in
            TimeSample(
                timestamp: date.addingTimeInterval(Double(index * 300)),
                value: 58 + Double(index % 65),
                metadata: ["source": "benchmark"]
            )
        }
        let workoutSamples = (0..<120).map { index in
            TimeSeriesSample(
                timestamp: date.addingTimeInterval(43_200 + Double(index * 5)),
                value: 120 + Double(index % 45)
            )
        }
        let sleepStart = date.addingTimeInterval(-28_800)
        let sleepEnd = date.addingTimeInterval(-1_800)

        var record = HealthData(date: date)
        record.sleep = SleepData(
            totalDuration: 27_000,
            deepSleep: 5_400,
            remSleep: 6_300,
            coreSleep: 14_400,
            awakeTime: 900,
            inBedTime: 28_800,
            sessionStart: sleepStart,
            sessionEnd: sleepEnd,
            stages: [
                SleepStageSample(stage: "core", startDate: sleepStart, endDate: sleepStart.addingTimeInterval(7_200)),
                SleepStageSample(stage: "deep", startDate: sleepStart.addingTimeInterval(7_200), endDate: sleepStart.addingTimeInterval(12_600)),
                SleepStageSample(stage: "rem", startDate: sleepStart.addingTimeInterval(12_600), endDate: sleepEnd)
            ]
        )
        record.activity.steps = 10_234
        record.activity.activeCalories = 612
        record.activity.exerciseMinutes = 54
        record.activity.walkingRunningDistance = 8_420
        record.heart.averageHeartRate = 78
        record.heart.restingHeartRate = 56
        record.heart.heartRateMin = 49
        record.heart.heartRateMax = 172
        record.heart.hrv = 48
        record.heart.heartRateSamples = heartRateSamples
        record.vitals.respiratoryRateAvg = 15.2
        record.vitals.bloodOxygenAvg = 97.4
        record.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: date.addingTimeInterval(43_200),
                duration: 1_800,
                calories: 320,
                distance: 5_000,
                avgHeartRate: 148,
                maxHeartRate: 172,
                minHeartRate: 112,
                timeSeries: WorkoutTimeSeries(heartRate: workoutSamples)
            )
        ]
        return record
    }

    nonisolated private static func currentResidentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    nonisolated private final class ResidentSampler: @unchecked Sendable {
        private let lock = NSLock()
        private var running = false
        private var peak: UInt64 = 0
        private let group = DispatchGroup()

        var peakBytes: UInt64 {
            lock.lock(); defer { lock.unlock() }
            return peak
        }

        func start() {
            lock.lock()
            running = true
            peak = ExportPipelineBenchmarkTests.currentResidentBytes()
            lock.unlock()
            group.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                defer { group.leave() }
                while true {
                    lock.lock()
                    let shouldContinue = running
                    peak = max(peak, ExportPipelineBenchmarkTests.currentResidentBytes())
                    lock.unlock()
                    if !shouldContinue { return }
                    usleep(2_000)
                }
            }
        }

        func stop() {
            lock.lock()
            running = false
            peak = max(peak, ExportPipelineBenchmarkTests.currentResidentBytes())
            lock.unlock()
            group.wait()
        }
    }
}

import Foundation

/// A strict raw-result JSON object prepared on disk. The object is the public
/// `healthmd.raw_result` value (not an internal Codable transport envelope), so
/// callers can embed it in a streamed control response without materializing the
/// complete corpus in memory.
struct CanonicalRawResultSpool {
    let file: ConnectedTransferPreparedFile
    let captureSummary: CanonicalRawCaptureSummary
    let missingDates: [String]
    let totalRequestedDays: Int
    let dateRangeStart: String
    let dateRangeEnd: String

    var hasPartialResult: Bool {
        captureSummary.partialDayCount > 0
            || captureSummary.failedDayCount > 0
            || captureSummary.cancelledDayCount > 0
            || captureSummary.missingDayCount > 0
            || !missingDates.isEmpty
    }

    func remove() {
        file.remove()
    }
}

/// Composes a strict raw result one daily spool at a time. Peak memory is bounded
/// by one canonical day rather than the complete requested corpus.
enum CanonicalRawResultSpoolWriter {
    enum WriterError: Error, Equatable {
        case dayCountMismatch
        case dateMismatch(expected: String, actual: String)
        case invalidDay(date: String, issues: [String])
        case invalidJSONObject
    }

    static func write(
        createdAt: Date,
        sourceDeviceName: String,
        expectedDates: [String],
        dayFiles: [URL],
        progress: ((_ processed: Int, _ total: Int) -> Void)? = nil,
        cancellationCheck: () -> Bool = { false }
    ) async throws -> CanonicalRawResultSpool {
        guard dayFiles.count == expectedDates.count else {
            throw WriterError.dayCountMismatch
        }

        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "canonical-raw-result")
        let handle = try FileHandle(forWritingTo: outputURL)
        var shouldRemoveOutput = true
        defer {
            try? handle.close()
            if shouldRemoveOutput { try? FileManager.default.removeItem(at: outputURL) }
        }

        var accumulator = CanonicalRawCaptureAccumulator()
        var missingDates: [String] = []
        let decoder = JSONDecoder()

        do {
            try handle.write(contentsOf: Data("{".utf8))
            try writeJSONKey("schema", value: CanonicalRawResultEnvelope.schemaIdentifier, to: handle, leadingComma: false)
            try writeJSONKey("schema_version", value: CanonicalRawResultEnvelope.currentSchemaVersion, to: handle)
            try writeJSONKey("profile", value: IPhoneExportRequest.RawProfile.canonicalSourceRecordsV1.rawValue, to: handle)
            try writeJSONKey("created_at", value: CanonicalRFC3339UTC.string(from: createdAt), to: handle)
            try writeJSONKey("source_device_name", value: sourceDeviceName, to: handle)
            try writeJSONKey(
                "date_range",
                value: ["start": expectedDates.first ?? "", "end": expectedDates.last ?? ""],
                to: handle
            )
            try writeJSONKey("total_requested_days", value: expectedDates.count, to: handle)
            try handle.write(contentsOf: Data(",\"days\":[".utf8))

            for (index, fileURL) in dayFiles.enumerated() {
                let dayData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                let day = try decoder.decode(CanonicalRawDayResult.self, from: dayData)
                let expectedDate = expectedDates[index]
                guard day.date == expectedDate else {
                    throw WriterError.dateMismatch(expected: expectedDate, actual: day.date)
                }

                let validationEnvelope = CanonicalRawResultEnvelope(
                    createdAt: createdAt,
                    sourceDeviceName: sourceDeviceName,
                    requestedDates: [expectedDate],
                    days: [day]
                )
                let issues = validationEnvelope.strictValidationIssues(expectedDates: [expectedDate])
                guard issues.isEmpty else {
                    throw WriterError.invalidDay(date: expectedDate, issues: issues)
                }

                if index > 0 { try handle.write(contentsOf: Data(",".utf8)) }
                let object = try day.controlAPIJSONObject()
                let encodedObject = try JSONSerialization.data(
                    withJSONObject: object,
                    options: [.sortedKeys, .withoutEscapingSlashes]
                )
                try handle.write(contentsOf: encodedObject)
                accumulator.append(day)
                if day.status == .missing { missingDates.append(day.date) }
                progress?(index + 1, dayFiles.count)
                if cancellationCheck() { throw CancellationError() }
                try Task.checkCancellation()
                await Task.yield()
            }

            if cancellationCheck() { throw CancellationError() }
            try Task.checkCancellation()
            try handle.write(contentsOf: Data("]".utf8))
            try writeJSONKey("capture_summary", value: accumulator.summary.controlAPIJSONObject(), to: handle)
            try writeJSONKey("missing_dates", value: missingDates, to: handle)
            try handle.write(contentsOf: Data("}".utf8))
            try handle.synchronize()
            try handle.close()

            let inspected = try ConnectedTransferFile.inspect(outputURL)
            shouldRemoveOutput = false
            return CanonicalRawResultSpool(
                file: inspected,
                captureSummary: accumulator.summary,
                missingDates: missingDates,
                totalRequestedDays: expectedDates.count,
                dateRangeStart: expectedDates.first ?? "",
                dateRangeEnd: expectedDates.last ?? ""
            )
        } catch {
            throw error
        }
    }

    private static func writeJSONKey(
        _ key: String,
        value: Any,
        to handle: FileHandle,
        leadingComma: Bool = true
    ) throws {
        guard JSONSerialization.isValidJSONObject([key: value]) else {
            throw WriterError.invalidJSONObject
        }
        let keyData = try JSONSerialization.data(withJSONObject: key, options: [.fragmentsAllowed])
        let valueData = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
        if leadingComma { try handle.write(contentsOf: Data(",".utf8)) }
        try handle.write(contentsOf: keyData)
        try handle.write(contentsOf: Data(":".utf8))
        try handle.write(contentsOf: valueData)
    }
}

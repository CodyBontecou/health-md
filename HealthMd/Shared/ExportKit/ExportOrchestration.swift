import Foundation

public struct ExportDateWindowRequest: Equatable, Sendable {
    public var startDate: Date
    public var endDate: Date

    public init(startDate: Date, endDate: Date) {
        self.startDate = startDate
        self.endDate = endDate
    }

    /// Builds an array of calendar days from startDate through endDate (inclusive).
    public func dates(calendar: Calendar = .current) -> [Date] {
        var dates: [Date] = []
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }
}

public struct ExportRecordReference: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var date: Date?
    public var displayName: String

    public init(id: String, date: Date? = nil, displayName: String? = nil) {
        self.id = id
        self.date = date
        self.displayName = displayName ?? id
    }
}

public enum ExportRunFailureReason: String, Codable, Equatable, Sendable {
    case noDestination = "no_destination"
    case accessDenied = "access_denied"
    case noData = "no_data"
    case noFormatsSelected = "no_formats_selected"
    case protectedDataUnavailable = "protected_data_unavailable"
    case dataSourceError = "data_source_error"
    case renderError = "render_error"
    case writeError = "write_error"
    case cancelled = "cancelled"
    case unknown = "unknown"
}

public struct ExportRunFailure: Codable, Equatable, Sendable {
    public var reason: ExportRunFailureReason
    public var errorDescription: String?

    public init(reason: ExportRunFailureReason, errorDescription: String? = nil) {
        self.reason = reason
        self.errorDescription = errorDescription
    }
}

public struct ExportFailedRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String { record.id }
    public var record: ExportRecordReference
    public var failure: ExportRunFailure

    public init(record: ExportRecordReference, failure: ExportRunFailure) {
        self.record = record
        self.failure = failure
    }
}

public enum ExportRunStatus: String, Codable, Equatable, Sendable {
    case fullSuccess = "full_success"
    case partialSuccess = "partial_success"
    case failure
    case empty
}

public struct ExportRunResult: Codable, Equatable, Sendable {
    public var successCount: Int
    public var totalCount: Int
    public var filesWritten: Int
    public var failedRecords: [ExportFailedRecord]
    public var warnings: [ExportWarning]
    public var wasCancelled: Bool
    public var formatsPerRecord: Int

    public init(
        successCount: Int,
        totalCount: Int,
        filesWritten: Int,
        failedRecords: [ExportFailedRecord] = [],
        warnings: [ExportWarning] = [],
        wasCancelled: Bool = false,
        formatsPerRecord: Int = 1
    ) {
        self.successCount = successCount
        self.totalCount = totalCount
        self.filesWritten = filesWritten
        self.failedRecords = failedRecords
        self.warnings = warnings
        self.wasCancelled = wasCancelled
        self.formatsPerRecord = formatsPerRecord
    }

    public var status: ExportRunStatus {
        if totalCount == 0 { return .empty }
        if successCount == totalCount && !wasCancelled && failedRecords.isEmpty { return .fullSuccess }
        if successCount > 0 { return .partialSuccess }
        return .failure
    }

    public var isFullSuccess: Bool { status == .fullSuccess }
    public var isPartialSuccess: Bool { status == .partialSuccess }
    public var isFailure: Bool { status == .failure }
    public var primaryFailure: ExportRunFailure? { failedRecords.first?.failure }
}

public enum ExportProgressPhase: String, Codable, Equatable, Sendable {
    case planning
    case fetching
    case rendering
    case writing
    case completed
}

public struct ExportProgress: Codable, Equatable, Sendable {
    public var phase: ExportProgressPhase
    public var currentRecord: ExportRecordReference?
    public var currentIndex: Int
    public var totalRecords: Int
    public var successCount: Int
    public var filesWritten: Int
    public var currentFormatID: String?

    public init(
        phase: ExportProgressPhase,
        currentRecord: ExportRecordReference? = nil,
        currentIndex: Int = 0,
        totalRecords: Int,
        successCount: Int = 0,
        filesWritten: Int = 0,
        currentFormatID: String? = nil
    ) {
        self.phase = phase
        self.currentRecord = currentRecord
        self.currentIndex = currentIndex
        self.totalRecords = totalRecords
        self.successCount = successCount
        self.filesWritten = filesWritten
        self.currentFormatID = currentFormatID
    }
}

public struct ExportHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var sourceID: String
    public var success: Bool
    public var dateRangeStart: Date
    public var dateRangeEnd: Date
    public var successCount: Int
    public var totalCount: Int
    public var failure: ExportRunFailure?
    public var failedRecords: [ExportFailedRecord]
    public var targetLabel: String?
    public var fileCount: Int?
    public var warnings: [ExportWarning]
    public var wasCancelled: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sourceID: String,
        success: Bool,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        successCount: Int,
        totalCount: Int,
        failure: ExportRunFailure? = nil,
        failedRecords: [ExportFailedRecord] = [],
        targetLabel: String? = nil,
        fileCount: Int? = nil,
        warnings: [ExportWarning] = [],
        wasCancelled: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sourceID = sourceID
        self.success = success
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.successCount = successCount
        self.totalCount = totalCount
        self.failure = failure
        self.failedRecords = failedRecords
        self.targetLabel = targetLabel
        self.fileCount = fileCount
        self.warnings = warnings
        self.wasCancelled = wasCancelled
    }

    public init(
        runResult: ExportRunResult,
        sourceID: String,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        targetLabel: String? = nil,
        fileCount: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.init(
            timestamp: timestamp,
            sourceID: sourceID,
            success: runResult.successCount > 0,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            successCount: runResult.successCount,
            totalCount: runResult.totalCount,
            failure: runResult.primaryFailure,
            failedRecords: runResult.failedRecords,
            targetLabel: targetLabel,
            fileCount: fileCount ?? runResult.filesWritten,
            warnings: runResult.warnings,
            wasCancelled: runResult.wasCancelled
        )
    }
}

public struct ExportFetchedRecord<Record: ExportRecord> {
    public var record: Record?
    public var warnings: [ExportWarning]

    public init(record: Record?, warnings: [ExportWarning] = []) {
        self.record = record
        self.warnings = warnings
    }
}

public protocol ExportRecordDataSource {
    associatedtype Input
    associatedtype Record: ExportRecord

    func fetchRecord(for input: Input) async throws -> ExportFetchedRecord<Record>
}

public struct AnyExportRecordDataSource<Input, Record: ExportRecord>: ExportRecordDataSource {
    private let fetchClosure: (Input) async throws -> ExportFetchedRecord<Record>

    public init(fetch: @escaping (Input) async throws -> ExportFetchedRecord<Record>) {
        self.fetchClosure = fetch
    }

    public func fetchRecord(for input: Input) async throws -> ExportFetchedRecord<Record> {
        try await fetchClosure(input)
    }
}

public struct ExportRunWriteContext {
    public var formatIDs: [String]
    public var destination: ExportDestination?
    public var writeMode: ExportWriteMode

    public init(
        formatIDs: [String],
        destination: ExportDestination?,
        writeMode: ExportWriteMode
    ) {
        self.formatIDs = formatIDs
        self.destination = destination
        self.writeMode = writeMode
    }
}

public struct ExportRecordWriteSummary: Equatable, Sendable {
    public var filesWritten: Int
    public var warnings: [ExportWarning]

    public init(filesWritten: Int, warnings: [ExportWarning] = []) {
        self.filesWritten = filesWritten
        self.warnings = warnings
    }
}

public protocol ExportRecordWriter {
    associatedtype Record: ExportRecord

    func write(record: Record, context: ExportRunWriteContext) async throws -> ExportRecordWriteSummary
}

public struct AnyExportRecordWriter<Record: ExportRecord>: ExportRecordWriter {
    private let writeClosure: (Record, ExportRunWriteContext) async throws -> ExportRecordWriteSummary

    public init(write: @escaping (Record, ExportRunWriteContext) async throws -> ExportRecordWriteSummary) {
        self.writeClosure = write
    }

    public func write(record: Record, context: ExportRunWriteContext) async throws -> ExportRecordWriteSummary {
        try await writeClosure(record, context)
    }
}

public struct ExportRunRequest<Input> {
    public var recordInputs: [Input]
    public var formatIDs: [String]
    public var destination: ExportDestination?
    public var writeMode: ExportWriteMode
    public var requiresDestination: Bool
    public var requiresFormats: Bool
    public var recordReference: (Input) -> ExportRecordReference

    public init(
        recordInputs: [Input],
        formatIDs: [String],
        destination: ExportDestination?,
        writeMode: ExportWriteMode = .overwrite,
        requiresDestination: Bool = true,
        requiresFormats: Bool = true,
        recordReference: @escaping (Input) -> ExportRecordReference
    ) {
        self.recordInputs = recordInputs
        self.formatIDs = formatIDs
        self.destination = destination
        self.writeMode = writeMode
        self.requiresDestination = requiresDestination
        self.requiresFormats = requiresFormats
        self.recordReference = recordReference
    }
}

public struct ExportRunOrchestrator<Input, Record: ExportRecord> {
    public typealias FailureMapper = (Error) -> ExportRunFailure

    public var dataSource: AnyExportRecordDataSource<Input, Record>
    public var writer: AnyExportRecordWriter<Record>
    public var failureMapper: FailureMapper

    public init(
        dataSource: AnyExportRecordDataSource<Input, Record>,
        writer: AnyExportRecordWriter<Record>,
        failureMapper: @escaping FailureMapper = { error in
            ExportRunFailure(reason: .unknown, errorDescription: error.localizedDescription)
        }
    ) {
        self.dataSource = dataSource
        self.writer = writer
        self.failureMapper = failureMapper
    }

    public func run(
        _ request: ExportRunRequest<Input>,
        onProgress: ((ExportProgress) -> Void)? = nil
    ) async -> ExportRunResult {
        let total = request.recordInputs.count
        let formatsPerRecord = request.formatIDs.count
        onProgress?(ExportProgress(phase: .planning, totalRecords: total))

        if Task.isCancelled {
            let result = ExportRunResult(
                successCount: 0,
                totalCount: total,
                filesWritten: 0,
                wasCancelled: true,
                formatsPerRecord: formatsPerRecord
            )
            onProgress?(ExportProgress(
                phase: .completed,
                totalRecords: total,
                filesWritten: result.filesWritten
            ))
            return result
        }

        if let preflightFailure = preflightFailure(for: request) {
            return completePreflightFailure(
                request: request,
                total: total,
                formatsPerRecord: formatsPerRecord,
                failure: preflightFailure,
                onProgress: onProgress
            )
        }

        var successCount = 0
        var filesWritten = 0
        var failedRecords: [ExportFailedRecord] = []
        var warnings: [ExportWarning] = []
        let context = ExportRunWriteContext(
            formatIDs: request.formatIDs,
            destination: request.destination,
            writeMode: request.writeMode
        )

        for (offset, input) in request.recordInputs.enumerated() {
            if Task.isCancelled {
                return completedResult(
                    total: total,
                    successCount: successCount,
                    filesWritten: filesWritten,
                    failedRecords: failedRecords,
                    warnings: warnings,
                    wasCancelled: true,
                    formatsPerRecord: formatsPerRecord,
                    onProgress: onProgress
                )
            }

            let reference = request.recordReference(input)
            let index = offset + 1
            onProgress?(ExportProgress(
                phase: .fetching,
                currentRecord: reference,
                currentIndex: index,
                totalRecords: total,
                successCount: successCount,
                filesWritten: filesWritten
            ))

            do {
                let fetched = try await dataSource.fetchRecord(for: input)
                warnings.append(contentsOf: fetched.warnings)

                guard let record = fetched.record else {
                    failedRecords.append(ExportFailedRecord(
                        record: reference,
                        failure: ExportRunFailure(reason: .noData)
                    ))
                    continue
                }

                if Task.isCancelled {
                    return completedResult(
                        total: total,
                        successCount: successCount,
                        filesWritten: filesWritten,
                        failedRecords: failedRecords,
                        warnings: warnings,
                        wasCancelled: true,
                        formatsPerRecord: formatsPerRecord,
                        onProgress: onProgress
                    )
                }

                for formatID in request.formatIDs {
                    onProgress?(ExportProgress(
                        phase: .rendering,
                        currentRecord: reference,
                        currentIndex: index,
                        totalRecords: total,
                        successCount: successCount,
                        filesWritten: filesWritten,
                        currentFormatID: formatID
                    ))
                }

                onProgress?(ExportProgress(
                    phase: .writing,
                    currentRecord: reference,
                    currentIndex: index,
                    totalRecords: total,
                    successCount: successCount,
                    filesWritten: filesWritten
                ))

                let summary = try await writer.write(record: record, context: context)
                successCount += 1
                filesWritten += summary.filesWritten
                warnings.append(contentsOf: summary.warnings)
            } catch is CancellationError {
                return completedResult(
                    total: total,
                    successCount: successCount,
                    filesWritten: filesWritten,
                    failedRecords: failedRecords,
                    warnings: warnings,
                    wasCancelled: true,
                    formatsPerRecord: formatsPerRecord,
                    onProgress: onProgress
                )
            } catch {
                failedRecords.append(ExportFailedRecord(
                    record: reference,
                    failure: failureMapper(error)
                ))
            }
        }

        return completedResult(
            total: total,
            successCount: successCount,
            filesWritten: filesWritten,
            failedRecords: failedRecords,
            warnings: warnings,
            wasCancelled: false,
            formatsPerRecord: formatsPerRecord,
            onProgress: onProgress
        )
    }

    private func preflightFailure(for request: ExportRunRequest<Input>) -> ExportRunFailure? {
        if request.requiresDestination && request.destination == nil {
            return ExportRunFailure(reason: .noDestination)
        }
        if request.requiresFormats && request.formatIDs.isEmpty {
            return ExportRunFailure(
                reason: .noFormatsSelected,
                errorDescription: "At least one export format must be selected"
            )
        }
        return nil
    }

    private func completePreflightFailure(
        request: ExportRunRequest<Input>,
        total: Int,
        formatsPerRecord: Int,
        failure: ExportRunFailure,
        onProgress: ((ExportProgress) -> Void)?
    ) -> ExportRunResult {
        var failedRecords: [ExportFailedRecord] = []
        for (offset, input) in request.recordInputs.enumerated() {
            let reference = request.recordReference(input)
            onProgress?(ExportProgress(
                phase: .fetching,
                currentRecord: reference,
                currentIndex: offset + 1,
                totalRecords: total
            ))
            failedRecords.append(ExportFailedRecord(record: reference, failure: failure))
        }

        let result = ExportRunResult(
            successCount: 0,
            totalCount: total,
            filesWritten: 0,
            failedRecords: failedRecords,
            formatsPerRecord: formatsPerRecord
        )
        onProgress?(ExportProgress(
            phase: .completed,
            totalRecords: total,
            successCount: result.successCount,
            filesWritten: result.filesWritten
        ))
        return result
    }

    private func completedResult(
        total: Int,
        successCount: Int,
        filesWritten: Int,
        failedRecords: [ExportFailedRecord],
        warnings: [ExportWarning],
        wasCancelled: Bool,
        formatsPerRecord: Int,
        onProgress: ((ExportProgress) -> Void)?
    ) -> ExportRunResult {
        let result = ExportRunResult(
            successCount: successCount,
            totalCount: total,
            filesWritten: filesWritten,
            failedRecords: failedRecords,
            warnings: warnings,
            wasCancelled: wasCancelled,
            formatsPerRecord: formatsPerRecord
        )
        onProgress?(ExportProgress(
            phase: .completed,
            totalRecords: total,
            successCount: result.successCount,
            filesWritten: result.filesWritten
        ))
        return result
    }
}

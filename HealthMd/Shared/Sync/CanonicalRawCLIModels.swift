import Foundation

/// Versioned strict raw-result contract used by the CLI control path.
///
/// The sync representation carries each canonical daily document as a JSON string so
/// integer identity and the public exporter representation are not changed by an
/// intermediate Codable model. The local control server injects those documents as
/// JSON objects in its response.
struct CanonicalRawResultEnvelope: Codable, Equatable {
    static let schemaIdentifier = "healthmd.raw_result"
    static let currentSchemaVersion = 1

    let schema: String
    let schemaVersion: Int
    let profile: IPhoneExportRequest.RawProfile
    let createdAt: Date
    let sourceDeviceName: String
    let dateRangeStart: String
    let dateRangeEnd: String
    let totalRequestedDays: Int
    let days: [CanonicalRawDayResult]
    let captureSummary: CanonicalRawCaptureSummary
    let missingDates: [String]

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case profile
        case createdAt = "created_at"
        case sourceDeviceName = "source_device_name"
        case dateRangeStart = "date_range_start"
        case dateRangeEnd = "date_range_end"
        case totalRequestedDays = "total_requested_days"
        case days
        case captureSummary = "capture_summary"
        case missingDates = "missing_dates"
    }

    init(
        createdAt: Date,
        sourceDeviceName: String,
        requestedDates: [String],
        days suppliedDays: [CanonicalRawDayResult]
    ) {
        let uniqueRequestedDates = requestedDates.reduce(into: [String]()) { result, date in
            if !result.contains(date) { result.append(date) }
        }
        var suppliedByDate: [String: CanonicalRawDayResult] = [:]
        for day in suppliedDays where suppliedByDate[day.date] == nil {
            suppliedByDate[day.date] = day
        }
        let normalizedDays = uniqueRequestedDates.map { date in
            suppliedByDate[date] ?? .missing(date: date)
        }
        let missingDates = normalizedDays.filter { $0.status == .missing }.map(\.date)

        self.schema = Self.schemaIdentifier
        self.schemaVersion = Self.currentSchemaVersion
        self.profile = .canonicalSourceRecordsV1
        self.createdAt = createdAt
        self.sourceDeviceName = sourceDeviceName
        self.dateRangeStart = uniqueRequestedDates.first ?? ""
        self.dateRangeEnd = uniqueRequestedDates.last ?? ""
        self.totalRequestedDays = uniqueRequestedDates.count
        self.days = normalizedDays
        self.captureSummary = CanonicalRawCaptureSummary(days: normalizedDays)
        self.missingDates = missingDates
    }

    var calculatedCaptureSummary: CanonicalRawCaptureSummary {
        CanonicalRawCaptureSummary(days: days)
    }

    var hasPartialResult: Bool {
        let summary = calculatedCaptureSummary
        return summary.partialDayCount > 0 ||
            summary.failedDayCount > 0 ||
            summary.cancelledDayCount > 0 ||
            summary.missingDayCount > 0 ||
            !missingDates.isEmpty ||
            days.count != totalRequestedDays ||
            Set(days.map(\.date)).count != days.count
    }

    /// Validates receiver-side strict raw invariants independently of Codable.
    /// This prevents a same-count wrong date set, legacy daily document, or
    /// silently dropped lossless archive from being reported as success.
    func strictValidationIssues(
        expectedDates: [String],
        expectsLosslessArchive: Bool = true
    ) -> [String] {
        var issues: [String] = []
        if schema != Self.schemaIdentifier { issues.append("raw_result_schema_mismatch") }
        if schemaVersion != Self.currentSchemaVersion { issues.append("raw_result_schema_version_mismatch") }
        if profile != .canonicalSourceRecordsV1 { issues.append("raw_result_profile_mismatch") }
        if totalRequestedDays != expectedDates.count { issues.append("raw_result_total_requested_days_mismatch") }
        if dateRangeStart != (expectedDates.first ?? "") || dateRangeEnd != (expectedDates.last ?? "") {
            issues.append("raw_result_date_range_mismatch")
        }

        let suppliedDates = days.map(\.date)
        if Set(suppliedDates).count != suppliedDates.count {
            issues.append("raw_result_duplicate_dates")
        }
        if suppliedDates != expectedDates {
            issues.append("raw_result_date_set_mismatch")
        }
        if captureSummary != calculatedCaptureSummary {
            issues.append("raw_result_capture_summary_mismatch")
        }
        let calculatedMissingDates = days.filter { $0.status == .missing }.map(\.date).sorted()
        if missingDates.sorted() != calculatedMissingDates {
            issues.append("raw_result_missing_dates_mismatch")
        }

        for day in days {
            let retainedStatus = day.status != .failed && day.status != .cancelled && day.status != .missing
            guard let canonicalDailyJSON = day.canonicalDailyJSON else {
                if retainedStatus { issues.append("daily_health_data_missing:\(day.date)") }
                continue
            }
            guard let data = canonicalDailyJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                issues.append("daily_health_data_invalid_json:\(day.date)")
                continue
            }
            if object["schema"] as? String != HealthMdExportSchema.identifier {
                issues.append("daily_schema_mismatch:\(day.date)")
            }
            if object["schema_version"] as? Int != HealthMdExportSchema.version {
                issues.append("daily_schema_version_mismatch:\(day.date)")
            }
            if expectsLosslessArchive {
                guard let archive = object["healthkit_record_archive"] as? [String: Any] else {
                    issues.append("canonical_archive_missing:\(day.date)")
                    continue
                }
                if archive["schema"] as? String != HealthKitRecordArchive.canonicalSchemaIdentifier {
                    issues.append("canonical_archive_schema_mismatch:\(day.date)")
                }
                if archive["schema_version"] as? Int != HealthKitRecordArchive.currentRecordSchemaVersion {
                    issues.append("canonical_archive_schema_version_mismatch:\(day.date)")
                }
            }
        }
        return issues
    }

    /// Public local-control representation. `health_data` is the canonical daily
    /// `healthmd.health_data` JSON object, never internal `HealthData` Codable.
    func controlAPIJSONObject() throws -> [String: Any] {
        let object: [String: Any] = [
            "schema": schema,
            "schema_version": schemaVersion,
            "profile": profile.rawValue,
            "created_at": CanonicalRFC3339UTC.string(from: createdAt),
            "source_device_name": sourceDeviceName,
            "date_range": [
                "start": dateRangeStart,
                "end": dateRangeEnd
            ],
            "total_requested_days": totalRequestedDays,
            "days": try days.map { try $0.controlAPIJSONObject() },
            "capture_summary": calculatedCaptureSummary.controlAPIJSONObject(),
            "missing_dates": Array(Set(missingDates + days.filter { $0.status == .missing }.map(\.date))).sorted()
        ]
        return object
    }
}

enum CanonicalRawDayCaptureStatus: String, Codable, Equatable {
    case complete
    case completeEmpty = "complete_empty"
    case completeWithWarnings = "complete_with_warnings"
    case partial
    case failed
    case cancelled
    case missing
}

struct CanonicalRawQueryStatusCounts: Codable, Equatable {
    var success = 0
    var failure = 0
    var unsupported = 0
    var skipped = 0
    var cancelled = 0

    init(results: [HealthKitQueryResult] = []) {
        for result in results {
            switch result.status {
            case .success: success += 1
            case .failure: failure += 1
            case .unsupported: unsupported += 1
            case .skipped: skipped += 1
            case .cancelled: cancelled += 1
            }
        }
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        var result = Self()
        result.success = lhs.success + rhs.success
        result.failure = lhs.failure + rhs.failure
        result.unsupported = lhs.unsupported + rhs.unsupported
        result.skipped = lhs.skipped + rhs.skipped
        result.cancelled = lhs.cancelled + rhs.cancelled
        return result
    }

    var hasIncompleteQuery: Bool {
        failure > 0 || unsupported > 0 || skipped > 0 || cancelled > 0
    }

    func controlAPIJSONObject() -> [String: Int] {
        [
            "success": success,
            "failure": failure,
            "unsupported": unsupported,
            "skipped": skipped,
            "cancelled": cancelled
        ]
    }
}

struct CanonicalRawDayResult: Codable, Equatable {
    let date: String
    let status: CanonicalRawDayCaptureStatus
    let captureStatus: HealthKitRecordCaptureStatus?
    let sampleCount: Int
    let recordCount: Int
    let queryStatusCounts: CanonicalRawQueryStatusCounts
    let integrityWarningCount: Int
    let integrityWarningCodes: [String]
    let partialFailureCount: Int
    let partialFailureTypes: [String]
    let failureCode: String?
    /// Sync-only transport representation. The control API exposes this as the
    /// nested `health_data` object instead of a JSON-encoded string.
    let canonicalDailyJSON: String?

    enum CodingKeys: String, CodingKey {
        case date
        case status
        case captureStatus = "capture_status"
        case sampleCount = "sample_count"
        case recordCount = "record_count"
        case queryStatusCounts = "query_status_counts"
        case integrityWarningCount = "integrity_warning_count"
        case integrityWarningCodes = "integrity_warning_codes"
        case partialFailureCount = "partial_failure_count"
        case partialFailureTypes = "partial_failure_types"
        case failureCode = "failure_code"
        case canonicalDailyJSON = "canonical_daily_json"
    }

    static func captured(
        _ record: HealthData,
        customization: FormatCustomization
    ) throws -> Self {
        let archive = record.healthKitRecordArchive
        let queryCounts = CanonicalRawQueryStatusCounts(results: archive?.queryResults ?? [])
        let warningCodes = Array(Set(archive?.integrityWarnings.map(\.code) ?? [])).sorted()
        let partialFailureTypes = Array(Set(record.partialFailures.map(\.dataType))).sorted()

        let status: CanonicalRawDayCaptureStatus
        if archive?.captureStatus != .complete || queryCounts.hasIncompleteQuery || !record.partialFailures.isEmpty {
            status = .partial
        } else if !warningCodes.isEmpty {
            status = .completeWithWarnings
        } else if !record.hasSummaryData,
                  archive?.records.isEmpty != false,
                  archive?.externalRecords.isEmpty != false,
                  archive?.medicationInventoryRecords.isEmpty != false {
            status = .completeEmpty
        } else {
            status = .complete
        }

        let canonicalJSON = try record.toJSONThrowing(customization: customization)
        guard let data = canonicalJSON.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schema"] as? String == HealthMdExportSchema.identifier,
              object["schema_version"] as? Int == HealthMdExportSchema.version,
              object["time_context"] != nil,
              let canonicalArchive = object["healthkit_record_archive"] as? [String: Any],
              canonicalArchive["schema"] as? String == HealthKitRecordArchive.canonicalSchemaIdentifier,
              canonicalArchive["schema_version"] as? Int == HealthKitRecordArchive.currentRecordSchemaVersion else {
            throw CanonicalRawResultError.invalidCanonicalDailyDocument
        }

        return Self(
            date: canonicalDate(for: record),
            status: status,
            captureStatus: record.healthKitRecordCaptureStatus,
            sampleCount: archive?.records.count ?? 0,
            recordCount: (archive?.records.count ?? 0) +
                (archive?.externalRecords.count ?? 0) +
                (archive?.medicationInventoryRecords.count ?? 0),
            queryStatusCounts: queryCounts,
            integrityWarningCount: archive?.integrityWarnings.count ?? 0,
            integrityWarningCodes: warningCodes,
            partialFailureCount: record.partialFailures.count,
            partialFailureTypes: partialFailureTypes,
            failureCode: nil,
            canonicalDailyJSON: canonicalJSON
        )
    }

    static func failed(date: String, code: String) -> Self {
        Self(
            date: date,
            status: .failed,
            captureStatus: nil,
            sampleCount: 0,
            recordCount: 0,
            queryStatusCounts: .init(),
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: code,
            canonicalDailyJSON: nil
        )
    }

    static func cancelled(date: String) -> Self {
        Self(
            date: date,
            status: .cancelled,
            captureStatus: nil,
            sampleCount: 0,
            recordCount: 0,
            queryStatusCounts: .init(),
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: "cancelled",
            canonicalDailyJSON: nil
        )
    }

    static func missing(date: String) -> Self {
        Self(
            date: date,
            status: .missing,
            captureStatus: nil,
            sampleCount: 0,
            recordCount: 0,
            queryStatusCounts: .init(),
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: "missing_day",
            canonicalDailyJSON: nil
        )
    }

    func controlAPIJSONObject() throws -> [String: Any] {
        var object: [String: Any] = [
            "date": date,
            "status": status.rawValue,
            "sample_count": sampleCount,
            "record_count": recordCount,
            "query_status_counts": queryStatusCounts.controlAPIJSONObject(),
            "integrity_warning_count": integrityWarningCount,
            "integrity_warning_codes": integrityWarningCodes,
            "partial_failure_count": partialFailureCount,
            "partial_failure_types": partialFailureTypes
        ]
        if let captureStatus {
            object["capture_status"] = HealthKitRecordArchiveSerializer.captureStatusString(captureStatus)
        }
        if let failureCode { object["failure_code"] = failureCode }
        if let canonicalDailyJSON,
           let data = canonicalDailyJSON.data(using: .utf8) {
            object["health_data"] = try JSONSerialization.jsonObject(with: data)
        }
        return object
    }

    private static func canonicalDate(for record: HealthData) -> String {
        if let ownerDate = record.healthKitRecordArchive?.dailyOwnership.ownerDate {
            return ownerDate
        }
        return HealthKitDailyOwnershipMetadata.ownerDate(
            for: record.date,
            calendarTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier
        )
    }
}

struct CanonicalRawCaptureAccumulator: Codable, Equatable {
    private(set) var retainedDayCount = 0
    private(set) var completeDayCount = 0
    private(set) var completeEmptyDayCount = 0
    private(set) var warningDayCount = 0
    private(set) var partialDayCount = 0
    private(set) var failedDayCount = 0
    private(set) var cancelledDayCount = 0
    private(set) var missingDayCount = 0
    private(set) var sampleCount = 0
    private(set) var recordCount = 0
    private(set) var queryStatusCounts = CanonicalRawQueryStatusCounts()
    private(set) var integrityWarningCount = 0
    private(set) var partialFailureCount = 0
    private(set) var dayStatusCounts: [String: Int] = [:]

    mutating func append(_ day: CanonicalRawDayResult) {
        if day.canonicalDailyJSON != nil { retainedDayCount += 1 }
        switch day.status {
        case .complete: completeDayCount += 1
        case .completeEmpty: completeEmptyDayCount += 1
        case .completeWithWarnings: warningDayCount += 1
        case .partial: partialDayCount += 1
        case .failed: failedDayCount += 1
        case .cancelled: cancelledDayCount += 1
        case .missing: missingDayCount += 1
        }
        sampleCount += day.sampleCount
        recordCount += day.recordCount
        queryStatusCounts = queryStatusCounts + day.queryStatusCounts
        integrityWarningCount += day.integrityWarningCount
        partialFailureCount += day.partialFailureCount
        dayStatusCounts[day.status.rawValue, default: 0] += 1
    }

    var summary: CanonicalRawCaptureSummary {
        CanonicalRawCaptureSummary(
            retainedDayCount: retainedDayCount,
            completeDayCount: completeDayCount,
            completeEmptyDayCount: completeEmptyDayCount,
            warningDayCount: warningDayCount,
            partialDayCount: partialDayCount,
            failedDayCount: failedDayCount,
            cancelledDayCount: cancelledDayCount,
            missingDayCount: missingDayCount,
            sampleCount: sampleCount,
            recordCount: recordCount,
            queryStatusCounts: queryStatusCounts,
            integrityWarningCount: integrityWarningCount,
            partialFailureCount: partialFailureCount,
            dayStatusCounts: dayStatusCounts
        )
    }
}

struct CanonicalRawCaptureSummary: Codable, Equatable {
    let retainedDayCount: Int
    let completeDayCount: Int
    let completeEmptyDayCount: Int
    let warningDayCount: Int
    let partialDayCount: Int
    let failedDayCount: Int
    let cancelledDayCount: Int
    let missingDayCount: Int
    let sampleCount: Int
    let recordCount: Int
    let queryStatusCounts: CanonicalRawQueryStatusCounts
    let integrityWarningCount: Int
    let partialFailureCount: Int
    let dayStatusCounts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case retainedDayCount = "retained_day_count"
        case completeDayCount = "complete_day_count"
        case completeEmptyDayCount = "complete_empty_day_count"
        case warningDayCount = "warning_day_count"
        case partialDayCount = "partial_day_count"
        case failedDayCount = "failed_day_count"
        case cancelledDayCount = "cancelled_day_count"
        case missingDayCount = "missing_day_count"
        case sampleCount = "sample_count"
        case recordCount = "record_count"
        case queryStatusCounts = "query_status_counts"
        case integrityWarningCount = "integrity_warning_count"
        case partialFailureCount = "partial_failure_count"
        case dayStatusCounts = "day_status_counts"
    }

    init(days: [CanonicalRawDayResult]) {
        var accumulator = CanonicalRawCaptureAccumulator()
        for day in days { accumulator.append(day) }
        self = accumulator.summary
    }

    init(
        retainedDayCount: Int,
        completeDayCount: Int,
        completeEmptyDayCount: Int,
        warningDayCount: Int,
        partialDayCount: Int,
        failedDayCount: Int,
        cancelledDayCount: Int,
        missingDayCount: Int,
        sampleCount: Int,
        recordCount: Int,
        queryStatusCounts: CanonicalRawQueryStatusCounts,
        integrityWarningCount: Int,
        partialFailureCount: Int,
        dayStatusCounts: [String: Int]
    ) {
        self.retainedDayCount = retainedDayCount
        self.completeDayCount = completeDayCount
        self.completeEmptyDayCount = completeEmptyDayCount
        self.warningDayCount = warningDayCount
        self.partialDayCount = partialDayCount
        self.failedDayCount = failedDayCount
        self.cancelledDayCount = cancelledDayCount
        self.missingDayCount = missingDayCount
        self.sampleCount = sampleCount
        self.recordCount = recordCount
        self.queryStatusCounts = queryStatusCounts
        self.integrityWarningCount = integrityWarningCount
        self.partialFailureCount = partialFailureCount
        self.dayStatusCounts = dayStatusCounts
    }

    func controlAPIJSONObject() -> [String: Any] {
        [
            "retained_day_count": retainedDayCount,
            "complete_day_count": completeDayCount,
            "complete_empty_day_count": completeEmptyDayCount,
            "warning_day_count": warningDayCount,
            "partial_day_count": partialDayCount,
            "failed_day_count": failedDayCount,
            "cancelled_day_count": cancelledDayCount,
            "missing_day_count": missingDayCount,
            "sample_count": sampleCount,
            "record_count": recordCount,
            "query_status_counts": queryStatusCounts.controlAPIJSONObject(),
            "integrity_warning_count": integrityWarningCount,
            "partial_failure_count": partialFailureCount,
            "day_status_counts": dayStatusCounts
        ]
    }
}

enum CanonicalRawResultError: Error {
    case invalidCanonicalDailyDocument
}

/// Builds a non-persisted request-scoped settings clone. Strict raw requests
/// always request canonical granular capture, regardless of the saved toggle.
enum IPhoneExportRequestSettingsResolver {
    static func settings(
        for request: IPhoneExportRequest,
        savedSettings: AdvancedExportSettings
    ) -> AdvancedExportSettings {
        let settings = ExportSettingsSnapshot.from(savedSettings).makeAdvancedExportSettings()

        switch request.settingsPolicy {
        case .currentIPhoneSettings:
            break
        case .requestedDatesOnly:
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
            settings.summaryOnlyExport = false
        }

        if request.rawProfile == .canonicalSourceRecordsV1 {
            settings.includeGranularData = true
            // Strict raw is a lossless capture profile, not a summary-only file job.
            // Keep this request-scoped so the saved iPhone setting is untouched.
            settings.summaryOnlyExport = false
        }
        return settings
    }
}

import Foundation

private let defaultBaseURL = "http://127.0.0.1:17645"

struct ParsedCommand {
    var baseURL = defaultBaseURL
    var command: Command
}

enum Command {
    case status
    case export(ExportOptions)
    case help
    case noOp
}

struct ExportOptions {
    var fromDate: String?
    var toDate: String?
    var lastDays: Int?
    var yesterday = false
    var timeout: Double = 300
    var raw = false
    var allowPartial = false
    var useIPhoneSettings = false
}

struct HTTPResult {
    let statusCode: Int
    let payload: Any
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case invalidDate(String)
    case invalidInteger(String)
    case invalidDouble(String)
    case invalidURL(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .invalidDate(let value): return "invalid date '\(value)', expected YYYY-MM-DD"
        case .invalidInteger(let value): return "invalid integer '\(value)'"
        case .invalidDouble(let value): return "invalid number '\(value)'"
        case .invalidURL(let value): return "invalid base URL '\(value)'"
        }
    }
}

@main
struct HealthMdCLI {
    static func main() async {
        do {
            let parsed = try parse(Array(CommandLine.arguments.dropFirst()))
            let exitCode = try await run(parsed)
            Foundation.exit(Int32(exitCode))
        } catch let error as CLIError {
            fputs("\(error.description)\n", stderr)
            Foundation.exit(2)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private func run(_ parsed: ParsedCommand) async throws -> Int {
    switch parsed.command {
    case .help:
        printGeneralHelp()
        return 0
    case .noOp:
        return 0
    case .status:
        let result = await requestJSON(method: "GET", path: "/v1/status", baseURL: parsed.baseURL)
        printJSON(result.payload)
        return result.statusCode == 200 ? 0 : 1
    case .export(let options):
        let range = try resolveDateRange(options)
        let body = makeExportRequestBody(
            options: options,
            startDate: range.start,
            endDate: range.end
        )
        let result = await requestJSON(
            method: "POST",
            path: "/v1/exports",
            body: body,
            baseURL: parsed.baseURL,
            timeout: max(options.timeout + 30, 60)
        )
        let status = (result.payload as? [String: Any])?["status"] as? String
        if options.raw, result.statusCode == 200 {
            let expectedDates = requestedISODateRange(startDate: range.start, endDate: range.end)
            let validation = validateStrictRawHTTPSuccess(
                payload: result.payload,
                expectedDates: expectedDates
            )
            if !validation.isValid {
                printJSON(validation.outputPayload)
                return 1
            }
        }
        printJSON(result.payload)
        return exportExitCode(
            httpStatusCode: result.statusCode,
            status: status,
            isRaw: options.raw,
            allowPartial: options.allowPartial
        )
    }
}

private func requestJSON(
    method: String,
    path: String,
    body: [String: Any]? = nil,
    baseURL: String,
    timeout: Double = 10
) async -> HTTPResult {
    guard let url = URL(string: baseURL + path) else {
        return HTTPResult(statusCode: 503, payload: ["error": "invalid_base_url", "message": baseURL])
    }

    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let payload = parsePayload(data) ?? [:]
        return HTTPResult(statusCode: statusCode, payload: payload)
    } catch {
        return HTTPResult(
            statusCode: 503,
            payload: [
                "error": "mac_app_unreachable",
                "message": readableNetworkError(error)
            ]
        )
    }
}

private func parsePayload(_ data: Data) -> Any? {
    guard !data.isEmpty else { return [:] }
    if let object = try? JSONSerialization.jsonObject(with: data, options: []) {
        return object
    }
    return String(data: data, encoding: .utf8).map { ["error": $0] }
}

private func readableNetworkError(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorCannotConnectToHost:
            return "Connection refused"
        case NSURLErrorTimedOut:
            return "The request timed out"
        default:
            break
        }
    }
    return error.localizedDescription
}

private func printJSON(_ object: Any) {
    let jsonObject: Any
    if JSONSerialization.isValidJSONObject(object) {
        jsonObject = object
    } else {
        jsonObject = ["error": String(describing: object)]
    }

    do {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    } catch {
        print("{\"error\":\"encode_failed\"}")
    }
}

func parse(_ arguments: [String]) throws -> ParsedCommand {
    var args = arguments
    var baseURL = defaultBaseURL

    if args.isEmpty || args.first == "-h" || args.first == "--help" {
        return ParsedCommand(baseURL: baseURL, command: .help)
    }

    if args.first == "--base-url" {
        guard args.count >= 2 else { throw CLIError.usage("--base-url requires a value") }
        baseURL = args[1]
        args.removeFirst(2)
    } else if let first = args.first, first.hasPrefix("--base-url=") {
        baseURL = String(first.dropFirst("--base-url=".count))
        args.removeFirst()
    }

    guard let command = args.first else { return ParsedCommand(baseURL: baseURL, command: .help) }
    args.removeFirst()

    switch command {
    case "status":
        if args.contains("-h") || args.contains("--help") {
            printStatusHelp()
            return ParsedCommand(baseURL: baseURL, command: .noOp)
        }
        return ParsedCommand(baseURL: baseURL, command: .status)
    case "export":
        if args.contains("-h") || args.contains("--help") {
            printExportHelp()
            return ParsedCommand(baseURL: baseURL, command: .noOp)
        }
        return ParsedCommand(baseURL: baseURL, command: .export(try parseExportOptions(args)))
    default:
        throw CLIError.usage("unknown command '\(command)'\n\nRun 'healthmd --help' for usage.")
    }
}

func parseExportOptions(_ args: [String]) throws -> ExportOptions {
    var options = ExportOptions()
    var index = 0

    func requireValue(for flag: String) throws -> String {
        guard index + 1 < args.count else { throw CLIError.usage("\(flag) requires a value") }
        index += 1
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--from":
            let value = try requireValue(for: arg)
            options.fromDate = try normalizedISODate(value)
        case "--to":
            let value = try requireValue(for: arg)
            options.toDate = try normalizedISODate(value)
        case "--last":
            let value = try requireValue(for: arg)
            guard let n = Int(value) else { throw CLIError.invalidInteger(value) }
            options.lastDays = n
        case "--yesterday":
            options.yesterday = true
        case "--timeout":
            let value = try requireValue(for: arg)
            guard let timeout = Double(value),
                  timeout.isFinite,
                  timeout >= 5,
                  timeout <= 900 else {
                throw CLIError.usage("--timeout must be a finite number between 5 and 900 seconds")
            }
            options.timeout = timeout
        case "--raw":
            options.raw = true
        case "--allow-partial":
            options.allowPartial = true
        case "--use-iphone-settings":
            options.useIPhoneSettings = true
        case "--iphone":
            break
        default:
            throw CLIError.usage("unknown export option '\(arg)'\n\nRun 'healthmd export --help' for usage.")
        }
        index += 1
    }

    return options
}

func makeExportRequestBody(
    options: ExportOptions,
    startDate: String,
    endDate: String
) -> [String: Any] {
    var body: [String: Any] = [
        "source": "connected_iphone",
        "date_range": [
            "start": startDate,
            "end": endDate
        ],
        "settings_policy": options.useIPhoneSettings ? "current_iphone_settings" : "requested_dates_only",
        "response_mode": options.raw ? "raw_json" : "write_files",
        "wait_timeout_seconds": options.timeout
    ]
    if options.raw {
        body["raw_profile"] = "canonical_source_records_v1"
    }
    return body
}

private let strictRawResultSchema = "healthmd.raw_result"
private let strictRawResultVersion = 1
private let strictRawProfile = "canonical_source_records_v1"
private let currentDailySchema = "healthmd.health_data"
private let currentDailySchemaVersion = 6
private let currentArchiveSchema = "healthmd.healthkit_records"
private let currentArchiveSchemaVersion = 1

func strictRawValidationIssues(payload: Any, expectedDates: [String]) -> [String] {
    guard let response = payload as? [String: Any] else {
        return ["success_response_not_object"]
    }
    guard let rawResult = response["raw_result"] as? [String: Any] else {
        return ["raw_result_missing"]
    }

    var issues: [String] = []
    let responseStatus = response["status"] as? String
    if responseStatus != "success" && responseStatus != "partial_success" {
        issues.append("success_response_status_mismatch")
    }
    if rawResult["schema"] as? String != strictRawResultSchema {
        issues.append("raw_result_schema_mismatch")
    }
    if rawResult["schema_version"] as? Int != strictRawResultVersion {
        issues.append("raw_result_schema_version_mismatch")
    }
    if rawResult["profile"] as? String != strictRawProfile {
        issues.append("raw_result_profile_mismatch")
    }
    if rawResult["created_at"] as? String == nil {
        issues.append("raw_result_created_at_missing")
    }
    if rawResult["source_device_name"] as? String == nil {
        issues.append("raw_result_source_device_name_missing")
    }
    if rawResult["total_requested_days"] as? Int != expectedDates.count {
        issues.append("raw_result_total_requested_days_mismatch")
    }
    if let dateRange = rawResult["date_range"] as? [String: Any] {
        if dateRange["start"] as? String != expectedDates.first
            || dateRange["end"] as? String != expectedDates.last {
            issues.append("raw_result_date_range_mismatch")
        }
    } else {
        issues.append("raw_result_date_range_missing")
    }

    let captureSummary = rawResult["capture_summary"] as? [String: Any]
    if captureSummary == nil { issues.append("raw_result_capture_summary_missing") }
    let declaredMissingDates = rawResult["missing_dates"] as? [String]
    if declaredMissingDates == nil { issues.append("raw_result_missing_dates_missing") }

    guard let days = rawResult["days"] as? [[String: Any]] else {
        issues.append("raw_result_days_missing")
        return issues
    }
    let suppliedDates = days.compactMap { $0["date"] as? String }
    if suppliedDates.count != days.count {
        issues.append("raw_result_day_date_missing")
    }
    if Set(suppliedDates).count != suppliedDates.count {
        issues.append("raw_result_duplicate_dates")
    }
    if suppliedDates != expectedDates {
        issues.append("raw_result_date_set_mismatch")
    }
    let calculatedMissingDates = days.compactMap { day in
        day["status"] as? String == "missing" ? day["date"] as? String : nil
    }.sorted()
    if declaredMissingDates?.sorted() != calculatedMissingDates {
        issues.append("raw_result_missing_dates_mismatch")
    }
    let retainedDayCount = days.filter { $0["health_data"] is [String: Any] }.count
    if captureSummary?["retained_day_count"] as? Int != retainedDayCount {
        issues.append("raw_result_capture_summary_mismatch")
    }
    if captureSummary?["missing_day_count"] as? Int != calculatedMissingDates.count {
        issues.append("raw_result_capture_summary_mismatch")
    }

    for day in days {
        let date = day["date"] as? String ?? "unknown"
        let status = day["status"] as? String
        let mayOmitHealthData = responseStatus == "partial_success"
            && (status == "failed" || status == "cancelled" || status == "missing")
        guard let healthData = day["health_data"] as? [String: Any] else {
            if !mayOmitHealthData { issues.append("daily_health_data_missing:\(date)") }
            continue
        }
        if healthData["schema"] as? String != currentDailySchema {
            issues.append("daily_schema_mismatch:\(date)")
        }
        if healthData["schema_version"] as? Int != currentDailySchemaVersion {
            issues.append("daily_schema_version_mismatch:\(date)")
        }
        guard let archive = healthData["healthkit_record_archive"] as? [String: Any] else {
            issues.append("canonical_archive_missing:\(date)")
            continue
        }
        if archive["schema"] as? String != currentArchiveSchema {
            issues.append("canonical_archive_schema_mismatch:\(date)")
        }
        if archive["schema_version"] as? Int != currentArchiveSchemaVersion {
            issues.append("canonical_archive_schema_version_mismatch:\(date)")
        }
    }
    return issues
}

func validateStrictRawHTTPSuccess(
    payload: Any,
    expectedDates: [String]
) -> (isValid: Bool, outputPayload: Any) {
    let issues = strictRawValidationIssues(payload: payload, expectedDates: expectedDates)
    guard !issues.isEmpty else { return (true, payload) }
    return (false, strictRawValidationFailurePayload(
        serverPayload: payload,
        expectedDates: expectedDates,
        issues: issues
    ))
}

func strictRawValidationFailurePayload(
    serverPayload: Any,
    expectedDates: [String],
    issues: [String]
) -> [String: Any] {
    [
        "status": "failure",
        "error": "invalid_strict_raw_success",
        "message": "The Mac app returned HTTP 200 with an invalid strict raw success envelope.",
        "diagnostics": [
            "validation": "strict_raw_success_envelope",
            "issues": issues,
            "requested_dates": expectedDates
        ],
        "server_response": serverPayload
    ]
}

func requestedISODateRange(startDate: String, endDate: String) -> [String] {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let start = formatter.date(from: startDate),
          let end = formatter.date(from: endDate),
          start <= end else { return [] }

    var dates: [String] = []
    var date = start
    while date <= end, dates.count <= 366 {
        dates.append(formatter.string(from: date))
        guard let next = formatter.calendar.date(byAdding: .day, value: 1, to: date) else { break }
        date = next
    }
    return dates
}

func exportExitCode(
    httpStatusCode: Int,
    status: String?,
    isRaw: Bool,
    allowPartial: Bool
) -> Int {
    guard httpStatusCode == 200 else { return 1 }
    switch status {
    case "success":
        return 0
    case "partial_success":
        // Preserve the historical file-export exit behavior. Strict raw capture
        // requires an explicit opt-in before partial results exit successfully.
        return !isRaw || allowPartial ? 0 : 1
    default:
        return 1
    }
}

private func resolveDateRange(_ options: ExportOptions) throws -> (start: String, end: String) {
    if options.yesterday {
        let day = dateString(daysFromToday: -1)
        return (day, day)
    }

    if let n = options.lastDays {
        guard n >= 1 && n <= 366 else { throw CLIError.usage("--last must be between 1 and 366") }
        let end = dateString(daysFromToday: -1)
        let start = dateString(daysFromToday: -n)
        return (start, end)
    }

    guard let fromDate = options.fromDate, let toDate = options.toDate else {
        throw CLIError.usage("export requires --from/--to, --last, or --yesterday")
    }
    return (fromDate, toDate)
}

private func normalizedISODate(_ value: String) throws -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: value) else { throw CLIError.invalidDate(value) }
    return formatter.string(from: date)
}

private func dateString(daysFromToday offset: Int) -> String {
    let calendar = Calendar.current
    let target = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    let components = calendar.dateComponents([.year, .month, .day], from: target)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
}

private func printGeneralHelp() {
    print("""
    usage: healthmd [-h] [--base-url BASE_URL] {status,export} ...

    Control the running Health.md Mac app

    positional arguments:
      {status,export}
        status         Show Mac app, iPhone, and destination readiness as JSON
        export         Ask the connected/open iPhone to export to this Mac

    options:
      -h, --help       show this help message and exit
    """)
}

private func printStatusHelp() {
    print("""
    usage: healthmd status [-h]

    Show Mac app, iPhone, and destination readiness as JSON
    """)
}

private func printExportHelp() {
    print("""
    usage: healthmd export [-h] [--from FROM_DATE] [--to TO_DATE] [--last LAST]
                           [--yesterday] [--timeout TIMEOUT] [--raw]
                           [--allow-partial] [--use-iphone-settings] [--iphone]

    options:
      -h, --help            show this help message and exit
      --from FROM_DATE      Start date, YYYY-MM-DD
      --to TO_DATE          End date, YYYY-MM-DD
      --last LAST           Export the last N complete days ending yesterday
      --yesterday           Export yesterday
      --timeout TIMEOUT     Inactivity timeout, 5...900 seconds (default: 300)
      --raw                 Return strict canonical_source_records_v1 JSON; do not write files
      --allow-partial       Exit 0 for a raw partial_success response (diagnostics are still printed)
      --use-iphone-settings Use the iPhone app's saved export settings exactly, including roll-ups
      --iphone              Accepted for readability; connected iPhone is the only export source
    """)
}

/// Local, health-free status text. This is deliberately not a Codable payload
/// field: deployed result bytes remain unchanged, and failure details, dates,
/// destination labels and paths never enter the summary.
enum MacExportResultSummary {
    static func message(for result: MacExportResultPayload) -> String {
        let status: String
        switch result.status {
        case .success: status = "Export completed"
        case .partialSuccess: status = "Export partially completed"
        case .failure: status = "Export failed"
        case .cancelled: status = "Export cancelled"
        }
        let files = result.generatedFileCountDescription ?? "file count unavailable"
        return "\(status): \(result.successCount) of \(result.totalCount) day(s); \(files)."
    }
}

import Foundation

struct ExportDateRange: Equatable {
    let startDate: Date
    let endDate: Date
}

enum ExportDateRangePreset: String, CaseIterable, Codable, Equatable, Identifiable {
    case today
    case yesterday
    case allTime
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return "Today"
        case .yesterday:
            return "Yesterday"
        case .allTime:
            return "All Time"
        case .custom:
            return "Custom"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .today:
            return "Sets the export date range to today."
        case .yesterday:
            return "Sets the export date range to yesterday."
        case .allTime:
            return "Sets the export date range to all available health data."
        case .custom:
            return "Shows start and end date pickers for a custom export range."
        }
    }

    func resolvedRange(
        referenceDate: Date = Date(),
        currentStartDate: Date,
        currentEndDate: Date,
        allTimeStartDate: Date? = nil,
        allTimeEndDate: Date? = nil,
        calendar: Calendar = .current
    ) -> ExportDateRange? {
        let today = calendar.startOfDay(for: referenceDate)

        switch self {
        case .today:
            return ExportDateRange(startDate: today, endDate: today)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            return ExportDateRange(startDate: yesterday, endDate: yesterday)
        case .allTime:
            guard let allTimeStartDate else { return nil }
            let requestedEndDate = allTimeEndDate ?? referenceDate
            let endDate = requestedEndDate > referenceDate ? referenceDate : requestedEndDate
            return ExportDateRange(
                startDate: calendar.startOfDay(for: allTimeStartDate),
                endDate: calendar.startOfDay(for: endDate)
            )
        case .custom:
            return ExportDateRange(startDate: currentStartDate, endDate: currentEndDate)
        }
    }
}

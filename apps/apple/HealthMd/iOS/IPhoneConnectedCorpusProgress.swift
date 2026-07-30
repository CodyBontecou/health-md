#if os(iOS)
import Foundation

/// Local, presentation-only progress for iPhone-produced connected corpus exports.
/// Counts describe durable work boundaries rather than the day currently being attempted.
struct IPhoneConnectedCorpusProgressUpdate: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing
        case prepared
        case transferring
        case finalizing
    }

    let phase: Phase
    let preparedDays: Int
    let transferredDays: Int
    let totalDays: Int
    let activeDate: Date?
    let activeDayNumber: Int?
    let message: String

    static func preparing(
        itemIndex: Int,
        totalDays: Int,
        date: Date,
        includesGranularData: Bool,
        transferredDays: Int
    ) -> Self {
        let counts = normalizedCounts(
            preparedDays: itemIndex,
            transferredDays: transferredDays,
            totalDays: totalDays
        )
        let dayNumber = normalizedDayNumber(itemIndex + 1, totalDays: counts.totalDays)
        return Self(
            phase: .preparing,
            preparedDays: counts.preparedDays,
            transferredDays: counts.transferredDays,
            totalDays: counts.totalDays,
            activeDate: date,
            activeDayNumber: dayNumber,
            message: captureMessage(
                includesGranularData: includesGranularData,
                dayNumber: dayNumber,
                totalDays: counts.totalDays
            )
        )
    }

    static func prepared(
        itemIndex: Int,
        totalDays: Int,
        date: Date,
        includesGranularData: Bool,
        transferredDays: Int
    ) -> Self {
        let counts = normalizedCounts(
            preparedDays: itemIndex + 1,
            transferredDays: transferredDays,
            totalDays: totalDays
        )
        let dayNumber = normalizedDayNumber(itemIndex + 1, totalDays: counts.totalDays)
        let subject = includesGranularData
            ? "lossless HealthKit records"
            : "HealthKit summary"
        return Self(
            phase: .prepared,
            preparedDays: counts.preparedDays,
            transferredDays: counts.transferredDays,
            totalDays: counts.totalDays,
            activeDate: date,
            activeDayNumber: dayNumber,
            message: "Prepared \(subject) for day \(dayNumber ?? 0) of \(counts.totalDays)."
        )
    }

    static func transferring(
        preparedDays: Int,
        transferredDays: Int,
        totalDays: Int,
        date: Date?,
        dayNumber: Int?
    ) -> Self {
        let counts = normalizedCounts(
            preparedDays: preparedDays,
            transferredDays: transferredDays,
            totalDays: totalDays
        )
        let normalizedDay = dayNumber.flatMap {
            normalizedDayNumber($0, totalDays: counts.totalDays)
        }
        let message: String
        if let normalizedDay {
            message = "Transferring validated corpus data for day \(normalizedDay) of \(counts.totalDays)…"
        } else {
            message = "Transferring validated corpus data…"
        }
        return Self(
            phase: .transferring,
            preparedDays: counts.preparedDays,
            transferredDays: counts.transferredDays,
            totalDays: counts.totalDays,
            activeDate: date,
            activeDayNumber: normalizedDay,
            message: message
        )
    }

    /// Maps preparation to 0...0.75 and validated transfer to 0...0.15.
    /// Finalization begins at 0.9. Supplying the consumer's previous value makes
    /// repeated journal and live updates monotonic while remaining a pure function.
    static func presentationFraction(
        preparedDays: Int,
        transferredDays: Int,
        totalDays: Int,
        isFinalizing: Bool = false,
        previousFraction: Double = 0
    ) -> Double {
        let counts = normalizedCounts(
            preparedDays: preparedDays,
            transferredDays: transferredDays,
            totalDays: totalDays
        )
        let previous = previousFraction.isFinite
            ? min(max(previousFraction, 0), 1)
            : 0
        let weighted: Double
        if counts.totalDays > 0 {
            let total = Double(counts.totalDays)
            weighted = (Double(counts.preparedDays) / total * 0.75)
                + (Double(counts.transferredDays) / total * 0.15)
        } else {
            weighted = 0
        }
        let phaseFloor = isFinalizing ? 0.9 : 0
        return min(max(previous, max(weighted, phaseFloor)), 1)
    }

    func presentationFraction(previousFraction: Double = 0) -> Double {
        Self.presentationFraction(
            preparedDays: preparedDays,
            transferredDays: transferredDays,
            totalDays: totalDays,
            isFinalizing: phase == .finalizing,
            previousFraction: previousFraction
        )
    }

    private static func normalizedCounts(
        preparedDays: Int,
        transferredDays: Int,
        totalDays: Int
    ) -> (preparedDays: Int, transferredDays: Int, totalDays: Int) {
        let total = max(totalDays, 0)
        let prepared = min(max(preparedDays, 0), total)
        let transferred = min(max(transferredDays, 0), prepared)
        return (prepared, transferred, total)
    }

    private static func normalizedDayNumber(_ dayNumber: Int, totalDays: Int) -> Int? {
        guard totalDays > 0 else { return nil }
        return min(max(dayNumber, 1), totalDays)
    }

    private static func captureMessage(
        includesGranularData: Bool,
        dayNumber: Int?,
        totalDays: Int
    ) -> String {
        let subject = includesGranularData
            ? "lossless HealthKit records"
            : "HealthKit summary"
        return "Capturing \(subject) for day \(dayNumber ?? 0) of \(totalDays)…"
    }
}
#endif

import Foundation

/// Selection is at the API-resource boundary: native response bodies remain
/// intact, rather than claiming field-level redaction of an archival sidecar.
nonisolated extension WHOOPResourceName {
    var displayName: String {
        switch self {
        case .cycles: String(localized: "Cycles & Strain")
        case .recovery: String(localized: "Recovery")
        case .sleep: String(localized: "Sleep")
        case .workouts: String(localized: "Workouts")
        case .body: String(localized: "Body Measurements")
        }
    }

    var selectionDescription: String {
        switch self {
        case .cycles: String(localized: "Physiological-cycle strain, steps, energy, and average/maximum heart rate.")
        case .recovery: String(localized: "Recovery score, HRV (RMSSD), resting heart rate, blood oxygen, and skin temperature.")
        case .sleep: String(localized: "Sleep and naps, stages, sleep need, performance, and respiratory rate.")
        case .workouts: String(localized: "Activities, strain, heart rate zones, energy, distance, and elevation.")
        case .body: String(localized: "Current height, weight, and maximum heart rate. Today only; not historical measurements.")
        }
    }

    static func resource(forPayloadName name: String) -> WHOOPResourceName? {
        if name == "cycles" || name.hasPrefix("cycles_page_") || name == "cycles_pagination" { return .cycles }
        if name == "recovery" || name.hasPrefix("recovery_page_") || name == "recovery_pagination" { return .recovery }
        if name == "sleep" || name.hasPrefix("sleep_page_") || name == "sleep_pagination" { return .sleep }
        if name == "workouts" || name.hasPrefix("workouts_page_") || name == "workouts_pagination" { return .workouts }
        if name == "body_measurements_snapshot" { return .body }
        return nil
    }
}

nonisolated extension Set where Element == WHOOPResourceName {
    /// Body has no historical measurement timestamp and is never planned for a
    /// historical owner day. Resolve this once before starting that day's read.
    func requested(for date: Date, calendar: Calendar, now: Date = Date()) -> Self {
        calendar.isDate(date, inSameDayAs: now) ? self : subtracting([.body])
    }
}

extension ExternalDailyRecord {
    /// Defense in depth for injected/legacy capture adapters and already-captured
    /// records. Unknown WHOOP payloads cannot bypass an explicit selection.
    func selectingWHOOPResources(_ resources: Set<WHOOPResourceName>) -> ExternalDailyRecord? {
        guard provider == .whoop else { return self }
        guard !resources.isEmpty else { return nil }
        guard resources != Set(WHOOPResourceName.allCases) else { return self }
        var selected = self
        selected.payloads = payloads.filter {
            guard let resource = WHOOPResourceName.resource(forPayloadName: $0.name) else { return false }
            return resources.contains(resource)
        }
        return selected
    }
}

nonisolated extension WHOOPDailyProviderSection {
    func selectingResources(_ selected: Set<WHOOPResourceName>) -> WHOOPDailyProviderSection? {
        guard !selected.isEmpty else { return nil }
        guard selected != Set(WHOOPResourceName.allCases) else { return self }
        let retained = resources.filter { selected.contains($0.resource) }
        return WHOOPDailyProviderSection(
            schema: schema,
            schemaVersion: schemaVersion,
            captureStatus: captureStatus == .notRequested ? .notRequested
                : (retained.allSatisfy { $0.status == .success } ? .complete : .partial),
            fetchedAt: fetchedAt,
            resources: retained,
            cycles: selected.contains(.cycles) ? cycles : [],
            recoveries: selected.contains(.recovery) ? recoveries : [],
            sleep: selected.contains(.sleep) ? sleep : [],
            workouts: selected.contains(.workouts) ? workouts : [],
            body: selected.contains(.body) ? body : nil,
            warnings: warnings.filter { $0.resource.map(selected.contains) ?? true }
        )
    }
}

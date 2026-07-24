import Foundation

/// Deterministic sleep-session projection and query-window calculations shared by
/// the in-memory evaluator and bounded encrypted-store executor.
nonisolated enum HealthMdSleepSessionQuery {
    static let sleepMetricIDs: Set<String> = [
        "sleep_total", "sleep_deep", "sleep_rem", "sleep_core", "sleep_awake",
        "sleep_in_bed", "sleep_bedtime", "sleep_wake", "sleep_analysis"
    ]

    private static let sessionGap: TimeInterval = 90 * 60
    private static let meaningfulGap: TimeInterval = 5 * 60

    static func contextSessions(
        sleep: SleepData,
        ownerDate: String,
        ownerIntervalStart: Date,
        calendarTimeZone: String,
        evidenceIDs: [String]
    ) throws -> [HealthMdContextSleepSession] {
        let timeZone = TimeZone(identifier: calendarTimeZone) ?? TimeZone(secondsFromGMT: 0)!
        let sleepWindow = sleepWindow(ownerIntervalStart: ownerIntervalStart, timeZone: timeZone)
        let intervals = sleep.stages.compactMap { sample -> HealthMdContextSleepStageInterval? in
            guard sample.endDate > sample.startDate else { return nil }
            return .init(stage: normalizedStage(sample.stage), start: sample.startDate, end: sample.endDate)
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return $0.stage < $1.stage
        }

        if intervals.isEmpty {
            guard let start = sleep.sessionStart,
                  let end = sleep.sessionEnd,
                  end > start else { return [] }
            let aggregates = finiteAggregates(sleep)
            let limitations = [HealthMdLimitation(
                code: "sleep_session_aggregated",
                message: "Session boundaries and totals are available, but interval-level sleep stages were not captured."
            )]
            return [HealthMdContextSleepSession(
                sessionID: try stableSessionID(start: start, end: end, timeZone: calendarTimeZone),
                start: start,
                end: end,
                classification: classification(start: start, end: end, timeZone: timeZone),
                completeness: .aggregated,
                aggregateStageDurations: aggregates,
                evidenceIDs: evidenceIDs,
                limitations: limitations
            )]
        }

        var groups: [[HealthMdContextSleepStageInterval]] = []
        var current: [HealthMdContextSleepStageInterval] = []
        var currentEnd: Date?
        for interval in intervals {
            if let end = currentEnd,
               interval.start.timeIntervalSince(end) > sessionGap {
                groups.append(current)
                current = []
                currentEnd = nil
            }
            current.append(interval)
            currentEnd = max(currentEnd ?? interval.end, interval.end)
        }
        if !current.isEmpty { groups.append(current) }

        return try groups.compactMap { group in
            guard let start = group.map(\.start).min(),
                  let end = group.map(\.end).max(),
                  end > start else { return nil }
            let observed = unionDuration(group.map { ($0.start, $0.end) })
            let elapsed = end.timeIntervalSince(start)
            let truncatedStart = start <= sleepWindow.start.addingTimeInterval(1)
            let truncatedEnd = end >= sleepWindow.end.addingTimeInterval(-1)
            let completeness: HealthMdSleepCompleteness
            if truncatedStart && truncatedEnd { completeness = .truncatedAtBoth }
            else if truncatedStart { completeness = .truncatedAtStart }
            else if truncatedEnd { completeness = .truncatedAtEnd }
            else if elapsed - observed > meaningfulGap { completeness = .partial }
            else { completeness = .complete }

            var limitations: [HealthMdLimitation] = []
            if truncatedStart || truncatedEnd {
                limitations.append(.init(
                    code: "sleep_session_clipped_to_capture_window",
                    message: "The session touches a noon-to-noon capture boundary and may continue outside the captured interval."
                ))
            }
            if elapsed - observed > meaningfulGap {
                limitations.append(.init(
                    code: "sleep_session_untracked_interval",
                    message: "The session contains more than five minutes without an observed sleep-stage interval."
                ))
            }
            return HealthMdContextSleepSession(
                sessionID: try stableSessionID(start: start, end: end, timeZone: calendarTimeZone),
                start: start,
                end: end,
                classification: classification(start: start, end: end, timeZone: timeZone),
                completeness: completeness,
                stageIntervals: group,
                aggregateStageDurations: stageDurations(group, clippedTo: start..<end),
                evidenceIDs: evidenceIDs,
                limitations: limitations
            )
        }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.sessionID < $1.sessionID
        }
    }

    static func result(
        session: HealthMdContextSleepSession,
        ownerDay: HealthMdCompactContextDay,
        relatedDays: [HealthMdCompactContextDay],
        window: HealthMdSleepWindow?,
        authorizedSleepMetricIDs: Set<String>,
        physiologyMetricIDs: Set<String>,
        authorizedEvidence: [HealthMdContextEvidence]
    ) -> HealthMdSleepSessionResult? {
        let requestedStart = session.start.addingTimeInterval(window?.startOffsetSeconds ?? 0)
        let requestedEnd = window.map { requestedStart.addingTimeInterval($0.durationSeconds) } ?? session.end
        let analysisStart = max(session.start, requestedStart)
        let analysisEnd = min(session.end, requestedEnd)
        guard analysisEnd > analysisStart else { return nil }

        let range = analysisStart..<analysisEnd
        let clippedIntervals = session.stageIntervals.compactMap { interval -> (String, Date, Date)? in
            let start = max(interval.start, analysisStart)
            let end = min(interval.end, analysisEnd)
            return end > start ? (interval.stage, start, end) : nil
        }
        let visibleIntervals = clippedIntervals.filter {
            stageMetricID($0.0).map(authorizedSleepMetricIDs.contains) == true
        }
        let structuralIntervals = authorizedSleepMetricIDs.contains("sleep_total")
            ? clippedIntervals
            : visibleIntervals
        let stageDurations: [String: Double]
        let observed: Double
        let asleep: Double
        let awake: Double
        var limitations = session.limitations
        if session.stageIntervals.isEmpty {
            if window == nil {
                stageDurations = session.aggregateStageDurations.filter {
                    stageMetricID($0.key).map(authorizedSleepMetricIDs.contains) == true
                }
            } else {
                stageDurations = [:]
                limitations.append(.init(
                    code: "sleep_window_stage_breakdown_unavailable",
                    message: "A fixed session-relative window requires interval-level sleep stages; aggregate stage totals were not apportioned."
                ))
            }
            // Aggregate totals prove values and boundaries, not interval-level
            // observation coverage. Do not claim the whole elapsed window was observed.
            observed = 0
            asleep = stageDurations["asleep_total"]
                ?? ["deep", "rem", "core", "unspecified"]
                    .compactMap { stageDurations[$0] }.reduce(0, +)
            awake = stageDurations["awake"] ?? 0
        } else {
            stageDurations = Self.stageDurations(
                visibleIntervals.map {
                    HealthMdContextSleepStageInterval(stage: $0.0, start: $0.1, end: $0.2)
                },
                clippedTo: range
            )
            observed = unionDuration(structuralIntervals.map { ($0.1, $0.2) })
            asleep = unionDuration(
                structuralIntervals.filter {
                    ["deep", "rem", "core", "unspecified"].contains($0.0)
                }.map { ($0.1, $0.2) }
            )
            awake = authorizedSleepMetricIDs.contains("sleep_awake")
                ? unionDuration(
                    clippedIntervals.filter { $0.0 == "awake" }.map { ($0.1, $0.2) }
                )
                : 0
            let visibleAsleepSum = ["deep", "rem", "core", "unspecified"]
                .compactMap { stageDurations[$0] }.reduce(0, +)
            if visibleAsleepSum > asleep + 1 {
                limitations.append(.init(
                    code: "overlapping_sleep_stage_sources",
                    message: "Overlapping stage observations were de-duplicated when calculating total asleep duration."
                ))
            }
        }

        var completeness = session.completeness
        if requestedStart < session.start || requestedEnd > session.end {
            completeness = .partial
            limitations.append(.init(
                code: "sleep_window_extends_beyond_session",
                message: "The requested session-relative window extends beyond the observed session boundary."
            ))
        }
        let elapsed = analysisEnd.timeIntervalSince(analysisStart)

        let sessionEvidence = authorizedEvidence.filter {
            session.evidenceIDs.contains($0.reference.evidenceID)
        }
        let physiology = physiologyCoverage(
            metricIDs: physiologyMetricIDs,
            range: range,
            evidence: authorizedEvidence,
            relatedDays: relatedDays
        )
        let references = Array(Set(
            sessionEvidence.map(\.reference) + physiology.flatMap(\.evidence)
        )).sorted { $0.evidenceID < $1.evidenceID }
        let timeZone = TimeZone(identifier: ownerDay.calendarTimeZone) ?? TimeZone(secondsFromGMT: 0)!

        return HealthMdSleepSessionResult(
            sessionID: session.sessionID,
            ownerDate: ownerDay.ownerDate,
            calendarDates: calendarDates(start: session.start, end: session.end, timeZone: timeZone),
            classification: session.classification,
            completeness: completeness,
            start: session.start,
            end: session.end,
            localStart: localTimestamp(session.start, timeZone: timeZone),
            localEnd: localTimestamp(session.end, timeZone: timeZone),
            calendarTimeZone: ownerDay.calendarTimeZone,
            analysisStart: analysisStart,
            analysisEnd: analysisEnd,
            requestedWindow: window,
            elapsedDurationSeconds: elapsed,
            observedDurationSeconds: min(elapsed, observed),
            untrackedDurationSeconds: max(0, elapsed - observed),
            asleepDurationSeconds: asleep,
            awakeDurationSeconds: awake,
            stageDurationsSeconds: stageDurations,
            physiology: physiology,
            evidence: references,
            limitations: Array(Set(limitations)).sorted { $0.code < $1.code }
        )
    }

    static func alignment(
        workout: HealthMdContextWorkout,
        preceding: (session: HealthMdContextSleepSession, ownerDay: HealthMdCompactContextDay)?,
        following: (session: HealthMdContextSleepSession, ownerDay: HealthMdCompactContextDay)?,
        relatedDays: [HealthMdCompactContextDay],
        window: HealthMdSleepWindow?,
        authorizedSleepMetricIDs: Set<String>,
        physiologyMetricIDs: Set<String>,
        authorizedEvidence: [HealthMdContextEvidence]
    ) throws -> HealthMdWorkoutSleepAlignment {
        let precedingResult = preceding.flatMap {
            result(
                session: $0.session,
                ownerDay: $0.ownerDay,
                relatedDays: relatedDays,
                window: window,
                authorizedSleepMetricIDs: authorizedSleepMetricIDs,
                physiologyMetricIDs: physiologyMetricIDs,
                authorizedEvidence: authorizedEvidence
            )
        }
        let followingResult = following.flatMap {
            result(
                session: $0.session,
                ownerDay: $0.ownerDay,
                relatedDays: relatedDays,
                window: window,
                authorizedSleepMetricIDs: authorizedSleepMetricIDs,
                physiologyMetricIDs: physiologyMetricIDs,
                authorizedEvidence: authorizedEvidence
            )
        }
        let status: HealthMdWorkoutSleepAlignmentStatus
        if precedingResult != nil, followingResult != nil { status = .complete }
        else if precedingResult != nil || followingResult != nil { status = .partial }
        else { status = .unavailable }
        var limitations = [HealthMdLimitation(
            code: "temporal_alignment_only",
            message: "Workout and sleep times are aligned deterministically; this is not evidence that either caused a change in the other."
        )]
        if precedingResult == nil {
            limitations.append(.init(
                code: "preceding_sleep_unavailable",
                message: "No eligible preceding sleep session was observed within 36 hours of this workout."
            ))
        }
        if followingResult == nil {
            limitations.append(.init(
                code: "following_sleep_unavailable",
                message: "No eligible following sleep session was observed within 36 hours of this workout."
            ))
        }
        limitations.append(contentsOf: precedingResult?.limitations ?? [])
        limitations.append(contentsOf: followingResult?.limitations ?? [])
        let workoutEvidence = authorizedEvidence
            .filter { workout.evidenceIDs.contains($0.reference.evidenceID) }
            .map(\.reference)
        let references = workoutEvidence
            + (precedingResult?.evidence ?? [])
            + (followingResult?.evidence ?? [])
        let identity = AlignmentIdentity(
            workoutID: workout.workoutID,
            precedingSessionID: precedingResult?.sessionID,
            followingSessionID: followingResult?.sessionID,
            window: window
        )
        let alignmentID = "alignment:\(try HealthMdQueryCanonicalSerializer.sha256(of: identity))"
        return HealthMdWorkoutSleepAlignment(
            alignmentID: alignmentID,
            workout: workout,
            precedingSleep: precedingResult,
            followingSleep: followingResult,
            secondsFromPrecedingSleep: precedingResult.map {
                max(0, workout.start.timeIntervalSince($0.end))
            },
            secondsUntilFollowingSleep: followingResult.map {
                max(0, $0.start.timeIntervalSince(workout.end))
            },
            physiologySampleCount: (precedingResult?.physiology.reduce(0) { $0 + $1.sampleCount } ?? 0)
                + (followingResult?.physiology.reduce(0) { $0 + $1.sampleCount } ?? 0),
            status: status,
            evidence: references,
            limitations: limitations
        )
    }

    private struct AlignmentIdentity: Codable {
        let workoutID: String
        let precedingSessionID: String?
        let followingSessionID: String?
        let window: HealthMdSleepWindow?
    }

    static func validate(window: HealthMdSleepWindow?) throws {
        guard let window else { return }
        guard window.startOffsetSeconds.isFinite,
              window.durationSeconds.isFinite,
              window.startOffsetSeconds >= 0,
              window.startOffsetSeconds <= 24 * 3_600,
              window.durationSeconds > 0,
              window.durationSeconds <= 24 * 3_600 else {
            throw HealthMdQueryContractError.unsupportedOperation
        }
    }

    static func authorizedSleepMetricIDs(
        selection: HealthMdMetricSelection,
        allowedMetricIDs: Set<String>
    ) -> Set<String> {
        let selected: Set<String>
        switch selection {
        case .allAvailable: selected = allowedMetricIDs
        case .explicit(let ids): selected = Set(ids).intersection(allowedMetricIDs)
        }
        return selected.intersection(sleepMetricIDs)
    }

    static func physiologyMetricIDs(
        selection: HealthMdMetricSelection,
        allowedMetricIDs: Set<String>? = nil
    ) -> Set<String> {
        let selected: Set<String>
        switch selection {
        case .explicit(let ids): selected = Set(ids)
        case .allAvailable: selected = allowedMetricIDs ?? []
        }
        return selected.subtracting(sleepMetricIDs)
    }

    static func hasSleepAuthorization(
        selection: HealthMdMetricSelection,
        allowedMetricIDs: Set<String>
    ) -> Bool {
        // Session boundaries and total/stage structure are broader than any
        // one narrow sleep-stage metric, so `sleep_total` is the minimum required scope.
        guard allowedMetricIDs.contains("sleep_total") else { return false }
        switch selection {
        case .allAvailable: return true
        case .explicit(let ids): return ids.contains("sleep_total")
        }
    }

    private static func physiologyCoverage(
        metricIDs: Set<String>,
        range: Range<Date>,
        evidence: [HealthMdContextEvidence],
        relatedDays: [HealthMdCompactContextDay]
    ) -> [HealthMdSleepPhysiologyCoverage] {
        metricIDs.sorted().map { metricID in
            let matching = evidence.compactMap { item -> (Date, Date, HealthMdEvidenceReference)? in
                guard item.metricIDs.contains(metricID),
                      let interval = canonicalInterval(item.value),
                      overlaps(interval, range) else { return nil }
                return (interval.start, interval.end, item.reference)
            }
            let status: HealthMdAvailabilityStatus
            if !matching.isEmpty { status = .available }
            else {
                let statuses = Set(relatedDays.map(\.status))
                status = statuses.allSatisfy { $0 == .available || $0 == .completeEmpty }
                    ? .completeEmpty : .partial
            }
            return HealthMdSleepPhysiologyCoverage(
                metricID: metricID,
                status: status,
                sampleCount: matching.count,
                firstSampleAt: matching.map(\.0).min(),
                lastSampleAt: matching.map { max($0.0, $0.1) }.max(),
                observedOwnerDates: matching.map { $0.2.locator.ownerDate },
                evidence: matching.map(\.2)
            )
        }
    }

    private static func canonicalInterval(_ value: HealthMdQueryValue?) -> (start: Date, end: Date)? {
        guard case .unknown(let type, let payload) = value,
              type == "canonical_healthkit_record",
              case .object(let object)? = payload,
              case .string(let startString)? = object["start"],
              case .string(let endString)? = object["end"],
              let start = parseTimestamp(startString),
              let end = parseTimestamp(endString) else { return nil }
        return (start, max(start, end))
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    private static func overlaps(_ interval: (start: Date, end: Date), _ range: Range<Date>) -> Bool {
        if interval.start == interval.end {
            return interval.start >= range.lowerBound && interval.start < range.upperBound
        }
        return interval.start < range.upperBound && interval.end > range.lowerBound
    }

    private static func finiteAggregates(_ sleep: SleepData) -> [String: Double] {
        let candidates: [(String, Double)] = [
            ("deep", sleep.deepSleep), ("rem", sleep.remSleep),
            ("core", sleep.coreSleep), ("awake", sleep.awakeTime),
            ("in_bed", sleep.inBedTime), ("asleep_total", sleep.totalDuration)
        ]
        return Dictionary(uniqueKeysWithValues: candidates.filter { $0.1.isFinite && $0.1 >= 0 })
    }

    private static func stageMetricID(_ stage: String) -> String? {
        switch normalizedStage(stage) {
        case "deep": return "sleep_deep"
        case "rem": return "sleep_rem"
        case "core": return "sleep_core"
        case "awake": return "sleep_awake"
        case "in_bed": return "sleep_in_bed"
        case "unspecified", "asleep_total": return "sleep_total"
        default: return nil
        }
    }

    private static func normalizedStage(_ value: String) -> String {
        switch value.lowercased() {
        case "inbed", "in_bed": return "in_bed"
        case "asleepunspecified", "asleep_unspecified": return "unspecified"
        default: return value.lowercased()
        }
    }

    private static func stageDurations(
        _ intervals: [HealthMdContextSleepStageInterval],
        clippedTo range: Range<Date>
    ) -> [String: Double] {
        let grouped = Dictionary(grouping: intervals, by: \.stage)
        return grouped.reduce(into: [String: Double]()) { result, entry in
            let clipped = entry.value.compactMap { interval -> (Date, Date)? in
                let start = max(interval.start, range.lowerBound)
                let end = min(interval.end, range.upperBound)
                return end > start ? (start, end) : nil
            }
            let duration = unionDuration(clipped)
            if duration > 0 { result[entry.key] = duration }
        }
    }

    private static func unionDuration(_ intervals: [(Date, Date)]) -> Double {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            return $0.1 < $1.1
        }
        guard var current = sorted.first else { return 0 }
        var total: Double = 0
        for interval in sorted.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                total += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        total += current.1.timeIntervalSince(current.0)
        return max(0, total)
    }

    private static func stableSessionID(start: Date, end: Date, timeZone: String) throws -> String {
        struct Identity: Codable { let start: Date; let end: Date; let timeZone: String }
        let digest = try HealthMdQueryCanonicalSerializer.sha256(of: Identity(
            start: start,
            end: end,
            timeZone: timeZone
        ))
        return "sleep:\(digest)"
    }

    private static func classification(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) -> HealthMdSleepSessionClassification {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: start)
        let duration = end.timeIntervalSince(start)
        if duration <= 3 * 3_600, hour >= 6, hour < 21 { return .nap }
        if duration >= 3 * 3_600, hour >= 17 || hour < 7 { return .overnight }
        return .sleep
    }

    private static func sleepWindow(
        ownerIntervalStart: Date,
        timeZone: TimeZone
    ) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfDay = calendar.startOfDay(for: ownerIntervalStart)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
            ?? startOfDay.addingTimeInterval(86_400)
        let start = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: startOfDay)
            ?? startOfDay.addingTimeInterval(12 * 3_600)
        let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: nextDay)
            ?? nextDay.addingTimeInterval(12 * 3_600)
        return (start, end)
    }

    private static func calendarDates(start: Date, end: Date, timeZone: TimeZone) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end.addingTimeInterval(-0.001))
        var values: [String] = []
        while cursor <= last {
            values.append(formatter.string(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return values
    }

    private static func localTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter.string(from: date)
    }
}

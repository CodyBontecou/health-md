import CryptoKit
import Foundation

/// Pure query evaluation over compact context days. It performs no HealthKit, file, network, CLI, or MCP I/O.
nonisolated struct HealthMdQueryEvaluator: Sendable {
    private let days: [HealthMdCompactContextDay]
    private let cursorKey: Data
    private let datasetFingerprint: String

    init(days: [HealthMdCompactContextDay], cursorKey: Data) throws {
        self.days = days.sorted {
            if $0.ownerDate != $1.ownerDate { return $0.ownerDate < $1.ownerDate }
            return $0.source.digest < $1.source.digest
        }
        self.cursorKey = cursorKey
        self.datasetFingerprint = try HealthMdQueryCanonicalSerializer.sha256(of: self.days)
    }

    func evaluate(
        _ request: HealthMdQueryRequest,
        evidenceScope: HealthMdEvidenceScope? = nil,
        generatedAt: Date = Date()
    ) throws -> HealthMdQueryResponse {
        guard request.schema == HealthMdQuerySchemas.queryRequest, request.schemaVersion == 1 else {
            throw HealthMdQueryContractError.unsupportedOperation
        }
        guard request.page.maxItems > 0,
              request.page.maxItems <= HealthMdPageControls.maximumItems,
              request.page.maxBytes > 0,
              request.page.maxBytes <= HealthMdPageControls.maximumBytes else {
            throw HealthMdQueryContractError.invalidPageControls
        }
        try validate(request.dates)
        switch request.operation {
        case .sleepSessionListing(let window, _),
             .workoutSleepAlignment(let window, _, _):
            try HealthMdSleepSessionQuery.validate(window: window)
        default:
            break
        }
        let selectedDays = try selectDays(request.dates)
        try validateScope(request, scope: evidenceScope)
        let fingerprint = try requestFingerprint(request)
        let offset = try cursorOffset(request.page.cursor, fingerprint: fingerprint)

        switch request.operation {
        case .metricSeries:
            let candidates = metricItems(days: selectedDays, selection: request.metrics)
            let page = try paginate(candidates, offset: offset, controls: request.page, fingerprint: fingerprint)
            return HealthMdQueryResponse(
                items: page.values,
                packet: nil,
                coverage: metricCoverage(for: selectedDays, requested: request.dates, items: candidates),
                sources: normalizedSources(selectedDays),
                evidence: responseEvidence(items: page.values, packet: nil, days: selectedDays),
                nextCursor: page.nextCursor,
                limitations: page.limitations
            )
        case .periodComparison(let first, let second, let descriptors):
            let items = try comparisonItems(
                first: first,
                second: second,
                descriptors: descriptors,
                metricSelection: request.metrics
            )
            let page = try paginate(items, offset: offset, controls: request.page, fingerprint: fingerprint)
            let comparisonDays = try selectDays(.exact(combined(first, second)))
            let comparedMetricIDs = Set(descriptors.map(\.metricID))
            let valueDays = Set(comparisonDays.filter { day in
                day.metrics.contains { comparedMetricIDs.contains($0.metricID) && $0.status == .available && $0.value != nil }
            }.map(\.ownerDate))
            return HealthMdQueryResponse(
                items: page.values,
                packet: nil,
                coverage: coverage(for: comparisonDays, requested: .exact(combined(first, second)), valueDays: valueDays),
                sources: normalizedSources(comparisonDays),
                evidence: responseEvidence(items: page.values, packet: nil, days: comparisonDays),
                nextCursor: page.nextCursor,
                limitations: page.limitations
            )
        case .workoutListing:
            let workouts = workoutItems(in: selectedDays)
            let page = try paginate(workouts, offset: offset, controls: request.page, fingerprint: fingerprint)
            let listedWorkoutIDs = Set(workouts.compactMap { item -> String? in
                guard case .workout(let workout) = item else { return nil }
                return workout.workoutID
            })
            let valueDays = Set(selectedDays.filter { day in
                day.workouts.contains { listedWorkoutIDs.contains($0.workoutID) }
            }.map(\.ownerDate))
            return HealthMdQueryResponse(
                items: page.values,
                packet: nil,
                coverage: coverage(for: selectedDays, requested: request.dates, valueDays: valueDays),
                sources: normalizedSources(selectedDays),
                evidence: responseEvidence(items: page.values, packet: nil, days: selectedDays),
                nextCursor: page.nextCursor,
                limitations: page.limitations
            )
        case .sleepSessionListing(let window, let includeNaps):
            let listing = try sleepSessionItems(
                in: selectedDays,
                request: request,
                window: window,
                includeNaps: includeNaps,
                scope: evidenceScope
            )
            let page = try paginate(
                listing.items,
                offset: offset,
                controls: request.page,
                fingerprint: fingerprint
            )
            var limitations = listing.limitations
            limitations.append(Self.medicalSafetyLimitation)
            limitations.append(contentsOf: page.limitations)
            return HealthMdQueryResponse(
                items: page.values,
                packet: nil,
                coverage: coverage(
                    for: selectedDays,
                    requested: request.dates,
                    valueDays: Set(listing.items.compactMap { item in
                        guard case .sleepSession(let session) = item else { return nil }
                        return session.ownerDate
                    })
                ),
                sources: normalizedSources(selectedDays),
                evidence: responseEvidence(items: page.values, packet: nil, days: days),
                nextCursor: page.nextCursor,
                limitations: uniqueLimitations(limitations),
                metadata: [
                    "excluded_session_count": .integer(Int64(listing.excludedCount)),
                    "excluded_nap_count": .integer(Int64(listing.excludedNapCount)),
                    "window_outside_session_count": .integer(Int64(listing.windowOutsideCount)),
                    "source_excluded_session_count": .integer(Int64(listing.sourceExcludedCount)),
                    "adjacent_owner_dates_considered": .array(
                        listing.adjacentOwnerDates.sorted().map(HealthMdJSONValue.string)
                    )
                ]
            )
        case .workoutSleepAlignment(let window, let workoutActivity, let includeNaps):
            let listing = try workoutSleepAlignmentItems(
                in: selectedDays,
                request: request,
                window: window,
                workoutActivity: workoutActivity,
                includeNaps: includeNaps,
                scope: evidenceScope
            )
            let page = try paginate(
                listing.items,
                offset: offset,
                controls: request.page,
                fingerprint: fingerprint
            )
            return HealthMdQueryResponse(
                items: page.values,
                packet: nil,
                coverage: coverage(
                    for: selectedDays,
                    requested: request.dates,
                    valueDays: listing.valueDays
                ),
                sources: normalizedSources(selectedDays),
                evidence: responseEvidence(items: page.values, packet: nil, days: days),
                nextCursor: page.nextCursor,
                limitations: uniqueLimitations(listing.limitations + page.limitations),
                metadata: [
                    "aligned_workout_count": .integer(Int64(listing.items.count)),
                    "complete_alignment_count": .integer(Int64(listing.completeCount)),
                    "partial_alignment_count": .integer(Int64(listing.partialCount)),
                    "unavailable_alignment_count": .integer(Int64(listing.unavailableCount)),
                    "activity_excluded_workout_count": .integer(Int64(listing.activityExcludedCount)),
                    "source_excluded_workout_count": .integer(Int64(listing.sourceExcludedCount)),
                    "physiology_sample_count": .integer(Int64(listing.physiologySampleCount))
                ]
            )
        case .sourceRecordListing:
            guard let scope = evidenceScope, scope.allowsEvidenceValues else {
                throw HealthMdQueryContractError.scopeViolation("evidence_values")
            }
            let candidates = sourceRecordItems(
                days: selectedDays,
                metrics: request.metrics,
                sources: request.sources,
                scope: scope
            )
            let page = try paginate(candidates, offset: offset, controls: request.page, fingerprint: fingerprint)
            let pageEvidence = page.values.compactMap { item -> HealthMdContextEvidence? in
                guard case .evidence(let evidence) = item else { return nil }
                return evidence
            }
            let valueDays = Set(pageEvidence.map { $0.reference.locator.ownerDate })
            return HealthMdQueryResponse(
                items: page.values,
                packet: nil,
                coverage: coverage(for: selectedDays, requested: request.dates, valueDays: valueDays),
                sources: normalizedSources(pageEvidence.map { $0.reference.source }),
                evidence: pageEvidence.map(\.reference),
                nextCursor: page.nextCursor,
                limitations: page.limitations
            )
        case .coverage:
            guard offset == 0 else { throw HealthMdQueryContractError.invalidCursor }
            return HealthMdQueryResponse(
                items: [], packet: nil,
                coverage: coverage(for: selectedDays, requested: request.dates, valueDays: Set(selectedDays.filter(hasAnyValue).map(\.ownerDate))),
                sources: normalizedSources(selectedDays), evidence: [],
                nextCursor: nil, limitations: allLimitations(in: selectedDays)
            )
        case .derivePacket(let kind, let detailIDs):
            guard let scope = evidenceScope else { throw HealthMdQueryContractError.scopeViolation("missing_evidence_scope") }
            let facts = try packetFacts(kind: kind, detailIDs: detailIDs, days: selectedDays, selection: request.metrics, scope: scope)
            let page = try paginate(facts, offset: offset, controls: request.page, fingerprint: fingerprint)
            var limitations = allLimitations(in: selectedDays)
            limitations.append(Self.medicalSafetyLimitation)
            limitations.append(contentsOf: page.limitations)
            if page.nextCursor != nil {
                limitations.append(.init(code: "packet_continues", message: "Additional factual packet items are available through the next cursor."))
            }
            limitations = uniqueLimitations(limitations)
            let packetCoverage = coverage(
                for: selectedDays,
                requested: request.dates,
                valueDays: Set(facts.compactMap(\.ownerDate))
            )
            let packet = try HealthMdQueryCanonicalSerializer.makePacket(
                kind: kind,
                range: selectedRange(request.dates, selectedDays: selectedDays),
                facts: page.values,
                coverage: packetCoverage,
                sources: selectedDays.map(\.source),
                limitations: limitations,
                metadata: .init(generatedAt: generatedAt)
            )
            return HealthMdQueryResponse(
                items: [], packet: packet, coverage: packetCoverage,
                sources: normalizedSources(selectedDays),
                evidence: responseEvidence(items: [], packet: packet, days: selectedDays),
                nextCursor: page.nextCursor, limitations: limitations
            )
        }
    }

    // MARK: Selection

    private func validateScope(
        _ request: HealthMdQueryRequest,
        scope: HealthMdEvidenceScope?
    ) throws {
        guard let scope else {
            if case .sourceRecordListing = request.operation {
                throw HealthMdQueryContractError.scopeViolation("missing_evidence_scope")
            }
            return
        }
        if case .explicit(let metricIDs) = request.metrics {
            let denied = Set(metricIDs).subtracting(scope.allowedMetricIDs)
            guard denied.isEmpty else {
                throw HealthMdQueryContractError.scopeViolation("metric_ids:\(denied.sorted().joined(separator: ","))")
            }
        }
        if case .explicit(let sourceIDs, let providerIDs) = request.sources {
            if let allowed = scope.allowedSourceIDs {
                let denied = Set(sourceIDs).subtracting(allowed)
                guard denied.isEmpty else {
                    throw HealthMdQueryContractError.scopeViolation("source_ids:\(denied.sorted().joined(separator: ","))")
                }
            }
            if let allowed = scope.allowedProviderIDs {
                let denied = Set(providerIDs).subtracting(allowed)
                guard denied.isEmpty else {
                    throw HealthMdQueryContractError.scopeViolation("provider_ids:\(denied.sorted().joined(separator: ","))")
                }
            }
        }
        if case .workoutListing = request.operation, !scope.allowsWorkouts {
            throw HealthMdQueryContractError.scopeViolation("workouts")
        }
        switch request.operation {
        case .sleepSessionListing(let window, _):
            try HealthMdSleepSessionQuery.validate(window: window)
            guard HealthMdSleepSessionQuery.hasSleepAuthorization(
                selection: request.metrics,
                allowedMetricIDs: scope.allowedMetricIDs
            ) else {
                throw HealthMdQueryContractError.scopeViolation("sleep_sessions")
            }
        case .workoutSleepAlignment(let window, let activity, _):
            try HealthMdSleepSessionQuery.validate(window: window)
            guard scope.allowsWorkouts else {
                throw HealthMdQueryContractError.scopeViolation("workouts")
            }
            guard HealthMdSleepSessionQuery.hasSleepAuthorization(
                selection: request.metrics,
                allowedMetricIDs: scope.allowedMetricIDs
            ) else {
                throw HealthMdQueryContractError.scopeViolation("sleep_sessions")
            }
            if let activity, activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw HealthMdQueryContractError.unsupportedOperation
            }
        default:
            break
        }
    }

    private func evidenceIsAuthorized(
        _ evidence: HealthMdContextEvidence,
        selection: HealthMdSourceSelection,
        scope: HealthMdEvidenceScope
    ) -> Bool {
        if let allowed = scope.allowedSourceIDs, !allowed.contains(evidence.reference.sourceID) { return false }
        if let providerID = evidence.reference.providerID,
           let allowed = scope.allowedProviderIDs,
           !allowed.contains(providerID) { return false }
        switch selection {
        case .allAvailable:
            return true
        case .explicit(let sourceIDs, let providerIDs):
            let sourceMatch = sourceIDs.contains(evidence.reference.sourceID)
            let providerMatch = evidence.reference.providerID.map(providerIDs.contains) ?? false
            return sourceMatch || providerMatch
        }
    }

    private func evidencePassesSourceRestriction(
        originalEvidenceIDs: [String],
        authorizedEvidence: [HealthMdContextEvidence],
        selection: HealthMdSourceSelection,
        scope: HealthMdEvidenceScope
    ) -> Bool {
        let scopeRestrictsSources = scope.allowedSourceIDs != nil
            || scope.allowedProviderIDs != nil
        let requestRestrictsSources: Bool
        switch selection {
        case .allAvailable: requestRestrictsSources = false
        case .explicit: requestRestrictsSources = true
        }
        guard scopeRestrictsSources || requestRestrictsSources else { return true }
        return !originalEvidenceIDs.isEmpty && !authorizedEvidence.isEmpty
    }

    private func selectDays(_ selection: HealthMdDateSelection) throws -> [HealthMdCompactContextDay] {
        try validate(selection)
        switch selection {
        case .allAvailable: return days
        case .exact(let range):
            return days.filter { $0.ownerDate >= range.startDate && $0.ownerDate <= range.endDate }
        }
    }

    private func validate(_ selection: HealthMdDateSelection) throws {
        guard case .exact(let range) = selection else { return }
        try validate(range)
    }

    private func validate(_ range: HealthMdDateRange) throws {
        guard range.startDate <= range.endDate,
              isCanonicalDate(range.startDate),
              isCanonicalDate(range.endDate) else {
            throw HealthMdQueryContractError.invalidDateRange
        }
    }

    private func isCanonicalDate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    private func selectedMetricIDs(_ selection: HealthMdMetricSelection, in selectedDays: [HealthMdCompactContextDay]) -> Set<String> {
        switch selection {
        case .explicit(let ids): return Set(ids)
        case .allAvailable: return Set(selectedDays.flatMap { $0.metrics.map(\.metricID) })
        }
    }

    private func metricItems(days: [HealthMdCompactContextDay], selection: HealthMdMetricSelection) -> [HealthMdQueryItem] {
        let selected = selectedMetricIDs(selection, in: days)
        let evidence = evidenceIndex(days)
        var seen = Set<String>()
        var points: [HealthMdMetricPoint] = []
        for day in days {
            for metric in day.metrics where selected.contains(metric.metricID) {
                let identity = "\(day.ownerDate)|\(metric.observationID)"
                guard seen.insert(identity).inserted else { continue }
                points.append(HealthMdMetricPoint(
                    metricID: metric.metricID,
                    displayName: metric.displayName,
                    ownerDate: day.ownerDate,
                    value: metric.value,
                    status: metric.value == nil && metric.status == .available ? .completeEmpty : metric.status,
                    evidence: metric.evidenceIDs.compactMap { evidence[$0]?.reference }.sorted { $0.evidenceID < $1.evidenceID },
                    limitations: metric.limitations
                ))
            }
        }
        return points.sorted {
            if $0.ownerDate != $1.ownerDate { return $0.ownerDate < $1.ownerDate }
            if $0.metricID != $1.metricID { return $0.metricID < $1.metricID }
            return $0.displayName < $1.displayName
        }.map(HealthMdQueryItem.metric)
    }

    private func sourceRecordItems(
        days: [HealthMdCompactContextDay],
        metrics: HealthMdMetricSelection,
        sources: HealthMdSourceSelection,
        scope: HealthMdEvidenceScope
    ) -> [HealthMdQueryItem] {
        let requestedMetrics: Set<String>
        switch metrics {
        case .explicit(let ids): requestedMetrics = Set(ids)
        case .allAvailable: requestedMetrics = scope.allowedMetricIDs
        }
        return days.flatMap { day -> [HealthMdQueryItem] in
            var linkedMetrics: [String: Set<String>] = [:]
            for metric in day.metrics {
                for evidenceID in metric.evidenceIDs {
                    linkedMetrics[evidenceID, default: []].insert(metric.metricID)
                }
            }
            return day.evidence.compactMap { evidence in
                guard evidenceIsAuthorized(evidence, selection: sources, scope: scope) else { return nil }
                let associated = Set(evidence.metricIDs).union(linkedMetrics[evidence.reference.evidenceID] ?? [])
                switch metrics {
                case .explicit:
                    guard !associated.isDisjoint(with: requestedMetrics) else { return nil }
                case .allAvailable:
                    guard associated.isEmpty || !associated.isDisjoint(with: requestedMetrics) else { return nil }
                }
                return .evidence(evidence)
            }
        }.sorted { lhs, rhs in
            guard case .evidence(let a) = lhs, case .evidence(let b) = rhs else { return false }
            if a.reference.locator.ownerDate != b.reference.locator.ownerDate {
                return a.reference.locator.ownerDate < b.reference.locator.ownerDate
            }
            return a.reference.evidenceID < b.reference.evidenceID
        }
    }

    private func workoutItems(in selectedDays: [HealthMdCompactContextDay]) -> [HealthMdQueryItem] {
        var byID: [String: HealthMdContextWorkout] = [:]
        for workout in selectedDays.flatMap(\.workouts) {
            if let existing = byID[workout.workoutID] {
                let existingKey = (try? HealthMdQueryCanonicalSerializer.string(for: existing)) ?? ""
                let candidateKey = (try? HealthMdQueryCanonicalSerializer.string(for: workout)) ?? ""
                if candidateKey < existingKey { byID[workout.workoutID] = workout }
            } else {
                byID[workout.workoutID] = workout
            }
        }
        return byID.values.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.workoutID < $1.workoutID
        }.map(HealthMdQueryItem.workout)
    }

    private struct SleepListing {
        let items: [HealthMdQueryItem]
        let excludedCount: Int
        let excludedNapCount: Int
        let windowOutsideCount: Int
        let sourceExcludedCount: Int
        let adjacentOwnerDates: Set<String>
        let limitations: [HealthMdLimitation]
    }

    private func sleepSessionItems(
        in selectedDays: [HealthMdCompactContextDay],
        request: HealthMdQueryRequest,
        window: HealthMdSleepWindow?,
        includeNaps: Bool,
        scope: HealthMdEvidenceScope?
    ) throws -> SleepListing {
        let permissiveScope = scope ?? HealthMdEvidenceScope(
            allowedMetricIDs: selectedMetricIDs(request.metrics, in: days)
        )
        let authorizedSleepMetricIDs = HealthMdSleepSessionQuery.authorizedSleepMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: permissiveScope.allowedMetricIDs
        )
        let physiologyMetricIDs = HealthMdSleepSessionQuery.physiologyMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: permissiveScope.allowedMetricIDs
        )
        var items: [HealthMdQueryItem] = []
        var excludedNaps = 0
        var outside = 0
        var sourceExcluded = 0
        var adjacentOwnerDates = Set<String>()
        var limitations: [HealthMdLimitation] = []

        for day in selectedDays {
            for session in day.sleepSessions {
                if session.classification == .nap, !includeNaps {
                    excludedNaps += 1
                    continue
                }
                let calendarDates = sessionCalendarDates(session, ownerDay: day)
                let related = adjacentDays(around: [day], radius: 1).filter {
                    $0.ownerDate == day.ownerDate || calendarDates.contains($0.ownerDate)
                }
                adjacentOwnerDates.formUnion(
                    related.map(\.ownerDate).filter { $0 != day.ownerDate }
                )
                let evidence = related.flatMap(\.evidence).filter {
                    evidenceIsAuthorized($0, selection: request.sources, scope: permissiveScope)
                }
                let sessionEvidence = evidence.filter {
                    session.evidenceIDs.contains($0.reference.evidenceID)
                }
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: session.evidenceIDs,
                    authorizedEvidence: sessionEvidence,
                    selection: request.sources,
                    scope: permissiveScope
                ) else {
                    sourceExcluded += 1
                    continue
                }
                guard let result = HealthMdSleepSessionQuery.result(
                    session: session,
                    ownerDay: day,
                    relatedDays: related,
                    window: window,
                    authorizedSleepMetricIDs: authorizedSleepMetricIDs,
                    physiologyMetricIDs: physiologyMetricIDs,
                    authorizedEvidence: evidence
                ) else {
                    outside += 1
                    continue
                }
                limitations.append(contentsOf: result.limitations)
                items.append(.sleepSession(result))
            }
        }
        items.sort { lhs, rhs in
            guard case .sleepSession(let first) = lhs,
                  case .sleepSession(let second) = rhs else { return false }
            if first.start != second.start { return first.start < second.start }
            return first.sessionID < second.sessionID
        }
        return SleepListing(
            items: items,
            excludedCount: excludedNaps + outside + sourceExcluded,
            excludedNapCount: excludedNaps,
            windowOutsideCount: outside,
            sourceExcludedCount: sourceExcluded,
            adjacentOwnerDates: adjacentOwnerDates,
            limitations: limitations
        )
    }

    private func adjacentDays(
        around selectedDays: [HealthMdCompactContextDay],
        radius: Int
    ) -> [HealthMdCompactContextDay] {
        let selectedOwnerDates = Set(selectedDays.map(\.ownerDate))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        var allowedOwnerDates = selectedOwnerDates
        for ownerDate in selectedOwnerDates {
            guard let center = formatter.date(from: ownerDate),
                  formatter.string(from: center) == ownerDate else { continue }
            for offset in -radius...radius {
                if let date = formatter.calendar.date(byAdding: .day, value: offset, to: center) {
                    allowedOwnerDates.insert(formatter.string(from: date))
                }
            }
        }
        return days.filter { allowedOwnerDates.contains($0.ownerDate) }
    }

    private func sessionCalendarDates(
        _ session: HealthMdContextSleepSession,
        ownerDay: HealthMdCompactContextDay
    ) -> Set<String> {
        let timeZone = TimeZone(identifier: ownerDay.calendarTimeZone)
            ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var cursor = calendar.startOfDay(for: session.start)
        let final = calendar.startOfDay(for: session.end.addingTimeInterval(-0.001))
        var values = Set<String>()
        while cursor <= final {
            values.insert(formatter.string(from: cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor),
                  next > cursor else { break }
            cursor = next
        }
        return values
    }

    private struct AlignmentListing {
        let items: [HealthMdQueryItem]
        let valueDays: Set<String>
        let completeCount: Int
        let partialCount: Int
        let unavailableCount: Int
        let activityExcludedCount: Int
        let sourceExcludedCount: Int
        let physiologySampleCount: Int
        let limitations: [HealthMdLimitation]
    }

    private func workoutSleepAlignmentItems(
        in selectedDays: [HealthMdCompactContextDay],
        request: HealthMdQueryRequest,
        window: HealthMdSleepWindow?,
        workoutActivity: String?,
        includeNaps: Bool,
        scope: HealthMdEvidenceScope?
    ) throws -> AlignmentListing {
        let permissiveScope = scope ?? HealthMdEvidenceScope(
            allowedMetricIDs: selectedMetricIDs(request.metrics, in: days),
            allowsWorkouts: true
        )
        let authorizedSleepMetricIDs = HealthMdSleepSessionQuery.authorizedSleepMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: permissiveScope.allowedMetricIDs
        )
        let physiologyMetricIDs = HealthMdSleepSessionQuery.physiologyMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: permissiveScope.allowedMetricIDs
        ).subtracting(["workouts"])
        let relatedDays = adjacentDays(around: selectedDays, radius: 2)
        let evidence = relatedDays.flatMap(\.evidence).filter {
            evidenceIsAuthorized($0, selection: request.sources, scope: permissiveScope)
        }
        let normalizedActivity = workoutActivity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sleepCandidates = relatedDays.flatMap { day in
            day.sleepSessions.compactMap { session
                -> (session: HealthMdContextSleepSession, ownerDay: HealthMdCompactContextDay)? in
                if session.classification == .nap, !includeNaps { return nil }
                let sessionEvidence = evidence.filter {
                    session.evidenceIDs.contains($0.reference.evidenceID)
                }
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: session.evidenceIDs,
                    authorizedEvidence: sessionEvidence,
                    selection: request.sources,
                    scope: permissiveScope
                ) else { return nil }
                return (session, day)
            }
        }
        let workoutValues = workoutItems(in: selectedDays).compactMap { item -> HealthMdContextWorkout? in
            guard case .workout(let workout) = item else { return nil }
            return workout
        }

        var items: [HealthMdQueryItem] = []
        var valueDays = Set<String>()
        var complete = 0
        var partial = 0
        var unavailable = 0
        var activityExcluded = 0
        var sourceExcluded = 0
        var physiologySamples = 0
        var limitations: [HealthMdLimitation] = []
        let maximumDistance: TimeInterval = 36 * 3_600

        for workout in workoutValues {
            guard normalizedActivity == nil
                    || workout.activity.lowercased() == normalizedActivity else {
                activityExcluded += 1
                continue
            }
            let workoutEvidence = evidence.filter {
                workout.evidenceIDs.contains($0.reference.evidenceID)
            }
            guard evidencePassesSourceRestriction(
                originalEvidenceIDs: workout.evidenceIDs,
                authorizedEvidence: workoutEvidence,
                selection: request.sources,
                scope: permissiveScope
            ) else {
                sourceExcluded += 1
                continue
            }
            let preceding = sleepCandidates
                .filter {
                    $0.session.end <= workout.start
                        && workout.start.timeIntervalSince($0.session.end) <= maximumDistance
                }
                .max {
                    if $0.session.end != $1.session.end { return $0.session.end < $1.session.end }
                    return $0.session.sessionID < $1.session.sessionID
                }
            let following = sleepCandidates
                .filter {
                    $0.session.start >= workout.end
                        && $0.session.start.timeIntervalSince(workout.end) <= maximumDistance
                }
                .min {
                    if $0.session.start != $1.session.start { return $0.session.start < $1.session.start }
                    return $0.session.sessionID < $1.session.sessionID
                }
            let alignment = try HealthMdSleepSessionQuery.alignment(
                workout: workout,
                preceding: preceding,
                following: following,
                relatedDays: relatedDays,
                window: window,
                authorizedSleepMetricIDs: authorizedSleepMetricIDs,
                physiologyMetricIDs: physiologyMetricIDs,
                authorizedEvidence: evidence
            )
            switch alignment.status {
            case .complete: complete += 1
            case .partial: partial += 1
            case .unavailable: unavailable += 1
            }
            physiologySamples += alignment.physiologySampleCount
            limitations.append(contentsOf: alignment.limitations)
            if let ownerDate = selectedDays.first(where: {
                $0.workouts.contains { $0.workoutID == workout.workoutID }
            })?.ownerDate {
                valueDays.insert(ownerDate)
            }
            items.append(.workoutSleepAlignment(alignment))
        }
        items.sort { lhs, rhs in
            guard case .workoutSleepAlignment(let first) = lhs,
                  case .workoutSleepAlignment(let second) = rhs else { return false }
            if first.workout.start != second.workout.start {
                return first.workout.start < second.workout.start
            }
            return first.alignmentID < second.alignmentID
        }
        return AlignmentListing(
            items: items,
            valueDays: valueDays,
            completeCount: complete,
            partialCount: partial,
            unavailableCount: unavailable,
            activityExcludedCount: activityExcluded,
            sourceExcludedCount: sourceExcluded,
            physiologySampleCount: physiologySamples,
            limitations: limitations
        )
    }

    // MARK: Comparisons

    private func comparisonItems(
        first: HealthMdDateRange,
        second: HealthMdDateRange,
        descriptors: [HealthMdAggregationDescriptor],
        metricSelection: HealthMdMetricSelection
    ) throws -> [HealthMdQueryItem] {
        try validate(first)
        try validate(second)
        let selected = selectedMetricIDs(metricSelection, in: days)
        var uniqueDescriptors: [String: HealthMdAggregationDescriptor] = [:]
        for descriptor in descriptors where selected.contains(descriptor.metricID) { uniqueDescriptors[descriptor.metricID] = descriptor }
        return try uniqueDescriptors.values.sorted { $0.metricID < $1.metricID }.map { descriptor in
            let firstMetrics = metrics(for: descriptor.metricID, range: first)
            let secondMetrics = metrics(for: descriptor.metricID, range: second)
            let firstValue = try aggregate(firstMetrics, descriptor: descriptor)
            let secondValue = try aggregate(secondMetrics, descriptor: descriptor)
            let firstNumber = firstValue?.finiteNumericValue
            let secondNumber = secondValue?.finiteNumericValue
            let direction: HealthMdComparisonDirection
            if let lhs = firstNumber, let rhs = secondNumber {
                direction = rhs == lhs ? .unchanged : (rhs > lhs ? .increased : .decreased)
            } else { direction = .notComparable }
            var limitations = (firstMetrics + secondMetrics).flatMap(\.limitations)
            var percent: Double?
            if let lhs = firstNumber, let rhs = secondNumber {
                if lhs == 0 {
                    limitations.append(.init(code: "zero_baseline", message: "Percent change is unavailable because the first period value is zero."))
                } else { percent = ((rhs - lhs) / abs(lhs)) * 100 }
            }
            let absolute = try difference(first: firstValue, second: secondValue)
            let evidence = Array(Set((firstMetrics + secondMetrics).flatMap(\.evidence))).sorted { $0.evidenceID < $1.evidenceID }
            let selectedDays = try selectDays(.exact(combined(first, second)))
            let valueDays = Set((firstMetrics + secondMetrics).map(\.ownerDate))
            return .comparison(HealthMdPeriodComparison(
                metricID: descriptor.metricID, aggregation: descriptor,
                firstRange: first, secondRange: second,
                firstValue: firstValue, secondValue: secondValue,
                absoluteChange: absolute, percentChange: percent, direction: direction,
                coverage: coverage(for: selectedDays, requested: .exact(combined(first, second)), valueDays: valueDays),
                evidence: evidence, limitations: uniqueLimitations(limitations)
            ))
        }
    }

    private func metrics(for metricID: String, range: HealthMdDateRange) -> [HealthMdMetricPoint] {
        metricItems(days: days.filter { $0.ownerDate >= range.startDate && $0.ownerDate <= range.endDate }, selection: .explicit([metricID])).compactMap {
            if case .metric(let metric) = $0, metric.value != nil, metric.status == .available { return metric }
            return nil
        }
    }

    private func aggregate(_ metrics: [HealthMdMetricPoint], descriptor: HealthMdAggregationDescriptor) throws -> HealthMdQueryValue? {
        guard !metrics.isEmpty else { return nil }
        let values = metrics.compactMap(\.value)
        guard !values.isEmpty else { return nil }
        if descriptor.kind == .latest { return metrics.max { $0.ownerDate < $1.ownerDate }?.value }
        if descriptor.kind == .count { return .count(Int64(values.count)) }
        let pairs = values.compactMap { value -> (Double, String?, ValueShape)? in
            guard let number = value.finiteNumericValue else { return nil }
            switch value {
            case .quantity(_, let unit): return (number, unit, .quantity)
            case .duration: return (number, "s", .duration)
            case .count: return (number, "count", .count)
            default: return nil
            }
        }
        guard pairs.count == values.count, let first = pairs.first else { throw HealthMdQueryContractError.invalidAggregation(descriptor.metricID) }
        let units = Set(pairs.compactMap { $0.1 })
        guard units.count <= 1, descriptor.expectedUnit == nil || descriptor.expectedUnit == first.1 else {
            throw HealthMdQueryContractError.invalidAggregation("unit_mismatch:\(descriptor.metricID)")
        }
        let numbers = pairs.map(\.0)
        let result: Double
        switch descriptor.kind {
        case .sum, .durationSum: result = numbers.reduce(0, +)
        case .average: result = numbers.reduce(0, +) / Double(numbers.count)
        case .minimum: result = numbers.min()!
        case .maximum: result = numbers.max()!
        case .latest, .count: throw HealthMdQueryContractError.invalidAggregation("unexpected_aggregation_branch")
        }
        guard result.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
        return typedNumeric(result, shape: first.2, unit: first.1)
    }

    private enum ValueShape { case quantity, duration, count }
    private func typedNumeric(_ value: Double, shape: ValueShape, unit: String?) -> HealthMdQueryValue {
        switch shape {
        case .quantity: return .quantity(value: value, unit: unit ?? "")
        case .duration: return .duration(seconds: value)
        case .count:
            if value.rounded() == value, value <= Double(Int64.max), value >= Double(Int64.min) { return .count(Int64(value)) }
            return .quantity(value: value, unit: unit ?? "count")
        }
    }

    private func difference(first: HealthMdQueryValue?, second: HealthMdQueryValue?) throws -> HealthMdQueryValue? {
        guard let first, let second, let lhs = first.finiteNumericValue, let rhs = second.finiteNumericValue else { return nil }
        guard first.unit == second.unit else { return nil }
        let delta = rhs - lhs
        guard delta.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
        switch second {
        case .quantity(_, let unit): return .quantity(value: delta, unit: unit)
        case .duration: return .duration(seconds: delta)
        case .count where delta.rounded() == delta: return .count(Int64(delta))
        default: return .quantity(value: delta, unit: second.unit ?? "")
        }
    }

    // MARK: Packet derivations

    private func packetFacts(
        kind: HealthMdPacketKind,
        detailIDs: [String],
        days: [HealthMdCompactContextDay],
        selection: HealthMdMetricSelection,
        scope: HealthMdEvidenceScope
    ) throws -> [HealthMdPacketFact] {
        let requested: Set<String>
        switch selection {
        case .explicit(let ids):
            requested = Set(ids)
            let denied = requested.subtracting(scope.allowedMetricIDs)
            guard denied.isEmpty else { throw HealthMdQueryContractError.scopeViolation("metric_ids:\(denied.sorted().joined(separator: ","))") }
        case .allAvailable: requested = scope.allowedMetricIDs
        }
        let requestedDetails = Set(detailIDs)
        let deniedDetails = requestedDetails.subtracting(scope.allowedDetailIDs)
        guard deniedDetails.isEmpty else { throw HealthMdQueryContractError.scopeViolation("detail_ids:\(deniedDetails.sorted().joined(separator: ","))") }

        let evidence = evidenceIndex(days)
        var facts: [HealthMdPacketFact] = []
        var seen = Set<String>()
        for day in days {
            for metric in day.metrics where requested.contains(metric.metricID) && metric.status == .available {
                guard let value = metric.value else { continue }
                let factID = "metric:\(day.ownerDate):\(metric.metricID):\(metric.observationID)"
                guard seen.insert(factID).inserted else { continue }
                facts.append(.init(
                    factID: factID, label: metric.displayName, ownerDate: day.ownerDate, value: value,
                    evidence: metric.evidenceIDs.compactMap { evidence[$0]?.reference }
                ))
            }
            if kind == .training, scope.allowsWorkouts {
                for workout in day.workouts {
                    for detailID in requestedDetails.sorted() {
                        guard let value = workout.details[detailID] else { continue }
                        let factID = "workout:\(workout.workoutID):\(detailID)"
                        guard seen.insert(factID).inserted else { continue }
                        facts.append(.init(
                            factID: factID, label: "\(workout.activity) \(detailID)", ownerDate: day.ownerDate,
                            value: value, evidence: workout.evidenceIDs.compactMap { evidence[$0]?.reference }
                        ))
                    }
                }
            }
        }
        return facts.sorted { $0.factID < $1.factID }
    }

    private static let medicalSafetyLimitation = HealthMdLimitation(
        code: "factual_observations_only",
        message: "This packet reports stored observations only and does not diagnose conditions or recommend treatment."
    )

    // MARK: Coverage

    private func metricCoverage(
        for selectedDays: [HealthMdCompactContextDay],
        requested: HealthMdDateSelection,
        items: [HealthMdQueryItem]
    ) -> HealthMdCoverage {
        let points = items.compactMap { item -> HealthMdMetricPoint? in
            guard case .metric(let point) = item else { return nil }
            return point
        }
        let valueDays = Set(points.filter { $0.value != nil && $0.status == .available }.map(\.ownerDate))
        var result = coverage(for: selectedDays, requested: requested, valueDays: valueDays)
        let unavailable = Dictionary(grouping: points.filter { $0.value == nil || $0.status != .available }, by: \.ownerDate)
        guard !unavailable.isEmpty else { return result }
        var missing = result.missing.filter { unavailable[$0.range.startDate] == nil }
        for (ownerDate, dayPoints) in unavailable {
            let statuses = Set(dayPoints.map(\.status))
            let status: HealthMdAvailabilityStatus = statuses.count == 1 ? statuses.first! : .partial
            missing.append(.init(range: .init(startDate: ownerDate, endDate: ownerDate), status: status))
        }
        let overall: HealthMdAvailabilityStatus
        if valueDays.isEmpty, Set(missing.map(\.status)).count == 1 { overall = missing.first?.status ?? result.status }
        else { overall = .partial }
        result = HealthMdCoverage(
            requestedRange: result.requestedRange, availableRange: result.availableRange,
            status: overall, daysConsidered: result.daysConsidered,
            daysWithValues: result.daysWithValues, missing: missing
        )
        return result
    }

    private func coverage(
        for selectedDays: [HealthMdCompactContextDay],
        requested: HealthMdDateSelection,
        valueDays: Set<String>
    ) -> HealthMdCoverage {
        let requestedRange = selectedRange(requested, selectedDays: selectedDays)
        let availableRange = days.first.flatMap { first in days.last.map { HealthMdDateRange(startDate: first.ownerDate, endDate: $0.ownerDate) } }
        let missing = selectedDays.compactMap { day -> HealthMdMissingInterval? in
            let status: HealthMdAvailabilityStatus
            if valueDays.contains(day.ownerDate) { return nil }
            if day.status == .available { status = .completeEmpty } else { status = day.status }
            return .init(range: .init(startDate: day.ownerDate, endDate: day.ownerDate), status: status)
        }
        let status: HealthMdAvailabilityStatus
        if selectedDays.isEmpty { status = .notSynchronized }
        else if missing.isEmpty { status = .available }
        else if valueDays.isEmpty {
            let statuses = Set(missing.map(\.status))
            status = statuses.count == 1 ? statuses.first! : .partial
        } else { status = .partial }
        return HealthMdCoverage(
            requestedRange: requestedRange, availableRange: availableRange, status: status,
            daysConsidered: selectedDays.count, daysWithValues: valueDays.count, missing: missing
        )
    }

    private func selectedRange(_ selection: HealthMdDateSelection, selectedDays: [HealthMdCompactContextDay]) -> HealthMdDateRange? {
        switch selection {
        case .exact(let range): return range
        case .allAvailable:
            guard let first = selectedDays.first, let last = selectedDays.last else { return nil }
            return .init(startDate: first.ownerDate, endDate: last.ownerDate)
        }
    }

    private func combined(_ first: HealthMdDateRange, _ second: HealthMdDateRange) -> HealthMdDateRange {
        .init(startDate: min(first.startDate, second.startDate), endDate: max(first.endDate, second.endDate))
    }

    private func hasAnyValue(_ day: HealthMdCompactContextDay) -> Bool {
        day.metrics.contains { $0.value != nil && $0.status == .available }
            || !day.workouts.isEmpty
            || !day.sleepSessions.isEmpty
    }

    private func allLimitations(in days: [HealthMdCompactContextDay]) -> [HealthMdLimitation] {
        uniqueLimitations(
            days.flatMap(\.limitations)
                + days.flatMap { $0.metrics.flatMap(\.limitations) }
                + days.flatMap { $0.sleepSessions.flatMap(\.limitations) }
        )
    }

    private func uniqueLimitations(_ values: [HealthMdLimitation]) -> [HealthMdLimitation] {
        Array(Set(values)).sorted { $0.code != $1.code ? $0.code < $1.code : $0.message < $1.message }
    }

    private func normalizedSources(_ days: [HealthMdCompactContextDay]) -> [HealthMdSourceDescriptor] {
        normalizedSources(days.map(\.source))
    }

    private func normalizedSources(_ sources: [HealthMdSourceDescriptor]) -> [HealthMdSourceDescriptor] {
        Array(Set(sources)).sorted {
            if $0.schema != $1.schema { return $0.schema < $1.schema }
            if $0.schemaVersion != $1.schemaVersion { return $0.schemaVersion < $1.schemaVersion }
            return $0.digest < $1.digest
        }
    }

    private func responseEvidence(
        items: [HealthMdQueryItem],
        packet: HealthMdEvidencePacket?,
        days: [HealthMdCompactContextDay]
    ) -> [HealthMdEvidenceReference] {
        let index = evidenceIndex(days)
        var references: [HealthMdEvidenceReference] = []
        for item in items {
            switch item {
            case .metric(let metric): references.append(contentsOf: metric.evidence)
            case .comparison(let comparison): references.append(contentsOf: comparison.evidence)
            case .workout(let workout):
                references.append(contentsOf: workout.evidenceIDs.compactMap { index[$0]?.reference })
            case .sleepSession(let session):
                references.append(contentsOf: session.evidence)
                references.append(contentsOf: session.physiology.flatMap(\.evidence))
            case .workoutSleepAlignment(let alignment):
                references.append(contentsOf: alignment.evidence)
            case .evidence(let evidence):
                references.append(evidence.reference)
            }
        }
        references.append(contentsOf: packet?.facts.flatMap(\.evidence) ?? [])
        return Array(Set(references)).sorted { $0.evidenceID < $1.evidenceID }
    }

    private func evidenceIndex(_ days: [HealthMdCompactContextDay]) -> [String: HealthMdContextEvidence] {
        var result: [String: HealthMdContextEvidence] = [:]
        for item in days.flatMap(\.evidence) where result[item.reference.evidenceID] == nil { result[item.reference.evidenceID] = item }
        return result
    }

    // MARK: Cursor paging

    private struct Page<Value> { let values: [Value]; let nextCursor: String?; let limitations: [HealthMdLimitation] }

    private func paginate<Value: Encodable>(
        _ values: [Value], offset: Int, controls: HealthMdPageControls, fingerprint: String
    ) throws -> Page<Value> {
        guard offset >= 0, offset <= values.count else { throw HealthMdQueryContractError.invalidCursor }
        var result: [Value] = []
        var bytes = 0
        var index = offset
        while index < values.count, result.count < controls.maxItems {
            let size = try HealthMdQueryCanonicalSerializer.data(for: values[index]).count
            if size > controls.maxBytes { throw HealthMdQueryContractError.singleItemExceedsPageBytes }
            if !result.isEmpty, bytes + size > controls.maxBytes { break }
            result.append(values[index]); bytes += size; index += 1
            if bytes >= controls.maxBytes { break }
        }
        let cursor = index < values.count ? try makeCursor(offset: index, fingerprint: fingerprint) : nil
        return Page(values: result, nextCursor: cursor, limitations: [])
    }

    private struct RequestFingerprint: Encodable {
        let schema: String
        let schemaVersion: Int
        let metrics: HealthMdMetricSelection
        let sources: HealthMdSourceSelection
        let dates: HealthMdDateSelection
        let operation: HealthMdQueryOperation
        let maxItems: Int
        let maxBytes: Int
        enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case metrics, sources, dates, operation
            case maxItems = "max_items"
            case maxBytes = "max_bytes"
        }
    }

    private func requestFingerprint(_ request: HealthMdQueryRequest) throws -> String {
        try HealthMdQueryCanonicalSerializer.sha256(of: RequestFingerprint(
            schema: request.schema,
            schemaVersion: request.schemaVersion,
            metrics: request.metrics,
            sources: request.sources,
            dates: request.dates,
            operation: request.operation,
            maxItems: request.page.maxItems,
            maxBytes: request.page.maxBytes
        ))
    }

    private struct CursorPayload: Codable { let offset: Int; let query: String; let dataset: String }
    private struct CursorEnvelope: Codable { let payload: String; let mac: String }

    private func makeCursor(offset: Int, fingerprint: String) throws -> String {
        let payload = CursorPayload(offset: offset, query: fingerprint, dataset: datasetFingerprint)
        let payloadData = try HealthMdQueryCanonicalSerializer.data(for: payload)
        let payloadString = base64URL(payloadData)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payloadString.utf8), using: SymmetricKey(data: cursorKey))
        let envelope = CursorEnvelope(payload: payloadString, mac: Data(mac).map { String(format: "%02x", $0) }.joined())
        return base64URL(try HealthMdQueryCanonicalSerializer.data(for: envelope))
    }

    private func cursorOffset(_ cursor: String?, fingerprint: String) throws -> Int {
        guard let cursor else { return 0 }
        guard let envelopeData = decodeBase64URL(cursor),
              let envelope = try? JSONDecoder().decode(CursorEnvelope.self, from: envelopeData),
              let payloadData = decodeBase64URL(envelope.payload),
              let payload = try? JSONDecoder().decode(CursorPayload.self, from: payloadData) else {
            throw HealthMdQueryContractError.invalidCursor
        }
        let expected = HMAC<SHA256>.authenticationCode(for: Data(envelope.payload.utf8), using: SymmetricKey(data: cursorKey))
        let expectedHex = Data(expected).map { String(format: "%02x", $0) }.joined()
        guard constantTimeEqual(expectedHex, envelope.mac) else { throw HealthMdQueryContractError.invalidCursor }
        guard payload.query == fingerprint, payload.dataset == datasetFingerprint else { throw HealthMdQueryContractError.cursorDoesNotMatchQuery }
        return payload.offset
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices { difference |= a[index] ^ b[index] }
        return difference == 0
    }
}

private nonisolated extension HealthMdQueryItem {
    var ownerDateForCoverage: String? {
        switch self {
        case .metric(let value): return value.value == nil ? nil : value.ownerDate
        case .workout: return nil
        case .sleepSession(let value): return value.ownerDate
        case .workoutSleepAlignment: return nil
        case .comparison: return nil
        case .evidence: return nil
        }
    }
}

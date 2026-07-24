#if os(macOS)
import CryptoKit
import Foundation

nonisolated private enum EncryptedQueryExecutionContext {
    @TaskLocal static var evidenceScope: HealthMdEvidenceScope?
}

/// Bounded-memory production query execution over the encrypted one-day-per-blob store.
///
/// The executor retains an authenticated manifest snapshot, one decrypted context day, and the
/// bounded response page. It never materializes an all-history day or result array. Cursors carry a
/// day/in-day traversal position (or comparison descriptor position), are AES-GCM authenticated and
/// encrypted, and are bound to both the complete request without its cursor and the immutable
/// manifest revision.
actor EncryptedHealthContextQueryExecutor: HealthMdAgentQueryExecuting, HealthMdAgentQueryReadinessProviding {
    nonisolated private static let cursorAAD = Data("healthmd/encrypted-query-executor/v1/cursor".utf8)
    nonisolated private static let medicalSafetyLimitation = HealthMdLimitation(
        code: "factual_observations_only",
        message: "This packet reports stored observations only and does not diagnose conditions or recommend treatment."
    )

    private let store: EncryptedHealthContextStore
    private let defaultEvidenceScope: HealthMdEvidenceScope
    private let now: @Sendable () -> Date
    private let didLoadDay: @Sendable (String) -> Void

    /// A missing task-local scope is a programming error, but still fails closed
    /// rather than inheriting permissions from another re-entrant actor task.
    private var evidenceScope: HealthMdEvidenceScope {
        EncryptedQueryExecutionContext.evidenceScope
            ?? HealthMdEvidenceScope(allowedMetricIDs: [])
    }

    init(
        store: EncryptedHealthContextStore,
        evidenceScope: HealthMdEvidenceScope = HealthMdEvidenceScope(allowedMetricIDs: []),
        now: @escaping @Sendable () -> Date = { Date() },
        didLoadDay: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.store = store
        self.defaultEvidenceScope = evidenceScope
        self.now = now
        self.didLoadDay = didLoadDay
    }

    func queryStoreReadiness() async throws -> HealthMdAgentQueryStoreReadiness {
        let snapshot = try await store.snapshot()
        return HealthMdAgentQueryStoreReadiness(
            revision: snapshot.revision,
            ownerDateCount: snapshot.entries.count,
            firstOwnerDate: snapshot.entries.first?.ownerDate,
            lastOwnerDate: snapshot.entries.last?.ownerDate
        )
    }

    func queryStoreBaseline() async throws -> HealthMdAgentQueryStoreBaseline? {
        let snapshot = try await store.snapshot()
        return HealthMdAgentQueryStoreBaseline(
            revision: snapshot.revision,
            ownerDateMutationIDs: snapshot.ownerDateMutationIDs
        )
    }

    func requestedScopeCompletion(
        dates: HealthMdDateSelection,
        metricIDs: Set<String>,
        sources: HealthMdSourceSelection = .allAvailable,
        changedSince baseline: HealthMdAgentQueryStoreBaseline? = nil
    ) async throws -> HealthMdRequestedScopeCompletion? {
        guard !metricIDs.isEmpty else { return nil }
        let requestedSources = requestedCompletionSources(sources)
        guard !requestedSources.isEmpty else { return nil }
        let snapshot = try await store.snapshot()
        let bounds = try selectionBounds(dates, snapshot: snapshot)
        let requestedDayCount: Int
        switch dates {
        case .allAvailable:
            requestedDayCount = bounds.endIndex - bounds.startIndex
        case .exact(let range):
            requestedDayCount = try ownerDateCount(range)
        }
        let presentDayCount = bounds.endIndex - bounds.startIndex
        let missingDayCount = max(0, requestedDayCount - presentDayCount)
        var statusCounts: [String: Int] = [:]
        var completeMetricDays = 0
        var incompleteMetricDays = 0

        struct SkipAccumulator {
            let identifier: String
            let status: HealthMdAvailabilityStatus
            let metricIDs: [String]
            var occurrenceCount: Int
            var firstOwnerDate: String
            var lastOwnerDate: String
            var reason: String?
        }
        var unrelated: [String: SkipAccumulator] = [:]

        for index in bounds.startIndex..<bounds.endIndex {
            let day = try await loadDay(snapshot, at: index)
            let wasChanged = baseline.map {
                $0.ownerDateMutationIDs[day.ownerDate]
                    != snapshot.ownerDateMutationIDs[day.ownerDate]
            } ?? true
            for metricID in metricIDs.sorted() {
                for source in requestedSources {
                    let status = wasChanged
                        ? requestedMetricStatus(metricID, in: day, source: source)
                        : .notSynchronized
                    statusCounts[status.rawValue, default: 0] += 1
                    if status == .available || status == .completeEmpty {
                        completeMetricDays += 1
                    } else {
                        incompleteMetricDays += 1
                    }
                }
            }
            guard wasChanged else { continue }
            for item in day.evidence {
                guard evidenceMatchesSourceSelection(item, sources: sources),
                      case .queryManifest(_, let identifier) = item.reference.locator,
                      let diagnostic = queryDiagnostic(item),
                      diagnostic.status == .skipped || diagnostic.status == .unsupported,
                      Set(diagnostic.metricIDs).isDisjoint(with: metricIDs) else { continue }
                let key = "\(identifier)|\(diagnostic.status.rawValue)|\(diagnostic.metricIDs.joined(separator: ","))"
                if var existing = unrelated[key] {
                    existing.occurrenceCount += 1
                    existing.firstOwnerDate = min(existing.firstOwnerDate, day.ownerDate)
                    existing.lastOwnerDate = max(existing.lastOwnerDate, day.ownerDate)
                    if existing.reason == nil { existing.reason = item.note }
                    unrelated[key] = existing
                } else {
                    unrelated[key] = SkipAccumulator(
                        identifier: identifier,
                        status: diagnostic.status,
                        metricIDs: diagnostic.metricIDs,
                        occurrenceCount: 1,
                        firstOwnerDate: day.ownerDate,
                        lastOwnerDate: day.ownerDate,
                        reason: item.note
                    )
                }
            }
        }

        if missingDayCount > 0 {
            let missingMetricDays = missingDayCount * metricIDs.count * requestedSources.count
            statusCounts[HealthMdAvailabilityStatus.notSynchronized.rawValue, default: 0]
                += missingMetricDays
            incompleteMetricDays += missingMetricDays
        }
        // The v1 field name is retained for compatibility; each count now
        // represents one requested metric × source/provider × owner-day cell.
        let metricDaysConsidered = requestedDayCount * metricIDs.count * requestedSources.count
        let status: HealthMdRequestedScopeStatus
        if metricDaysConsidered == 0 { status = .unavailable }
        else if incompleteMetricDays == 0 { status = .success }
        else if completeMetricDays > 0 { status = .partialSuccess }
        else { status = .failure }
        let skips = unrelated.values.map {
            HealthMdUnrelatedSkip(
                identifier: $0.identifier,
                status: $0.status,
                metricIDs: $0.metricIDs,
                occurrenceCount: $0.occurrenceCount,
                firstOwnerDate: $0.firstOwnerDate,
                lastOwnerDate: $0.lastOwnerDate,
                reason: $0.reason
            )
        }.sorted {
            if $0.identifier != $1.identifier { return $0.identifier < $1.identifier }
            return $0.status.rawValue < $1.status.rawValue
        }
        return HealthMdRequestedScopeCompletion(
            status: status,
            requestedMetricIDs: Array(metricIDs),
            daysConsidered: requestedDayCount,
            metricDaysConsidered: metricDaysConsidered,
            completeMetricDays: completeMetricDays,
            incompleteMetricDays: incompleteMetricDays,
            statusCounts: statusCounts,
            unrelatedSkips: skips
        )
    }

    private enum RequestedCompletionSource: Hashable {
        case any
        case source(String)
        case provider(String)
    }

    private func requestedCompletionSources(
        _ selection: HealthMdSourceSelection
    ) -> [RequestedCompletionSource] {
        switch selection {
        case .allAvailable:
            return [.any]
        case .explicit(let sourceIDs, let providerIDs):
            return sourceIDs.sorted().map(RequestedCompletionSource.source)
                + providerIDs.sorted().map(RequestedCompletionSource.provider)
        }
    }

    private func requestedMetricStatus(
        _ metricID: String,
        in day: HealthMdCompactContextDay,
        source: RequestedCompletionSource
    ) -> HealthMdAvailabilityStatus {
        if case .provider(let providerID) = source {
            return providerMetricStatus(metricID, providerID: providerID, in: day)
        }
        let evidenceByID = Dictionary(
            uniqueKeysWithValues: day.evidence.map { ($0.reference.evidenceID, $0) }
        )
        func hasSelectedEvidence(_ evidenceIDs: [String]) -> Bool {
            if source == .any { return true }
            return evidenceIDs.contains {
                evidenceByID[$0].map { evidenceMatchesCompletionSource($0, source: source) } == true
            }
        }
        if metricID == "workouts",
           day.workouts.contains(where: { hasSelectedEvidence($0.evidenceIDs) }) {
            return .available
        }
        let matches = day.metrics.filter {
            $0.metricID == metricID && hasSelectedEvidence($0.evidenceIDs)
        }
        guard !matches.isEmpty else {
            if metricID == "workouts" {
                return day.status == .available || day.status == .completeEmpty
                    ? .completeEmpty : day.status
            }
            return .notSynchronized
        }
        if matches.contains(where: { $0.status == .available && $0.value != nil }) {
            return .available
        }
        let statuses = Set(matches.map {
            $0.status == .available && $0.value == nil ? .completeEmpty : $0.status
        })
        return statuses.count == 1 ? statuses.first! : .partial
    }

    private func providerMetricStatus(
        _ metricID: String,
        providerID: String,
        in day: HealthMdCompactContextDay
    ) -> HealthMdAvailabilityStatus {
        let statuses = day.evidence.compactMap { evidence -> HealthMdAvailabilityStatus? in
            guard evidence.reference.providerID == providerID,
                  evidence.metricIDs.contains(metricID),
                  case .queryManifest = evidence.reference.locator,
                  case .unknown(let type, let payload) = evidence.value,
                  type == "external_provider_fetch_result",
                  case .object(let object)? = payload,
                  case .string(let rawStatus)? = object["status"] else { return nil }
            return HealthMdAvailabilityStatus(rawValue: rawStatus)
        }
        guard !statuses.isEmpty else { return .notSynchronized }
        let unique = Set(statuses)
        if unique.count == 1 { return unique.first! }
        if unique.allSatisfy({ $0 == .available || $0 == .completeEmpty }) {
            return unique.contains(.available) ? .available : .completeEmpty
        }
        return .partial
    }

    private func evidenceMatchesCompletionSource(
        _ evidence: HealthMdContextEvidence,
        source: RequestedCompletionSource
    ) -> Bool {
        switch source {
        case .any:
            return true
        case .provider(let providerID):
            return evidence.reference.providerID == providerID
        case .source(let sourceID):
            if evidence.reference.providerID != nil { return false }
            return evidence.reference.sourceID == sourceID
                || sourceID == "apple_health"
        }
    }

    private func evidenceMatchesSourceSelection(
        _ evidence: HealthMdContextEvidence,
        sources: HealthMdSourceSelection
    ) -> Bool {
        switch sources {
        case .allAvailable:
            return true
        case .explicit(let sourceIDs, let providerIDs):
            if let providerID = evidence.reference.providerID {
                return providerIDs.contains(providerID)
            }
            return sourceIDs.contains(evidence.reference.sourceID)
                || sourceIDs.contains("apple_health")
        }
    }

    private func queryDiagnostic(
        _ item: HealthMdContextEvidence
    ) -> (status: HealthMdAvailabilityStatus, metricIDs: [String])? {
        guard case .unknown(let type, let payload) = item.value,
              type == "healthkit_query_result",
              case .object(let object)? = payload,
              case .string(let rawStatus)? = object["status"] else { return nil }
        let status: HealthMdAvailabilityStatus
        switch rawStatus {
        case "success": status = .available
        case "failure": status = .failed
        case "unsupported": status = .unsupported
        case "skipped": status = .skipped
        case "cancelled": status = .cancelled
        default: return nil
        }
        let valueMetricIDs: [String]
        if case .array(let values)? = object["metric_ids"] {
            valueMetricIDs = values.compactMap {
                guard case .string(let value) = $0 else { return nil }
                return value
            }
        } else {
            valueMetricIDs = []
        }
        return (status, Array(Set(item.metricIDs + valueMetricIDs)).sorted())
    }

    private func ownerDateCount(_ range: HealthMdDateRange) throws -> Int {
        try validate(range)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: range.startDate),
              let end = formatter.date(from: range.endDate),
              let days = formatter.calendar.dateComponents([.day], from: start, to: end).day else {
            throw HealthMdQueryContractError.invalidDateRange
        }
        return days + 1
    }

    /// Convenience for direct in-process callers. The loopback query API
    /// uses the explicit request-scoped evidence overload below.
    func execute(
        _ request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel
    ) async throws -> HealthMdQueryResponse {
        try await execute(
            request,
            detailLevel: detailLevel,
            evidenceScope: defaultEvidenceScope
        )
    }

    func execute(
        _ request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel,
        evidenceScope: HealthMdEvidenceScope
    ) async throws -> HealthMdQueryResponse {
        try await EncryptedQueryExecutionContext.$evidenceScope.withValue(evidenceScope) {
            try validate(request, detailLevel: detailLevel)
            let snapshot = try await store.snapshot()
            let fingerprint = try requestFingerprint(request, detailLevel: detailLevel)
            let initial = try await cursorPosition(
                request.page.cursor,
                fingerprint: fingerprint,
                datasetRevision: snapshot.revision
            )

            switch request.operation {
            case .metricSeries:
                return try await metricSeries(
                    request,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .workoutListing:
                return try await workoutListing(
                    request,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .sleepSessionListing(let window, let includeNaps):
                return try await sleepSessionListing(
                    request,
                    window: window,
                    includeNaps: includeNaps,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .workoutSleepAlignment(let window, let activity, let includeNaps):
                return try await workoutSleepAlignment(
                    request,
                    window: window,
                    workoutActivity: activity,
                    includeNaps: includeNaps,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .sourceRecordListing:
                return try await sourceRecordListing(
                    request,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .coverage:
                return try await coverageListing(
                    request,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .periodComparison(let first, let second, let descriptors):
                return try await periodComparisons(
                    request,
                    first: first,
                    second: second,
                    descriptors: descriptors,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            case .derivePacket(let kind, let detailIDs):
                return try await packet(
                    request,
                    kind: kind,
                    detailIDs: detailIDs,
                    snapshot: snapshot,
                    position: initial,
                    fingerprint: fingerprint
                )
            }
        }
    }

    // MARK: - Metric series

    private func metricSeries(
        _ request: HealthMdQueryRequest,
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        var budget = PageBudget(controls: request.page)
        var items: [HealthMdQueryItem] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var pageCoverage = CoverageAccumulator()
        var stopped: TraversalPosition?

        dayLoop: while cursor.major < bounds.endIndex {
            let day = try await loadDay(snapshot, at: cursor.major)
            let evidenceByID = Dictionary(
                day.evidence.map { ($0.reference.evidenceID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            if !cursor.metadataDone {
                let summary = metricDaySummary(day, request: request, evidenceByID: evidenceByID)
                guard try pageCoverage.consider(
                    ownerDate: day.ownerDate,
                    hasValue: summary.hasValue,
                    missingStatus: summary.missingStatus,
                    budget: &budget
                ) else {
                    stopped = cursor
                    break dayLoop
                }
                limitations.formUnion(day.limitations)
                cursor.metadataDone = true
            }

            guard cursor.minor >= 0, cursor.minor <= day.metrics.count else {
                throw HealthMdQueryContractError.invalidCursor
            }
            while cursor.minor < day.metrics.count {
                let metric = day.metrics[cursor.minor]
                let rawIndex = cursor.minor
                cursor.minor += 1
                guard metricIsSelected(metric.metricID, selection: request.metrics) else { continue }
                let evidence = authorizedEvidence(
                    ids: metric.evidenceIDs,
                    in: evidenceByID,
                    selection: request.sources
                )
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: metric.evidenceIDs,
                    authorizedEvidence: evidence,
                    selection: request.sources
                ) else { continue }

                let point = HealthMdMetricPoint(
                    metricID: metric.metricID,
                    displayName: metric.displayName,
                    ownerDate: day.ownerDate,
                    value: metric.value,
                    status: metric.value == nil && metric.status == .available ? .completeEmpty : metric.status,
                    evidence: evidence.map(\.reference).sorted { $0.evidenceID < $1.evidenceID },
                    limitations: metric.limitations
                )
                let item = HealthMdQueryItem.metric(point)
                guard try budget.appendItem(item) else {
                    cursor.minor = rawIndex
                    stopped = cursor
                    break dayLoop
                }
                items.append(item)
                references.formUnion(point.evidence)
                sources.insert(day.source)
                sources.formUnion(point.evidence.map(\.source))
                limitations.formUnion(metric.limitations)
            }

            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        return HealthMdQueryResponse(
            items: items,
            packet: nil,
            coverage: pageCoverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations)
        )
    }

    // MARK: - Evidence/source records

    private func sourceRecordListing(
        _ request: HealthMdQueryRequest,
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        var budget = PageBudget(controls: request.page)
        var items: [HealthMdQueryItem] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var pageCoverage = CoverageAccumulator()
        var stopped: TraversalPosition?

        dayLoop: while cursor.major < bounds.endIndex {
            let day = try await loadDay(snapshot, at: cursor.major)
            let linkedMetrics = evidenceMetricLinks(day)
            if !cursor.metadataDone {
                let hasValue = day.evidence.contains {
                    evidenceIsSelected($0, linkedMetrics: linkedMetrics, request: request)
                }
                guard try pageCoverage.consider(
                    ownerDate: day.ownerDate,
                    hasValue: hasValue,
                    missingStatus: hasValue ? .available : missingStatus(for: day.status),
                    budget: &budget
                ) else {
                    stopped = cursor
                    break dayLoop
                }
                limitations.formUnion(day.limitations)
                cursor.metadataDone = true
            }

            guard cursor.minor >= 0, cursor.minor <= day.evidence.count else {
                throw HealthMdQueryContractError.invalidCursor
            }
            while cursor.minor < day.evidence.count {
                let evidence = day.evidence[cursor.minor]
                let rawIndex = cursor.minor
                cursor.minor += 1
                guard evidenceIsSelected(evidence, linkedMetrics: linkedMetrics, request: request) else { continue }
                let item = HealthMdQueryItem.evidence(evidence)
                guard try budget.appendItem(item) else {
                    cursor.minor = rawIndex
                    stopped = cursor
                    break dayLoop
                }
                items.append(item)
                references.insert(evidence.reference)
                sources.insert(evidence.reference.source)
            }
            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        return HealthMdQueryResponse(
            items: items,
            packet: nil,
            coverage: pageCoverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations)
        )
    }

    // MARK: - Workouts

    private struct WorkoutCandidate: Sendable {
        let workout: HealthMdContextWorkout
        let ownerDate: String
        let source: HealthMdSourceDescriptor
        let evidence: [HealthMdContextEvidence]
        let isAuthorized: Bool
    }

    private func workoutListing(
        _ request: HealthMdQueryRequest,
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        var budget = PageBudget(controls: request.page)
        var items: [HealthMdQueryItem] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var pageCoverage = CoverageAccumulator()
        var stopped: TraversalPosition?

        dayLoop: while cursor.major < bounds.endIndex {
            if !cursor.metadataDone {
                let day = try await loadDay(snapshot, at: cursor.major)
                let hasValue = day.workouts.contains { workout in
                    let evidenceByID = Dictionary(
                        day.evidence.map { ($0.reference.evidenceID, $0) },
                        uniquingKeysWith: { first, _ in first }
                    )
                    let evidence = authorizedEvidence(
                        ids: workout.evidenceIDs,
                        in: evidenceByID,
                        selection: request.sources
                    )
                    return evidencePassesSourceRestriction(
                        originalEvidenceIDs: workout.evidenceIDs,
                        authorizedEvidence: evidence,
                        selection: request.sources
                    )
                }
                guard try pageCoverage.consider(
                    ownerDate: day.ownerDate,
                    hasValue: hasValue,
                    missingStatus: hasValue ? .available : missingStatus(for: day.status),
                    budget: &budget
                ) else {
                    stopped = cursor
                    break dayLoop
                }
                limitations.formUnion(day.limitations)
                cursor.metadataDone = true
            }

            while let raw = try await workoutCandidate(
                snapshot: snapshot,
                dayIndex: cursor.major,
                workoutIndex: cursor.minor,
                sourceSelection: request.sources
            ) {
                let rawIndex = cursor.minor
                cursor.minor += 1
                guard raw.isAuthorized else { continue }
                guard try await isFirstWorkoutOccurrence(
                    raw.workout.workoutID,
                    dayIndex: cursor.major,
                    workoutIndex: rawIndex,
                    bounds: bounds,
                    snapshot: snapshot
                ) else { continue }
                let candidate = try await canonicalWorkout(
                    raw.workout.workoutID,
                    fallback: raw,
                    bounds: bounds,
                    snapshot: snapshot,
                    sourceSelection: request.sources
                )
                let item = HealthMdQueryItem.workout(candidate.workout)
                guard try budget.appendItem(item) else {
                    cursor.minor = rawIndex
                    stopped = cursor
                    break dayLoop
                }
                items.append(item)
                references.formUnion(candidate.evidence.map(\.reference))
                sources.insert(candidate.source)
                sources.formUnion(candidate.evidence.map { $0.reference.source })
            }
            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        return HealthMdQueryResponse(
            items: items,
            packet: nil,
            coverage: pageCoverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations)
        )
    }

    /// Returns a small candidate value; the decrypted day is released before any cross-day scan.
    private func workoutCandidate(
        snapshot: HealthContextStoreSnapshot,
        dayIndex: Int,
        workoutIndex: Int,
        sourceSelection: HealthMdSourceSelection
    ) async throws -> WorkoutCandidate? {
        let day = try await loadDay(snapshot, at: dayIndex)
        guard workoutIndex >= 0 else { throw HealthMdQueryContractError.invalidCursor }
        guard workoutIndex < day.workouts.count else { return nil }
        let workout = day.workouts[workoutIndex]
        let evidenceByID = Dictionary(
            day.evidence.map { ($0.reference.evidenceID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let evidence = authorizedEvidence(
            ids: workout.evidenceIDs,
            in: evidenceByID,
            selection: sourceSelection
        )
        guard evidencePassesSourceRestriction(
            originalEvidenceIDs: workout.evidenceIDs,
            authorizedEvidence: evidence,
            selection: sourceSelection
        ) else {
            return WorkoutCandidate(
                workout: workout,
                ownerDate: day.ownerDate,
                source: day.source,
                evidence: [],
                isAuthorized: false
            )
        }
        return WorkoutCandidate(
            workout: workout,
            ownerDate: day.ownerDate,
            source: day.source,
            evidence: evidence,
            isAuthorized: true
        )
    }

    private func isFirstWorkoutOccurrence(
        _ workoutID: String,
        dayIndex: Int,
        workoutIndex: Int,
        bounds: SelectionBounds,
        snapshot: HealthContextStoreSnapshot
    ) async throws -> Bool {
        for index in bounds.startIndex...dayIndex {
            let day = try await loadDay(snapshot, at: index)
            let end = index == dayIndex ? min(workoutIndex, day.workouts.count) : day.workouts.count
            if day.workouts[..<end].contains(where: { $0.workoutID == workoutID }) { return false }
        }
        return true
    }

    private func canonicalWorkout(
        _ workoutID: String,
        fallback: WorkoutCandidate,
        bounds: SelectionBounds,
        snapshot: HealthContextStoreSnapshot,
        sourceSelection: HealthMdSourceSelection
    ) async throws -> WorkoutCandidate {
        var best = fallback
        var bestEncoding = try HealthMdQueryCanonicalSerializer.data(for: fallback.workout)
        for index in bounds.startIndex..<bounds.endIndex {
            let day = try await loadDay(snapshot, at: index)
            let evidenceByID = Dictionary(
                day.evidence.map { ($0.reference.evidenceID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for workout in day.workouts where workout.workoutID == workoutID {
                let evidence = authorizedEvidence(
                    ids: workout.evidenceIDs,
                    in: evidenceByID,
                    selection: sourceSelection
                )
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: workout.evidenceIDs,
                    authorizedEvidence: evidence,
                    selection: sourceSelection
                ) else { continue }
                let encoding = try HealthMdQueryCanonicalSerializer.data(for: workout)
                if encoding.lexicographicallyPrecedes(bestEncoding) {
                    best = WorkoutCandidate(
                        workout: workout,
                        ownerDate: day.ownerDate,
                        source: day.source,
                        evidence: evidence,
                        isAuthorized: true
                    )
                    bestEncoding = encoding
                }
            }
        }
        return best
    }

    // MARK: - Sleep sessions

    private func sleepSessionListing(
        _ request: HealthMdQueryRequest,
        window: HealthMdSleepWindow?,
        includeNaps: Bool,
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        var budget = PageBudget(controls: request.page)
        var items: [HealthMdQueryItem] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations: Set<HealthMdLimitation> = [Self.medicalSafetyLimitation]
        var pageCoverage = CoverageAccumulator()
        var stopped: TraversalPosition?
        var excludedNaps = 0
        var outsideWindow = 0
        var sourceExcluded = 0
        var adjacentOwnerDates = Set<String>()
        let authorizedSleepMetricIDs = HealthMdSleepSessionQuery.authorizedSleepMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: evidenceScope.allowedMetricIDs
        )
        let physiologyMetricIDs = HealthMdSleepSessionQuery.physiologyMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: evidenceScope.allowedMetricIDs
        )

        dayLoop: while cursor.major < bounds.endIndex {
            let day = try await loadDay(snapshot, at: cursor.major)
            if !cursor.metadataDone {
                let hasValue = day.sleepSessions.contains { session in
                    (includeNaps || session.classification != .nap)
                        && sleepWindowOverlapsSession(window, session: session)
                }
                guard try pageCoverage.consider(
                    ownerDate: day.ownerDate,
                    hasValue: hasValue,
                    missingStatus: hasValue ? .available : missingStatus(for: day.status),
                    budget: &budget
                ) else {
                    stopped = cursor
                    break dayLoop
                }
                limitations.formUnion(day.limitations)
                cursor.metadataDone = true
            }

            guard cursor.minor >= 0, cursor.minor <= day.sleepSessions.count else {
                throw HealthMdQueryContractError.invalidCursor
            }
            while cursor.minor < day.sleepSessions.count {
                let rawIndex = cursor.minor
                let session = day.sleepSessions[rawIndex]
                cursor.minor += 1
                if session.classification == .nap, !includeNaps {
                    excludedNaps += 1
                    continue
                }
                guard sleepWindowOverlapsSession(window, session: session) else {
                    outsideWindow += 1
                    continue
                }

                let related = try await sleepRelatedDays(
                    snapshot: snapshot,
                    around: cursor.major
                )
                adjacentOwnerDates.formUnion(
                    related.map(\.ownerDate).filter { $0 != day.ownerDate }
                )
                let evidence = related.flatMap(\.evidence).filter {
                    evidenceIsAuthorized($0, selection: request.sources)
                }
                let sessionEvidence = evidence.filter {
                    session.evidenceIDs.contains($0.reference.evidenceID)
                }
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: session.evidenceIDs,
                    authorizedEvidence: sessionEvidence,
                    selection: request.sources
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
                    outsideWindow += 1
                    continue
                }
                let item = HealthMdQueryItem.sleepSession(result)
                guard try budget.appendItem(item) else {
                    cursor.minor = rawIndex
                    stopped = cursor
                    break dayLoop
                }
                items.append(item)
                references.formUnion(result.evidence)
                references.formUnion(result.physiology.flatMap(\.evidence))
                sources.insert(day.source)
                sources.formUnion(result.evidence.map(\.source))
                limitations.formUnion(result.limitations)
            }
            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        return HealthMdQueryResponse(
            items: items,
            packet: nil,
            coverage: pageCoverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations),
            metadata: [
                "excluded_session_count": .integer(Int64(excludedNaps + outsideWindow + sourceExcluded)),
                "excluded_nap_count": .integer(Int64(excludedNaps)),
                "window_outside_session_count": .integer(Int64(outsideWindow)),
                "source_excluded_session_count": .integer(Int64(sourceExcluded)),
                "adjacent_owner_dates_considered": .array(
                    adjacentOwnerDates.sorted().map(HealthMdJSONValue.string)
                )
            ]
        )
    }

    private func sleepWindowOverlapsSession(
        _ window: HealthMdSleepWindow?,
        session: HealthMdContextSleepSession
    ) -> Bool {
        guard let window else { return true }
        let start = session.start.addingTimeInterval(window.startOffsetSeconds)
        return start < session.end && start.addingTimeInterval(window.durationSeconds) > session.start
    }

    /// The current owner day plus at most one manifest neighbor on either side.
    /// This is enough to cover midnight-spanning session physiology while keeping
    /// encrypted-store execution bounded to three decrypted day values at a time.
    private func sleepRelatedDays(
        snapshot: HealthContextStoreSnapshot,
        around index: Int,
        radius: Int = 1
    ) async throws -> [HealthMdCompactContextDay] {
        let lower = max(0, index - radius)
        let upper = min(snapshot.entries.count, index + radius + 1)
        let centerOwnerDate = snapshot.entries[index].ownerDate
        let allowedOwnerDates = try ownerDates(
            centeredOn: centerOwnerDate,
            radius: radius
        )
        var result: [HealthMdCompactContextDay] = []
        for dayIndex in lower..<upper
        where allowedOwnerDates.contains(snapshot.entries[dayIndex].ownerDate) {
            result.append(try await loadDay(snapshot, at: dayIndex))
        }
        return result
    }

    private func ownerDates(centeredOn value: String, radius: Int) throws -> Set<String> {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let center = formatter.date(from: value),
              formatter.string(from: center) == value else {
            throw HealthMdQueryContractError.invalidDateRange
        }
        return try Set((-radius...radius).map { offset in
            guard let date = formatter.calendar.date(byAdding: .day, value: offset, to: center)
            else { throw HealthMdQueryContractError.invalidDateRange }
            return formatter.string(from: date)
        })
    }

    // MARK: - Workout/sleep alignment

    private func workoutSleepAlignment(
        _ request: HealthMdQueryRequest,
        window: HealthMdSleepWindow?,
        workoutActivity: String?,
        includeNaps: Bool,
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        var budget = PageBudget(controls: request.page)
        var items: [HealthMdQueryItem] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var pageCoverage = CoverageAccumulator()
        var stopped: TraversalPosition?
        var activityExcluded = 0
        var sourceExcluded = 0
        var complete = 0
        var partial = 0
        var unavailable = 0
        var physiologySamples = 0
        let normalizedActivity = workoutActivity?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let authorizedSleepMetricIDs = HealthMdSleepSessionQuery.authorizedSleepMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: evidenceScope.allowedMetricIDs
        )
        let physiologyMetricIDs = HealthMdSleepSessionQuery.physiologyMetricIDs(
            selection: request.metrics,
            allowedMetricIDs: evidenceScope.allowedMetricIDs
        ).subtracting(["workouts"])
        let maximumDistance: TimeInterval = 36 * 3_600

        dayLoop: while cursor.major < bounds.endIndex {
            let day = try await loadDay(snapshot, at: cursor.major)
            if !cursor.metadataDone {
                let hasValue = day.workouts.contains {
                    normalizedActivity == nil || $0.activity.lowercased() == normalizedActivity
                }
                guard try pageCoverage.consider(
                    ownerDate: day.ownerDate,
                    hasValue: hasValue,
                    missingStatus: hasValue ? .available : missingStatus(for: day.status),
                    budget: &budget
                ) else {
                    stopped = cursor
                    break dayLoop
                }
                limitations.formUnion(day.limitations)
                cursor.metadataDone = true
            }

            guard cursor.minor >= 0, cursor.minor <= day.workouts.count else {
                throw HealthMdQueryContractError.invalidCursor
            }
            while cursor.minor < day.workouts.count {
                let rawIndex = cursor.minor
                cursor.minor += 1
                let raw = try await workoutCandidate(
                    snapshot: snapshot,
                    dayIndex: cursor.major,
                    workoutIndex: rawIndex,
                    sourceSelection: request.sources
                )
                guard let raw else { continue }
                guard normalizedActivity == nil
                        || raw.workout.activity.lowercased() == normalizedActivity else {
                    activityExcluded += 1
                    continue
                }
                guard raw.isAuthorized else {
                    sourceExcluded += 1
                    continue
                }
                guard try await isFirstWorkoutOccurrence(
                    raw.workout.workoutID,
                    dayIndex: cursor.major,
                    workoutIndex: rawIndex,
                    bounds: bounds,
                    snapshot: snapshot
                ) else { continue }
                let canonical = try await canonicalWorkout(
                    raw.workout.workoutID,
                    fallback: raw,
                    bounds: bounds,
                    snapshot: snapshot,
                    sourceSelection: request.sources
                )
                let related = try await sleepRelatedDays(
                    snapshot: snapshot,
                    around: cursor.major,
                    radius: 2
                )
                let evidence = related.flatMap(\.evidence).filter {
                    evidenceIsAuthorized($0, selection: request.sources)
                }
                let sleepCandidates = related.flatMap { relatedDay in
                    relatedDay.sleepSessions.compactMap { session
                        -> (session: HealthMdContextSleepSession, ownerDay: HealthMdCompactContextDay)? in
                        if session.classification == .nap, !includeNaps { return nil }
                        let sessionEvidence = evidence.filter {
                            session.evidenceIDs.contains($0.reference.evidenceID)
                        }
                        guard evidencePassesSourceRestriction(
                            originalEvidenceIDs: session.evidenceIDs,
                            authorizedEvidence: sessionEvidence,
                            selection: request.sources
                        ) else { return nil }
                        return (session, relatedDay)
                    }
                }
                let preceding = sleepCandidates
                    .filter {
                        $0.session.end <= canonical.workout.start
                            && canonical.workout.start.timeIntervalSince($0.session.end) <= maximumDistance
                    }
                    .max {
                        if $0.session.end != $1.session.end {
                            return $0.session.end < $1.session.end
                        }
                        return $0.session.sessionID < $1.session.sessionID
                    }
                let following = sleepCandidates
                    .filter {
                        $0.session.start >= canonical.workout.end
                            && $0.session.start.timeIntervalSince(canonical.workout.end) <= maximumDistance
                    }
                    .min {
                        if $0.session.start != $1.session.start {
                            return $0.session.start < $1.session.start
                        }
                        return $0.session.sessionID < $1.session.sessionID
                    }
                let alignment = try HealthMdSleepSessionQuery.alignment(
                    workout: canonical.workout,
                    preceding: preceding,
                    following: following,
                    relatedDays: related,
                    window: window,
                    authorizedSleepMetricIDs: authorizedSleepMetricIDs,
                    physiologyMetricIDs: physiologyMetricIDs,
                    authorizedEvidence: evidence + canonical.evidence
                )
                let item = HealthMdQueryItem.workoutSleepAlignment(alignment)
                guard try budget.appendItem(item) else {
                    cursor.minor = rawIndex
                    stopped = cursor
                    break dayLoop
                }
                items.append(item)
                switch alignment.status {
                case .complete: complete += 1
                case .partial: partial += 1
                case .unavailable: unavailable += 1
                }
                physiologySamples += alignment.physiologySampleCount
                references.formUnion(alignment.evidence)
                sources.insert(canonical.source)
                sources.formUnion(alignment.evidence.map(\.source))
                limitations.formUnion(alignment.limitations)
            }
            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        return HealthMdQueryResponse(
            items: items,
            packet: nil,
            coverage: pageCoverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations),
            metadata: [
                "aligned_workout_count": .integer(Int64(items.count)),
                "complete_alignment_count": .integer(Int64(complete)),
                "partial_alignment_count": .integer(Int64(partial)),
                "unavailable_alignment_count": .integer(Int64(unavailable)),
                "activity_excluded_workout_count": .integer(Int64(activityExcluded)),
                "source_excluded_workout_count": .integer(Int64(sourceExcluded)),
                "physiology_sample_count": .integer(Int64(physiologySamples))
            ]
        )
    }

    // MARK: - Coverage

    private func coverageListing(
        _ request: HealthMdQueryRequest,
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        let requestedMetricIDs: Set<String>
        switch request.metrics {
        case .explicit(let ids): requestedMetricIDs = Set(ids)
        case .allAvailable: requestedMetricIDs = evidenceScope.allowedMetricIDs
        }
        let scopeCompletion = try await requestedScopeCompletion(
            dates: request.dates,
            metricIDs: requestedMetricIDs,
            sources: request.sources,
            changedSince: nil
        )
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        guard cursor.minor == 0 else { throw HealthMdQueryContractError.invalidCursor }
        var budget = PageBudget(controls: request.page)
        var pageCoverage = CoverageAccumulator()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var stopped: TraversalPosition?

        while cursor.major < bounds.endIndex {
            let day = try await loadDay(snapshot, at: cursor.major)
            let evidenceByID = Dictionary(
                day.evidence.map { ($0.reference.evidenceID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let summary = scopeCoverageDaySummary(
                day,
                request: request,
                evidenceByID: evidenceByID
            )
            guard try pageCoverage.consider(
                ownerDate: day.ownerDate,
                hasValue: summary.hasValue,
                missingStatus: summary.missingStatus,
                budget: &budget
            ) else {
                stopped = cursor
                break
            }
            sources.insert(day.source)
            limitations.formUnion(day.limitations)
            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        return HealthMdQueryResponse(
            items: [],
            packet: nil,
            coverage: pageCoverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            sources: sortedSources(sources),
            evidence: [],
            nextCursor: next,
            limitations: sortedLimitations(limitations),
            metadata: scopeCompletion.map {
                [
                    "requested_scope_status": .string($0.status.rawValue),
                    "days_considered": .integer(Int64($0.daysConsidered)),
                    "metric_days_considered": .integer(Int64($0.metricDaysConsidered)),
                    "complete_metric_days": .integer(Int64($0.completeMetricDays)),
                    "incomplete_metric_days": .integer(Int64($0.incompleteMetricDays))
                ]
            }
        )
    }

    // MARK: - Period comparisons

    private struct ComparisonBuild {
        let item: HealthMdQueryItem
        let sources: Set<HealthMdSourceDescriptor>
        let references: Set<HealthMdEvidenceReference>
        let limitations: Set<HealthMdLimitation>
    }

    private func periodComparisons(
        _ request: HealthMdQueryRequest,
        first: HealthMdDateRange,
        second: HealthMdDateRange,
        descriptors: [HealthMdAggregationDescriptor],
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        try validate(first)
        try validate(second)
        let combined = HealthMdDateRange(
            startDate: min(first.startDate, second.startDate),
            endDate: max(first.endDate, second.endDate)
        )
        let bounds = try selectionBounds(.exact(combined), snapshot: snapshot)
        let normalized = normalizedDescriptors(descriptors, metrics: request.metrics)
        guard position.minor == 0, !position.metadataDone,
              position.major >= 0, position.major <= normalized.count else {
            throw HealthMdQueryContractError.invalidCursor
        }
        var descriptorIndex = position.major
        var budget = PageBudget(controls: request.page)
        var items: [HealthMdQueryItem] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var stopped: TraversalPosition?

        while descriptorIndex < normalized.count {
            let built = try await comparison(
                descriptor: normalized[descriptorIndex],
                first: first,
                second: second,
                bounds: bounds,
                snapshot: snapshot,
                request: request
            )
            guard try budget.appendItem(built.item) else {
                stopped = TraversalPosition(major: descriptorIndex, minor: 0, metadataDone: false)
                break
            }
            items.append(built.item)
            references.formUnion(built.references)
            sources.formUnion(built.sources)
            limitations.formUnion(built.limitations)
            descriptorIndex += 1
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        let responseCoverage: HealthMdCoverage
        if case .comparison(let comparison) = items.first {
            responseCoverage = comparison.coverage
        } else {
            responseCoverage = CoverageAccumulator().makeCoverage(
                requestedRange: combined,
                availableRange: bounds.availableRange
            )
        }
        return HealthMdQueryResponse(
            items: items,
            packet: nil,
            coverage: responseCoverage,
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations)
        )
    }

    private func comparison(
        descriptor: HealthMdAggregationDescriptor,
        first: HealthMdDateRange,
        second: HealthMdDateRange,
        bounds: SelectionBounds,
        snapshot: HealthContextStoreSnapshot,
        request: HealthMdQueryRequest
    ) async throws -> ComparisonBuild {
        var firstState = AggregationState(descriptor: descriptor)
        var secondState = AggregationState(descriptor: descriptor)
        var coverage = ExactCoverageAccumulator(maxBytes: request.page.maxBytes)
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var provenanceBytes = 0

        for index in bounds.startIndex..<bounds.endIndex {
            let day = try await loadDay(snapshot, at: index)
            let evidenceByID = Dictionary(
                day.evidence.map { ($0.reference.evidenceID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var seen = Set<String>()
            var dayHasValue = false
            var unavailableStatuses = Set<HealthMdAvailabilityStatus>()
            for metric in day.metrics where metric.metricID == descriptor.metricID {
                guard seen.insert(metric.observationID).inserted else { continue }
                let evidence = authorizedEvidence(
                    ids: metric.evidenceIDs,
                    in: evidenceByID,
                    selection: request.sources
                )
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: metric.evidenceIDs,
                    authorizedEvidence: evidence,
                    selection: request.sources
                ) else { continue }
                guard metric.status == .available, let value = metric.value else {
                    unavailableStatuses.insert(metric.status == .available ? .completeEmpty : metric.status)
                    continue
                }
                dayHasValue = true
                if day.ownerDate >= first.startDate, day.ownerDate <= first.endDate {
                    try firstState.consume(value, ownerDate: day.ownerDate, observationID: metric.observationID)
                }
                if day.ownerDate >= second.startDate, day.ownerDate <= second.endDate {
                    try secondState.consume(value, ownerDate: day.ownerDate, observationID: metric.observationID)
                }
                sources.insert(day.source)
                for item in evidence {
                    if references.insert(item.reference).inserted {
                        provenanceBytes += try HealthMdQueryCanonicalSerializer.data(for: item.reference).count
                    }
                }
                limitations.formUnion(metric.limitations)
                if provenanceBytes > request.page.maxBytes {
                    throw HealthMdQueryContractError.singleItemExceedsPageBytes
                }
            }
            let status: HealthMdAvailabilityStatus
            if dayHasValue { status = .available }
            else if unavailableStatuses.count == 1 { status = unavailableStatuses.first! }
            else if unavailableStatuses.isEmpty { status = missingStatus(for: day.status) }
            else { status = .partial }
            try coverage.consider(ownerDate: day.ownerDate, hasValue: dayHasValue, missingStatus: status)
            limitations.formUnion(day.limitations)
        }

        let firstValue = try firstState.finish()
        let secondValue = try secondState.finish()
        let firstNumber = firstValue?.finiteNumericValue
        let secondNumber = secondValue?.finiteNumericValue
        let direction: HealthMdComparisonDirection
        if let firstNumber, let secondNumber {
            direction = secondNumber == firstNumber ? .unchanged : (secondNumber > firstNumber ? .increased : .decreased)
        } else {
            direction = .notComparable
        }
        var percentChange: Double?
        if let firstNumber, let secondNumber {
            if firstNumber == 0 {
                limitations.insert(.init(
                    code: "zero_baseline",
                    message: "Percent change is unavailable because the first period value is zero."
                ))
            } else {
                percentChange = ((secondNumber - firstNumber) / abs(firstNumber)) * 100
            }
        }
        let absoluteChange = try difference(first: firstValue, second: secondValue)
        let result = HealthMdPeriodComparison(
            metricID: descriptor.metricID,
            aggregation: descriptor,
            firstRange: first,
            secondRange: second,
            firstValue: firstValue,
            secondValue: secondValue,
            absoluteChange: absoluteChange,
            percentChange: percentChange,
            direction: direction,
            coverage: coverage.makeCoverage(
                requestedRange: bounds.requestedRange,
                availableRange: bounds.availableRange
            ),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            limitations: sortedLimitations(limitations)
        )
        let item = HealthMdQueryItem.comparison(result)
        guard try HealthMdQueryCanonicalSerializer.data(for: item).count <= request.page.maxBytes else {
            throw HealthMdQueryContractError.singleItemExceedsPageBytes
        }
        return ComparisonBuild(
            item: item,
            sources: sources,
            references: references,
            limitations: limitations
        )
    }

    // MARK: - Evidence packets

    private func packet(
        _ request: HealthMdQueryRequest,
        kind: HealthMdPacketKind,
        detailIDs: [String],
        snapshot: HealthContextStoreSnapshot,
        position: TraversalPosition,
        fingerprint: String
    ) async throws -> HealthMdQueryResponse {
        let bounds = try selectionBounds(request.dates, snapshot: snapshot)
        let details = Array(Set(detailIDs)).sorted()
        var cursor = try normalizedDayPosition(position, bounds: bounds)
        var budget = PageBudget(controls: request.page)
        var facts: [HealthMdPacketFact] = []
        var references = Set<HealthMdEvidenceReference>()
        var sources = Set<HealthMdSourceDescriptor>()
        var limitations = Set<HealthMdLimitation>()
        var pageCoverage = CoverageAccumulator()
        var stopped: TraversalPosition?

        dayLoop: while cursor.major < bounds.endIndex {
            let day = try await loadDay(snapshot, at: cursor.major)
            let evidenceByID = Dictionary(
                day.evidence.map { ($0.reference.evidenceID, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if !cursor.metadataDone {
                let hasValue = dayHasPacketFact(
                    day,
                    kind: kind,
                    details: details,
                    request: request,
                    evidenceByID: evidenceByID
                )
                guard try pageCoverage.consider(
                    ownerDate: day.ownerDate,
                    hasValue: hasValue,
                    missingStatus: hasValue ? .available : missingStatus(for: day.status),
                    budget: &budget
                ) else {
                    stopped = cursor
                    break dayLoop
                }
                limitations.formUnion(day.limitations)
                cursor.metadataDone = true
            }

            var ordinal = 0
            for metric in day.metrics {
                guard metricIsSelected(metric.metricID, selection: request.metrics),
                      metric.status == .available,
                      let value = metric.value else { continue }
                let evidence = authorizedEvidence(
                    ids: metric.evidenceIDs,
                    in: evidenceByID,
                    selection: request.sources
                )
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: metric.evidenceIDs,
                    authorizedEvidence: evidence,
                    selection: request.sources
                ) else { continue }
                defer { ordinal += 1 }
                guard ordinal >= cursor.minor else { continue }
                let fact = HealthMdPacketFact(
                    factID: "metric:\(day.ownerDate):\(metric.metricID):\(metric.observationID)",
                    label: metric.displayName,
                    ownerDate: day.ownerDate,
                    value: value,
                    evidence: evidence.map(\.reference)
                )
                guard try budget.appendItem(fact) else {
                    stopped = TraversalPosition(major: cursor.major, minor: ordinal, metadataDone: true)
                    break dayLoop
                }
                facts.append(fact)
                references.formUnion(fact.evidence)
                sources.insert(day.source)
                sources.formUnion(fact.evidence.map(\.source))
            }
            if kind == .training, evidenceScope.allowsWorkouts {
                for workout in day.workouts {
                    let evidence = authorizedEvidence(
                        ids: workout.evidenceIDs,
                        in: evidenceByID,
                        selection: request.sources
                    )
                    guard evidencePassesSourceRestriction(
                        originalEvidenceIDs: workout.evidenceIDs,
                        authorizedEvidence: evidence,
                        selection: request.sources
                    ) else { continue }
                    for detailID in details {
                        guard let value = workout.details[detailID] else { continue }
                        defer { ordinal += 1 }
                        guard ordinal >= cursor.minor else { continue }
                        let fact = HealthMdPacketFact(
                            factID: "workout:\(workout.workoutID):\(detailID)",
                            label: "\(workout.activity) \(detailID)",
                            ownerDate: day.ownerDate,
                            value: value,
                            evidence: evidence.map(\.reference)
                        )
                        guard try budget.appendItem(fact) else {
                            stopped = TraversalPosition(major: cursor.major, minor: ordinal, metadataDone: true)
                            break dayLoop
                        }
                        facts.append(fact)
                        references.formUnion(fact.evidence)
                        sources.insert(day.source)
                        sources.formUnion(fact.evidence.map(\.source))
                    }
                }
            }
            cursor = TraversalPosition(major: cursor.major + 1, minor: 0, metadataDone: false)
        }

        let next = try await nextCursor(
            stopped,
            fingerprint: fingerprint,
            datasetRevision: snapshot.revision
        )
        limitations.insert(Self.medicalSafetyLimitation)
        if next != nil {
            limitations.insert(.init(
                code: "packet_continues",
                message: "Additional factual packet items are available through the next cursor."
            ))
        }
        let packetCoverage = pageCoverage.makeCoverage(
            requestedRange: bounds.requestedRange,
            availableRange: bounds.availableRange
        )
        let packet = try HealthMdQueryCanonicalSerializer.makePacket(
            kind: kind,
            range: bounds.requestedRange,
            facts: facts,
            coverage: packetCoverage,
            sources: Array(sources),
            limitations: Array(limitations),
            metadata: .init(generatedAt: now())
        )
        return HealthMdQueryResponse(
            items: [],
            packet: packet,
            coverage: packetCoverage,
            sources: sortedSources(sources),
            evidence: references.sorted { $0.evidenceID < $1.evidenceID },
            nextCursor: next,
            limitations: sortedLimitations(limitations)
        )
    }

    // MARK: - Authorization and filtering

    private func validate(
        _ request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel
    ) throws {
        guard request.schema == HealthMdQuerySchemas.queryRequest,
              request.schemaVersion == HealthMdQuerySchemas.version else {
            throw HealthMdQueryContractError.unsupportedOperation
        }
        guard request.page.maxItems > 0,
              request.page.maxItems <= HealthMdPageControls.maximumItems,
              request.page.maxBytes > 0,
              request.page.maxBytes <= HealthMdPageControls.maximumBytes else {
            throw HealthMdQueryContractError.invalidPageControls
        }
        try validate(request.dates)

        if case .explicit(let metricIDs) = request.metrics {
            let denied = Set(metricIDs).subtracting(evidenceScope.allowedMetricIDs)
            guard denied.isEmpty else {
                throw HealthMdQueryContractError.scopeViolation(
                    "metric_ids:\(denied.sorted().joined(separator: ","))"
                )
            }
        }
        if case .explicit(let sourceIDs, let providerIDs) = request.sources {
            if let allowed = evidenceScope.allowedSourceIDs {
                let denied = Set(sourceIDs).subtracting(allowed)
                guard denied.isEmpty else {
                    throw HealthMdQueryContractError.scopeViolation(
                        "source_ids:\(denied.sorted().joined(separator: ","))"
                    )
                }
            }
            if let allowed = evidenceScope.allowedProviderIDs {
                let denied = Set(providerIDs).subtracting(allowed)
                guard denied.isEmpty else {
                    throw HealthMdQueryContractError.scopeViolation(
                        "provider_ids:\(denied.sorted().joined(separator: ","))"
                    )
                }
            }
        }

        switch request.operation {
        case .workoutListing:
            guard evidenceScope.allowsWorkouts else {
                throw HealthMdQueryContractError.scopeViolation("workouts")
            }
        case .sleepSessionListing(let window, _):
            try HealthMdSleepSessionQuery.validate(window: window)
            guard HealthMdSleepSessionQuery.hasSleepAuthorization(
                selection: request.metrics,
                allowedMetricIDs: evidenceScope.allowedMetricIDs
            ) else {
                throw HealthMdQueryContractError.scopeViolation("sleep_sessions")
            }
        case .workoutSleepAlignment(let window, let activity, _):
            try HealthMdSleepSessionQuery.validate(window: window)
            guard evidenceScope.allowsWorkouts else {
                throw HealthMdQueryContractError.scopeViolation("workouts")
            }
            guard HealthMdSleepSessionQuery.hasSleepAuthorization(
                selection: request.metrics,
                allowedMetricIDs: evidenceScope.allowedMetricIDs
            ) else {
                throw HealthMdQueryContractError.scopeViolation("sleep_sessions")
            }
            if let activity, activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw HealthMdQueryContractError.unsupportedOperation
            }
        case .sourceRecordListing:
            guard evidenceScope.allowsEvidenceValues else {
                throw HealthMdQueryContractError.scopeViolation("evidence_values")
            }
            guard detailLevel == .lossless else {
                throw HealthMdQueryContractError.scopeViolation("record_detail_level")
            }
        case .derivePacket(_, let detailIDs):
            let denied = Set(detailIDs).subtracting(evidenceScope.allowedDetailIDs)
            guard denied.isEmpty else {
                throw HealthMdQueryContractError.scopeViolation(
                    "detail_ids:\(denied.sorted().joined(separator: ","))"
                )
            }
        case .periodComparison(let first, let second, let descriptors):
            try validate(first)
            try validate(second)
            let denied = Set(descriptors.map(\.metricID)).subtracting(evidenceScope.allowedMetricIDs)
            guard denied.isEmpty else {
                throw HealthMdQueryContractError.scopeViolation(
                    "metric_ids:\(denied.sorted().joined(separator: ","))"
                )
            }
        case .metricSeries, .coverage:
            break
        }
    }

    private func metricIsSelected(_ metricID: String, selection: HealthMdMetricSelection) -> Bool {
        guard evidenceScope.allowedMetricIDs.contains(metricID) else { return false }
        switch selection {
        case .allAvailable: return true
        case .explicit(let ids): return ids.contains(metricID)
        }
    }

    private func evidenceIsSelected(
        _ evidence: HealthMdContextEvidence,
        linkedMetrics: [String: Set<String>],
        request: HealthMdQueryRequest
    ) -> Bool {
        guard evidenceIsAuthorized(evidence, selection: request.sources) else { return false }
        let associated = Set(evidence.metricIDs)
            .union(linkedMetrics[evidence.reference.evidenceID] ?? [])
        switch request.metrics {
        case .allAvailable:
            return associated.isEmpty || !associated.isDisjoint(with: evidenceScope.allowedMetricIDs)
        case .explicit(let metricIDs):
            return !associated.isDisjoint(with: Set(metricIDs))
        }
    }

    private func evidenceIsAuthorized(
        _ evidence: HealthMdContextEvidence,
        selection: HealthMdSourceSelection
    ) -> Bool {
        let reference = evidence.reference
        if let providerID = reference.providerID {
            if let allowed = evidenceScope.allowedProviderIDs,
               !allowed.contains(providerID) { return false }
        } else if let allowed = evidenceScope.allowedSourceIDs,
                  !allowed.contains(reference.sourceID) { return false }
        switch selection {
        case .allAvailable:
            return true
        case .explicit(let sourceIDs, let providerIDs):
            return sourceIDs.contains(reference.sourceID)
                || (reference.providerID == nil && sourceIDs.contains("apple_health"))
                || reference.providerID.map { providerIDs.contains($0) } == true
        }
    }

    private func authorizedEvidence(
        ids: [String],
        in evidenceByID: [String: HealthMdContextEvidence],
        selection: HealthMdSourceSelection
    ) -> [HealthMdContextEvidence] {
        ids.compactMap { evidenceByID[$0] }
            .filter { evidenceIsAuthorized($0, selection: selection) }
            .sorted { $0.reference.evidenceID < $1.reference.evidenceID }
    }

    private func evidencePassesSourceRestriction(
        originalEvidenceIDs: [String],
        authorizedEvidence: [HealthMdContextEvidence],
        selection: HealthMdSourceSelection
    ) -> Bool {
        let scopeRestrictsSources = evidenceScope.allowedSourceIDs != nil
            || evidenceScope.allowedProviderIDs != nil
        let requestRestrictsSources: Bool
        switch selection {
        case .allAvailable: requestRestrictsSources = false
        case .explicit: requestRestrictsSources = true
        }
        guard scopeRestrictsSources || requestRestrictsSources else { return true }
        return !originalEvidenceIDs.isEmpty && !authorizedEvidence.isEmpty
    }

    private func evidenceMetricLinks(_ day: HealthMdCompactContextDay) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for metric in day.metrics {
            for evidenceID in metric.evidenceIDs {
                result[evidenceID, default: []].insert(metric.metricID)
            }
        }
        return result
    }

    // MARK: - Day summaries and packet facts

    private func metricDaySummary(
        _ day: HealthMdCompactContextDay,
        request: HealthMdQueryRequest,
        evidenceByID: [String: HealthMdContextEvidence]
    ) -> (hasValue: Bool, missingStatus: HealthMdAvailabilityStatus) {
        var statuses = Set<HealthMdAvailabilityStatus>()
        var hasValue = false
        for metric in day.metrics where metricIsSelected(metric.metricID, selection: request.metrics) {
            let evidence = authorizedEvidence(
                ids: metric.evidenceIDs,
                in: evidenceByID,
                selection: request.sources
            )
            guard evidencePassesSourceRestriction(
                originalEvidenceIDs: metric.evidenceIDs,
                authorizedEvidence: evidence,
                selection: request.sources
            ) else { continue }
            if metric.status == .available, metric.value != nil { hasValue = true }
            else { statuses.insert(metric.status == .available ? .completeEmpty : metric.status) }
        }
        if hasValue { return (true, .available) }
        if statuses.count == 1 { return (false, statuses.first!) }
        if statuses.count > 1 { return (false, .partial) }
        return (false, missingStatus(for: day.status))
    }

    private func scopeCoverageDaySummary(
        _ day: HealthMdCompactContextDay,
        request: HealthMdQueryRequest,
        evidenceByID: [String: HealthMdContextEvidence]
    ) -> (hasValue: Bool, missingStatus: HealthMdAvailabilityStatus) {
        let requestedMetricIDs: Set<String>
        switch request.metrics {
        case .explicit(let ids): requestedMetricIDs = Set(ids)
        case .allAvailable: requestedMetricIDs = evidenceScope.allowedMetricIDs
        }
        guard !requestedMetricIDs.isEmpty else {
            return (false, .notRequested)
        }
        var statuses: [HealthMdAvailabilityStatus] = []
        var hasValue = false
        for metricID in requestedMetricIDs.sorted() {
            if metricID == "workouts" {
                guard evidenceScope.allowsWorkouts else {
                    statuses.append(.redacted)
                    continue
                }
                if !day.workouts.isEmpty {
                    hasValue = true
                    statuses.append(.available)
                } else {
                    statuses.append(
                        day.status == .available || day.status == .completeEmpty
                            ? .completeEmpty : day.status
                    )
                }
                continue
            }
            let metrics = day.metrics.filter { $0.metricID == metricID }
            guard !metrics.isEmpty else {
                statuses.append(.notSynchronized)
                continue
            }
            var metricStatuses: [HealthMdAvailabilityStatus] = []
            for metric in metrics {
                let evidence = authorizedEvidence(
                    ids: metric.evidenceIDs,
                    in: evidenceByID,
                    selection: request.sources
                )
                guard evidencePassesSourceRestriction(
                    originalEvidenceIDs: metric.evidenceIDs,
                    authorizedEvidence: evidence,
                    selection: request.sources
                ) else {
                    metricStatuses.append(.redacted)
                    continue
                }
                if metric.status == .available, metric.value != nil {
                    hasValue = true
                    metricStatuses.append(.available)
                } else {
                    metricStatuses.append(
                        metric.status == .available ? .completeEmpty : metric.status
                    )
                }
            }
            if metricStatuses.contains(.available) { statuses.append(.available) }
            else if Set(metricStatuses).count == 1 { statuses.append(metricStatuses[0]) }
            else { statuses.append(.partial) }
        }
        let incomplete = statuses.filter { $0 != .available && $0 != .completeEmpty }
        if !incomplete.isEmpty {
            let completeCount = statuses.count - incomplete.count
            let unique = Set(incomplete)
            return (
                false,
                completeCount > 0 || unique.count > 1 ? .partial : unique.first!
            )
        }
        return (hasValue, hasValue ? .available : .completeEmpty)
    }

    private func dayHasPacketFact(
        _ day: HealthMdCompactContextDay,
        kind: HealthMdPacketKind,
        details: [String],
        request: HealthMdQueryRequest,
        evidenceByID: [String: HealthMdContextEvidence]
    ) -> Bool {
        for metric in day.metrics where metricIsSelected(metric.metricID, selection: request.metrics) {
            guard metric.status == .available, metric.value != nil else { continue }
            let evidence = authorizedEvidence(
                ids: metric.evidenceIDs,
                in: evidenceByID,
                selection: request.sources
            )
            if evidencePassesSourceRestriction(
                originalEvidenceIDs: metric.evidenceIDs,
                authorizedEvidence: evidence,
                selection: request.sources
            ) { return true }
        }
        guard kind == .training, evidenceScope.allowsWorkouts else { return false }
        return day.workouts.contains { workout in
            details.contains { workout.details[$0] != nil }
        }
    }

    private func missingStatus(for dayStatus: HealthMdAvailabilityStatus) -> HealthMdAvailabilityStatus {
        dayStatus == .available ? .completeEmpty : dayStatus
    }

    // MARK: - Manifest selection

    private struct SelectionBounds {
        let startIndex: Int
        let endIndex: Int
        let requestedRange: HealthMdDateRange?
        let availableRange: HealthMdDateRange?
    }

    private func selectionBounds(
        _ selection: HealthMdDateSelection,
        snapshot: HealthContextStoreSnapshot
    ) throws -> SelectionBounds {
        try validate(selection)
        let availableRange = snapshot.entries.first.flatMap { first in
            snapshot.entries.last.map {
                HealthMdDateRange(startDate: first.ownerDate, endDate: $0.ownerDate)
            }
        }
        switch selection {
        case .allAvailable:
            return SelectionBounds(
                startIndex: 0,
                endIndex: snapshot.entries.count,
                requestedRange: availableRange,
                availableRange: availableRange
            )
        case .exact(let range):
            let start = snapshot.entries.firstIndex { $0.ownerDate >= range.startDate }
                ?? snapshot.entries.count
            let end = snapshot.entries.firstIndex { $0.ownerDate > range.endDate }
                ?? snapshot.entries.count
            return SelectionBounds(
                startIndex: min(start, end),
                endIndex: end,
                requestedRange: range,
                availableRange: availableRange
            )
        }
    }

    private func normalizedDayPosition(
        _ position: TraversalPosition,
        bounds: SelectionBounds
    ) throws -> TraversalPosition {
        if position == .initial {
            return TraversalPosition(major: bounds.startIndex, minor: 0, metadataDone: false)
        }
        guard position.major >= bounds.startIndex,
              position.major <= bounds.endIndex,
              position.minor >= 0 else {
            throw HealthMdQueryContractError.invalidCursor
        }
        return position
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

    private func loadDay(
        _ snapshot: HealthContextStoreSnapshot,
        at index: Int
    ) async throws -> HealthMdCompactContextDay {
        let day = try await store.loadDay(from: snapshot, at: index)
        didLoadDay(day.ownerDate)
        return day
    }

    // MARK: - Paging and opaque cursors

    private struct TraversalPosition: Codable, Equatable {
        let major: Int
        var minor: Int
        var metadataDone: Bool

        static let initial = TraversalPosition(major: 0, minor: 0, metadataDone: false)

        enum CodingKeys: String, CodingKey {
            case major, minor
            case metadataDone = "metadata_done"
        }
    }

    private struct CursorPayload: Codable {
        let version: Int
        let requestFingerprint: String
        let datasetRevision: String
        let position: TraversalPosition

        enum CodingKeys: String, CodingKey {
            case version
            case requestFingerprint = "request_fingerprint"
            case datasetRevision = "dataset_revision"
            case position
        }
    }

    private struct FingerprintMaterial: Encodable {
        let schema: String
        let schemaVersion: Int
        let metrics: HealthMdMetricSelection
        let sources: HealthMdSourceSelection
        let dates: HealthMdDateSelection
        let operation: HealthMdQueryOperation
        let maxItems: Int
        let maxBytes: Int
        let detailLevel: HealthMdQueryDetailLevel
        let allowedMetricIDs: [String]
        let allowedDetailIDs: [String]
        let allowedSourceIDs: [String]?
        let allowedProviderIDs: [String]?
        let allowsWorkouts: Bool
        let allowsEvidenceValues: Bool

        enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
            case metrics, sources, dates, operation
            case maxItems = "max_items"
            case maxBytes = "max_bytes"
            case detailLevel = "detail_level"
            case allowedMetricIDs = "allowed_metric_ids"
            case allowedDetailIDs = "allowed_detail_ids"
            case allowedSourceIDs = "allowed_source_ids"
            case allowedProviderIDs = "allowed_provider_ids"
            case allowsWorkouts = "allows_workouts"
            case allowsEvidenceValues = "allows_evidence_values"
        }
    }

    private func requestFingerprint(
        _ request: HealthMdQueryRequest,
        detailLevel: HealthMdQueryDetailLevel
    ) throws -> String {
        try HealthMdQueryCanonicalSerializer.sha256(of: FingerprintMaterial(
            schema: request.schema,
            schemaVersion: request.schemaVersion,
            metrics: request.metrics,
            sources: request.sources,
            dates: request.dates,
            operation: request.operation,
            maxItems: request.page.maxItems,
            maxBytes: request.page.maxBytes,
            detailLevel: detailLevel,
            allowedMetricIDs: evidenceScope.allowedMetricIDs.sorted(),
            allowedDetailIDs: evidenceScope.allowedDetailIDs.sorted(),
            allowedSourceIDs: evidenceScope.allowedSourceIDs?.sorted(),
            allowedProviderIDs: evidenceScope.allowedProviderIDs?.sorted(),
            allowsWorkouts: evidenceScope.allowsWorkouts,
            allowsEvidenceValues: evidenceScope.allowsEvidenceValues
        ))
    }

    private func cursorPosition(
        _ cursor: String?,
        fingerprint: String,
        datasetRevision: String
    ) async throws -> TraversalPosition {
        guard let cursor else { return .initial }
        guard let combined = decodeBase64URL(cursor) else {
            throw HealthMdQueryContractError.invalidCursor
        }
        let keyData: Data
        do {
            keyData = try await store.cursorAuthenticationKeyData()
        } catch {
            throw HealthMdQueryContractError.invalidCursor
        }
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            plaintext = try AES.GCM.open(
                box,
                using: SymmetricKey(data: keyData),
                authenticating: Self.cursorAAD
            )
        } catch {
            throw HealthMdQueryContractError.invalidCursor
        }
        let payload: CursorPayload
        do {
            payload = try HealthMdQueryCanonicalSerializer.decode(CursorPayload.self, from: plaintext)
        } catch {
            throw HealthMdQueryContractError.invalidCursor
        }
        guard payload.version == 1 else { throw HealthMdQueryContractError.invalidCursor }
        guard payload.requestFingerprint == fingerprint else {
            throw HealthMdQueryContractError.cursorDoesNotMatchQuery
        }
        guard payload.datasetRevision == datasetRevision else {
            throw HealthMdQueryContractError.staleCursor
        }
        return payload.position
    }

    private func nextCursor(
        _ position: TraversalPosition?,
        fingerprint: String,
        datasetRevision: String
    ) async throws -> String? {
        guard let position else { return nil }
        let payload = CursorPayload(
            version: 1,
            requestFingerprint: fingerprint,
            datasetRevision: datasetRevision,
            position: position
        )
        let keyData = try await store.cursorAuthenticationKeyData()
        let box = try AES.GCM.seal(
            HealthMdQueryCanonicalSerializer.data(for: payload),
            using: SymmetricKey(data: keyData),
            authenticating: Self.cursorAAD
        )
        guard let combined = box.combined else {
            throw HealthMdQueryContractError.invalidCursor
        }
        return base64URL(combined)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    // MARK: - Page coverage and byte accounting

    private struct PageBudget {
        let maxItems: Int
        let maxBytes: Int
        private(set) var itemCount = 0
        private(set) var missingCount = 0
        private(set) var bytes = 0

        init(controls: HealthMdPageControls) {
            maxItems = controls.maxItems
            maxBytes = controls.maxBytes
        }

        mutating func appendItem<Value: Encodable>(_ value: Value) throws -> Bool {
            let size = try HealthMdQueryCanonicalSerializer.data(for: value).count
            guard size <= maxBytes else {
                throw HealthMdQueryContractError.singleItemExceedsPageBytes
            }
            guard itemCount < maxItems, bytes + size <= maxBytes else { return false }
            itemCount += 1
            bytes += size
            return true
        }

        mutating func appendMissing(_ value: HealthMdMissingInterval) throws -> Bool {
            let size = try HealthMdQueryCanonicalSerializer.data(for: value).count
            guard size <= maxBytes else {
                throw HealthMdQueryContractError.singleItemExceedsPageBytes
            }
            guard missingCount < maxItems, bytes + size <= maxBytes else { return false }
            missingCount += 1
            bytes += size
            return true
        }

        mutating func replaceMissing(
            _ old: HealthMdMissingInterval,
            with new: HealthMdMissingInterval
        ) throws -> Bool {
            let oldSize = try HealthMdQueryCanonicalSerializer.data(for: old).count
            let newSize = try HealthMdQueryCanonicalSerializer.data(for: new).count
            guard newSize <= maxBytes else {
                throw HealthMdQueryContractError.singleItemExceedsPageBytes
            }
            guard bytes - oldSize + newSize <= maxBytes else { return false }
            bytes = bytes - oldSize + newSize
            return true
        }
    }

    private struct CoverageAccumulator {
        private(set) var daysConsidered = 0
        private(set) var daysWithValues = 0
        private(set) var missing: [HealthMdMissingInterval] = []

        mutating func consider(
            ownerDate: String,
            hasValue: Bool,
            missingStatus: HealthMdAvailabilityStatus,
            budget: inout PageBudget
        ) throws -> Bool {
            if hasValue {
                daysConsidered += 1
                daysWithValues += 1
                return true
            }
            let interval = HealthMdMissingInterval(
                range: .init(startDate: ownerDate, endDate: ownerDate),
                status: missingStatus
            )
            if let last = missing.last,
               last.status == interval.status,
               last.reason == interval.reason,
               Self.areAdjacent(last.range.endDate, ownerDate) {
                let merged = HealthMdMissingInterval(
                    range: .init(startDate: last.range.startDate, endDate: ownerDate),
                    status: last.status,
                    reason: last.reason
                )
                guard try budget.replaceMissing(last, with: merged) else { return false }
                missing[missing.count - 1] = merged
            } else {
                guard try budget.appendMissing(interval) else { return false }
                missing.append(interval)
            }
            daysConsidered += 1
            return true
        }

        func makeCoverage(
            requestedRange: HealthMdDateRange?,
            availableRange: HealthMdDateRange?
        ) -> HealthMdCoverage {
            let status: HealthMdAvailabilityStatus
            if daysConsidered == 0 { status = .notSynchronized }
            else if missing.isEmpty { status = .available }
            else if daysWithValues > 0 { status = .partial }
            else {
                let statuses = Set(missing.map(\.status))
                status = statuses.count == 1 ? statuses.first! : .partial
            }
            return HealthMdCoverage(
                requestedRange: requestedRange,
                availableRange: availableRange,
                status: status,
                daysConsidered: daysConsidered,
                daysWithValues: daysWithValues,
                missing: missing
            )
        }

        private static func areAdjacent(_ first: String, _ second: String) -> Bool {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: first),
                  let next = formatter.calendar.date(byAdding: .day, value: 1, to: date) else {
                return false
            }
            return formatter.string(from: next) == second
        }
    }

    /// Comparison coverage belongs to one indivisible comparison item. It is retained exactly up
    /// to max_bytes; if the logical item cannot fit, execution fails explicitly instead of dropping
    /// missing intervals or provenance.
    private struct ExactCoverageAccumulator {
        let maxBytes: Int
        private var daysConsidered = 0
        private var daysWithValues = 0
        private var missing: [HealthMdMissingInterval] = []
        private var missingBytes = 0

        init(maxBytes: Int) { self.maxBytes = maxBytes }

        mutating func consider(
            ownerDate: String,
            hasValue: Bool,
            missingStatus: HealthMdAvailabilityStatus
        ) throws {
            daysConsidered += 1
            if hasValue {
                daysWithValues += 1
                return
            }
            let next = HealthMdMissingInterval(
                range: .init(startDate: ownerDate, endDate: ownerDate),
                status: missingStatus
            )
            if let last = missing.last,
               last.status == next.status,
               last.reason == next.reason,
               areAdjacent(last.range.endDate, ownerDate) {
                let merged = HealthMdMissingInterval(
                    range: .init(startDate: last.range.startDate, endDate: ownerDate),
                    status: last.status,
                    reason: last.reason
                )
                missingBytes -= try HealthMdQueryCanonicalSerializer.data(for: last).count
                missingBytes += try HealthMdQueryCanonicalSerializer.data(for: merged).count
                missing[missing.count - 1] = merged
            } else {
                missingBytes += try HealthMdQueryCanonicalSerializer.data(for: next).count
                missing.append(next)
            }
            guard missingBytes <= maxBytes else {
                throw HealthMdQueryContractError.singleItemExceedsPageBytes
            }
        }

        func makeCoverage(
            requestedRange: HealthMdDateRange?,
            availableRange: HealthMdDateRange?
        ) -> HealthMdCoverage {
            let status: HealthMdAvailabilityStatus
            if daysConsidered == 0 { status = .notSynchronized }
            else if missing.isEmpty { status = .available }
            else if daysWithValues > 0 { status = .partial }
            else {
                let statuses = Set(missing.map(\.status))
                status = statuses.count == 1 ? statuses.first! : .partial
            }
            return HealthMdCoverage(
                requestedRange: requestedRange,
                availableRange: availableRange,
                status: status,
                daysConsidered: daysConsidered,
                daysWithValues: daysWithValues,
                missing: missing
            )
        }

        private func areAdjacent(_ first: String, _ second: String) -> Bool {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            guard let date = formatter.date(from: first),
                  let next = formatter.calendar.date(byAdding: .day, value: 1, to: date) else {
                return false
            }
            return formatter.string(from: next) == second
        }
    }

    // MARK: - Aggregation

    private struct AggregationState {
        private enum Shape { case quantity, duration, count }

        let descriptor: HealthMdAggregationDescriptor
        private var count: Int64 = 0
        private var sum = 0.0
        private var minimum: Double?
        private var maximum: Double?
        private var shape: Shape?
        private var unit: String?
        private var latest: (ownerDate: String, observationID: String, value: HealthMdQueryValue)?

        init(descriptor: HealthMdAggregationDescriptor) {
            self.descriptor = descriptor
        }

        mutating func consume(
            _ value: HealthMdQueryValue,
            ownerDate: String,
            observationID: String
        ) throws {
            if descriptor.kind == .latest {
                if latest == nil
                    || (latest!.ownerDate, latest!.observationID) < (ownerDate, observationID) {
                    latest = (ownerDate, observationID, value)
                }
                return
            }
            if descriptor.kind == .count {
                let (newCount, overflow) = count.addingReportingOverflow(1)
                guard !overflow else { throw HealthMdQueryContractError.invalidAggregation("count_overflow") }
                count = newCount
                return
            }
            guard let number = value.finiteNumericValue else {
                throw HealthMdQueryContractError.invalidAggregation(descriptor.metricID)
            }
            let nextShape: Shape
            let nextUnit: String
            switch value {
            case .quantity(_, let valueUnit):
                nextShape = .quantity
                nextUnit = valueUnit
            case .duration:
                nextShape = .duration
                nextUnit = "s"
            case .count:
                nextShape = .count
                nextUnit = "count"
            default:
                throw HealthMdQueryContractError.invalidAggregation(descriptor.metricID)
            }
            if let shape, shape != nextShape {
                throw HealthMdQueryContractError.invalidAggregation("shape_mismatch:\(descriptor.metricID)")
            }
            if let unit, unit != nextUnit {
                throw HealthMdQueryContractError.invalidAggregation("unit_mismatch:\(descriptor.metricID)")
            }
            if let expected = descriptor.expectedUnit, expected != nextUnit {
                throw HealthMdQueryContractError.invalidAggregation("unit_mismatch:\(descriptor.metricID)")
            }
            shape = nextShape
            unit = nextUnit
            let (newCount, overflow) = count.addingReportingOverflow(1)
            guard !overflow else { throw HealthMdQueryContractError.invalidAggregation("count_overflow") }
            count = newCount
            sum += number
            guard sum.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            minimum = Swift.min(minimum ?? number, number)
            maximum = Swift.max(maximum ?? number, number)
        }

        func finish() throws -> HealthMdQueryValue? {
            if descriptor.kind == .latest { return latest?.value }
            if descriptor.kind == .count { return count == 0 ? nil : .count(count) }
            guard count > 0, let shape else { return nil }
            let number: Double
            switch descriptor.kind {
            case .sum, .durationSum: number = sum
            case .average: number = sum / Double(count)
            case .minimum: number = minimum!
            case .maximum: number = maximum!
            case .latest, .count:
                throw HealthMdQueryContractError.invalidAggregation("unexpected_aggregation_branch")
            }
            guard number.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
            switch shape {
            case .quantity:
                return .quantity(value: number, unit: unit ?? "")
            case .duration:
                return .duration(seconds: number)
            case .count:
                if number.rounded() == number,
                   number <= Double(Int64.max),
                   number >= Double(Int64.min) {
                    return .count(Int64(number))
                }
                return .quantity(value: number, unit: "count")
            }
        }
    }

    private func normalizedDescriptors(
        _ descriptors: [HealthMdAggregationDescriptor],
        metrics: HealthMdMetricSelection
    ) -> [HealthMdAggregationDescriptor] {
        var byMetric: [String: HealthMdAggregationDescriptor] = [:]
        for descriptor in descriptors where metricIsSelected(descriptor.metricID, selection: metrics) {
            byMetric[descriptor.metricID] = descriptor
        }
        return byMetric.values.sorted { $0.metricID < $1.metricID }
    }

    private func difference(
        first: HealthMdQueryValue?,
        second: HealthMdQueryValue?
    ) throws -> HealthMdQueryValue? {
        guard let first, let second,
              let firstNumber = first.finiteNumericValue,
              let secondNumber = second.finiteNumericValue,
              first.unit == second.unit else { return nil }
        let delta = secondNumber - firstNumber
        guard delta.isFinite else { throw HealthMdQueryContractError.nonFiniteNumber }
        switch second {
        case .quantity(_, let unit):
            return .quantity(value: delta, unit: unit)
        case .duration:
            return .duration(seconds: delta)
        case .count:
            if delta.rounded() == delta,
               delta <= Double(Int64.max),
               delta >= Double(Int64.min) {
                return .count(Int64(delta))
            }
            return .quantity(value: delta, unit: second.unit ?? "")
        default:
            return .quantity(value: delta, unit: second.unit ?? "")
        }
    }

    // MARK: - Normalization

    private func sortedSources(
        _ values: Set<HealthMdSourceDescriptor>
    ) -> [HealthMdSourceDescriptor] {
        values.sorted {
            if $0.schema != $1.schema { return $0.schema < $1.schema }
            if $0.schemaVersion != $1.schemaVersion { return $0.schemaVersion < $1.schemaVersion }
            return $0.digest < $1.digest
        }
    }

    private func sortedLimitations(
        _ values: Set<HealthMdLimitation>
    ) -> [HealthMdLimitation] {
        values.sorted {
            $0.code != $1.code ? $0.code < $1.code : $0.message < $1.message
        }
    }
}
#endif

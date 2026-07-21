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
        let selectedDays = try selectDays(request.dates)
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
        day.metrics.contains { $0.value != nil && $0.status == .available } || !day.workouts.isEmpty
    }

    private func allLimitations(in days: [HealthMdCompactContextDay]) -> [HealthMdLimitation] {
        uniqueLimitations(days.flatMap(\.limitations) + days.flatMap { $0.metrics.flatMap(\.limitations) })
    }

    private func uniqueLimitations(_ values: [HealthMdLimitation]) -> [HealthMdLimitation] {
        Array(Set(values)).sorted { $0.code != $1.code ? $0.code < $1.code : $0.message < $1.message }
    }

    private func normalizedSources(_ days: [HealthMdCompactContextDay]) -> [HealthMdSourceDescriptor] {
        Array(Set(days.map(\.source))).sorted {
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
        var oversized = false
        while index < values.count, result.count < controls.maxItems {
            let size = try HealthMdQueryCanonicalSerializer.data(for: values[index]).count
            if !result.isEmpty, bytes + size > controls.maxBytes { break }
            if result.isEmpty, size > controls.maxBytes { oversized = true }
            result.append(values[index]); bytes += size; index += 1
            if bytes >= controls.maxBytes { break }
        }
        let cursor = index < values.count ? try makeCursor(offset: index, fingerprint: fingerprint) : nil
        let limitations = oversized ? [HealthMdLimitation(
            code: "single_item_exceeds_page_bytes",
            message: "One indivisible item exceeded max_bytes and was returned alone so it remains reachable."
        )] : []
        return Page(values: result, nextCursor: cursor, limitations: limitations)
    }

    private struct RequestFingerprint: Encodable {
        let schema: String; let schemaVersion: Int; let metrics: HealthMdMetricSelection
        let dates: HealthMdDateSelection; let operation: HealthMdQueryOperation
        enum CodingKeys: String, CodingKey { case schema, schemaVersion = "schema_version", metrics, dates, operation }
    }

    private func requestFingerprint(_ request: HealthMdQueryRequest) throws -> String {
        try HealthMdQueryCanonicalSerializer.sha256(of: RequestFingerprint(
            schema: request.schema, schemaVersion: request.schemaVersion,
            metrics: request.metrics, dates: request.dates, operation: request.operation
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
        case .comparison: return nil
        }
    }
}

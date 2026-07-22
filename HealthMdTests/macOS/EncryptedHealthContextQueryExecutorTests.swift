import XCTest
@testable import HealthMd

#if os(macOS)
final class EncryptedHealthContextQueryExecutorTests: XCTestCase {
    func testMultiThousandDayAndDenseDayPaginationHasNoLossOrDuplicates() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"])
        let dates = ownerDates(count: 2_001)
        try await store.upsert(dates.enumerated().map { index, date in
            day(date, metrics: [metric("steps", id: "day-\(index)", value: .count(Int64(index)))])
        })

        let history = try await collectItems(
            executor: executor,
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            maxItems: 73
        )
        let historyIDs = history.compactMap { item -> String? in
            guard case .metric(let point) = item else { return nil }
            return "\(point.ownerDate)|\(point.metricID)|\(point.value!)"
        }
        XCTAssertEqual(historyIDs.count, 2_001)
        XCTAssertEqual(Set(historyIDs).count, 2_001)

        let denseDate = dates.last!
        let dense = (0..<2_505).map {
            metric("steps", id: String(format: "dense-%04d", $0), value: .count(Int64($0)))
        }
        try await store.upsert(day(denseDate, metrics: dense))
        let denseItems = try await collectItems(
            executor: executor,
            metrics: .allAvailable,
            dates: .exact(.init(startDate: denseDate, endDate: denseDate)),
            operation: .metricSeries,
            maxItems: 91
        )
        XCTAssertEqual(denseItems.count, 2_505)
    }

    func testCursorTamperingAndMutationFailClosedAndSingleOversizeItemFails() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"], allowsEvidenceValues: true)
        let evidence = contextEvidence(
            id: "large",
            day: "2026-01-01",
            sourceID: HealthMdEvidenceSourceIDs.appleHealth,
            value: .string(String(repeating: "x", count: 2_000)),
            metricIDs: ["steps"]
        )
        try await store.upsert(day(
            "2026-01-01",
            metrics: [metric("steps", id: "a"), metric("steps", id: "b")],
            evidence: [evidence]
        ))
        let firstRequest = HealthMdQueryRequest(
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .metricSeries,
            page: .init(maxItems: 1, maxBytes: 50_000)
        )
        let first = try await executor.execute(firstRequest, detailLevel: .summary)
        let cursor = try XCTUnwrap(first.nextCursor)

        var tampered = cursor
        let index = tampered.index(tampered.startIndex, offsetBy: tampered.count / 2)
        tampered.replaceSubrange(index...index, with: tampered[index] == "A" ? "B" : "A")
        await XCTAssertThrowsQueryError(.invalidCursor) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .allAvailable,
                    operation: .metricSeries,
                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: tampered)
                ),
                detailLevel: .summary
            )
        }

        try await store.upsert(day("2026-01-02", metrics: [metric("steps", id: "c")]))
        await XCTAssertThrowsQueryError(.staleCursor) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .allAvailable,
                    operation: .metricSeries,
                    page: .init(maxItems: 1, maxBytes: 50_000, cursor: cursor)
                ),
                detailLevel: .summary
            )
        }

        await XCTAssertThrowsQueryError(.singleItemExceedsPageBytes) {
            _ = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: .allAvailable,
                    dates: .exact(.init(startDate: "2026-01-01", endDate: "2026-01-01")),
                    operation: .sourceRecordListing,
                    page: .init(maxItems: 10, maxBytes: 200)
                ),
                detailLevel: .losslessRecords
            )
        }
    }

    func testAppleAndProviderEvidenceValuesArePagedAndFilterableWithBackwardSourceDefault() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"], allowsEvidenceValues: true)
        let source = HealthMdSourceDescriptor(schema: "healthmd.health_data", schemaVersion: 7, digest: "source")
        let apple = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "apple",
                locator: .canonicalUUID(ownerDate: "2026-02-01", uuid: "00000000-0000-0000-0000-000000000001"),
                source: source,
                sourceID: HealthMdEvidenceSourceIDs.appleHealth
            ),
            value: .unknown(type: "canonical_healthkit_record", value: .object(["uuid": .string("00000000-0000-0000-0000-000000000001")])),
            metricIDs: ["steps"]
        )
        let provider = HealthMdContextEvidence(
            reference: .init(
                evidenceID: "provider",
                locator: .externalIdentity(ownerDate: "2026-02-01", identifier: "provider:oura:record"),
                source: source,
                sourceID: HealthMdEvidenceSourceIDs.providerNative,
                providerID: "oura"
            ),
            value: .unknown(type: "external_provider_payload", value: .object(["provider": .string("oura"), "raw": .integer(7)]))
        )
        try await store.upsert(day("2026-02-01", evidence: [apple, provider]))

        let all = try await collectItems(
            executor: executor,
            metrics: .allAvailable,
            dates: .allAvailable,
            operation: .sourceRecordListing,
            maxItems: 1,
            detailLevel: .losslessRecords
        )
        let values = all.compactMap { item -> HealthMdContextEvidence? in
            guard case .evidence(let evidence) = item else { return nil }
            return evidence
        }
        XCTAssertEqual(values.map { $0.reference.evidenceID }, ["apple", "provider"])
        XCTAssertNotNil(values[0].value)
        XCTAssertNotNil(values[1].value)

        let providerOnly = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .allAvailable,
                sources: .explicit(sourceIDs: [], providerIDs: ["oura"]),
                dates: .allAvailable,
                operation: .sourceRecordListing,
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .losslessRecords
        )
        XCTAssertEqual(providerOnly.items.count, 1)
        guard case .evidence(let selected) = try XCTUnwrap(providerOnly.items.first) else {
            return XCTFail("Expected provider evidence")
        }
        XCTAssertEqual(selected.reference.providerID, "oura")

        let legacyJSON = #"{"schema":"healthmd.query_request","schema_version":1,"metrics":{"type":"all_available"},"dates":{"type":"all_available"},"operation":{"type":"metric_series"},"page":{"max_items":10,"max_bytes":10000}}"#
        let decoded = try HealthMdQueryCanonicalSerializer.decode(
            HealthMdQueryRequest.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(decoded.sources, .allAvailable)
    }

    func testComparisonPacketAndMissingnessRemainExactAndNeutral() async throws {
        let (store, executor) = try makeSystem(metrics: ["steps"])
        try await store.upsert([
            day("2026-03-01", metrics: [metric("steps", id: "zero", value: .count(0))]),
            day("2026-03-02", metrics: [metric("steps", id: "five", value: .count(5))]),
            day("2026-03-03", status: .partial, metrics: [metric("steps", id: "missing", value: nil, status: .partial)])
        ])

        let comparisonResponse = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["steps"]),
                dates: .allAvailable,
                operation: .periodComparison(
                    first: .init(startDate: "2026-03-01", endDate: "2026-03-01"),
                    second: .init(startDate: "2026-03-02", endDate: "2026-03-02"),
                    aggregations: [.init(metricID: "steps", kind: .sum)]
                )
            ),
            detailLevel: .aggregates
        )
        guard case .comparison(let comparison) = try XCTUnwrap(comparisonResponse.items.first) else {
            return XCTFail("Expected comparison")
        }
        XCTAssertEqual(comparison.firstValue, .count(0))
        XCTAssertEqual(comparison.secondValue, .count(5))
        XCTAssertNil(comparison.percentChange)
        XCTAssertEqual(comparison.direction, .increased)

        let packetResponse = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["steps"]),
                dates: .allAvailable,
                operation: .derivePacket(kind: .doctorVisit, detailIDs: []),
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .summary
        )
        let packet = try XCTUnwrap(packetResponse.packet)
        XCTAssertEqual(packet.facts.count, 2)
        XCTAssertTrue(packet.limitations.contains { $0.code == "factual_observations_only" })
        XCTAssertFalse(try HealthMdQueryCanonicalSerializer.string(for: packet).lowercased().contains("you should"))

        let series = try await executor.execute(
            HealthMdQueryRequest(
                metrics: .explicit(["steps"]),
                dates: .allAvailable,
                operation: .metricSeries,
                page: .init(maxItems: 10, maxBytes: 100_000)
            ),
            detailLevel: .summary
        )
        let missing = series.items.compactMap { item -> HealthMdMetricPoint? in
            guard case .metric(let point) = item, point.ownerDate == "2026-03-03" else { return nil }
            return point
        }
        XCTAssertEqual(missing.first?.value, nil)
        XCTAssertEqual(missing.first?.status, .partial)
        XCTAssertEqual(series.coverage.missing.last?.status, .partial)
    }

    // MARK: - Helpers

    private func makeSystem(
        metrics: Set<String>,
        allowsEvidenceValues: Bool = false
    ) throws -> (EncryptedHealthContextStore, EncryptedHealthContextQueryExecutor) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EncryptedQueryExecutorTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let provider = InMemoryHealthContextEncryptionKeyProvider(keyData: Data(repeating: 0x8a, count: 32))
        let store = EncryptedHealthContextStore(rootURL: root, keyProvider: provider)
        let executor = EncryptedHealthContextQueryExecutor(
            store: store,
            evidenceScope: .init(
                allowedMetricIDs: metrics,
                allowedDetailIDs: ["duration"],
                allowsWorkouts: true,
                allowsEvidenceValues: allowsEvidenceValues
            ),
            now: { Date(timeIntervalSince1970: 1) }
        )
        return (store, executor)
    }

    private func collectItems(
        executor: EncryptedHealthContextQueryExecutor,
        metrics: HealthMdMetricSelection,
        dates: HealthMdDateSelection,
        operation: HealthMdQueryOperation,
        maxItems: Int,
        detailLevel: AgentDetailLevel = .summary
    ) async throws -> [HealthMdQueryItem] {
        var cursor: String?
        var result: [HealthMdQueryItem] = []
        repeat {
            let response = try await executor.execute(
                HealthMdQueryRequest(
                    metrics: metrics,
                    dates: dates,
                    operation: operation,
                    page: .init(maxItems: maxItems, maxBytes: HealthMdPageControls.maximumBytes, cursor: cursor)
                ),
                detailLevel: detailLevel
            )
            XCTAssertLessThanOrEqual(response.items.count, maxItems)
            result.append(contentsOf: response.items)
            cursor = response.nextCursor
        } while cursor != nil
        return result
    }

    private func day(
        _ ownerDate: String,
        status: HealthMdAvailabilityStatus = .available,
        metrics: [HealthMdContextMetric] = [],
        evidence: [HealthMdContextEvidence] = []
    ) -> HealthMdCompactContextDay {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return .init(
            ownerDate: ownerDate,
            intervalStart: start,
            intervalEnd: start.addingTimeInterval(86_400),
            calendarTimeZone: "UTC",
            source: .init(schema: "healthmd.health_data", schemaVersion: 7, digest: "source-\(ownerDate)"),
            status: status,
            metrics: metrics,
            evidence: evidence
        )
    }

    private func metric(
        _ metricID: String,
        id: String,
        value: HealthMdQueryValue? = .count(1),
        status: HealthMdAvailabilityStatus = .available
    ) -> HealthMdContextMetric {
        .init(
            observationID: id,
            metricID: metricID,
            displayName: metricID,
            value: value,
            status: status
        )
    }

    private func contextEvidence(
        id: String,
        day: String,
        sourceID: String,
        value: HealthMdQueryValue,
        metricIDs: [String]
    ) -> HealthMdContextEvidence {
        .init(
            reference: .init(
                evidenceID: id,
                locator: .summaryKey(ownerDate: day, key: id),
                source: .init(schema: "healthmd.health_data", schemaVersion: 7, digest: "source-\(day)"),
                sourceID: sourceID
            ),
            value: value,
            metricIDs: metricIDs
        )
    }

    private func ownerDates(count: Int) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<count).map {
            formatter.string(from: calendar.date(byAdding: .day, value: $0, to: start)!)
        }
    }

    private func XCTAssertThrowsQueryError(
        _ expected: HealthMdQueryContractError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as HealthMdQueryContractError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}
#endif

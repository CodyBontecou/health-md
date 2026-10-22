import Foundation
import HealthMdCoreRust
import XCTest
@testable import HealthMd

@MainActor
final class HealthMdRenderInputAdapterTests: XCTestCase {
    func testWakeDateNativeStagesReachEveryFormatWithoutLosingMetadataOrClocks() throws {
        let service = HealthMdCoreService()
        let registry = try service.metricRegistry(profile: .appleHealthDataV11, expectedRegistryVersion: 2)
        let context = AppleSleepCaptureContext(timeZone: TimeZone(secondsFromGMT: 0)!, sleepDayAttribution: .morningEnds)
        let formatter = ExportDateFormatting.utcISO8601Formatter()
        let owner = try XCTUnwrap(formatter.date(from: "2026-07-25T00:00:00Z"))
        let start = owner.addingTimeInterval(-3600.25)
        let end = owner.addingTimeInterval(0.75)
        let data = HealthData(date: owner, timeContext: ExportTimeContext(timeZone: TimeZone(identifier: context.calendarTimeZoneIdentifier)!, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: 3601, coreSleep: 3601, sessionStart: start, sessionEnd: end,
                stages: [SleepStageSample(stage: "core", startDate: start, endDate: end,
                    metadata: ["note": "synthetic \"quoted\" | source"])]))
        let selection = MetricSelectionState()
        selection.enabledMetrics = ["sleep_core", "sleep_total"]
        let customization = FormatCustomization()
        customization.markdownTemplate.style = .custom
        customization.markdownTemplate.customTemplate = "# My summary\n"
        let config = try HealthMdSemanticInputAdapter.sessionConfiguration(sessionID: "apple-stage-detail",
            selection: selection, registry: registry, customization: customization,
            calendarTimeZoneIdentifier: "GMT", retainPlatformExtensions: false, rollupPeriods: [], captureContext: context)
        let batch = try HealthMdSemanticInputAdapter.batch(sessionID: "apple-stage-detail", batchIndex: 0,
            finalBatch: true, healthData: [data], registry: registry, customization: customization,
            calendarTimeZoneIdentifier: "GMT", captureContext: context)
        let semantic = try service.semanticSession(configuration: config).process(batch: batch.data)
        let encoded = try HealthMdRenderInputAdapter.encode(semanticResult: semantic, registry: registry,
            calendarTimeZoneIdentifier: "GMT", options: .init(requestID: "apple-stage-detail",
                formats: ["json", "csv", "markdown", "obsidian_bases"], customTemplate: "# My summary\n"),
            presentationByOwnerDate: ["2026-07-25": data], presentationCustomization: customization, captureContext: context)
        let session = try service.renderSession(configuration: encoded.configuration, semanticResult: semantic)
        for bytes in encoded.batches { _ = try session.process(batch: bytes) }
        let plan = try session.finish()
        let texts = plan.items.map { String(decoding: $0.content, as: UTF8.self) }
        let csv = try XCTUnwrap(texts.first { $0.contains(",Sleep Detail,Sleep Stage,") })
        XCTAssertTrue(csv.contains("2026-07-24T22:59:59.750000000Z"))
        XCTAssertTrue(csv.contains("2026-07-25T00:00:00.750000000Z"))
        XCTAssertTrue(csv.contains("note"))
        let markdown = try XCTUnwrap(texts.first { $0.contains("Sleep Stage Details") })
        XCTAssertEqual(markdown.components(separatedBy: "Sleep Stage Details").count - 1, 1)
        XCTAssertTrue(markdown.contains("| core |"))
        let bases = try XCTUnwrap(texts.first { $0.contains("sleep_stage_details") })
        XCTAssertTrue(bases.contains("synthetic"))
        XCTAssertTrue(bases.contains("3601"))
        let json = try XCTUnwrap(plan.items.first { $0.relativePath.hasSuffix(".json") })
        XCTAssertEqual(json.content, try data.toJSONDataThrowing(customization: customization, captureContext: context))
        for invalidStages in [
            [SleepStageSample(stage: "deep", startDate: start, endDate: end)],
            Array(repeating: data.sleep.stages[0], count: 1500),
        ] {
            var invalid = data
            invalid.sleep.stages = invalidStages
            XCTAssertThrowsError(try HealthMdRenderInputAdapter.encode(semanticResult: semantic, registry: registry,
                calendarTimeZoneIdentifier: "GMT", options: .init(requestID: "apple-stage-detail",
                    formats: ["json", "csv", "markdown", "obsidian_bases"]),
                presentationByOwnerDate: ["2026-07-25": invalid], presentationCustomization: customization, captureContext: context))
        }
    }

    func testCapturedDayRendersAllFormatsThroughPackagedRustPlan() throws {
        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let selection = MetricSelectionState()
        selection.enabledMetrics = ["steps"]
        let customization = FormatCustomization()
        let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: "apple-render-test",
            selection: selection,
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "UTC",
            retainPlatformExtensions: false,
            rollupPeriods: []
        )
        var data = HealthData(
            date: Date(timeIntervalSince1970: 1_753_401_600),
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
        )
        data.activity.steps = 1_234
        let semanticBatch = try HealthMdSemanticInputAdapter.batch(
            sessionID: "apple-render-test",
            batchIndex: 0,
            finalBatch: true,
            healthData: [data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: "UTC"
        )
        let semanticSession = try service.semanticSession(configuration: semanticConfiguration)
        let semanticResult = try semanticSession.process(batch: semanticBatch.data)

        let encoded = try HealthMdRenderInputAdapter.encode(
            semanticResult: semanticResult,
            registry: registry,
            calendarTimeZoneIdentifier: "UTC",
            options: .init(
                requestID: "apple-render-request",
                formats: ["markdown", "obsidian_bases", "json", "csv"],
                writeMode: "update"
            )
        )
        let renderSession = try service.renderSession(
            configuration: encoded.configuration,
            semanticResult: semanticResult
        )
        for batch in encoded.batches {
            _ = try renderSession.process(batch: batch)
        }
        let plan = try renderSession.finish()

        XCTAssertEqual(plan.profile, .appleHealthDataV8)
        XCTAssertEqual(plan.items.count, 4)
        XCTAssertEqual(
            plan.items.map(\.relativePath),
            [
                "Health/2025-07-25.csv",
                "Health/2025-07-25.json",
                "Health/2025-07-25.md",
                "Health/2025-07-25-bases.md",
            ]
        )
        XCTAssertTrue(plan.items.allSatisfy { $0.byteCount == $0.content.count && $0.sha256.count == 64 })
        let json = try XCTUnwrap(plan.items.first(where: { $0.relativePath.hasSuffix(".json") }))
        let jsonText = try XCTUnwrap(String(data: json.content, encoding: .utf8))
        XCTAssertTrue(jsonText.contains("\"schema\" : \"healthmd.health_data\""))
        XCTAssertTrue(jsonText.contains("\"steps\" : 1234"))
        XCTAssertEqual(plan.items.first(where: { $0.relativePath == "Health/2025-07-25.md" })?.writeMode, .markdownMerge)
        XCTAssertEqual(plan.items.first(where: { $0.relativePath.hasSuffix(".json") })?.writeMode, .overwrite)
    }

    func testAppleAllFormatsMatchNativeV8RendererAcrossSyntheticCases() throws {
        let imperial = FormatCustomization()
        imperial.unitPreference = .imperial
        let custom = FormatCustomization()
        custom.frontmatterConfig.customFields = ["reviewed": "false", "project": "health-md"]
        custom.frontmatterConfig.placeholderFields = ["notes", "mood_override"]
        custom.markdownTemplate.useEmoji = false
        custom.markdownTemplate.sectionHeaderLevel = 3
        let cases = [
            ("partial-default", ExportFixtures.partialDay, FormatCustomization()),
            ("full-imperial", ExportFixtures.fullDay, imperial),
            ("lossless-custom", ExportFixtures.losslessDay, custom),
        ]
        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let selection = MetricSelectionState()
        selection.enabledMetrics = Set(HealthMetrics.all.map(\.id))

        for (identifier, data, customization) in cases {
            let sessionID = "apple-render-parity-\(identifier)"
            let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionID: sessionID,
                selection: selection,
                registry: registry,
                customization: customization,
                calendarTimeZoneIdentifier: "UTC",
                retainPlatformExtensions: false,
                rollupPeriods: []
            )
            let semanticBatch = try HealthMdSemanticInputAdapter.batch(
                sessionID: sessionID,
                batchIndex: 0,
                finalBatch: true,
                healthData: [data],
                registry: registry,
                customization: customization,
                calendarTimeZoneIdentifier: "UTC"
            )
            let semanticSession = try service.semanticSession(configuration: semanticConfiguration)
            let semanticResult = try semanticSession.process(batch: semanticBatch.data)
            XCTAssertThrowsError(try HealthMdRenderInputAdapter.encode(
                semanticResult: semanticResult,
                registry: registry,
                calendarTimeZoneIdentifier: "UTC",
                options: .init(requestID: sessionID, formats: ["markdown"]),
                presentationByOwnerDate: ["2026-03-15": data],
                allowNativeProfileDocuments: false,
                presentationCustomization: customization
            )) { error in
                XCTAssertEqual(
                    error as? HealthMdRenderInputAdapter.AdapterError,
                    .invalidPresentation
                )
            }
            let encoded = try HealthMdRenderInputAdapter.encode(
                semanticResult: semanticResult,
                registry: registry,
                calendarTimeZoneIdentifier: "UTC",
                options: .init(requestID: sessionID, formats: ["markdown", "obsidian_bases", "json", "csv"]),
                presentationByOwnerDate: ["2026-03-15": data],
                presentationCustomization: customization
            )
            let renderSession = try service.renderSession(
                configuration: encoded.configuration,
                semanticResult: semanticResult
            )
            for batch in encoded.batches { _ = try renderSession.process(batch: batch) }
            let plan = try renderSession.finish()
            XCTAssertEqual(plan.items.count, 4, identifier)
            let expected: [String: Data] = [
                "Health/2026-03-15.md": Data(data.toMarkdown(customization: customization).utf8),
                "Health/2026-03-15-bases.md": Data(data.toObsidianBases(customization: customization).utf8),
                "Health/2026-03-15.json": Data(try data.toJSONThrowing(customization: customization).utf8),
                "Health/2026-03-15.csv": Data(try data.toCSVThrowing(customization: customization).utf8),
            ]
            for (path, expectedBytes) in expected {
                let item = try XCTUnwrap(plan.items.first { $0.relativePath == path })
                XCTAssertEqual(item.content, expectedBytes, "\(identifier)/\(path)")
            }
        }
    }

    func testAppleV1APIEnvelopeMatchesNativeCompactBytes() throws {
        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let timeZone = TimeZone.current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let exportedAt = Date(timeIntervalSince1970: 1_753_632_000)
        let exportedAtFormatter = ISO8601DateFormatter()
        exportedAtFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dayString = "2026-07-25"
        let selection = MetricSelectionState()
        selection.enabledMetrics = ["steps"]
        let customization = FormatCustomization()
        var data = HealthData(
            date: date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: timeZone.identifier)
        )
        data.activity.steps = 1_234
        let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: "apple-api-parity",
            selection: selection,
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: timeZone.identifier,
            retainPlatformExtensions: false,
            rollupPeriods: []
        )
        let semanticBatch = try HealthMdSemanticInputAdapter.batch(
            sessionID: "apple-api-parity",
            batchIndex: 0,
            finalBatch: true,
            healthData: [data],
            registry: registry,
            customization: customization,
            calendarTimeZoneIdentifier: timeZone.identifier
        )
        let semanticSession = try service.semanticSession(configuration: semanticConfiguration)
        let semanticResult = try semanticSession.process(batch: semanticBatch.data)
        let encoded = try HealthMdRenderInputAdapter.encode(
            semanticResult: semanticResult,
            registry: registry,
            calendarTimeZoneIdentifier: timeZone.identifier,
            options: .init(
                requestID: "apple-api-parity",
                formats: ["json"],
                writeMode: "overwrite",
                api: .init(
                    envelopeVersion: 1,
                    exportedAt: exportedAtFormatter.string(from: exportedAt),
                    source: "ios",
                    dateRangeStart: dayString,
                    dateRangeEnd: dayString
                )
            ),
            presentationByOwnerDate: [dayString: data],
            presentationCustomization: customization
        )
        let renderSession = try service.renderSession(
            configuration: encoded.configuration,
            semanticResult: semanticResult
        )
        for batch in encoded.batches {
            try renderSession.process(batch: batch)
        }
        let plan = try renderSession.finish()
        let apiItems = plan.items.filter { $0.relativePath.hasPrefix("api/") }
        XCTAssertEqual(apiItems.count, 1)
        let rust = try XCTUnwrap(apiItems.first)
#if os(macOS)
        let settings = AdvancedExportSettings()
        settings.metricSelection = selection
        settings.formatCustomization = customization
        let native = try APIExportClient.makePayload(
            records: [data],
            failedDateDetails: [FailedDateDetail](),
            settings: settings,
            dateRangeStart: date,
            dateRangeEnd: date,
            exportedAt: exportedAt,
            connectedAppsEnabled: false
        )
        XCTAssertEqual(rust.content, native)

        let external = Data(#"{"date":"2026-07-25","provider":"whoop","schema":"healthmd.external_provider_daily","schema_version":1,"url":"https://example.com/provider"}"#.utf8)
        let encodedV2 = try HealthMdRenderInputAdapter.encode(
            semanticResult: semanticResult,
            registry: registry,
            calendarTimeZoneIdentifier: timeZone.identifier,
            options: .init(
                requestID: "apple-api-v2-parity",
                formats: ["json"],
                writeMode: "overwrite",
                api: .init(
                    envelopeVersion: 2,
                    exportedAt: exportedAtFormatter.string(from: exportedAt),
                    source: "ios",
                    dateRangeStart: dayString,
                    dateRangeEnd: dayString,
                    externalRecordSchema: ExternalDailyRecord.schema,
                    externalRecordSchemaVersion: ExternalDailyRecord.schemaVersion,
                    externalRecords: [.init(ownerDate: dayString, json: external)]
                )
            ),
            presentationByOwnerDate: [dayString: data],
            presentationCustomization: customization
        )
        let renderSessionV2 = try service.renderSession(
            configuration: encodedV2.configuration,
            semanticResult: semanticResult
        )
        for batch in encodedV2.batches { try renderSessionV2.process(batch: batch) }
        let rustV2 = try XCTUnwrap(try renderSessionV2.finish().items.first { $0.relativePath.hasPrefix("api/") })
        let nativeV2 = try APIExportClient.makePayload(
            recordData: [try APIExportClient.makeRecordJSONData(data, settings: settings)],
            failedDateData: [],
            externalRecordData: [external],
            dateRangeStart: date,
            dateRangeEnd: date,
            exportedAt: exportedAt,
            connectedAppsEnabled: true
        )
        XCTAssertEqual(rustV2.content, nativeV2)
#else
        XCTAssertFalse(rust.content.isEmpty)
#endif
    }

    func testAppleWeeklyRollupMatchesAllLegacyFormatBytesAndPaths() throws {
#if os(iOS)
        throw XCTSkip("AdvancedExportSettings roll-up oracle is macOS-only; packaged iOS rendering is covered separately.")
#else
        let suite = "healthmd.tests.m5.rollup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = true
        settings.generateYearlyRollups = true
        settings.metricSelection.enabledMetrics = Set(HealthMetrics.all.map(\.id))
        settings.formatCustomization.unitPreference = .imperial
        settings.formatCustomization.frontmatterConfig.customFields = ["reviewed": "false"]
        settings.formatCustomization.frontmatterConfig.placeholderFields = ["notes"]
        settings.formatCustomization.markdownTemplate.useEmoji = false
        settings.formatCustomization.markdownTemplate.sectionHeaderLevel = 3
        let data = ExportFixtures.fullDay
        let generatedAt = Date(timeIntervalSince1970: 1_781_395_200)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let nativeSummaries = HealthRollupExporter.makeSummaries(
            from: [data],
            settings: settings,
            periods: [.weekly, .monthly, .yearly],
            generatedAt: generatedAt,
            calendar: calendar
        )
        XCTAssertEqual(nativeSummaries.count, 3)

        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let selection = MetricSelectionState()
        selection.enabledMetrics = Set(HealthMetrics.all.map(\.id))
        let sessionID = "apple-rollup-parity"
        let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: sessionID,
            selection: selection,
            registry: registry,
            customization: settings.formatCustomization,
            calendarTimeZoneIdentifier: "UTC",
            retainPlatformExtensions: false,
            rollupPeriods: [.weekly, .monthly, .yearly]
        )
        let semanticBatch = try HealthMdSemanticInputAdapter.batch(
            sessionID: sessionID,
            batchIndex: 0,
            finalBatch: true,
            healthData: [data],
            registry: registry,
            customization: settings.formatCustomization,
            calendarTimeZoneIdentifier: "UTC"
        )
        let semanticSession = try service.semanticSession(configuration: semanticConfiguration)
        let semanticResult = try semanticSession.process(batch: semanticBatch.data)
        var options = HealthMdRenderInputAdapter.Options(
            requestID: sessionID,
            formats: ["markdown", "obsidian_bases", "json", "csv"]
        )
        options.rollupGeneratedAt = HealthRollupDateFormatting.timestampString(generatedAt)
        let encoded = try HealthMdRenderInputAdapter.encode(
            semanticResult: semanticResult,
            registry: registry,
            calendarTimeZoneIdentifier: "UTC",
            options: options,
            allowNativeProfileDocuments: false,
            presentationCustomization: settings.formatCustomization
        )
        let renderSession = try service.renderSession(
            configuration: encoded.configuration,
            semanticResult: semanticResult
        )
        for batch in encoded.batches { _ = try renderSession.process(batch: batch) }
        let plan = try renderSession.finish()
        let rollups = plan.items.filter { $0.relativePath.contains("/Rollups/") }
        XCTAssertEqual(rollups.count, 12)
        let nativeTargets = HealthRollupExporter.outputTargets(
            for: nativeSummaries,
            healthSubfolder: "Health",
            settings: settings
        )
        XCTAssertEqual(rollups.map(\.relativePath), nativeTargets.map(\.relativePath))
        for target in nativeTargets {
            let item = try XCTUnwrap(rollups.first { $0.relativePath == target.relativePath })
            XCTAssertEqual(String(data: item.content, encoding: .utf8), target.content, target.relativePath)
        }
#endif
    }

    func testApplePureRustRollupsMatchEveryFormatSubset() throws {
#if os(iOS)
        throw XCTSkip("AdvancedExportSettings roll-up oracle is macOS-only; packaged iOS rendering is covered separately.")
#else
        let suite = "healthmd.tests.m5.rollup-subsets.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.generateWeeklyRollups = true
        settings.metricSelection.enabledMetrics = ["steps"]
        let calendarTimeZoneIdentifier = "America/New_York"
        let fixture = ExportFixtures.partialDay
        var data = HealthData(
            date: fixture.date,
            timeContext: ExportTimeContext(
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
        )
        data.activity = fixture.activity
        let generatedAt = Date(timeIntervalSince1970: 1_781_395_200)
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: calendarTimeZoneIdentifier))
        let service = HealthMdCoreService()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let formats = ExportFormat.allCases

        for mask in 1..<(1 << formats.count) {
            settings.exportFormats = Set(formats.enumerated().compactMap { index, format in
                mask & (1 << index) == 0 ? nil : format
            })
            let sessionID = "apple-rollup-subset-\(mask)"
            let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionID: sessionID,
                selection: settings.metricSelection,
                registry: registry,
                customization: settings.formatCustomization,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
                retainPlatformExtensions: false,
                rollupPeriods: [.weekly]
            )
            let semanticBatch = try HealthMdSemanticInputAdapter.batch(
                sessionID: sessionID,
                batchIndex: 0,
                finalBatch: true,
                healthData: [data],
                registry: registry,
                customization: settings.formatCustomization,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
            let semanticSession = try service.semanticSession(configuration: semanticConfiguration)
            let semanticResult = try semanticSession.process(batch: semanticBatch.data)
            var options = HealthMdRenderInputAdapter.Options(
                requestID: sessionID,
                formats: settings.exportFormats.sorted(by: { $0.rawValue < $1.rawValue }).map {
                    switch $0 {
                    case .markdown: "markdown"
                    case .obsidianBases: "obsidian_bases"
                    case .json: "json"
                    case .csv: "csv"
                    }
                }
            )
            options.rollupGeneratedAt = HealthRollupDateFormatting.timestampString(generatedAt)
            let encoded = try HealthMdRenderInputAdapter.encode(
                semanticResult: semanticResult,
                registry: registry,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
                options: options,
                allowNativeProfileDocuments: false,
                presentationCustomization: settings.formatCustomization
            )
            let renderSession = try service.renderSession(
                configuration: encoded.configuration,
                semanticResult: semanticResult
            )
            for batch in encoded.batches { try renderSession.process(batch: batch) }
            let rustRollups = try renderSession.finish().items.filter {
                $0.relativePath.contains("/Rollups/")
            }
            let nativeSummaries = HealthRollupExporter.makeSummaries(
                from: [data],
                settings: settings,
                periods: [.weekly],
                generatedAt: generatedAt,
                calendar: calendar
            )
            let nativeTargets = HealthRollupExporter.outputTargets(
                for: nativeSummaries,
                healthSubfolder: "Health",
                settings: settings
            )
            XCTAssertEqual(rustRollups.map(\.relativePath), nativeTargets.map(\.relativePath), "mask=\(mask)")
            for target in nativeTargets {
                let item = try XCTUnwrap(rustRollups.first { $0.relativePath == target.relativePath })
                XCTAssertEqual(String(data: item.content, encoding: .utf8), target.content, "mask=\(mask) \(target.relativePath)")
            }
        }
#endif
    }

    func testLosslessStreamAndMarkdownMergeStayBoundedAndDeterministic() throws {
        let service = HealthMdCoreService()
        let stream = try service.plannedLosslessArtifactStream(
            mode: .jsonArray,
            artifact: CoreStreamArtifactConfig(
                requestId: "apple-lossless-test",
                sessionId: "apple-lossless-session",
                profile: .appleHealthDataV8,
                relativePath: "Health/Raw/archive.json",
                mediaType: "application/json",
                writeMode: .overwrite
            )
        )
        let first = try stream.push(jsonItem: Data("{\"id\":1}".utf8))
        let second = try stream.push(jsonItem: Data("{\"id\":2}".utf8))
        let finish = try stream.finish()
        XCTAssertEqual(Data(first + second + finish.chunk), Data("[{\"id\":1},{\"id\":2}]".utf8))
        XCTAssertEqual(finish.descriptor.itemCount, 2)
        XCTAssertEqual(finish.descriptor.sha256.count, 64)
        XCTAssertEqual(finish.descriptor.artifact?.relativePath, "Health/Raw/archive.json")
        XCTAssertEqual(finish.descriptor.artifact?.byteCount, finish.descriptor.byteCount)
        XCTAssertEqual(finish.descriptor.artifact?.sha256, finish.descriptor.sha256)
        XCTAssertEqual(finish.descriptor.artifact?.artifactId.count, 64)

        let existing = "---\nuser: keep\ndate: old\ntags:\n  - personal\n---\n# User title\n\n## Sleep\nold\n\n## Notes\nkeep\n"
        let generated = "---\ndate: new\ntags:\n  - health\n---\n# Health Data — new\n\n## Sleep\nnew\n\n## Activity\nsteps\n"
        let merged = try service.mergeMarkdown(
            profile: .appleHealthDataV8,
            existing: existing,
            generated: generated
        )
        XCTAssertEqual(merged, MarkdownMerger.merge(existing: existing, new: generated))
        let preserving = try service.mergeMarkdown(
            profile: .appleHealthDataV8,
            existing: existing,
            generated: generated,
            preservePreamble: true
        )
        XCTAssertEqual(
            preserving,
            MarkdownMerger.mergePreservingPreamble(existing: existing, new: generated)
        )
    }
}

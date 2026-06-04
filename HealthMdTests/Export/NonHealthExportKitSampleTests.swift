import XCTest
@testable import HealthMd

final class NonHealthExportKitSampleTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested
    // ObservableObjects; retaining avoids the macOS 26 / Swift 6 deinit crash.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testInvoiceSampleForegroundExportUsesRenderersPathTemplatesWriterPluginsAndProgress() async throws {
        let fileSystem = SampleFileSystem()
        let destination = ExportDestination(
            rootURL: URL(fileURLWithPath: "/tmp/InvoiceExports"),
            baseRelativePath: "ClientExports"
        )
        let records = InvoiceSampleAdapter.sampleRecords
        let formatIDs = [InvoiceSampleAdapter.markdownDescriptor.id, InvoiceSampleAdapter.jsonDescriptor.id]
        var progressEvents: [ExportProgress] = []

        let result = await InvoiceSampleAdapter.runExport(
            recordsByDate: Dictionary(uniqueKeysWithValues: records.map { ($0.exportDate, $0) }),
            inputs: records.map(\.exportDate),
            formatIDs: formatIDs,
            destination: destination,
            writeMode: .overwrite,
            fileSystem: fileSystem
        ) { progress in
            progressEvents.append(progress)
        }

        XCTAssertEqual(result.status, .fullSuccess)
        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.filesWritten, 6, "Two aggregate formats plus one supplemental plugin file per invoice")
        XCTAssertEqual(progressEvents.map(\.phase), [
            .planning,
            .fetching, .rendering, .rendering, .writing,
            .fetching, .rendering, .rendering, .writing,
            .completed
        ])
        XCTAssertEqual(
            progressEvents.filter { $0.phase == .rendering }.map(\.currentFormatID),
            ["invoice-markdown", "invoice-json", "invoice-markdown", "invoice-json"]
        )

        let first = try XCTUnwrap(records.first)
        let firstMarkdownPath = try absolutePath(
            for: InvoiceSampleAdapter.planAggregateFile(
                record: first,
                descriptor: InvoiceSampleAdapter.markdownDescriptor,
                rendered: InvoiceSampleAdapter.renderedMarkdown(first)
            ),
            destination: destination
        )
        let firstJSONPath = try absolutePath(
            for: InvoiceSampleAdapter.planAggregateFile(
                record: first,
                descriptor: InvoiceSampleAdapter.jsonDescriptor,
                rendered: InvoiceSampleAdapter.renderedJSON(first)
            ),
            destination: destination
        )
        let firstLedgerPath = try absolutePath(
            for: InvoiceLedgerPlugin(fileWriter: ExportFileWriter(fileSystem: fileSystem)).ledgerFile(for: first),
            destination: destination
        )

        XCTAssertEqual(fileSystem.files[firstMarkdownPath], InvoiceSampleAdapter.markdownContent(for: first))
        XCTAssertEqual(
            try jsonObject(from: try XCTUnwrap(fileSystem.files[firstJSONPath])),
            try jsonObject(from: InvoiceSampleAdapter.jsonContent(for: first))
        )
        XCTAssertEqual(fileSystem.files[firstLedgerPath], InvoiceLedgerPlugin.ledgerContent(for: first))

        let ledgerPaths = fileSystem.files.keys.filter { $0.contains("/Ledger/") }
        XCTAssertEqual(ledgerPaths.count, 2, "Supplemental plugin output should run once per record, not once per format")
    }

    func testInvoiceSamplePreviewUsesSamePlanningAndPluginWarningsWithoutWriting() async throws {
        let fileSystem = SampleFileSystem()
        let newest = InvoiceSampleAdapter.sampleRecords[1]
        let oldest = InvoiceSampleAdapter.sampleRecords[0]
        let inputs = [oldest.exportDate, newest.exportDate]
        let preview = try await InvoiceSampleAdapter.buildPreview(
            recordsByDate: Dictionary(uniqueKeysWithValues: [oldest, newest].map { ($0.exportDate, $0) }),
            inputs: inputs,
            formatIDs: [InvoiceSampleAdapter.csvDescriptor.id, InvoiceSampleAdapter.markdownDescriptor.id],
            fileSystem: fileSystem
        )

        XCTAssertTrue(fileSystem.files.isEmpty, "Preview must not write files")
        XCTAssertEqual(preview.records.map(\.id), [newest.exportRecordID, oldest.exportRecordID])
        XCTAssertEqual(preview.records.first?.files.map(\.role), [
            .aggregate(formatID: "invoice-csv"),
            .aggregate(formatID: "invoice-markdown"),
            .supplemental(pluginID: "invoice-ledger")
        ])
        XCTAssertEqual(preview.records.first?.files.map(\.displayName), ["Invoice CSV", "Invoice Markdown", "Invoice Ledger"])
        XCTAssertEqual(preview.warnings.map(\.message), ["Invoice inv-002 is still draft"])
    }

    func testInvoiceSampleWriteModesAppendAndUpdateAreDomainAgnostic() throws {
        let fileSystem = SampleFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/InvoiceWriteModes"))

        let appendFile = PlannedExportFile(
            id: "append",
            role: .aggregate(formatID: InvoiceSampleAdapter.markdownDescriptor.id),
            relativePath: "Invoices/append.md",
            content: "first export"
        )
        _ = try writer.write(appendFile, to: destination, mode: .overwrite)
        _ = try writer.write(
            PlannedExportFile(
                id: "append",
                role: .aggregate(formatID: InvoiceSampleAdapter.markdownDescriptor.id),
                relativePath: "Invoices/append.md",
                content: "second export"
            ),
            to: destination,
            mode: .append
        )
        XCTAssertEqual(fileSystem.files["/tmp/InvoiceWriteModes/Invoices/append.md"], "first export\n\nsecond export")

        let updateFile = PlannedExportFile(
            id: "update",
            role: .aggregate(formatID: InvoiceSampleAdapter.markdownDescriptor.id),
            relativePath: "Invoices/update.md",
            content: """
            # Invoice inv-100

            ## Invoice
            - Total: $150.00
            - Status: paid
            """
        )
        fileSystem.files["/tmp/InvoiceWriteModes/Invoices/update.md"] = """
        # Invoice inv-100

        ## Invoice
        - Total: $125.00
        - Status: draft

        ## Client Notes
        Keep this negotiated discount note.
        """

        _ = try writer.write(
            updateFile,
            to: destination,
            mode: .update,
            mergeStrategy: MarkdownMergeStrategy(managedSectionNames: ["invoice"])
        )

        let updated = try XCTUnwrap(fileSystem.files["/tmp/InvoiceWriteModes/Invoices/update.md"])
        XCTAssertTrue(updated.contains("- Total: $150.00"))
        XCTAssertTrue(updated.contains("Keep this negotiated discount note."))
        XCTAssertFalse(updated.contains("- Total: $125.00"))
    }

    @MainActor
    func testInvoiceSamplePendingRetryUsesScheduledWindowAndExactStoredDates() async throws {
        let fileSystem = SampleFileSystem()
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/InvoicePendingRetry"))
        let store = InMemoryPendingExportStore()
        let schedule = AutomationSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            lookbackDays: 2,
            timeZoneIdentifier: "UTC"
        )
        let fireDate = InvoiceSampleAdapter.date(year: 2026, month: 5, day: 18, hour: 8)
        let requestID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let requestBuilder = AutomationPendingScheduledExportRequestBuilder(
            calendar: InvoiceSampleAdapter.calendar,
            now: { fireDate },
            makeID: { requestID },
            metadata: ["sampleDomain": "invoice"]
        )
        let request = requestBuilder.makeRequest(
            schedule: schedule,
            fireDate: fireDate,
            existingRequests: []
        )
        try store.upsert(request)

        var executedDates: [Date] = []
        let coordinator = AutomationPendingExportForegroundRetryCoordinator(pendingExportStore: store)
        let outcome = await coordinator.retryPendingExport(
            requestID: request.id,
            source: .scheduled,
            trigger: .notificationTap,
            shouldAttempt: { pendingRequest, trigger in
                let policy = trigger.exportTriggerSource.policy(
                    resolvedSourceFamily: pendingRequest.source.exportTriggerSourceFamily
                )
                XCTAssertEqual(policy.sourceFamily, .scheduled)
                XCTAssertEqual(policy.destinationPolicy, .localDevice)
                return .eligible
            },
            execute: { pendingRequest, _ in
                executedDates = pendingRequest.dates
                let recordsByDate = Dictionary(uniqueKeysWithValues: InvoiceSampleAdapter.sampleRecords.map { ($0.exportDate, $0) })
                let result = await InvoiceSampleAdapter.runExport(
                    recordsByDate: recordsByDate,
                    inputs: pendingRequest.dates,
                    formatIDs: [InvoiceSampleAdapter.markdownDescriptor.id, InvoiceSampleAdapter.jsonDescriptor.id],
                    destination: destination,
                    writeMode: .overwrite,
                    fileSystem: fileSystem
                )
                XCTAssertTrue(result.isFullSuccess)
                try? store.clearCompletedRequests(ids: [pendingRequest.id])
            }
        )

        XCTAssertTrue(outcome.didExecute)
        XCTAssertEqual(executedDates, request.dates)
        XCTAssertEqual(try store.loadAll(), [])
        XCTAssertEqual(fileSystem.files.keys.filter { $0.contains("/Invoices/") }.count, 4)
        XCTAssertEqual(fileSystem.files.keys.filter { $0.contains("/Ledger/") }.count, 2)
    }

    func testInvoiceSamplePortableSnapshotRoundTripsGenericConfigurationAndPayload() throws {
        let profile = InvoiceSampleAdapter.profile(
            formatIDs: ["invoice-markdown", "invoice-json", "invoice-json"],
            writeMode: .append
        )
        let target = PortableExportTargetSnapshot(
            kindID: "local-folder",
            displayName: "Shared Samples",
            destinationDisplayName: "Invoices"
        )
        let job = PortableRemoteExportJobSnapshot(
            jobID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: InvoiceSampleAdapter.date(year: 2026, month: 5, day: 18, hour: 9),
            sourceDeviceName: "Sample iPhone",
            dateRangeStart: InvoiceSampleAdapter.sampleRecords[0].exportDate,
            dateRangeEnd: InvoiceSampleAdapter.sampleRecords[1].exportDate,
            records: InvoiceSampleAdapter.sampleRecords,
            exportProfile: profile,
            requestedTarget: target
        )

        let data = try JSONEncoder().encode(job)
        let decoded = try JSONDecoder().decode(PortableRemoteExportJobSnapshot<InvoiceRecord>.self, from: data)

        XCTAssertEqual(decoded.exportProfile.formatIDs, ["invoice-markdown", "invoice-json"])
        XCTAssertEqual(decoded.exportProfile.aggregateFolderTemplate, "Invoices/{customerSlug}/{year}/{month}/{format}")
        XCTAssertEqual(decoded.exportProfile.aggregateFilenameTemplate, "{recordID}")
        XCTAssertEqual(decoded.exportProfile.writeMode, .append)
        XCTAssertEqual(decoded.exportProfile.enabledPluginIDs, ["invoice-ledger"])
        XCTAssertEqual(decoded.records, InvoiceSampleAdapter.sampleRecords)
        XCTAssertEqual(decoded.requestedTarget, target)
    }

    func testHealthAggregateWriterStillMatchesDirectHealthExportContracts() throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.filenameFormat = "daily/{date}"
        settings.folderStructure = "{year}/{month}"
        settings.includeMetadata = true
        settings.groupByCategory = true
        settings.writeMode = .overwrite

        let fileSystem = SampleFileSystem()
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/HealthAggregateParity"))
        let record = HealthExportRecord(healthData: ExportFixtures.fullDayGranular)
        let plan = try HealthAggregateExportAdapter.planAggregateFiles(
            record: record,
            settings: settings,
            healthSubfolder: "Health"
        )
        let summary = try HealthAggregateExportAdapter.write(
            plan: plan,
            to: destination,
            settings: settings,
            fileWriter: ExportFileWriter(fileSystem: fileSystem)
        )

        XCTAssertEqual(summary.filesWritten, settings.sortedExportFormats.count)
        for (file, format) in zip(plan.files, settings.sortedExportFormats) {
            let written = try XCTUnwrap(fileSystem.files[try absolutePath(for: file, destination: destination)])
            let expected = ExportFixtures.fullDayGranular.export(format: format, settings: settings)
            if format == .json {
                XCTAssertEqual(try jsonObject(from: written), try jsonObject(from: expected))
            } else {
                XCTAssertEqual(written, expected)
            }
        }
    }

    func testExportKitAndAutomationKitSourcesStayDomainFree() throws {
        let forbiddenTerms = [
            "health.md",
            "healthdata",
            "healthkit",
            "metricselectionstate",
            "healthmetricsdictionary",
            "health metrics",
            "obsidian",
            "vault"
        ]

        for sourceFile in try sourceFiles(in: "HealthMd/Shared/ExportKit") + sourceFiles(in: "HealthMd/Shared/ExportAutomationKit") {
            let lowercased = try String(contentsOf: sourceFile, encoding: .utf8).lowercased()
            for term in forbiddenTerms {
                XCTAssertFalse(
                    lowercased.contains(term),
                    "Generic export source \(sourceFile.lastPathComponent) must not reference \(term)"
                )
            }
        }
    }

    private func makeSettings() -> (AdvancedExportSettings, UserDefaults, String) {
        let suiteName = "healthmd.tests.non-health-exportkit-sample.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return (settings, defaults, suiteName)
    }

    private func absolutePath(for file: PlannedExportFile, destination: ExportDestination) throws -> String {
        let base = try destination.resolvedBaseURL()
        return try ExportPathSafetyPolicy.rejectTraversalAndAbsolutePaths
            .appending(file.relativePath, to: base, isDirectory: false)
            .path
    }

    private func jsonObject(from string: String) throws -> NSDictionary {
        let data = try XCTUnwrap(string.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? NSDictionary)
    }

    private func sourceFiles(in relativePath: String) throws -> [URL] {
        let root = try projectRoot()
        let directory = root.appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }

    private func projectRoot() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("HealthMd").path),
               FileManager.default.fileExists(atPath: directory.appendingPathComponent("HealthMdTests").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "NonHealthExportKitSampleTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate project root from \(#filePath)."]
        )
    }
}

private struct InvoiceLine: Codable, Equatable {
    var title: String
    var quantity: Int
    var unitCents: Int

    var subtotalCents: Int { quantity * unitCents }
}

private enum InvoiceStatus: String, Codable, Equatable {
    case draft
    case paid
}

private struct InvoiceRecord: ExportRecord, Codable, Equatable {
    var id: String
    var issuedDate: Date
    var customer: String
    var status: InvoiceStatus
    var lines: [InvoiceLine]

    var exportRecordID: String { id }
    var exportDate: Date { issuedDate }
    var totalCents: Int { lines.reduce(0) { $0 + $1.subtotalCents } }
    var customerSlug: String { InvoiceSampleAdapter.slug(customer) }
}

private enum InvoiceSampleAdapter {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static let markdownDescriptor = ExportFormatDescriptor(
        id: "invoice-markdown",
        displayName: "Invoice Markdown",
        fileExtension: "md",
        contentType: "text/markdown",
        defaultSortKey: "20-Markdown"
    )
    static let jsonDescriptor = ExportFormatDescriptor(
        id: "invoice-json",
        displayName: "Invoice JSON",
        fileExtension: "json",
        contentType: "application/json",
        defaultSortKey: "30-JSON"
    )
    static let csvDescriptor = ExportFormatDescriptor(
        id: "invoice-csv",
        displayName: "Invoice CSV",
        fileExtension: "csv",
        contentType: "text/csv",
        defaultSortKey: "10-CSV"
    )

    static let sampleRecords: [InvoiceRecord] = [
        InvoiceRecord(
            id: "inv-001",
            issuedDate: date(year: 2026, month: 5, day: 16),
            customer: "Acme Labs",
            status: .paid,
            lines: [
                InvoiceLine(title: "Research", quantity: 2, unitCents: 5_000),
                InvoiceLine(title: "Prototype", quantity: 1, unitCents: 2_000)
            ]
        ),
        InvoiceRecord(
            id: "inv-002",
            issuedDate: date(year: 2026, month: 5, day: 17),
            customer: "Beta Books",
            status: .draft,
            lines: [
                InvoiceLine(title: "Editing", quantity: 3, unitCents: 1_500)
            ]
        )
    ]

    static func profile(formatIDs: [String], writeMode: ExportWriteMode = .overwrite) -> PortableExportProfileSnapshot {
        PortableExportProfileSnapshot(
            formatIDs: formatIDs,
            aggregateFolderTemplate: "Invoices/{customerSlug}/{year}/{month}/{format}",
            aggregateFilenameTemplate: "{recordID}",
            writeMode: writeMode,
            enabledPluginIDs: ["invoice-ledger"],
            metadata: ["sampleDomain": "invoice"]
        )
    }

    static func runExport(
        recordsByDate: [Date: InvoiceRecord],
        inputs: [Date],
        formatIDs: [String],
        destination: ExportDestination,
        writeMode: ExportWriteMode,
        fileSystem: SampleFileSystem,
        onProgress: ((ExportProgress) -> Void)? = nil
    ) async -> ExportRunResult {
        let orchestrator = ExportRunOrchestrator<Date, InvoiceRecord>(
            dataSource: AnyExportRecordDataSource { date in
                ExportFetchedRecord(record: recordsByDate[calendar.startOfDay(for: date)])
            },
            writer: makeRecordWriter(fileSystem: fileSystem),
            failureMapper: { error in
                ExportRunFailure(reason: .writeError, errorDescription: error.localizedDescription)
            }
        )
        let request = ExportRunRequest(
            recordInputs: inputs.map { calendar.startOfDay(for: $0) },
            formatIDs: formatIDs,
            destination: destination,
            writeMode: writeMode,
            recordReference: { input in
                ExportRecordReference(id: dayString(input), date: input)
            }
        )
        return await orchestrator.run(request, onProgress: onProgress)
    }

    static func buildPreview(
        recordsByDate: [Date: InvoiceRecord],
        inputs: [Date],
        formatIDs: [String],
        fileSystem: SampleFileSystem
    ) async throws -> ExportPreview {
        let registry = try rendererRegistry()
        let pluginRunner = ExportPluginRunner(plugins: [AnyExportPlugin(InvoiceLedgerPlugin(
            fileWriter: ExportFileWriter(fileSystem: fileSystem)
        ))])
        let request = ExportPreviewRequest(
            recordInputs: inputs,
            selectedFormatIDs: formatIDs,
            dataSource: AnyExportRecordDataSource { date in
                ExportFetchedRecord(record: recordsByDate[calendar.startOfDay(for: date)])
            },
            rendererRegistry: registry,
            recordReference: { date in
                ExportRecordReference(id: dayString(date), date: date)
            },
            planAggregateFile: { record, descriptor, rendered in
                try planAggregateFile(record: record, descriptor: descriptor, rendered: rendered)
            },
            supplementalFilePlanner: { record, aggregateFiles in
                let context = ExportPluginContext(
                    record: record,
                    operation: .preview,
                    aggregateFiles: aggregateFiles,
                    writeMode: .overwrite
                )
                return try pluginRunner.previewSupplementalPlan(record: record, context: context)
            }
        )
        return try await ExportPreviewBuilder<Date, InvoiceRecord>().buildPreview(request)
    }

    static func makeRecordWriter(fileSystem: SampleFileSystem) -> AnyExportRecordWriter<InvoiceRecord> {
        AnyExportRecordWriter { record, context in
            guard let destination = context.destination else {
                throw SampleExportError.noDestination
            }
            let registry = try rendererRegistry()
            let descriptors = try registry.descriptors(for: context.formatIDs)
            let files = try descriptors.map { descriptor in
                try planAggregateFile(
                    record: record,
                    descriptor: descriptor,
                    rendered: registry.render(record: record, formatID: descriptor.id)
                )
            }
            let writer = ExportFileWriter(fileSystem: fileSystem)
            let pluginRunner = ExportPluginRunner(plugins: [AnyExportPlugin(InvoiceLedgerPlugin(fileWriter: writer))])
            let validationWarnings = try pluginRunner.validate(
                record: record,
                context: ExportPluginContext(
                    record: record,
                    operation: .validation,
                    destination: destination,
                    aggregateFiles: files,
                    writeMode: context.writeMode
                )
            )
            let writeResults = try writer.write(
                files,
                to: destination,
                mode: context.writeMode,
                mergeStrategies: [
                    markdownDescriptor.id: MarkdownMergeStrategy(managedSectionNames: ["invoice"])
                ]
            )
            let pluginResults = try pluginRunner.performSideEffects(
                record: record,
                context: ExportPluginContext(
                    record: record,
                    operation: .write,
                    destination: destination,
                    aggregateFiles: files,
                    writeMode: context.writeMode
                )
            )
            return ExportRecordWriteSummary(
                filesWritten: writeResults.count + pluginResults.reduce(0) { $0 + $1.filesWritten },
                warnings: validationWarnings + pluginResults.flatMap(\.warnings)
            )
        }
    }

    static func rendererRegistry() throws -> ExportRendererRegistry<InvoiceRecord> {
        try ExportRendererRegistry(renderers: [
            AnyExportRenderer(InvoiceMarkdownRenderer()),
            AnyExportRenderer(InvoiceJSONRenderer()),
            AnyExportRenderer(InvoiceCSVRenderer())
        ])
    }

    static func planAggregateFile(
        record: InvoiceRecord,
        descriptor: ExportFormatDescriptor,
        rendered: RenderedExport
    ) throws -> PlannedExportFile {
        let relativePath = try profile(formatIDs: [descriptor.id])
            .aggregatePathTemplate(fileExtension: descriptor.fileExtension)
            .plannedRelativePath(
                variables: pathVariables(record: record, descriptor: descriptor),
                safetyPolicy: .rejectTraversalAndAbsolutePaths
            )
        return PlannedExportFile(
            id: "\(record.exportRecordID)-\(descriptor.id)",
            role: .aggregate(formatID: descriptor.id),
            relativePath: relativePath,
            content: rendered.content,
            format: descriptor,
            contentType: rendered.contentType,
            displayName: descriptor.displayName,
            estimatedByteCount: rendered.content.utf8.count
        )
    }

    static func pathVariables(record: InvoiceRecord, descriptor: ExportFormatDescriptor) -> ExportPathVariables {
        ExportPathVariables(date: record.exportDate, values: [
            "customerSlug": record.customerSlug,
            "recordID": record.exportRecordID,
            "format": descriptor.id.replacingOccurrences(of: "invoice-", with: "")
        ])
    }

    static func renderedMarkdown(_ record: InvoiceRecord) -> RenderedExport {
        RenderedExport(content: markdownContent(for: record), contentType: markdownDescriptor.contentType)
    }

    static func renderedJSON(_ record: InvoiceRecord) throws -> RenderedExport {
        RenderedExport(content: try jsonContent(for: record), contentType: jsonDescriptor.contentType)
    }

    static func markdownContent(for record: InvoiceRecord) -> String {
        let lines = record.lines.map { line in
            "- \(line.title): \(line.quantity) × \(currency(line.unitCents)) = \(currency(line.subtotalCents))"
        }.joined(separator: "\n")
        return """
        # Invoice \(record.id)

        ## Invoice
        - Customer: \(record.customer)
        - Date: \(dayString(record.exportDate))
        - Status: \(record.status.rawValue)
        - Total: \(currency(record.totalCents))

        ## Line Items
        \(lines)
        """
    }

    static func jsonContent(for record: InvoiceRecord) throws -> String {
        let payload = InvoiceJSONPayload(
            id: record.id,
            date: dayString(record.exportDate),
            customer: record.customer,
            status: record.status.rawValue,
            totalCents: record.totalCents,
            lines: record.lines.map { line in
                InvoiceJSONPayload.Line(
                    title: line.title,
                    quantity: line.quantity,
                    unitCents: line.unitCents,
                    subtotalCents: line.subtotalCents
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SampleExportError.invalidEncoding
        }
        return string
    }

    static func csvContent(for record: InvoiceRecord) -> String {
        let rows = record.lines.map { line in
            [
                record.id,
                dayString(record.exportDate),
                record.customer,
                record.status.rawValue,
                line.title,
                String(line.quantity),
                String(line.unitCents),
                String(line.subtotalCents)
            ].map(csvEscape).joined(separator: ",")
        }
        return (["invoice_id,date,customer,status,line_title,quantity,unit_cents,subtotal_cents"] + rows)
            .joined(separator: "\n")
    }

    static func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    static func dayString(_ date: Date) -> String {
        let values = ExportPathVariables.datePlaceholderValues(for: date)
        return values["date"] ?? ""
    }

    static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let characters = value.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(characters)
            .split(separator: "-")
            .joined(separator: "-")
    }

    static func currency(_ cents: Int) -> String {
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

private struct InvoiceMarkdownRenderer: ExportRenderer {
    var descriptor: ExportFormatDescriptor { InvoiceSampleAdapter.markdownDescriptor }

    func render(record: InvoiceRecord, context: ExportRenderContext) throws -> RenderedExport {
        InvoiceSampleAdapter.renderedMarkdown(record)
    }
}

private struct InvoiceJSONRenderer: ExportRenderer {
    var descriptor: ExportFormatDescriptor { InvoiceSampleAdapter.jsonDescriptor }

    func render(record: InvoiceRecord, context: ExportRenderContext) throws -> RenderedExport {
        try InvoiceSampleAdapter.renderedJSON(record)
    }
}

private struct InvoiceCSVRenderer: ExportRenderer {
    var descriptor: ExportFormatDescriptor { InvoiceSampleAdapter.csvDescriptor }

    func render(record: InvoiceRecord, context: ExportRenderContext) throws -> RenderedExport {
        RenderedExport(
            content: InvoiceSampleAdapter.csvContent(for: record),
            contentType: descriptor.contentType
        )
    }
}

private struct InvoiceLedgerPlugin: ExportPlugin {
    let fileWriter: ExportFileWriter
    let id = "invoice-ledger"

    func validate(record: InvoiceRecord, context: ExportPluginContext<InvoiceRecord>) throws -> [ExportWarning] {
        record.status == .draft
            ? [ExportWarning(id: "\(record.id)-draft", message: "Invoice \(record.id) is still draft")]
            : []
    }

    func planFiles(
        record: InvoiceRecord,
        context: ExportPluginContext<InvoiceRecord>
    ) throws -> ExportPluginPlan {
        ExportPluginPlan(
            files: [try ledgerFile(for: record)],
            warnings: try validate(record: record, context: context)
        )
    }

    func performSideEffects(
        record: InvoiceRecord,
        context: ExportPluginContext<InvoiceRecord>
    ) throws -> ExportPluginRunResult {
        guard let destination = context.destination else {
            throw SampleExportError.noDestination
        }
        let result = try fileWriter.write(try ledgerFile(for: record), to: destination, mode: .overwrite)
        return ExportPluginRunResult(
            pluginID: id,
            filesWritten: 1,
            warnings: try validate(record: record, context: context),
            metadata: ["relativePath": result.relativePath]
        )
    }

    func ledgerFile(for record: InvoiceRecord) throws -> PlannedExportFile {
        let template = ExportPathTemplate(
            folderTemplate: "Ledger/{year}/{month}",
            filenameTemplate: "{recordID}",
            fileExtension: "md"
        )
        let relativePath = try template.plannedRelativePath(
            variables: ExportPathVariables(
                date: record.exportDate,
                values: ["recordID": record.exportRecordID]
            ),
            safetyPolicy: .rejectTraversalAndAbsolutePaths
        )
        return PlannedExportFile(
            id: "\(record.exportRecordID)-ledger",
            role: .supplemental(pluginID: id),
            relativePath: relativePath,
            content: Self.ledgerContent(for: record),
            contentType: "text/markdown",
            displayName: "Invoice Ledger"
        )
    }

    static func ledgerContent(for record: InvoiceRecord) -> String {
        """
        ## Ledger Entry
        - Invoice: \(record.id)
        - Customer: \(record.customer)
        - Status: \(record.status.rawValue)
        - Total: \(InvoiceSampleAdapter.currency(record.totalCents))
        """
    }
}

private struct InvoiceJSONPayload: Encodable {
    struct Line: Encodable {
        var title: String
        var quantity: Int
        var unitCents: Int
        var subtotalCents: Int
    }

    var id: String
    var date: String
    var customer: String
    var status: String
    var totalCents: Int
    var lines: [Line]
}

private enum SampleExportError: LocalizedError {
    case noDestination
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .noDestination:
            return "No export destination was provided."
        case .invalidEncoding:
            return "Could not encode invoice export content."
        }
    }
}

private final class SampleFileSystem: ExportFileSystem {
    var files: [String: String] = [:]
    var directories: Set<String> = []

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil || directories.contains(url.path)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func readString(at url: URL) throws -> String {
        guard let value = files[url.path] else {
            throw SampleExportError.invalidEncoding
        }
        return value
    }

    func writeString(_ value: String, to url: URL, atomically: Bool) throws {
        files[url.path] = value
    }
}

private final class InMemoryPendingExportStore: AutomationPendingExportStoring {
    private var requests: [AutomationPendingExportRequest] = []
    private let identifiers = AutomationPendingExportNotificationIdentifierFactory(prefix: "sample.pending-export.")

    func loadAll() throws -> [AutomationPendingExportRequest] {
        requests
    }

    func upsert(_ request: AutomationPendingExportRequest) throws {
        requests.removeAll { $0.id == request.id }
        requests.append(request)
        requests.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func remove(id: AutomationPendingExportRequest.ID) throws {
        requests.removeAll { $0.id == id }
    }

    func clearCompletedRequests(ids: Set<AutomationPendingExportRequest.ID>) throws {
        requests.removeAll { ids.contains($0.id) }
    }

    func notificationIdentifier(for request: AutomationPendingExportRequest) -> String {
        identifiers.pendingExport(for: request)
    }
}

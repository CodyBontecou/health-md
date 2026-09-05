import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class SharedSetupAppleProfileFieldCoverageTests: XCTestCase {
    func testLedgerExactlyCoversCurrentStoredAndEncodedFields() throws {
        let ledger = try loadLedger()
        let inventories = try makeNativeInventories()
        let ledgerTypes = Set(ledger.fields.map(\.sourceType))
        let inventoryTypes = Set(inventories.map(\.sourceType))

        XCTAssertEqual(
            ledgerTypes,
            inventoryTypes,
            "Every ledger source type must have an executable native inventory, and vice versa."
        )

        for inventory in inventories {
            let rows = ledger.fields.filter { $0.sourceType == inventory.sourceType }
            let storedRows = rows.filter { $0.fieldKind == .stored }
            let expectedStoredFields = Set(storedRows.map(\.field))
            XCTAssertEqual(
                inventory.storedFields,
                expectedStoredFields,
                differenceMessage(
                    subject: "stored fields for \(inventory.sourceType)",
                    actual: inventory.storedFields,
                    expected: expectedStoredFields
                )
            )

            let encodedRows = rows.filter {
                $0.fieldKind == .stored || $0.fieldKind == .encodedOnly
            }
            let expectedEncodedKeys = Set(encodedRows.map(\.serializedKey))
            XCTAssertEqual(
                inventory.encodedKeys,
                expectedEncodedKeys,
                differenceMessage(
                    subject: "encoded keys for \(inventory.sourceType)",
                    actual: inventory.encodedKeys,
                    expected: expectedEncodedKeys
                )
            )
            XCTAssertEqual(
                encodedRows.count,
                expectedEncodedKeys.count,
                "\(inventory.sourceType) must not classify one encoded key more than once."
            )
        }
    }

    func testLedgerEnforcesDispositionAndV2PathInvariants() throws {
        let ledger = try loadLedger()

        XCTAssertEqual(ledger.schema, "healthmd.shared_setup.apple_profile_field_coverage")
        XCTAssertEqual(ledger.schemaVersion, 1)
        XCTAssertEqual(ledger.targetContract.schema, "healthmd.shared_setup")
        XCTAssertEqual(ledger.targetContract.schemaVersion, 2)
        XCTAssertEqual(Set(ledger.fieldKinds), Set(FieldKind.allCases))
        XCTAssertEqual(Set(ledger.dispositions), Set(Disposition.allCases))

        let identities = ledger.fields.map { "\($0.sourceType).\($0.field)" }
        XCTAssertEqual(
            Set(identities).count,
            identities.count,
            "Each source type and exact field may appear only once."
        )

        for row in ledger.fields {
            XCTAssertFalse(
                row.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(row.sourceType).\(row.field) needs concise audit evidence."
            )

            switch row.disposition {
            case .portable, .platformExtension, .destinationIntent, .scheduleIntent:
                XCTAssertNotNil(
                    row.contractPath,
                    "\(row.sourceType).\(row.field) must name its intended v2 path."
                )
            case .derivedOrLegacy, .localOnly, .prohibited:
                XCTAssertNil(
                    row.contractPath,
                    "\(row.sourceType).\(row.field) must not claim a v2 path."
                )
            }

            if row.fieldKind == .encodedOnly || row.fieldKind == .decodeOnly {
                XCTAssertEqual(
                    row.disposition,
                    .derivedOrLegacy,
                    "Serialization-only compatibility fields cannot become v2 authority."
                )
            }

            if let path = row.contractPath {
                XCTAssertTrue(
                    Self.allowedV2ContractPaths.contains(path),
                    "\(row.sourceType).\(row.field) claims an unreviewed v2 path: \(path)"
                )
                XCTAssertFalse(
                    Self.prohibitedPathFragments.contains(where: path.contains),
                    "\(row.sourceType).\(row.field) exposes prohibited state at \(path)"
                )
                XCTAssertFalse(
                    path.contains(".android"),
                    "The Apple audit must not claim an Android extension or equivalence."
                )
            }
        }
    }

    func testExplicitLegacyDecodeOnlyInventoryStillExercisesEveryAcceptedAlias() throws {
        let ledger = try loadLedger()
        let actualAliases = Set(
            ledger.fields
                .filter { $0.fieldKind == .decodeOnly }
                .map { "\($0.sourceType).\($0.serializedKey)" }
        )
        let expectedAliases: Set<String> = [
            "ExportSettingsSnapshot.archiveMarkdownExports",
            "ExportSettingsSnapshot.generateMonthlyRollups",
            "ExportSettingsSnapshot.generateWeeklyRollups",
            "ExportSettingsSnapshot.generateYearlyRollups",
        ]
        XCTAssertEqual(actualAliases, expectedAliases)

        let snapshot = try makeSyntheticValues().snapshot
        let encoded = try JSONEncoder().encode(snapshot)
        let base = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        var archiveLegacy = base
        archiveLegacy.removeValue(forKey: "archiveExportFiles")
        archiveLegacy["archiveMarkdownExports"] = true
        XCTAssertTrue(try decodeSnapshot(archiveLegacy).archiveExportFiles)

        for key in [
            "generateMonthlyRollups",
            "generateWeeklyRollups",
            "generateYearlyRollups",
        ] {
            var rollupLegacy = base
            rollupLegacy.removeValue(forKey: "generateRangeSummary")
            rollupLegacy[key] = true
            XCTAssertTrue(
                try decodeSnapshot(rollupLegacy).generateRangeSummary,
                "Legacy decoder alias \(key) is stale or no longer exercised."
            )
        }
    }

    private func loadLedger() throws -> CoverageLedger {
        try JSONDecoder().decode(
            CoverageLedger.self,
            from: Data(contentsOf: try ledgerURL())
        )
    }

    private func ledgerURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while directory.path != "/" {
            let candidate = directory.appendingPathComponent(
                "packages/contracts/shared-setup/v2/apple-profile-field-coverage.json"
            )
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw CoverageTestError.ledgerNotFound
    }

    private func makeNativeInventories() throws -> [NativeInventory] {
        let values = try makeSyntheticValues()
        return try [
            inventory(values.enginePin, sourceType: "AppleExportEnginePin"),
            inventory(values.frontmatterField, sourceType: "CustomFrontmatterField"),
            inventory(values.dailyNotes, sourceType: "DailyNoteInjectionSnapshot"),
            inventory(values.profile, sourceType: "ExportProfile"),
            inventory(values.snapshot, sourceType: "ExportSettingsSnapshot"),
            inventory(values.formatCustomization, sourceType: "FormatCustomizationSnapshot"),
            inventory(values.frontmatter, sourceType: "FrontmatterConfigurationSnapshot"),
            inventory(values.individualTracking, sourceType: "IndividualTrackingSnapshot"),
            inventory(values.markdown, sourceType: "MarkdownTemplateConfig"),
            inventory(values.metricSelection, sourceType: "MetricSelectionSnapshot"),
            inventory(values.metricTracking, sourceType: "MetricTrackingConfig"),
            inventory(values.apiEndpoint, sourceType: "SavedAPIEndpoint"),
            inventory(values.vault, sourceType: "SavedVaultDestination"),
            inventory(values.schedule, sourceType: "ScheduledExportEntry"),
            inventory(values.vaultIdentity, sourceType: "VaultFolderIdentity"),
        ]
    }

    private func makeSyntheticValues() throws -> SyntheticValues {
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let profileID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let scheduleID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let vaultID = try XCTUnwrap(UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        let endpointID = try XCTUnwrap(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))

        let frontmatterField = CustomFrontmatterField(
            originalKey: "steps",
            customKey: "step_count",
            isEnabled: false
        )
        let frontmatter = FrontmatterConfigurationSnapshot(
            fields: [frontmatterField],
            customFields: ["reviewed": "synthetic"],
            placeholderFields: ["notes"],
            includeDate: false,
            includeType: true,
            customDateKey: "day",
            customTypeKey: "kind",
            customTypeValue: "health",
            keyStyle: .camelCase
        )
        var markdown = MarkdownTemplateConfig()
        markdown.style = .custom
        markdown.customTemplate = "# {{date}}"
        markdown.sectionHeaderLevel = 3
        markdown.useEmoji = true
        markdown.includeSummary = false
        markdown.bulletStyle = .plus

        let formatCustomization = FormatCustomizationSnapshot(
            dateFormat: .friendly,
            timeFormat: .hour12WithSeconds,
            unitPreference: .imperial,
            frontmatterConfig: frontmatter,
            markdownTemplate: markdown
        )
        let metricTracking = MetricTrackingConfig(
            trackIndividually: true,
            customFolder: "Entries/Steps"
        )
        let individualTracking = IndividualTrackingSnapshot(
            globalEnabled: true,
            metricConfigs: ["steps": metricTracking],
            entriesFolder: "Entries",
            useCategoryFolders: false,
            filenameTemplate: "{date}_{time}_{metric}"
        )
        let dailyNotes = DailyNoteInjectionSnapshot(
            enabled: true,
            folderPath: "Daily",
            filenamePattern: "{date}",
            createIfMissing: true,
            injectMarkdownSections: true,
            dailyNotesOnly: true
        )
        let metricSelection = MetricSelectionSnapshot(
            enabledMetricIDs: ["steps"],
            enabledCategoryIDs: ["activity"]
        )
        let enginePin = try makeSyntheticAppleExportEnginePin(
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )
        let snapshot = ExportSettingsSnapshot(
            exportFormats: [.markdown, .obsidianBases, .json, .csv],
            includeMetadata: false,
            groupByCategory: false,
            filenameFormat: "health-{date}",
            folderStructure: "{year}/{month}",
            healthSubfolder: "Health",
            organizeFormatsIntoFolders: true,
            archiveExportFiles: true,
            includeDataDictionary: false,
            summaryOnlyExport: true,
            writeMode: .update,
            formatCustomization: formatCustomization,
            individualTracking: individualTracking,
            dailyNoteInjection: dailyNotes,
            includeGranularData: false,
            compatibilityDetail: .selectedTimeSeries,
            healthKitSourceArchivePolicy: .canonicalV1,
            generateRangeSummary: true,
            metricSelection: metricSelection,
            appleExportEnginePin: enginePin,
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )
        let profile = ExportProfile(
            id: profileID,
            name: "Synthetic Profile",
            settings: snapshot,
            target: .apiEndpoint,
            folderVaultID: vaultID,
            apiEndpointID: endpointID,
            createdAt: fixedDate,
            updatedAt: fixedDate.addingTimeInterval(60),
            isMigrationDefault: true
        )
        let schedule = ScheduledExportEntry(
            id: scheduleID,
            profileID: profileID,
            isEnabled: true,
            frequency: .custom,
            customInterval: 2,
            customUnit: .month,
            customAnchorDate: fixedDate,
            preferredHour: 8,
            preferredMinute: 15,
            weekday: 3,
            lookbackDays: 7,
            todayRefreshEnabled: true,
            todayRefreshIntervalHours: 6,
            lastExportDate: fixedDate.addingTimeInterval(-86_400),
            lastTodayRefreshDate: fixedDate.addingTimeInterval(-3_600),
            enabledAt: fixedDate.addingTimeInterval(-604_800)
        )
        let vaultIdentity = VaultFolderIdentity(
            volumeUUIDString: "synthetic-volume",
            fileIdentifier: 42
        )
        let vault = SavedVaultDestination(
            id: vaultID,
            name: "Synthetic Vault",
            standardizedPath: "/synthetic/vault",
            bookmarkData: Data("synthetic-bookmark".utf8),
            identity: vaultIdentity,
            createdAt: fixedDate
        )
        let apiEndpoint = SavedAPIEndpoint(
            id: endpointID,
            name: "Synthetic Endpoint",
            endpointURLString: "https://setup.invalid/synthetic",
            createdAt: fixedDate
        )

        return SyntheticValues(
            enginePin: enginePin,
            frontmatterField: frontmatterField,
            dailyNotes: dailyNotes,
            profile: profile,
            snapshot: snapshot,
            formatCustomization: formatCustomization,
            frontmatter: frontmatter,
            individualTracking: individualTracking,
            markdown: markdown,
            metricSelection: metricSelection,
            metricTracking: metricTracking,
            apiEndpoint: apiEndpoint,
            vault: vault,
            schedule: schedule,
            vaultIdentity: vaultIdentity
        )
    }

    private func inventory<Value: Encodable>(
        _ value: Value,
        sourceType: String
    ) throws -> NativeInventory {
        let storedFields = Set(
            Mirror(reflecting: value).children.compactMap(\.label)
        )
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        let encoded = try XCTUnwrap(
            object as? [String: Any],
            "Synthetic \(sourceType) must encode as a keyed object."
        )
        return NativeInventory(
            sourceType: sourceType,
            storedFields: storedFields,
            encodedKeys: Set(encoded.keys)
        )
    }

    private func decodeSnapshot(_ object: [String: Any]) throws -> ExportSettingsSnapshot {
        try JSONDecoder().decode(
            ExportSettingsSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func differenceMessage(
        subject: String,
        actual: Set<String>,
        expected: Set<String>
    ) -> String {
        let unclassified = actual.subtracting(expected).sorted()
        let stale = expected.subtracting(actual).sorted()
        return "\(subject): unclassified=\(unclassified), stale=\(stale)"
    }

    private static let prohibitedPathFragments = [
        "authorization",
        "bookmark",
        "credential",
        "created_at",
        "enabled_at",
        "fingerprint",
        "folder_grant",
        "folder_vault_id",
        "history",
        "identity",
        "last_export",
        "last_success",
        "last_today_refresh",
        "operation_id",
        "profile_id",
        "progress",
        "renderer_pin",
        "retry",
        "standardized_path",
        "time_zone",
        "token",
        "updated_at",
        "worker_id",
    ]

    private static let allowedV2ContractPaths: Set<String> = [
        "profiles[]",
        "profiles[].daily_notes",
        "profiles[].daily_notes.create_if_missing",
        "profiles[].daily_notes.enabled",
        "profiles[].daily_notes.filename_template",
        "profiles[].daily_notes.folder",
        "profiles[].daily_notes.inject_sections",
        "profiles[].destination.api_endpoint",
        "profiles[].destination.kind",
        "profiles[].export.compatibility_detail",
        "profiles[].export.filename_template",
        "profiles[].export.folder_template",
        "profiles[].export.formats",
        "profiles[].export.group_by_category",
        "profiles[].export.include_metadata",
        "profiles[].export.write_mode",
        "profiles[].individual_entries",
        "profiles[].individual_entries.enabled",
        "profiles[].individual_entries.entries_folder",
        "profiles[].individual_entries.filename_template",
        "profiles[].individual_entries.metrics",
        "profiles[].individual_entries.metrics.*.custom_folder",
        "profiles[].individual_entries.metrics.*.enabled",
        "profiles[].individual_entries.organize_by_category",
        "profiles[].metrics",
        "profiles[].metrics.enabled_ids",
        "profiles[].name",
        "profiles[].platform_extensions.apple.daily_notes.only",
        "profiles[].platform_extensions.apple.export.archive_files",
        "profiles[].platform_extensions.apple.export.generate_range_summary",
        "profiles[].platform_extensions.apple.export.healthkit_source_archive",
        "profiles[].platform_extensions.apple.export.include_data_dictionary",
        "profiles[].platform_extensions.apple.export.organize_formats_into_folders",
        "profiles[].platform_extensions.apple.export.summary_only",
        "profiles[].platform_extensions.apple.schedule.custom_unit",
        "profiles[].platform_extensions.apple.schedule.frequency",
        "profiles[].platform_extensions.apple.schedule.today_refresh_interval_hours",
        "profiles[].platform_extensions.apple.schedule.today_refresh_requested",
        "profiles[].presentation",
        "profiles[].presentation.date_format",
        "profiles[].presentation.frontmatter",
        "profiles[].presentation.frontmatter.custom_values",
        "profiles[].presentation.frontmatter.date_key",
        "profiles[].presentation.frontmatter.fields",
        "profiles[].presentation.frontmatter.fields[].enabled",
        "profiles[].presentation.frontmatter.fields[].output_key",
        "profiles[].presentation.frontmatter.fields[].source_key",
        "profiles[].presentation.frontmatter.include_date",
        "profiles[].presentation.frontmatter.include_type",
        "profiles[].presentation.frontmatter.key_style",
        "profiles[].presentation.frontmatter.placeholders",
        "profiles[].presentation.frontmatter.type_key",
        "profiles[].presentation.frontmatter.type_value",
        "profiles[].presentation.markdown",
        "profiles[].presentation.markdown.bullet_style",
        "profiles[].presentation.markdown.custom_text",
        "profiles[].presentation.markdown.header_level",
        "profiles[].presentation.markdown.include_summary",
        "profiles[].presentation.markdown.style",
        "profiles[].presentation.markdown.use_emoji",
        "profiles[].presentation.time_format",
        "profiles[].presentation.units",
        "profiles[].schedule.activation_requested",
        "profiles[].schedule.cadence.anchor_date",
        "profiles[].schedule.cadence.value",
        "profiles[].schedule.local_time.hour",
        "profiles[].schedule.local_time.minute",
        "profiles[].schedule.lookback_days",
        "profiles[].schedule.weekday",
    ]
}

private struct NativeInventory {
    let sourceType: String
    let storedFields: Set<String>
    let encodedKeys: Set<String>
}

private struct SyntheticValues {
    let enginePin: AppleExportEnginePin
    let frontmatterField: CustomFrontmatterField
    let dailyNotes: DailyNoteInjectionSnapshot
    let profile: ExportProfile
    let snapshot: ExportSettingsSnapshot
    let formatCustomization: FormatCustomizationSnapshot
    let frontmatter: FrontmatterConfigurationSnapshot
    let individualTracking: IndividualTrackingSnapshot
    let markdown: MarkdownTemplateConfig
    let metricSelection: MetricSelectionSnapshot
    let metricTracking: MetricTrackingConfig
    let apiEndpoint: SavedAPIEndpoint
    let vault: SavedVaultDestination
    let schedule: ScheduledExportEntry
    let vaultIdentity: VaultFolderIdentity
}

private struct CoverageLedger: Decodable {
    let schema: String
    let schemaVersion: Int
    let targetContract: TargetContract
    let fieldKinds: [FieldKind]
    let dispositions: [Disposition]
    let fields: [Field]

    struct TargetContract: Decodable {
        let schema: String
        let schemaVersion: Int

        enum CodingKeys: String, CodingKey {
            case schema
            case schemaVersion = "schema_version"
        }
    }

    struct Field: Decodable {
        let sourceType: String
        let field: String
        let fieldKind: FieldKind
        let serializedKey: String
        let disposition: Disposition
        let contractPath: String?
        let reason: String

        enum CodingKeys: String, CodingKey {
            case sourceType = "source_type"
            case field
            case fieldKind = "field_kind"
            case serializedKey = "serialized_key"
            case disposition
            case contractPath = "contract_path"
            case reason
        }
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case schemaVersion = "schema_version"
        case targetContract = "target_contract"
        case fieldKinds = "field_kinds"
        case dispositions
        case fields
    }
}

private enum FieldKind: String, Decodable, CaseIterable {
    case stored
    case encodedOnly = "encoded_only"
    case decodeOnly = "decode_only"
}

private enum Disposition: String, Decodable, CaseIterable {
    case portable
    case platformExtension = "platform_extension"
    case destinationIntent = "destination_intent"
    case scheduleIntent = "schedule_intent"
    case derivedOrLegacy = "derived_or_legacy"
    case localOnly = "local_only"
    case prohibited
}

private enum CoverageTestError: LocalizedError {
    case ledgerNotFound

    var errorDescription: String? {
        "Could not locate packages/contracts/shared-setup/v2/apple-profile-field-coverage.json"
    }
}

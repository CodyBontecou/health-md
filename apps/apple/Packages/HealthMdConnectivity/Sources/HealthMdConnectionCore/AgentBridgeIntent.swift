import Foundation

public struct AgentBridgeDateRange: Codable, Equatable, Sendable, BridgeValueCodable {
    public let startDate: AgentBridgeDate
    public let endDate: AgentBridgeDate
    public init(startDate: AgentBridgeDate, endDate: AgentBridgeDate) { self.startDate = startDate; self.endDate = endDate }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["start_date", "end_date"])
        startDate = try o.value("start_date"); endDate = try o.value("end_date")
        guard startDate.rawValue <= endDate.rawValue else { throw AgentBridgeValidationError.invalidRequest }
    }
    var bridgeJSON: BridgeJSON { .object([("start_date", startDate.bridgeJSON), ("end_date", endDate.bridgeJSON)]) }
}

public enum AgentBridgeDates: Codable, Equatable, Sendable, BridgeValueCodable {
    case exact(AgentBridgeDateRange), allAvailable, pastCompleteDays(days: Int64, anchorDate: AgentBridgeDate)
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type"], optional: ["range", "days", "anchor_date"]).text("type")
        switch tag {
        case "exact": self = .exact(try BridgeObject(bridgeJSON, ["type", "range"]).value("range"))
        case "all_available": _ = try BridgeObject(bridgeJSON, ["type"]); self = .allAvailable
        case "past_complete_days":
            let o = try BridgeObject(bridgeJSON, ["type", "days", "anchor_date"])
            self = .pastCompleteDays(days: try o.int("days", min: 1, max: 3650), anchorDate: try o.value("anchor_date"))
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .exact(let range): return .object([("type", .string("exact")), ("range", range.bridgeJSON)])
        case .allAvailable: return .object([("type", .string("all_available"))])
        case .pastCompleteDays(let days, let anchor): return .object([("type", .string("past_complete_days")), ("days", .int(days)), ("anchor_date", anchor.bridgeJSON)])
        }
    }
    public func resolved() throws -> Self {
        guard case .pastCompleteDays(let days, let anchor) = self else { return self }
        guard (1...3650).contains(days), let date = bridgeDate(anchor.rawValue) else { throw AgentBridgeValidationError.invalidRequest }
        let start = try AgentBridgeDate(bridgeCivil(date.addingTimeInterval(-Double(days) * 86_400)))
        let end = try AgentBridgeDate(bridgeCivil(date.addingTimeInterval(-86_400)))
        return .exact(.init(startDate: start, endDate: end))
    }
}

public struct AgentBridgeDestination: Codable, Equatable, Sendable, BridgeValueCodable {
    public let bindingID: AgentBridgeUUID
    public let identitySHA256: AgentBridgeDigest
    public let revision: Int64
    public let hostInstallationID: AgentBridgeUUID
    public init(bindingID: AgentBridgeUUID, identitySHA256: AgentBridgeDigest, revision: Int64, hostInstallationID: AgentBridgeUUID) {
        self.bindingID = bindingID; self.identitySHA256 = identitySHA256; self.revision = revision; self.hostInstallationID = hostInstallationID
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["binding_id", "identity_sha256", "revision", "host_installation_id"])
        bindingID = try o.value("binding_id"); identitySHA256 = try o.value("identity_sha256"); revision = try o.int("revision", min: 1, max: 2_147_483_647); hostInstallationID = try o.value("host_installation_id")
    }
    var bridgeJSON: BridgeJSON { .object([("binding_id", bindingID.bridgeJSON), ("identity_sha256", identitySHA256.bridgeJSON), ("revision", .int(revision)), ("host_installation_id", hostInstallationID.bridgeJSON)]) }
}

public struct AgentBridgeSelection: Codable, Equatable, Sendable, BridgeValueCodable {
    public let metricIDs: [AgentBridgeID]
    public let categoryIDs: [AgentBridgeID]
    public let sourceIDs: [AgentBridgeID]
    public let providerIDs: [AgentBridgeID]
    public let allMetrics: Bool
    public init(metricIDs: [AgentBridgeID], categoryIDs: [AgentBridgeID], sourceIDs: [AgentBridgeID], providerIDs: [AgentBridgeID], allMetrics: Bool) {
        self.metricIDs = metricIDs; self.categoryIDs = categoryIDs; self.sourceIDs = sourceIDs; self.providerIDs = providerIDs; self.allMetrics = allMetrics
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["metric_ids", "category_ids", "source_ids", "provider_ids", "all_metrics"])
        metricIDs = try o.list("metric_ids", max: 256); categoryIDs = try o.list("category_ids", max: 32); sourceIDs = try o.list("source_ids", min: 1, max: 16); providerIDs = try o.list("provider_ids", max: 16); allMetrics = try o.bool("all_metrics")
        for values in [metricIDs, categoryIDs, sourceIDs, providerIDs] { try bridgeSortedUnique(values.map(\.rawValue)) }
    }
    var bridgeJSON: BridgeJSON { .object([("metric_ids", .values(metricIDs)), ("category_ids", .values(categoryIDs)), ("source_ids", .values(sourceIDs)), ("provider_ids", .values(providerIDs)), ("all_metrics", .bool(allMetrics))]) }
}

public enum AgentBridgeSnapshotFormat: String, Codable, Sendable { case json, ndjson }
public enum AgentBridgeRecordScope: String, Codable, Sendable { case selected, allAuthorizedSupported = "all_authorized_supported" }
public enum AgentBridgeArchive: Codable, Equatable, Sendable, BridgeValueCodable {
    case none, appleHealthKitCanonical
    case androidProviderNativeSnapshot(providerID: AgentBridgeID, recordScope: AgentBridgeRecordScope, format: AgentBridgeSnapshotFormat, includeExerciseRoutes: Bool)
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type"], optional: ["provider_id", "record_scope", "format", "include_exercise_routes"]).text("type")
        switch tag {
        case "none": _ = try BridgeObject(bridgeJSON, ["type"]); self = .none
        case "apple_healthkit_canonical_v1": _ = try BridgeObject(bridgeJSON, ["type"]); self = .appleHealthKitCanonical
        case "android_provider_native_snapshot_v1":
            let o = try BridgeObject(bridgeJSON, ["type", "provider_id", "record_scope", "format", "include_exercise_routes"])
            self = .androidProviderNativeSnapshot(providerID: try o.value("provider_id"), recordScope: try o.token("record_scope"), format: try o.token("format"), includeExerciseRoutes: try o.bool("include_exercise_routes"))
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .none: return .object([("type", .string("none"))])
        case .appleHealthKitCanonical: return .object([("type", .string("apple_healthkit_canonical_v1"))])
        case .androidProviderNativeSnapshot(let provider, let scope, let format, let routes): return .object([("type", .string("android_provider_native_snapshot_v1")), ("provider_id", provider.bridgeJSON), ("record_scope", .string(scope.rawValue)), ("format", .string(format.rawValue)), ("include_exercise_routes", .bool(routes))])
        }
    }
}

public struct AgentBridgeCaptureScope: Codable, Equatable, Sendable, BridgeValueCodable {
    public let selection: AgentBridgeSelection
    public let compatibilityDetail: AgentBridgeDetail
    public let nativeArchive: AgentBridgeArchive
    public init(selection: AgentBridgeSelection, compatibilityDetail: AgentBridgeDetail, nativeArchive: AgentBridgeArchive) { self.selection = selection; self.compatibilityDetail = compatibilityDetail; self.nativeArchive = nativeArchive }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["selection", "compatibility_detail", "native_archive"])
        selection = try o.value("selection"); compatibilityDetail = try o.token("compatibility_detail"); nativeArchive = try o.value("native_archive")
    }
    var bridgeJSON: BridgeJSON { .object([("selection", selection.bridgeJSON), ("compatibility_detail", .string(compatibilityDetail.rawValue)), ("native_archive", nativeArchive.bridgeJSON)]) }
}

public struct AgentBridgeCustomField: Codable, Equatable, Sendable, BridgeValueCodable {
    public let key: AgentBridgeID
    public let value: String
    public init(key: AgentBridgeID, value: String) { self.key = key; self.value = value }
    init(bridgeJSON: BridgeJSON) throws { let o = try BridgeObject(bridgeJSON, ["key", "value"]); key = try o.value("key"); value = try o.text("value", max: 4096) }
    var bridgeJSON: BridgeJSON { .object([("key", key.bridgeJSON), ("value", .string(value))]) }
}

public struct AgentBridgeFrontmatter: Codable, Equatable, Sendable, BridgeValueCodable {
    public let enabledFieldIDs: [AgentBridgeID]
    public let customFields: [AgentBridgeCustomField]
    public let includeUnits: Bool
    public let includeCaptureDiagnostics: Bool
    public init(enabledFieldIDs: [AgentBridgeID], customFields: [AgentBridgeCustomField], includeUnits: Bool, includeCaptureDiagnostics: Bool) { self.enabledFieldIDs = enabledFieldIDs; self.customFields = customFields; self.includeUnits = includeUnits; self.includeCaptureDiagnostics = includeCaptureDiagnostics }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["enabled_field_ids", "custom_fields", "include_units", "include_capture_diagnostics"])
        enabledFieldIDs = try o.list("enabled_field_ids", max: 256); customFields = try o.list("custom_fields", max: 128); includeUnits = try o.bool("include_units"); includeCaptureDiagnostics = try o.bool("include_capture_diagnostics")
        try bridgeUnique(enabledFieldIDs.map(\.rawValue)); try bridgeUnique(customFields.map { $0.key.rawValue })
        guard !customFields.contains(where: { ["schema", "schema_version", "units", "raw_capture_status", "time_context"].contains($0.key.rawValue) }) else { throw AgentBridgeValidationError.invalidRequest }
    }
    var bridgeJSON: BridgeJSON { .object([("enabled_field_ids", .values(enabledFieldIDs)), ("custom_fields", .values(customFields)), ("include_units", .bool(includeUnits)), ("include_capture_diagnostics", .bool(includeCaptureDiagnostics))]) }
}

public enum AgentBridgeMarkdownStyle: String, Codable, Sendable { case tables, lists }
public struct AgentBridgeMarkdown: Codable, Equatable, Sendable, BridgeValueCodable {
    public let style: AgentBridgeMarkdownStyle
    public let customTemplate: String
    public let placeholderIDs: [AgentBridgeID]
    public init(style: AgentBridgeMarkdownStyle, customTemplate: String, placeholderIDs: [AgentBridgeID]) { self.style = style; self.customTemplate = customTemplate; self.placeholderIDs = placeholderIDs }
    init(bridgeJSON: BridgeJSON) throws { let o = try BridgeObject(bridgeJSON, ["style", "custom_template", "placeholder_ids"]); style = try o.token("style"); customTemplate = try o.text("custom_template"); placeholderIDs = try o.list("placeholder_ids", max: 128); try bridgeUnique(placeholderIDs.map(\.rawValue)) }
    var bridgeJSON: BridgeJSON { .object([("style", .string(style.rawValue)), ("custom_template", .string(customTemplate)), ("placeholder_ids", .values(placeholderIDs))]) }
}

public enum AgentBridgeDisplayUnits: String, Codable, Sendable { case metric, imperial }
public struct AgentBridgePresentation: Codable, Equatable, Sendable, BridgeValueCodable {
    public let displayUnits: AgentBridgeDisplayUnits
    public let locale: String
    public let includeMetadata: Bool
    public let groupByCategory: Bool
    public let frontmatter: AgentBridgeFrontmatter
    public let markdown: AgentBridgeMarkdown
    public init(displayUnits: AgentBridgeDisplayUnits, locale: String, includeMetadata: Bool, groupByCategory: Bool, frontmatter: AgentBridgeFrontmatter, markdown: AgentBridgeMarkdown) { self.displayUnits = displayUnits; self.locale = locale; self.includeMetadata = includeMetadata; self.groupByCategory = groupByCategory; self.frontmatter = frontmatter; self.markdown = markdown }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["display_units", "machine_units", "locale", "include_metadata", "group_by_category", "frontmatter", "markdown"])
        try o.constant("machine_units", .string("canonical")); displayUnits = try o.token("display_units"); locale = try o.text("locale", min: 1, max: 64); includeMetadata = try o.bool("include_metadata"); groupByCategory = try o.bool("group_by_category"); frontmatter = try o.value("frontmatter"); markdown = try o.value("markdown")
    }
    var bridgeJSON: BridgeJSON { .object([("display_units", .string(displayUnits.rawValue)), ("machine_units", .string("canonical")), ("locale", .string(locale)), ("include_metadata", .bool(includeMetadata)), ("group_by_category", .bool(groupByCategory)), ("frontmatter", frontmatter.bridgeJSON), ("markdown", markdown.bridgeJSON)]) }
}

public struct AgentBridgeIndividualEntries: Codable, Equatable, Sendable, BridgeValueCodable {
    public let enabled: Bool
    public let metricIDs: [AgentBridgeID]
    public let folderTemplate: String
    public let filenameTemplate: String
    public let categoryFolders: Bool
    public init(enabled: Bool, metricIDs: [AgentBridgeID], folderTemplate: String, filenameTemplate: String, categoryFolders: Bool) { self.enabled = enabled; self.metricIDs = metricIDs; self.folderTemplate = folderTemplate; self.filenameTemplate = filenameTemplate; self.categoryFolders = categoryFolders }
    init(bridgeJSON: BridgeJSON) throws { let o = try BridgeObject(bridgeJSON, ["enabled", "metric_ids", "folder_template", "filename_template", "category_folders"]); enabled = try o.bool("enabled"); metricIDs = try o.list("metric_ids", max: 256); folderTemplate = try o.text("folder_template", max: 4096); filenameTemplate = try o.text("filename_template", min: 1, max: 255); categoryFolders = try o.bool("category_folders"); try bridgeSortedUnique(metricIDs.map(\.rawValue)); try AgentBridgePaths.validate(folderTemplate, tokens: .entries); try AgentBridgePaths.validate(filenameTemplate, filename: true, tokens: .entries) }
    var bridgeJSON: BridgeJSON { .object([("enabled", .bool(enabled)), ("metric_ids", .values(metricIDs)), ("folder_template", .string(folderTemplate)), ("filename_template", .string(filenameTemplate)), ("category_folders", .bool(categoryFolders))]) }
}

public struct AgentBridgeDailyNotes: Codable, Equatable, Sendable, BridgeValueCodable {
    public let enabled: Bool
    public let only: Bool
    public let folderTemplate: String
    public let filenameTemplate: String
    public let createIfMissing: Bool
    public let sectionIDs: [AgentBridgeID]
    public init(enabled: Bool, only: Bool, folderTemplate: String, filenameTemplate: String, createIfMissing: Bool, sectionIDs: [AgentBridgeID]) { self.enabled = enabled; self.only = only; self.folderTemplate = folderTemplate; self.filenameTemplate = filenameTemplate; self.createIfMissing = createIfMissing; self.sectionIDs = sectionIDs }
    init(bridgeJSON: BridgeJSON) throws { let o = try BridgeObject(bridgeJSON, ["enabled", "only", "folder_template", "filename_template", "create_if_missing", "section_ids"]); enabled = try o.bool("enabled"); only = try o.bool("only"); folderTemplate = try o.text("folder_template", max: 4096); filenameTemplate = try o.text("filename_template", min: 1, max: 255); createIfMissing = try o.bool("create_if_missing"); sectionIDs = try o.list("section_ids", max: 64); try bridgeSortedUnique(sectionIDs.map(\.rawValue)); guard !only || enabled else { throw AgentBridgeValidationError.invalidRequest }; try AgentBridgePaths.validate(folderTemplate, tokens: .daily); try AgentBridgePaths.validate(filenameTemplate, filename: true, tokens: .daily) }
    var bridgeJSON: BridgeJSON { .object([("enabled", .bool(enabled)), ("only", .bool(only)), ("folder_template", .string(folderTemplate)), ("filename_template", .string(filenameTemplate)), ("create_if_missing", .bool(createIfMissing)), ("section_ids", .values(sectionIDs))]) }
}

public enum AgentBridgePackaging: Codable, Equatable, Sendable, BridgeValueCodable {
    case looseFiles
    case zip(filenameTemplate: String, includeLooseFiles: Bool, maxUncompressedBytes: Int64, maxEntries: Int64)
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type"], optional: ["filename_template", "include_loose_files", "max_uncompressed_bytes", "max_entries", "manifest"]).text("type")
        switch tag {
        case "loose_files": _ = try BridgeObject(bridgeJSON, ["type"]); self = .looseFiles
        case "zip":
            let o = try BridgeObject(bridgeJSON, ["type", "filename_template", "include_loose_files", "max_uncompressed_bytes", "max_entries", "manifest"])
            try o.constant("manifest", .string("healthmd.agent_artifact_manifest/1")); let name = try o.text("filename_template", min: 1, max: 255); try AgentBridgePaths.validate(name, filename: true, tokens: .daily)
            self = .zip(filenameTemplate: name, includeLooseFiles: try o.bool("include_loose_files"), maxUncompressedBytes: try o.int("max_uncompressed_bytes", min: 1, max: 1_073_741_824), maxEntries: try o.int("max_entries", min: 1, max: 4096))
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .looseFiles: return .object([("type", .string("loose_files"))])
        case .zip(let name, let loose, let bytes, let count): return .object([("type", .string("zip")), ("filename_template", .string(name)), ("include_loose_files", .bool(loose)), ("max_uncompressed_bytes", .int(bytes)), ("max_entries", .int(count)), ("manifest", .string("healthmd.agent_artifact_manifest/1"))])
        }
    }
}

public enum AgentBridgeDictionaryFormat: String, Codable, Sendable { case json, markdown }
public enum AgentBridgeDictionary: Codable, Equatable, Sendable, BridgeValueCodable {
    case none, profileDictionary(format: AgentBridgeDictionaryFormat, filenameTemplate: String)
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type"], optional: ["format", "filename_template"]).text("type")
        switch tag {
        case "none": _ = try BridgeObject(bridgeJSON, ["type"]); self = .none
        case "profile_dictionary_v1":
            let o = try BridgeObject(bridgeJSON, ["type", "format", "filename_template"]); let name = try o.text("filename_template", min: 1, max: 255); try AgentBridgePaths.validate(name, filename: true, tokens: .daily); self = .profileDictionary(format: try o.token("format"), filenameTemplate: name)
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .none: return .object([("type", .string("none"))])
        case .profileDictionary(let format, let name): return .object([("type", .string("profile_dictionary_v1")), ("format", .string(format.rawValue)), ("filename_template", .string(name))])
        }
    }
}

public struct AgentBridgeOutputSettings: Codable, Equatable, Sendable, BridgeValueCodable {
    public let formats: [AgentBridgeFormat]
    public let outputProfile: AgentBridgeOutputProfile
    public let subfolder: String
    public let folderTemplate: String
    public let filenameTemplate: String
    public let writeMode: AgentBridgeWriteMode
    public let presentation: AgentBridgePresentation
    public let individualEntries: AgentBridgeIndividualEntries
    public let dailyNotes: AgentBridgeDailyNotes
    public let packaging: AgentBridgePackaging
    public let dictionary: AgentBridgeDictionary
    public init(formats: [AgentBridgeFormat], outputProfile: AgentBridgeOutputProfile, subfolder: String, folderTemplate: String, filenameTemplate: String, writeMode: AgentBridgeWriteMode, presentation: AgentBridgePresentation, individualEntries: AgentBridgeIndividualEntries, dailyNotes: AgentBridgeDailyNotes, packaging: AgentBridgePackaging, dictionary: AgentBridgeDictionary) { self.formats = formats; self.outputProfile = outputProfile; self.subfolder = subfolder; self.folderTemplate = folderTemplate; self.filenameTemplate = filenameTemplate; self.writeMode = writeMode; self.presentation = presentation; self.individualEntries = individualEntries; self.dailyNotes = dailyNotes; self.packaging = packaging; self.dictionary = dictionary }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["formats", "output_profile", "subfolder", "folder_template", "filename_template", "write_mode", "presentation", "individual_entries", "daily_notes", "packaging", "dictionary"])
        formats = try o.tokens("formats", min: 1, max: 4); outputProfile = try o.token("output_profile"); subfolder = try o.text("subfolder", max: 4096); folderTemplate = try o.text("folder_template", max: 4096); filenameTemplate = try o.text("filename_template", min: 1, max: 255); writeMode = try o.token("write_mode"); presentation = try o.value("presentation"); individualEntries = try o.value("individual_entries"); dailyNotes = try o.value("daily_notes"); packaging = try o.value("packaging"); dictionary = try o.value("dictionary")
        try bridgeSortedUnique(formats.map(\.rawValue)); try AgentBridgePaths.validate(subfolder, tokens: .daily); try AgentBridgePaths.validate(folderTemplate, tokens: .daily); try AgentBridgePaths.validate(filenameTemplate, filename: true, tokens: .daily)
        if [.mergeMarkdown, .mergeMarkdownPreservingPreamble].contains(writeMode), formats != [.markdown] { throw AgentBridgeValidationError.unsupportedCapability }
    }
    var bridgeJSON: BridgeJSON { .object([("formats", bridgeTokens(formats)), ("output_profile", .string(outputProfile.rawValue)), ("subfolder", .string(subfolder)), ("folder_template", .string(folderTemplate)), ("filename_template", .string(filenameTemplate)), ("write_mode", .string(writeMode.rawValue)), ("presentation", presentation.bridgeJSON), ("individual_entries", individualEntries.bridgeJSON), ("daily_notes", dailyNotes.bridgeJSON), ("packaging", packaging.bridgeJSON), ("dictionary", dictionary.bridgeJSON)]) }
}

public enum AgentBridgeSettingsPolicy: Codable, Equatable, Sendable, BridgeValueCodable {
    case explicit(AgentBridgeOutputSettings), savedDeviceSettings(expectedRevision: Int64), profile(profileID: AgentBridgeUUID, expectedRevision: Int64)
    init(bridgeJSON: BridgeJSON) throws {
        let tag = try BridgeObject(bridgeJSON, ["type"], optional: ["settings", "expected_revision", "profile_id"]).text("type")
        switch tag {
        case "explicit": self = .explicit(try BridgeObject(bridgeJSON, ["type", "settings"]).value("settings"))
        case "saved_device_settings": self = .savedDeviceSettings(expectedRevision: try BridgeObject(bridgeJSON, ["type", "expected_revision"]).int("expected_revision", min: 1, max: 2_147_483_647))
        case "profile": let o = try BridgeObject(bridgeJSON, ["type", "profile_id", "expected_revision"]); self = .profile(profileID: try o.value("profile_id"), expectedRevision: try o.int("expected_revision", min: 1, max: 2_147_483_647))
        default: throw AgentBridgeValidationError.invalidRequest
        }
    }
    var bridgeJSON: BridgeJSON {
        switch self {
        case .explicit(let settings): return .object([("type", .string("explicit")), ("settings", settings.bridgeJSON)])
        case .savedDeviceSettings(let revision): return .object([("type", .string("saved_device_settings")), ("expected_revision", .int(revision))])
        case .profile(let id, let revision): return .object([("type", .string("profile")), ("profile_id", id.bridgeJSON), ("expected_revision", .int(revision))])
        }
    }
}

/// Bounded generated-files branch. The source-projection product has no forwarding fallback.
public struct AgentBridgeGeneratedIntent: Codable, Equatable, Sendable, BridgeValueCodable {
    public let intentID: AgentBridgeUUID
    public let peer: AgentBridgePeer
    public let destination: AgentBridgeDestination
    public let dates: AgentBridgeDates
    public let calendarTimezone: AgentBridgeZone
    public let captureScope: AgentBridgeCaptureScope
    public let settingsPolicy: AgentBridgeSettingsPolicy
    public init(intentID: AgentBridgeUUID, peer: AgentBridgePeer, destination: AgentBridgeDestination, dates: AgentBridgeDates, calendarTimezone: AgentBridgeZone, captureScope: AgentBridgeCaptureScope, settingsPolicy: AgentBridgeSettingsPolicy) { self.intentID = intentID; self.peer = peer; self.destination = destination; self.dates = dates; self.calendarTimezone = calendarTimezone; self.captureScope = captureScope; self.settingsPolicy = settingsPolicy }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "intent_id", "peer", "destination", "dates", "calendar_timezone", "timestamp_timezone", "capture_scope", "product", "settings_policy"])
        try o.schema("healthmd.agent_export_intent"); try o.constant("timestamp_timezone", .string("UTC")); let product = try BridgeObject(o.node("product"), ["type"]); guard try product.text("type") == "generated_files" else { throw AgentBridgeValidationError.unsupportedCapability }
        intentID = try o.value("intent_id"); peer = try o.value("peer"); destination = try o.value("destination"); dates = try o.value("dates"); calendarTimezone = try o.value("calendar_timezone"); captureScope = try o.value("capture_scope"); settingsPolicy = try o.value("settings_policy")
        guard destination.hostInstallationID == peer.hostInstallationID else { throw AgentBridgeValidationError.bindingChanged }
        let selection = captureScope.selection
        guard selection.sourceIDs.map(\.rawValue) == [peer.platform == .apple ? "apple_health" : "health_connect"], selection.providerIDs.isEmpty else { throw AgentBridgeValidationError.unsupportedCapability }
        switch captureScope.nativeArchive {
        case .none: break
        case .appleHealthKitCanonical: guard peer.platform == .apple else { throw AgentBridgeValidationError.unsupportedCapability }
        case .androidProviderNativeSnapshot(let provider, let scope, _, _):
            guard peer.platform == .android, provider.rawValue == "health_connect" else { throw AgentBridgeValidationError.unsupportedCapability }
            guard scope != .allAuthorizedSupported || selection.allMetrics else { throw AgentBridgeValidationError.bindingChanged }
        }
        if case .explicit(let settings) = settingsPolicy {
            guard (settings.outputProfile == .appleV8) == (peer.platform == .apple) else { throw AgentBridgeValidationError.unsupportedCapability }
        }
    }
    var bridgeJSON: BridgeJSON { .object([("schema", .string("healthmd.agent_export_intent")), ("schema_version", .int(1)), ("intent_id", intentID.bridgeJSON), ("peer", peer.bridgeJSON), ("destination", destination.bridgeJSON), ("dates", dates.bridgeJSON), ("calendar_timezone", calendarTimezone.bridgeJSON), ("timestamp_timezone", .string("UTC")), ("capture_scope", captureScope.bridgeJSON), ("product", .object([("type", .string("generated_files"))])), ("settings_policy", settingsPolicy.bridgeJSON)]) }
}

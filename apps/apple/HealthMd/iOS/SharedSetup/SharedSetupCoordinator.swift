import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let healthMdConfiguration = UTType(exportedAs: "com.healthmd.configuration", conformingTo: .json)
}

enum SharedSetupLoadedPreview: Equatable, Sendable {
    case v1(SharedSetupPreview)
    case v2(SharedSetupV2ImportPlan)

    var hasInvalidItems: Bool {
        switch self {
        case .v1(let preview): preview.hasInvalidItems
        case .v2(let preview): preview.hasInvalidItems
        }
    }
}

enum SharedSetupV2CoordinatorApplyMode: String, Equatable, Sendable {
    case add
    case replace
}

struct SharedSetupV2CoordinatorResult: Equatable, Sendable {
    var appliedItems: [String]
    var attentionItems: [String]

    init(appliedItems: [String] = [], attentionItems: [String] = []) {
        self.appliedItems = appliedItems
        self.attentionItems = attentionItems
    }
}

enum SharedSetupV2CoordinatorError: LocalizedError, Equatable {
    case transactionUnavailable
    case noLoadedPreview
    case invalidPreview
    case invalidSelection
    case noUndoSnapshot
    case metricRegistryUnavailable

    var errorDescription: String? {
        switch self {
        case .transactionUnavailable:
            "Shared Setup v2 cannot be applied until a verified transaction and Undo adapter is installed."
        case .noLoadedPreview:
            "There is no Shared Setup v2 preview to apply."
        case .invalidPreview:
            "This Shared Setup v2 plan is invalid and cannot be applied."
        case .invalidSelection:
            "Choose one or more valid Shared Setup v2 profiles explicitly."
        case .noUndoSnapshot:
            "There is no Shared Setup v2 import to undo."
        case .metricRegistryUnavailable:
            "The metric registry is unavailable."
        }
    }
}

/// Small production seam for the separately owned v2 transaction lane. The
/// adapter accepts an already validated, write-free plan plus an explicit
/// selection and mode. Its transaction remains the authority for durable
/// Add/Replace validation, rollback, and one-shot Undo.
struct SharedSetupV2CoordinatorAdapter {
    var apply: @MainActor (
        SharedSetupV2ImportPlan,
        [String],
        SharedSetupV2CoordinatorApplyMode
    ) throws -> SharedSetupV2CoordinatorResult
    var undo: @MainActor () throws -> SharedSetupV2CoordinatorResult
    var canUndo: @MainActor () -> Bool
}

/// Immutable value snapshots supplied by the profile/destination/schedule
/// owners. Construction copies every collection before the pure mapper runs;
/// the coordinator never opens a destination or reads credentials.
struct SharedSetupV2ExportContext {
    let profiles: [ExportProfile]
    let activeProfileID: UUID?
    let destinations: SharedSetupV2DestinationSnapshots
    let scheduledEntries: [ScheduledExportEntry]
    let preservedAndroidExtensions: [UUID: SharedSetupV2.AndroidExtension]

    init(
        profiles: [ExportProfile],
        activeProfileID: UUID?,
        destinationVaults: [SavedVaultDestination],
        destinationAPIEndpoints: [SavedAPIEndpoint],
        scheduledEntries: [ScheduledExportEntry],
        preservedAndroidExtensions: [UUID: SharedSetupV2.AndroidExtension]
    ) {
        self.profiles = Array(profiles)
        self.activeProfileID = activeProfileID
        self.destinations = SharedSetupV2DestinationSnapshots(
            vaults: Array(destinationVaults),
            apiEndpoints: Array(destinationAPIEndpoints)
        )
        self.scheduledEntries = Array(scheduledEntries)
        self.preservedAndroidExtensions = Dictionary(
            uniqueKeysWithValues: preservedAndroidExtensions.map { ($0.key, $0.value) }
        )
    }
}

struct SharedSetupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.healthMdConfiguration, .json] }
    static var writableContentTypes: [UTType] { [.healthMdConfiguration] }
    var data: Data

    init(data: Data) throws {
        self.data = try Self.validatedContents(data)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents,
              contents.count <= SharedSetupV2.maximumEncodedBytes else {
            throw SharedSetupV2Error.oversized(
                maximumBytes: SharedSetupV2.maximumEncodedBytes
            )
        }
        data = try Self.validatedContents(contents)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try validatedContentsForWriting())
    }

    func validatedContentsForWriting() throws -> Data {
        try Self.validatedContents(data)
    }

    static func validatedContents(_ data: Data) throws -> Data {
        _ = try SharedSetupVersionedCodec.decode(data)
        return data
    }
}

@MainActor
final class SharedSetupCoordinator: ObservableObject {
    // Keep deallocation on the releasing thread. Avoid Swift 6.2+'s crashing
    // isolated-deinit executor hop (swiftlang/swift#85663), which aborted CI
    // test processes when the last release happened off the main actor.
    nonisolated deinit {}
    enum RouteSource: Equatable { case fileImporter; case coldOpen; case warmOpen; case onboarding }

    @Published private(set) var loadedPreview: SharedSetupLoadedPreview?
    @Published private(set) var result: SharedSetupApplyResult?
    @Published private(set) var v2Result: SharedSetupV2CoordinatorResult?
    @Published var isFlowPresented = false
    @Published var errorMessage: String?
    @Published private(set) var lastRouteSource: RouteSource?

    /// Historical v1 convenience API retained for existing callers and tests.
    var preview: SharedSetupPreview? {
        guard case .v1(let preview) = loadedPreview else { return nil }
        return preview
    }

    var v2Preview: SharedSetupV2ImportPlan? {
        guard case .v2(let preview) = loadedPreview else { return nil }
        return preview
    }

    let settings: AdvancedExportSettings
    let apiExportSettings: APIExportSettings
    private let schedulingManager: SchedulingManager
    private let transaction: SharedSetupTransaction
    private let registry: SharedSetupMetricRegistry?
    private let fileManager: FileManager
    private let externalFileReader: @Sendable (URL) async throws -> Data
    private let accessibilityAnnouncer: @MainActor (String) -> Void
    private let v2Adapter: SharedSetupV2CoordinatorAdapter?
    private var importTask: Task<Void, Never>?
    private var importRequestID = 0

    init(
        settings: AdvancedExportSettings? = nil,
        apiExportSettings: APIExportSettings? = nil,
        schedulingManager: SchedulingManager? = nil,
        userDefaults: UserDefaults = .standard,
        registry: SharedSetupMetricRegistry?? = nil,
        fileManager: FileManager = .default,
        externalFileReader: @escaping @Sendable (URL) async throws -> Data = {
            try await SharedSetupCoordinator.readBoundedFile($0)
        },
        accessibilityAnnouncer: @escaping @MainActor @Sendable (String) -> Void = {
            UIAccessibility.post(notification: .announcement, argument: $0)
        },
        v2Adapter: SharedSetupV2CoordinatorAdapter? = nil
    ) {
        // Default argument expressions are evaluated in a nonisolated context (SE-0411),
        // so MainActor-isolated defaults are resolved inside the initializer body instead.
        let resolvedSettings = settings ?? AdvancedExportSettings()
        let resolvedAPIExportSettings = apiExportSettings ?? APIExportSettings()
        let resolvedSchedulingManager = schedulingManager ?? .shared
        let resolvedRegistry = registry ?? (try? SharedSetupMetricRegistry.current())
        self.settings = resolvedSettings
        self.apiExportSettings = resolvedAPIExportSettings
        self.schedulingManager = resolvedSchedulingManager
        self.transaction = SharedSetupTransaction(
            settings: resolvedSettings,
            apiExportSettings: resolvedAPIExportSettings,
            schedulingManager: resolvedSchedulingManager,
            userDefaults: userDefaults
        )
        self.registry = resolvedRegistry
        self.fileManager = fileManager
        self.externalFileReader = externalFileReader
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.v2Adapter = v2Adapter
    }

    var canUndo: Bool { transaction.canUndo }
    var canUndoV2: Bool { v2Adapter?.canUndo() ?? false }
    var isV2TransactionAvailable: Bool { v2Adapter != nil }
    var pendingEndpointHint: String? { transaction.pendingEndpointHint }

    func beginImport(source: RouteSource = .fileImporter) {
        lastRouteSource = source
    }

    func handleImportedURL(_ url: URL, source: RouteSource = .fileImporter) {
        lastRouteSource = source
        importTask?.cancel()
        importRequestID &+= 1
        let requestID = importRequestID
        let accessed = url.startAccessingSecurityScopedResource()
        let reader = externalFileReader
        let readTask = Task.detached(priority: .userInitiated) {
            try await reader(url)
        }
        importTask = Task { @MainActor in
            defer {
                readTask.cancel()
                if accessed { url.stopAccessingSecurityScopedResource() }
                if requestID == importRequestID { importTask = nil }
            }
            do {
                let data = try await withTaskCancellationHandler {
                    try await readTask.value
                } onCancel: {
                    readTask.cancel()
                }
                guard !Task.isCancelled, requestID == importRequestID else { return }
                try load(data)
            } catch is CancellationError {
                // A newer document owns the route; never let the older read overwrite its preview.
            } catch {
                guard requestID == importRequestID else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    func handleOpenURL(_ url: URL, cold: Bool) -> Bool {
        guard url.isFileURL, url.pathExtension.lowercased() == "healthmdconfig" else { return false }
        handleImportedURL(url, source: cold ? .coldOpen : .warmOpen)
        return true
    }

    func load(_ data: Data) throws {
        switch try SharedSetupVersionedCodec.decode(data) {
        case .v1(let document):
            let candidate = SharedSetupMapper.preview(document, registry: registry)
            guard !candidate.hasInvalidItems else {
                throw SharedSetupError.invalid(
                    candidate.items.first(where: { $0.status == .invalid })?.detail ??
                        "The setup is invalid."
                )
            }
            loadedPreview = .v1(candidate)
        case .v2(let document):
            guard let registry else {
                throw SharedSetupV2CoordinatorError.metricRegistryUnavailable
            }
            // Mapping is pure. Keep even an invalid local compatibility plan
            // reviewable, but never expose it as eligible for Apply.
            loadedPreview = .v2(SharedSetupV2Mapper.preview(document, registry: registry))
        }
        result = nil
        v2Result = nil
        errorMessage = nil
        isFlowPresented = true
    }

    func apply() {
        guard case .v1(let preview) = loadedPreview else { return }
        do {
            result = try transaction.apply(preview)
            accessibilityAnnouncer(
                String(localized: "Shared Setup applied. Review items requiring attention, then finish setup.")
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func canApplyV2(selectedBundleIDs: [String]) -> Bool {
        guard v2Adapter != nil,
              case .v2(let plan) = loadedPreview,
              !plan.hasInvalidItems else {
            return false
        }
        return Self.isValidV2Selection(selectedBundleIDs, in: plan)
    }

    @discardableResult
    func applyV2(
        selectedBundleIDs: [String],
        mode: SharedSetupV2CoordinatorApplyMode
    ) throws -> SharedSetupV2CoordinatorResult {
        do {
            guard let v2Adapter else {
                throw SharedSetupV2CoordinatorError.transactionUnavailable
            }
            guard case .v2(let plan) = loadedPreview else {
                throw SharedSetupV2CoordinatorError.noLoadedPreview
            }
            guard !plan.hasInvalidItems else {
                throw SharedSetupV2CoordinatorError.invalidPreview
            }
            guard Self.isValidV2Selection(selectedBundleIDs, in: plan) else {
                throw SharedSetupV2CoordinatorError.invalidSelection
            }

            let outcome = try v2Adapter.apply(plan, Array(selectedBundleIDs), mode)
            result = nil
            v2Result = outcome
            errorMessage = nil
            accessibilityAnnouncer(
                String(localized: "Shared Setup profiles applied. Complete local destination setup before exporting.")
            )
            return outcome
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func undo() {
        do {
            result = try transaction.undo()
            accessibilityAnnouncer(String(localized: "Shared Setup import undone"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func undoV2() throws -> SharedSetupV2CoordinatorResult {
        do {
            guard let v2Adapter else {
                throw SharedSetupV2CoordinatorError.transactionUnavailable
            }
            guard v2Adapter.canUndo() else {
                throw SharedSetupV2CoordinatorError.noUndoSnapshot
            }
            let outcome = try v2Adapter.undo()
            result = nil
            v2Result = outcome
            errorMessage = nil
            accessibilityAnnouncer(String(localized: "Shared Setup profile import undone"))
            return outcome
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func confirmPendingEndpoint(authorization: String) {
        do {
            try transaction.confirmPendingEndpoint(authorization: authorization)
            if var updated = result {
                updated.appliedItems.append("API endpoint confirmed with a new local credential")
                updated.attentionItems.removeAll { $0.hasPrefix("API endpoint:") }
                result = updated
            } else {
                objectWillChange.send()
            }
            accessibilityAnnouncer(String(localized: "API endpoint confirmed"))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish() {
        importTask?.cancel()
        importTask = nil
        importRequestID &+= 1
        loadedPreview = nil
        result = nil
        v2Result = nil
        isFlowPresented = false
    }

    /// The production default deliberately remains the shipped v1 writer. A
    /// post-merge caller must opt into the explicit v2 context API only after
    /// installing a verified v2 transaction/Undo adapter.
    func exportData(appVersion: String) throws -> Data {
        let document = try SharedSetupMapper.exportDocument(
            settings: settings,
            schedule: schedulingManager.schedule,
            apiExportSettings: apiExportSettings,
            appVersion: appVersion,
            preservedAndroidExtension: transaction.preservedAndroidExtension,
            registry: registry
        )
        return try SharedSetupCodec.encode(document)
    }

    func exportV2Data(
        context: SharedSetupV2ExportContext,
        appVersion: String,
        calendar: Calendar
    ) throws -> Data {
        guard let registry else {
            throw SharedSetupV2CoordinatorError.metricRegistryUnavailable
        }

        // Take a second call-boundary copy so mapping cannot observe later
        // mutations of collection storage supplied by a production owner.
        let profiles = Array(context.profiles)
        let destinations = SharedSetupV2DestinationSnapshots(
            vaults: Array(context.destinations.vaults),
            apiEndpoints: Array(context.destinations.apiEndpoints)
        )
        let schedules = Array(context.scheduledEntries)
        let preservedExtensions = Dictionary(
            uniqueKeysWithValues: context.preservedAndroidExtensions.map { ($0.key, $0.value) }
        )
        let document = try SharedSetupV2Mapper.exportDocument(
            profiles: profiles,
            activeProfileID: context.activeProfileID,
            destinations: destinations,
            scheduledEntries: schedules,
            registry: registry,
            appVersion: appVersion,
            preservedAndroidExtensions: preservedExtensions,
            calendar: calendar
        )
        return try SharedSetupV2Codec.encode(document)
    }

    func makeShareArtifact(appVersion: String) throws -> URL {
        try makeValidatedShareArtifact(exportData(appVersion: appVersion))
    }

    func makeV2ShareArtifact(
        context: SharedSetupV2ExportContext,
        appVersion: String,
        calendar: Calendar
    ) throws -> URL {
        try makeValidatedShareArtifact(
            exportV2Data(context: context, appVersion: appVersion, calendar: calendar)
        )
    }

    private func makeValidatedShareArtifact(_ data: Data) throws -> URL {
        let validated = try SharedSetupDocument.validatedContents(data)
        let directory = fileManager.temporaryDirectory.appendingPathComponent(
            "SharedSetup",
            isDirectory: true
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Health-md-Setup.healthmdconfig")
        try validated.write(to: url, options: .atomic)
        return url
    }

    func removeShareArtifact(_ url: URL?) {
        guard let url else { return }
        try? fileManager.removeItem(at: url)
        let directory = url.deletingLastPathComponent()
        if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
            try? fileManager.removeItem(at: directory)
        }
    }

    nonisolated static func readBoundedFile(_ url: URL) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let maximum = SharedSetupV2.maximumEncodedBytes
        var data = Data()
        data.reserveCapacity(min(64 * 1_024, maximum))
        while true {
            try Task.checkCancellation()
            // Once `maximum` bytes have been retained, request exactly one
            // more byte as the overflow probe. Chunk requests before that are
            // capped by the same maximum + 1 total-read budget.
            let remainingProbeBudget = maximum + 1 - data.count
            guard remainingProbeBudget > 0 else {
                throw SharedSetupV2Error.oversized(maximumBytes: maximum)
            }
            let chunkSize = min(64 * 1_024, remainingProbeBudget)
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                return data
            }
            data.append(chunk)
            guard data.count <= maximum else {
                throw SharedSetupV2Error.oversized(maximumBytes: maximum)
            }
        }
    }

    private static func isValidV2Selection(
        _ selectedBundleIDs: [String],
        in plan: SharedSetupV2ImportPlan
    ) -> Bool {
        guard !selectedBundleIDs.isEmpty,
              Set(selectedBundleIDs).count == selectedBundleIDs.count else {
            return false
        }
        let validProfiles = Dictionary(
            uniqueKeysWithValues: plan.profiles.map { ($0.bundleID, $0) }
        )
        return selectedBundleIDs.allSatisfy { bundleID in
            guard let profile = validProfiles[bundleID] else { return false }
            return !profile.hasInvalidItems
        }
    }
}

struct SharedSetupFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject var coordinator: SharedSetupCoordinator

    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        // SwiftUI's fileImporter can fail to present in iOS simulator and
        // development builds that also host the performance-lab importer.
        // Exercise the same native document picker through UIKit there.
        uiKitImporter(content)
        #else
        if #available(iOS 26.0, *) {
            // iOS 26 has the same presentation regression in production.
            uiKitImporter(content)
        } else {
            content.fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.healthMdConfiguration, .json],
                allowsMultipleSelection: false,
                onCompletion: completeImport
            )
        }
        #endif
    }

    private func uiKitImporter(_ content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            SharedSetupSystemDocumentPicker(
                onCompletion: completeImport,
                onCancel: { isPresented = false }
            )
            .ignoresSafeArea()
        }
    }

    private func completeImport(_ result: Result<[URL], Error>) {
        isPresented = false
        if case .success(let urls) = result, let url = urls.first {
            coordinator.handleImportedURL(
                url,
                source: coordinator.lastRouteSource ?? .fileImporter
            )
        } else if case .failure(let error) = result {
            coordinator.errorMessage = error.localizedDescription
        }
    }
}

private struct SharedSetupSystemDocumentPicker: UIViewControllerRepresentable {
    let onCompletion: (Result<[URL], Error>) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.healthMdConfiguration, .json],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Result<[URL], Error>) -> Void
        let onCancel: () -> Void

        init(
            onCompletion: @escaping (Result<[URL], Error>) -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onCompletion = onCompletion
            self.onCancel = onCancel
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            onCompletion(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}

extension View {
    func sharedSetupFileImporter(
        isPresented: Binding<Bool>,
        coordinator: SharedSetupCoordinator
    ) -> some View {
        modifier(SharedSetupFileImporter(isPresented: isPresented, coordinator: coordinator))
    }
}

private struct SharedSetupActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct SharedSetupFlowView: View {
    @ObservedObject var coordinator: SharedSetupCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let result = coordinator.result {
                    success(result)
                } else if let result = coordinator.v2Result {
                    v2Success(result)
                } else if let loadedPreview = coordinator.loadedPreview {
                    switch loadedPreview {
                    case .v1(let preview): review(preview)
                    case .v2(let preview): v2Review(preview)
                    }
                } else {
                    ContentUnavailableView(
                        "No Setup Selected",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Choose a .healthmdconfig file to review.")
                    )
                }
            }
            .navigationTitle(
                coordinator.result == nil && coordinator.v2Result == nil
                    ? "Review Shared Setup"
                    : "Setup Applied"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { coordinator.finish(); dismiss() } } }
        }
    }

    private func review(_ preview: SharedSetupPreview) -> some View {
        List {
            Section("Overview") {
                LabeledContent("Formats", value: preview.document.profile.export.formats.map(\.rawValue).joined(separator: ", "))
                LabeledContent("Selected metrics", value: "\(preview.selectedMetricCount)")
                LabeledContent("Naming", value: preview.document.profile.export.filenameTemplate)
                LabeledContent("Units", value: preview.document.profile.presentation.units.rawValue.capitalized)
                LabeledContent("Daily Notes", value: preview.document.profile.dailyNotes.enabled ? "On" : "Off")
                LabeledContent("Individual entries", value: preview.document.profile.individualEntries.enabled ? "On" : "Off")
            }
            if preview.document.profile.presentation.markdown.style == .custom || !preview.document.profile.presentation.frontmatter.customValues.isEmpty {
                Section("Custom Content") { Text("Custom templates and frontmatter are copied verbatim. Review them for personal, tenant, routing, or secret text.") }
            }
            Section("Automation") {
                Text("Schedule: \(preview.document.profile.schedule.cadence.value) \(preview.document.profile.schedule.cadence.unit.rawValue) at \(String(format: "%02d:%02d", preview.document.profile.schedule.localTime.hour, preview.document.profile.schedule.localTime.minute)); will remain off.")
                if let endpoint = preview.document.profile.apiEndpoint { Text("Endpoint: \(endpoint.host)\(endpoint.path). Authentication not included; confirmation and credentials are required.") }
            }
            Section("Compatibility") {
                ForEach(preview.items) { item in
                    HStack(alignment: .top) {
                        Image(systemName: icon(item.status)).foregroundStyle(color(item.status)).accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(statusTitle(item.status)).font(.caption.bold()).foregroundStyle(color(item.status))
                            Text(item.title).font(.headline)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(statusTitle(item.status)): \(item.title). \(item.detail)")
                }
            }
            Section("Still required on this device") { Text("Choose folders, grant Apple Health access, confirm purchases/entitlements, enter endpoint credentials, and enable automation locally. Existing device state is not changed.") }
            Section {
                Button("Apply Shared Setup") { coordinator.apply() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.apply)
            }
        }
    }

    private func v2Review(_ preview: SharedSetupV2ImportPlan) -> some View {
        List {
            Section("Bundle overview") {
                LabeledContent("Version", value: "2")
                LabeledContent("Profiles", value: "\(preview.document.profiles.count)")
                LabeledContent("Active sender profile", value: preview.activeBundleID)
                Text("This is a read-only review. Loading and changing future profile selection perform no writes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !preview.items.isEmpty {
                Section("Bundle compatibility") {
                    ForEach(preview.items) { compatibilityRow($0) }
                }
            }

            ForEach(preview.document.profiles, id: \.bundleID) { profile in
                Section {
                    LabeledContent("Bundle ID", value: profile.bundleID)
                    LabeledContent(
                        "Formats",
                        value: profile.export.formats.isEmpty
                            ? "None"
                            : profile.export.formats.map(\.rawValue).joined(separator: ", ")
                    )
                    LabeledContent("Selected metrics", value: "\(profile.metrics.enabledIDs.count)")
                    LabeledContent("Destination", value: destinationSummary(profile.destination))
                    LabeledContent("Schedule", value: scheduleSummary(profile.schedule))

                    let hasCustomContent = profile.presentation.markdown.style == .custom ||
                        !profile.presentation.frontmatter.customValues.isEmpty
                    LabeledContent(
                        "Custom content",
                        value: hasCustomContent ? "Included — review verbatim" : "None"
                    )
                    if hasCustomContent {
                        DisclosureGroup("Review custom content") {
                            if profile.presentation.markdown.style == .custom {
                                Text("Custom Markdown")
                                    .font(.caption.bold())
                                Text(profile.presentation.markdown.customText)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                            ForEach(
                                profile.presentation.frontmatter.customValues.keys.sorted(),
                                id: \.self
                            ) { key in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key).font(.caption.bold())
                                    Text(profile.presentation.frontmatter.customValues[key] ?? "")
                                        .font(.caption.monospaced())
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    if let profilePlan = preview.profiles.first(where: {
                        $0.bundleID == profile.bundleID
                    }) {
                        ForEach(profilePlan.items) { compatibilityRow($0) }
                    }
                } header: {
                    Text("\(profile.name) · \(profile.bundleID)")
                }
            }

            Section("Apply unavailable") {
                if preview.hasInvalidItems {
                    Text("This plan contains invalid items and cannot be applied.")
                } else if coordinator.isV2TransactionAvailable {
                    Text("A transaction adapter is present, but profile selection and local destination rebinding are not exposed by this read-only review yet.")
                } else {
                    Text("No verified Shared Setup v2 Add/Replace/Undo adapter is installed. The production Share action continues to write version 1.")
                }
                Button("Apply Shared Setup v2") {}
                    .disabled(true)
            }
        }
    }

    private func success(_ result: SharedSetupApplyResult) -> some View {
        List {
            Section("Applied items") { ForEach(result.appliedItems, id: \.self) { Label($0, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            Section("Items requiring attention") {
                if result.attentionItems.isEmpty { Text("None") }
                else { ForEach(result.attentionItems, id: \.self) { Text($0) } }
            }
            if coordinator.pendingEndpointHint != nil {
                Section("Finish API endpoint setup") {
                    SharedSetupEndpointConfirmation(coordinator: coordinator)
                }
            }
            Section {
                Button("Undo") { coordinator.undo() }
                    .disabled(!coordinator.canUndo)
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.undo)
                Button("Finish Setup") { coordinator.finish(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.finish)
            }
        }
    }

    private func v2Success(_ result: SharedSetupV2CoordinatorResult) -> some View {
        List {
            Section("Applied items") {
                if result.appliedItems.isEmpty {
                    Text("None reported")
                } else {
                    ForEach(result.appliedItems, id: \.self) {
                        Label($0, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                }
            }
            Section("Items requiring attention") {
                if result.attentionItems.isEmpty { Text("None") }
                else { ForEach(result.attentionItems, id: \.self) { Text($0) } }
            }
            Section {
                Button("Undo") {
                    do { _ = try coordinator.undoV2() } catch { /* Published by coordinator. */ }
                }
                .disabled(!coordinator.canUndoV2)
                Button("Finish Setup") { coordinator.finish(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.finish)
            }
        }
    }

    @ViewBuilder
    private func compatibilityRow(_ item: SharedSetupV2CompatibilityItem) -> some View {
        HStack(alignment: .top) {
            Image(systemName: icon(item.status))
                .foregroundStyle(color(item.status))
                .accessibilityHidden(true)
            VStack(alignment: .leading) {
                Text(statusTitle(item.status))
                    .font(.caption.bold())
                    .foregroundStyle(color(item.status))
                Text(item.title).font(.headline)
                Text(item.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusTitle(item.status)): \(item.title). \(item.detail)")
    }

    private func destinationSummary(_ destination: SharedSetupV2.Destination) -> String {
        switch destination.kind {
        case .deviceFolder:
            "Device folder — local access required"
        case .connectedMac:
            "Connected Mac — local pairing required"
        case .cloud:
            "Cloud — unsupported, preserved only"
        case .apiEndpoint:
            if let endpoint = destination.apiEndpoint {
                "API endpoint \(endpoint.host)\(endpoint.path) — credentials required"
            } else {
                "API endpoint — not configured"
            }
        }
    }

    private func scheduleSummary(_ schedule: SharedSetupV2.Schedule?) -> String {
        guard let schedule else { return "None" }
        return "\(schedule.cadence.value) \(schedule.cadence.unit.rawValue) from \(schedule.cadence.anchorDate), weekday \(schedule.weekday), \(String(format: "%02d:%02d", schedule.localTime.hour, schedule.localTime.minute)), \(schedule.lookbackDays)-day lookback — remains off"
    }

    private func icon(_ status: SharedSetupCompatibilityStatus) -> String { switch status { case .applied: "checkmark.circle.fill"; case .requiresAction: "exclamationmark.circle.fill"; case .unsupported: "minus.circle.fill"; case .invalid: "xmark.octagon.fill" } }
    private func color(_ status: SharedSetupCompatibilityStatus) -> Color { switch status { case .applied: .green; case .requiresAction: .orange; case .unsupported: .secondary; case .invalid: .red } }
    private func statusTitle(_ status: SharedSetupCompatibilityStatus) -> String { switch status { case .applied: String(localized: "Applied"); case .requiresAction: String(localized: "Requires action"); case .unsupported: String(localized: "Unsupported"); case .invalid: String(localized: "Invalid") } }
}

struct SharedSetupConfigurationCard: View {
    @ObservedObject var coordinator: SharedSetupCoordinator
    @State private var isImporterPresented = false
    @State private var exportDocument: SharedSetupDocument?
    @State private var isExporterPresented = false
    @State private var shareURL: URL?
    private var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Share My Setup", systemImage: "person.2.badge.gearshape")
                .font(.headline)
                .accessibilityIdentifier(AccessibilityID.SharedSetup.configurationCard)
            Text("Share export preferences—not health data, permissions, credentials, purchases, or device access. Custom Markdown, frontmatter values, and endpoint host/path are copied verbatim, so review them for personal, tenant, routing, or secret text before sending.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Use a Shared Setup") {
                    coordinator.beginImport()
                    isImporterPresented = true
                }
                .accessibilityIdentifier(AccessibilityID.SharedSetup.use)
                .sharedSetupFileImporter(
                    isPresented: $isImporterPresented,
                    coordinator: coordinator
                )
                Spacer()
                Menu("Share") {
                    Button("Save to Files") { prepareExport() }
                    Button("System Share") { prepareShare() }
                }
                .accessibilityIdentifier(AccessibilityID.SharedSetup.share)
            }
            if coordinator.pendingEndpointHint != nil {
                Divider()
                SharedSetupEndpointConfirmation(coordinator: coordinator)
            }
        }
        .fileExporter(isPresented: $isExporterPresented, document: exportDocument, contentType: .healthMdConfiguration, defaultFilename: "Health-md-Setup.healthmdconfig") { result in
            if case .failure(let error) = result { coordinator.errorMessage = error.localizedDescription }
        }
        .sheet(item: Binding(
            get: { shareURL.map(ShareURL.init) },
            set: { value in
                if value == nil {
                    coordinator.removeShareArtifact(shareURL)
                    shareURL = nil
                }
            }
        )) { item in
            SharedSetupActivityView(url: item.url)
        }
    }

    private func prepareExport() { do { exportDocument = try SharedSetupDocument(data: coordinator.exportData(appVersion: appVersion)); isExporterPresented = true } catch { coordinator.errorMessage = error.localizedDescription } }
    private func prepareShare() { do { shareURL = try coordinator.makeShareArtifact(appVersion: appVersion) } catch { coordinator.errorMessage = error.localizedDescription } }
    private struct ShareURL: Identifiable { let url: URL; var id: URL { url } }
}

private struct SharedSetupEndpointConfirmation: View {
    @ObservedObject var coordinator: SharedSetupCoordinator
    @State private var authorization = ""

    var body: some View {
        if let endpoint = coordinator.pendingEndpointHint {
            VStack(alignment: .leading, spacing: 8) {
                Text(endpoint).font(.caption.monospaced()).textSelection(.enabled)
                Text("Confirm this imported endpoint by entering a new credential. Existing credentials are never inherited.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Bearer token or Authorization value", text: $authorization)
                    .textContentType(.password)
                    .privacySensitive()
                    .accessibilityLabel("New local API endpoint credential")
                Button("Confirm Endpoint and Save Credential") {
                    coordinator.confirmPendingEndpoint(authorization: authorization)
                    if coordinator.pendingEndpointHint == nil { authorization = "" }
                }
                .disabled(authorization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

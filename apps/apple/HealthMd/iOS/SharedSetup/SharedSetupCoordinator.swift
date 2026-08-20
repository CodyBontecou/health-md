import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let healthMdConfiguration = UTType(exportedAs: "com.healthmd.configuration", conformingTo: .json)
}

struct SharedSetupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.healthMdConfiguration, .json] }
    static var writableContentTypes: [UTType] { [.healthMdConfiguration] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents,
              contents.count <= SharedSetupV1.maximumEncodedBytes else { throw SharedSetupError.oversized }
        _ = try SharedSetupCodec.decode(contents)
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
final class SharedSetupCoordinator: ObservableObject {
    // Keep deallocation on the releasing thread. Avoid Swift 6.2+'s crashing
    // isolated-deinit executor hop (swiftlang/swift#85663), which aborted CI
    // test processes when the last release happened off the main actor.
    nonisolated deinit {}
    enum RouteSource: Equatable { case fileImporter; case coldOpen; case warmOpen; case onboarding }

    @Published private(set) var preview: SharedSetupPreview?
    @Published private(set) var result: SharedSetupApplyResult?
    @Published var isFlowPresented = false
    @Published var errorMessage: String?
    @Published private(set) var lastRouteSource: RouteSource?

    let settings: AdvancedExportSettings
    let apiExportSettings: APIExportSettings
    private let schedulingManager: SchedulingManager
    private let transaction: SharedSetupTransaction
    private let registry: SharedSetupMetricRegistry?
    private let fileManager: FileManager
    private let externalFileReader: @Sendable (URL) async throws -> Data
    private let accessibilityAnnouncer: @MainActor (String) -> Void
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
        }
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
    }

    var canUndo: Bool { transaction.canUndo }
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
        let document = try SharedSetupCodec.decode(data)
        let candidate = SharedSetupMapper.preview(document, registry: registry)
        guard !candidate.hasInvalidItems else {
            throw SharedSetupError.invalid(candidate.items.first(where: { $0.status == .invalid })?.detail ?? "The setup is invalid.")
        }
        preview = candidate
        result = nil
        isFlowPresented = true
    }

    func apply() {
        guard let preview else { return }
        do {
            result = try transaction.apply(preview)
            accessibilityAnnouncer(
                String(localized: "Shared Setup applied. Review items requiring attention, then finish setup.")
            )
        } catch {
            errorMessage = error.localizedDescription
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
        preview = nil
        result = nil
        isFlowPresented = false
    }

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

    func makeShareArtifact(appVersion: String) throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("SharedSetup", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Health-md-Setup.healthmdconfig")
        try exportData(appVersion: appVersion).write(to: url, options: .atomic)
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

    nonisolated private static func readBoundedFile(_ url: URL) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(min(16_384, SharedSetupV1.maximumEncodedBytes))
        for try await byte in handle.bytes {
            try Task.checkCancellation()
            guard data.count < SharedSetupV1.maximumEncodedBytes else {
                throw SharedSetupError.oversized
            }
            data.append(byte)
        }
        return data
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
                if let result = coordinator.result { success(result) }
                else if let preview = coordinator.preview { review(preview) }
                else { ContentUnavailableView("No Setup Selected", systemImage: "doc.badge.gearshape", description: Text("Choose a .healthmdconfig file to review.")) }
            }
            .navigationTitle(coordinator.result == nil ? "Review Shared Setup" : "Setup Applied")
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

    private func prepareExport() { do { exportDocument = SharedSetupDocument(data: try coordinator.exportData(appVersion: appVersion)); isExporterPresented = true } catch { coordinator.errorMessage = error.localizedDescription } }
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

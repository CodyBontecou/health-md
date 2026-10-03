import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

extension UTType {
    static let healthMdConfiguration = UTType(exportedAs: "com.healthmd.configuration", conformingTo: .json)
}

enum SharedSetupLoadedPreview: Equatable, Sendable {
    case v2(SharedSetupV2ImportPlan)

    var hasInvalidItems: Bool {
        switch self {
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
    /// Structured review facts for the profiles this transaction created (or,
    /// after Undo, an empty list). Strings remain the human-readable result;
    /// this list only carries identities review surfaces need for live
    /// blocked-state queries and the rebind affordance.
    var importedProfiles: [SharedSetupV2ImportedProfileReview]

    init(
        appliedItems: [String] = [],
        attentionItems: [String] = [],
        importedProfiles: [SharedSetupV2ImportedProfileReview] = []
    ) {
        self.appliedItems = appliedItems
        self.attentionItems = attentionItems
        self.importedProfiles = importedProfiles
    }
}

enum SharedSetupV2CoordinatorError: LocalizedError, Equatable {
    case transactionUnavailable
    case noLoadedPreview
    case invalidPreview
    case invalidSelection
    case noUndoSnapshot
    case metricRegistryUnavailable
    case invalidCredential
    case exportProfileServiceUnavailable
    case importedEndpointUnavailable
    case v2ExportContextUnavailable

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
        case .invalidCredential:
            "Enter a valid local endpoint credential."
        case .exportProfileServiceUnavailable:
            "The export profile service is unavailable, so this endpoint cannot be confirmed here. The imported profile stays blocked."
        case .importedEndpointUnavailable:
            "The imported endpoint identity is no longer available, so it cannot be added here. Configure the endpoint in this profile's export settings."
        case .v2ExportContextUnavailable:
            "The export profile service is unavailable, so the current setup cannot be shared from here. Open the main export surface once, then try again."
        }
    }
}

/// Read-only facts about one imported API endpoint identity retained in
/// the still-loaded Shared Setup v2 plan.
struct SharedSetupV2ImportedEndpointIdentity: Equatable, Sendable {
    /// Human display hint (host + path) for an imported endpoint.
    let displayHint: String
    /// Canonical validated URL string — the conservative identity used to
    /// match a locally saved endpoint row.
    let validatedURLString: String
}

/// Honest, read-only snapshot of the connected-Mac facts Health.md tracks
/// natively today. There is no durable multipeer pairing record in the app;
/// the saved Manual IP connection is the only persistent pairing evidence,
/// and the live connection state is ephemeral transport state. Every fact is
/// reported exactly as tracked — informational only, never pairing proof.
struct SharedSetupV2ConnectedMacState: Equatable, Sendable {
    var hasSavedManualIPPairing: Bool
    var savedManualIPMacName: String?
    var isLiveConnectionActive: Bool
    var liveConnectedPeerName: String?

    init(
        hasSavedManualIPPairing: Bool,
        savedManualIPMacName: String?,
        isLiveConnectionActive: Bool,
        liveConnectedPeerName: String?
    ) {
        self.hasSavedManualIPPairing = hasSavedManualIPPairing
        self.savedManualIPMacName = savedManualIPMacName
        self.isLiveConnectionActive = isLiveConnectionActive
        self.liveConnectedPeerName = liveConnectedPeerName
    }

    /// Production snapshot read from the shared sync service. Property reads
    /// only — no transport work, no new entitlements, no state mutation.
    @MainActor
    init(syncService: SyncService) {
        self.init(
            hasSavedManualIPPairing: syncService.hasSavedManualIPConnection,
            savedManualIPMacName: syncService.savedManualIPMacName,
            isLiveConnectionActive: syncService.connectionState == .connected,
            liveConnectedPeerName: syncService.connectedPeerName
        )
    }

    var savedPairingCaption: String {
        hasSavedManualIPPairing
            ? "Saved Manual IP pairing: \(savedManualIPMacName ?? "a paired Mac")"
            : "No saved Manual IP pairing on this device"
    }

    var liveConnectionCaption: String {
        if isLiveConnectionActive {
            return liveConnectedPeerName.map { "Mac connection active (\($0))" }
                ?? "Mac connection active"
        }
        return "No Mac connection active right now"
    }
}

/// Conservative identity matching between an imported API endpoint and a
/// locally saved endpoint row. Any parse failure, non-http(s) scheme, or
/// component mismatch — scheme, host, effective port, path, query — means NO
/// match: the review stays fail-closed and points at export settings rather
/// than guessing a destination.
enum SharedSetupV2EndpointIdentity {
    static func localRowURL(
        _ rowURLString: String,
        matchesImportedURLString importedURLString: String
    ) -> Bool {
        guard let row = URLComponents(
            string: rowURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
            let imported = URLComponents(
                string: importedURLString.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
            let rowScheme = row.scheme?.lowercased(),
            let importedScheme = imported.scheme?.lowercased(),
            rowScheme == importedScheme,
            rowScheme == "https" || rowScheme == "http",
            let rowHost = row.host?.lowercased(),
            let importedHost = imported.host?.lowercased(),
            rowHost == importedHost,
            effectivePort(of: row, scheme: rowScheme)
                == effectivePort(of: imported, scheme: importedScheme),
            row.query == imported.query else {
            return false
        }
        return normalizedPath(row.path) == normalizedPath(imported.path)
    }

    /// A nil port means the scheme default; an explicit default port equals
    /// the implicit one. Non-default ports must match exactly.
    private static func effectivePort(of components: URLComponents, scheme: String) -> Int {
        components.port ?? (scheme == "https" ? 443 : 80)
    }

    private static func normalizedPath(_ path: String) -> String {
        path.isEmpty ? "/" : path
    }
}

/// Process-wide, weak production bridge to the lazily constructed
/// `ExportProfileCoordinator` owned by the main UI. The Shared Setup review
/// flow is presented above the tab view in `HealthMdApp`, while the export
/// profile coordinator is built lazily inside `ContentView`; this bridge lets
/// the injected production closures reach the single production instance —
/// and only that instance — without duplicating its stores or re-implementing
/// its verified rebind path. Weak by design: the bridge never extends the
/// coordinator's lifetime, and a missing registration keeps every in-flow
/// API endpoint confirmation honestly unavailable (fail closed).
@MainActor
enum SharedSetupV2ExportProfileBridge {
    static weak var current: ExportProfileCoordinator?

    static func register(_ coordinator: ExportProfileCoordinator) {
        current = coordinator
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
    /// Optional fail-closed execution-gate surface. When present it exposes
    /// live blocked-profile truth and the only verified rebind path. Absent
    /// closures keep the historical fail-closed behavior: no v2 apply, no
    /// v2 Undo, no rebind claim.
    var isExecutionBlocked: (@MainActor (UUID) -> Bool)? = nil
    var confirmRebind: (@MainActor (UUID, SharedSetupV2RebindConfirmation) throws -> Bool)? = nil
    /// Optional production surface for the in-flow API-credential
    /// confirmation. `localAPIEndpointID` resolves the single local endpoint
    /// row whose identity conservatively matches an imported endpoint; nil
    /// means no honest match exists. `confirmAPIEndpointRebind` persists a
    /// fresh local credential through the destination store's Keychain-backed
    /// token slot and then runs the ONLY verified rebind path on the
    /// production `ExportProfileCoordinator`. Absent closures surface honest
    /// unavailability — nothing in this flow may guess a destination or clear
    /// a blocked identity without them.
    var localAPIEndpointID: (@MainActor (String) -> UUID?)? = nil
    var confirmAPIEndpointRebind: (@MainActor (
        UUID,
        UUID,
        String
    ) throws -> Bool)? = nil
    /// Optional in-flow endpoint-row creation surface for the no-match review
    /// row. Given the name the caller resolved — the identity-derived display
    /// hint for a genuinely new row, or the existing name of the row the
    /// editor's upsert path is about to reuse — and the EXACT URL string the
    /// still-loaded plan retains (the user explicitly confirmed that URL in
    /// the flow), it creates or reuses the local endpoint row through the
    /// profile editor's exact upsert path, never inventing a URL and never
    /// storing a credential (the credential confirmation flow that follows
    /// owns that step). It returns the upserted row id so the caller can
    /// re-verify it against the conservative identity matcher; a mismatch
    /// must fail closed. Absent closures keep the no-match review row's
    /// honest dead-end copy.
    var upsertAPIEndpointForImportedURL: (@MainActor (String, String) throws -> UUID)? = nil
    /// Optional read-only lookup of the existing row name the profile
    /// editor's upsert path would REUSE for an imported URL — the editor's
    /// exact case-insensitive raw-URL rule, deliberately not the
    /// conservative identity matcher. Nil means no row would be reused (or
    /// the surface is honestly unavailable). The in-flow add consults it
    /// purely to PRESERVE a reused row's existing name: the identity-derived
    /// display hint names only a genuinely new row, so the flow never
    /// renames a row it did not create. An absent closure keeps the
    /// historical hint-naming behavior.
    var reusedAPIEndpointNameForImportedURL: (@MainActor (String) -> String?)? = nil
    /// Optional read-only connected-Mac pairing facts for the review rows.
    /// Informational only; the explicit attestation confirmation remains the
    /// only path that can clear a connected-Mac block.
    var connectedMacState: (@MainActor () -> SharedSetupV2ConnectedMacState?)? = nil
    /// Optional change signal for those read-only connected-Mac facts.
    /// Production supplies the shared sync service's published facts; every
    /// signal re-renders the presented review rows, which re-read the
    /// authoritative `connectedMacState` closure at render time. The signal
    /// performs no transport work and mutates no state, and absent signals
    /// keep the render-time snapshot semantics (the historical behavior).
    /// Production delivers on the main thread.
    var connectedMacStateChanges: (@MainActor () -> AnyPublisher<Void, Never>?)? = nil
}

extension SharedSetupV2CoordinatorAdapter {
    /// Production bridge from the coordinator seam onto the durable Shared
    /// Setup v2 profile transaction and its execution gate. Both collaborators
    /// run their real verified persistence paths — no verification overrides,
    /// no weakened bounds, no duplicated transaction semantics.
    static func production(
        _ service: SharedSetupV2TransactionAdapter
    ) -> SharedSetupV2CoordinatorAdapter {
        SharedSetupV2CoordinatorAdapter(
            apply: { plan, selectedBundleIDs, mode in
                let transactionResult = try service.apply(
                    plan,
                    selectedBundleIDs: selectedBundleIDs,
                    mode: mode == .add ? .add : .replace
                )
                return result(
                    plan: plan,
                    selectedBundleIDs: selectedBundleIDs,
                    transactionResult: transactionResult
                )
            },
            undo: {
                do {
                    return result(from: try service.undo())
                } catch let error as SharedSetupV2TransactionError
                where error == .noUndoSnapshot {
                    throw SharedSetupV2CoordinatorError.noUndoSnapshot
                }
            },
            canUndo: { service.canUndo },
            isExecutionBlocked: { service.isExecutionBlocked(profileID: $0) },
            confirmRebind: { profileID, confirmation in
                try service.confirmRebind(profileID: profileID, confirmation: confirmation)
            }
        )
    }

    /// Production wiring for the in-flow API-credential confirmation, the
    /// in-flow endpoint-row creation from a user-confirmed imported URL, and
    /// the connected-Mac pairing-state display. `exportProfiles` lazily
    /// resolves the single production export-profile coordinator (nil keeps
    /// both affordances honestly unavailable); `connectedMacState` supplies
    /// read-only native pairing facts and `connectedMacStateChanges` the
    /// signal that re-renders them while the review sheet stays presented.
    /// The verified paths stay exactly the coordinator's — nothing here
    /// re-implements binding, rollback, or the execution gate.
    static func production(
        _ service: SharedSetupV2TransactionAdapter,
        exportProfiles: @escaping @MainActor () -> ExportProfileCoordinator?,
        connectedMacState: @escaping @MainActor () -> SharedSetupV2ConnectedMacState?,
        connectedMacStateChanges: @escaping @MainActor () -> AnyPublisher<Void, Never>? = { nil }
    ) -> SharedSetupV2CoordinatorAdapter {
        var adapter = production(service)
        adapter.localAPIEndpointID = { importedEndpointURLString in
            guard let exportProfiles = exportProfiles() else { return nil }
            return exportProfiles.destinationStore.apiEndpoints
                .first { row in
                    SharedSetupV2EndpointIdentity.localRowURL(
                        row.endpointURLString,
                        matchesImportedURLString: importedEndpointURLString
                    )
                }?.id
        }
        adapter.upsertAPIEndpointForImportedURL = { name, urlString in
            guard let exportProfiles = exportProfiles() else {
                throw SharedSetupV2CoordinatorError.exportProfileServiceUnavailable
            }
            // The profile editor's exact upsert path: resolves rows
            // case-insensitively by raw URL string, stores a token only when
            // one is supplied (never clearing an existing Keychain-backed
            // slot), and never touches live shared endpoint settings. No
            // credential travels here — the caller re-verifies the row id
            // against the conservative identity matcher before the separate
            // credential confirmation runs.
            guard let rowID = exportProfiles.importAPIEndpointSelection(
                name: name,
                endpointURLString: urlString,
                bearerToken: nil
            ) else {
                throw SharedSetupV2CoordinatorError.exportProfileServiceUnavailable
            }
            return rowID
        }
        adapter.reusedAPIEndpointNameForImportedURL = { importedEndpointURLString in
            guard let exportProfiles = exportProfiles() else { return nil }
            // The profile editor's exact row-reuse rule — the same lookup
            // importAPIEndpointSelection performs before upserting: trimmed
            // raw-URL strings compare case-insensitively, first match wins.
            // Read-only: the caller uses the name solely to keep the upsert
            // from renaming the row it is about to reuse.
            let trimmedURL = importedEndpointURLString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return exportProfiles.destinationStore.apiEndpoints.first {
                $0.endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(trimmedURL) == .orderedSame
            }?.name
        }
        adapter.confirmAPIEndpointRebind = { profileID, endpointID, freshCredential in
            guard let exportProfiles = exportProfiles(),
                  let row = exportProfiles.destinationStore.apiEndpoint(id: endpointID) else {
                throw SharedSetupV2CoordinatorError.exportProfileServiceUnavailable
            }
            // Reuse the destination store's Keychain-backed token slot — the
            // same verified storage path the profile editor uses. The upsert
            // resolves by the row's own URL string, so the only durable change
            // is that row's credential; a different resolved row id means the
            // row changed concurrently and fails closed without clearing the
            // blocked identity.
            guard let storedEndpointID = exportProfiles.importAPIEndpointSelection(
                name: row.name,
                endpointURLString: row.endpointURLString,
                bearerToken: freshCredential
            ), storedEndpointID == endpointID else {
                throw SharedSetupV2ExecutionGateError.persistenceVerificationFailed
            }
            try exportProfiles.confirmAPIEndpointRebind(
                profileID: profileID,
                endpointID: endpointID,
                credentialsConfirmed: true
            )
            return true
        }
        adapter.connectedMacState = connectedMacState
        adapter.connectedMacStateChanges = connectedMacStateChanges
        return adapter
    }

    /// Precise change signal for the connected-Mac facts the review rows
    /// display: only the shared sync service's connection state, connected
    /// peer name, and saved Manual-IP pairing facts fire it. Pure
    /// subscription over existing `@Published` state — no transport work, no
    /// entitlements, no state mutation. `dropFirst()` discards the initial
    /// subscription-time replay of current values so only real changes fire.
    static func connectedMacFactChanges(
        syncService: SyncService
    ) -> AnyPublisher<Void, Never> {
        Publishers.CombineLatest4(
            syncService.$connectionState,
            syncService.$connectedPeerName,
            syncService.$hasSavedManualIPConnection,
            syncService.$savedManualIPMacName
        )
        .dropFirst()
        .map { _ in () }
        .eraseToAnyPublisher()
    }

    /// Honest result mapping for a successful Add/Replace. Counts, identities,
    /// and rebind requirements mirror exactly what the transaction persisted;
    /// nothing here claims a destination is bound or a schedule is enabled.
    private static func result(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIDs: [String],
        transactionResult: SharedSetupV2TransactionResult
    ) -> SharedSetupV2CoordinatorResult {
        let reviews = SharedSetupV2ImportedProfileReview.reviews(
            plan: plan,
            selectedBundleIDs: selectedBundleIDs,
            result: transactionResult
        )
        let modeLabel = transactionResult.mode == .add ? "Add" : "Replace"
        let importedCount = transactionResult.importedProfileIDs.count
        var applied: [String] = [
            "Imported \(importedCount) \(importedCount == 1 ? "profile" : "profiles") (\(modeLabel))",
            "Imported \(transactionResult.importedScheduleCount) " +
                "\(transactionResult.importedScheduleCount == 1 ? "schedule" : "schedules"); all remain disabled"
        ]
        if let activeID = transactionResult.activeProfileID,
           let activeReview = reviews.first(where: { $0.id == activeID }) {
            applied.append("Active profile: \(activeReview.sourceName)")
        } else {
            applied.append("Existing active profile retained")
        }

        var attention: [String] = []
        for review in reviews {
            switch review.destinationKind {
            case .deviceFolder:
                attention.append(
                    "\(review.sourceName): blocked — choose a local folder destination before this profile can export"
                )
            case .connectedMac:
                attention.append(
                    "\(review.sourceName): blocked — confirm Mac pairing locally before this profile can export"
                )
            case .apiEndpoint:
                attention.append(
                    "\(review.sourceName): blocked — confirm the API endpoint with a new local credential before this profile can export"
                )
            case .cloud:
                attention.append(
                    "\(review.sourceName): cloud destinations are unsupported on Apple and remain blocked"
                )
            }
            if review.unsupportedSemanticIDCount > 0 {
                attention.append(
                    "\(review.sourceName): \(review.unsupportedSemanticIDCount) unsupported " +
                        "\(review.unsupportedSemanticIDCount == 1 ? "meaning is" : "meanings are") " +
                        "preserved for review only"
                )
            }
        }
        return SharedSetupV2CoordinatorResult(
            appliedItems: applied,
            attentionItems: attention,
            importedProfiles: reviews
        )
    }

    /// Honest result mapping for a successful one-shot Undo.
    private static func result(from undoResult: SharedSetupV2UndoResult) -> SharedSetupV2CoordinatorResult {
        let profileCount = undoResult.restoredProfileIDs.count
        let scheduleCount = undoResult.restoredScheduleCount
        var applied: [String] = [
            "Restored \(profileCount) \(profileCount == 1 ? "profile" : "profiles") " +
                "and \(scheduleCount) \(scheduleCount == 1 ? "schedule" : "schedules") to the exact previous state"
        ]
        applied.append(
            undoResult.activeProfileID == nil
                ? "No active profile after restore"
                : "Active profile restored"
        )
        return SharedSetupV2CoordinatorResult(appliedItems: applied)
    }
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
    @Published private(set) var v2Result: SharedSetupV2CoordinatorResult?
    /// True when `v2Result` describes a successful one-shot Undo rather than
    /// an apply, so review surfaces never label an undone import as applied.
    @Published private(set) var v2ResultWasUndo = false
    /// Native profile IDs whose blocked state was cleared through the
    /// verified rebind path during this flow. Purely a presentation trigger;
    /// the execution gate remains the authority for blocked truth.
    @Published private(set) var v2ReboundProfileIDs: Set<UUID> = []
    /// Local endpoint rows created in-flow from a user-confirmed imported
    /// URL. Purely a presentation trigger: durable row truth lives in the
    /// destination store, and the verified credential rebind remains the
    /// only path that can clear a blocked identity.
    @Published private(set) var v2InFlowEndpointRowIDs: Set<UUID> = []
    /// Bumped whenever the adapter's connected-Mac change signal fires, so
    /// the presented review rows re-render and re-read the authoritative
    /// `v2ConnectedMacState` snapshot at render time. Monotonic presentation
    /// counter only — it carries no facts of its own.
    @Published private(set) var v2ConnectedMacStateRevision = 0
    @Published var isFlowPresented = false
    @Published var errorMessage: String?
    @Published private(set) var lastRouteSource: RouteSource?

    var v2Preview: SharedSetupV2ImportPlan? {
        guard case .v2(let preview) = loadedPreview else { return nil }
        return preview
    }

    private let registry: SharedSetupMetricRegistry?
    private let fileManager: FileManager
    private let externalFileReader: @Sendable (URL) async throws -> Data
    private let accessibilityAnnouncer: @MainActor (String) -> Void
    private let v2Adapter: SharedSetupV2CoordinatorAdapter?
    /// Production resolver for the v2 export context the default writer
    /// needs. Absent — or returning nil — keeps the default Share/Save path
    /// honestly unavailable; Health.md never falls back to another writer.
    private let v2ExportContextResolver: (@MainActor () -> SharedSetupV2ExportContext?)?
    private var v2ConnectedMacStateCancellable: AnyCancellable?
    private var importTask: Task<Void, Never>?
    private var importRequestID = 0

    init(
        registry: SharedSetupMetricRegistry?? = nil,
        fileManager: FileManager = .default,
        externalFileReader: @escaping @Sendable (URL) async throws -> Data = {
            try await SharedSetupCoordinator.readBoundedFile($0)
        },
        accessibilityAnnouncer: @escaping @MainActor @Sendable (String) -> Void = {
            UIAccessibility.post(notification: .announcement, argument: $0)
        },
        v2Adapter: SharedSetupV2CoordinatorAdapter? = nil,
        v2ExportContext: (@MainActor () -> SharedSetupV2ExportContext?)? = nil
    ) {
        // Default argument expressions are evaluated in a nonisolated context (SE-0411),
        // so MainActor-isolated defaults are resolved inside the initializer body instead.
        let resolvedRegistry = registry ?? (try? SharedSetupMetricRegistry.current())
        self.registry = resolvedRegistry
        self.fileManager = fileManager
        self.externalFileReader = externalFileReader
        self.accessibilityAnnouncer = accessibilityAnnouncer
        self.v2Adapter = v2Adapter
        self.v2ExportContextResolver = v2ExportContext
        // Re-render signal for the connected-Mac review rows: the adapter's
        // optional change publisher bumps the published revision, and rows
        // re-read the authoritative connectedMacState closure on the next
        // render. An absent signal keeps the render-time snapshot semantics
        // (the historical cycle-4 behavior); production delivers on main.
        if let connectedMacStateChanges = v2Adapter?.connectedMacStateChanges {
            v2ConnectedMacStateCancellable = connectedMacStateChanges()?
                .sink { [weak self] _ in self?.v2ConnectedMacStateRevision &+= 1 }
        }
    }

    var canUndoV2: Bool { v2Adapter?.canUndo() ?? false }
    var isV2TransactionAvailable: Bool { v2Adapter != nil }
    /// True only when the installed adapter exposes both the live blocked
    /// query and the verified rebind path. Pure closure adapters from tests
    /// honestly report rebind as unavailable.
    var isV2RebindAvailable: Bool {
        guard let v2Adapter else { return false }
        return v2Adapter.isExecutionBlocked != nil && v2Adapter.confirmRebind != nil
    }

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
        let document = try SharedSetupVersionedCodec.decode(data)
        guard let registry else {
            throw SharedSetupV2CoordinatorError.metricRegistryUnavailable
        }
        // Mapping is pure. Keep even an invalid local compatibility plan
        // reviewable, but never expose it as eligible for Apply.
        loadedPreview = .v2(SharedSetupV2Mapper.preview(document, registry: registry))
        v2Result = nil
        v2ResultWasUndo = false
        v2ReboundProfileIDs = []
        v2InFlowEndpointRowIDs = []
        errorMessage = nil
        isFlowPresented = true
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
            v2Result = outcome
            v2ResultWasUndo = false
            v2ReboundProfileIDs = []
            v2InFlowEndpointRowIDs = []
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
            v2Result = outcome
            v2ResultWasUndo = true
            v2ReboundProfileIDs = []
            v2InFlowEndpointRowIDs = []
            errorMessage = nil
            accessibilityAnnouncer(String(localized: "Shared Setup profile import undone"))
            return outcome
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Live blocked-profile truth from the installed execution gate. Without
    /// an adapter there are no v2-imported profiles, so false is honest.
    func isV2ProfileExecutionBlocked(profileID: UUID) -> Bool {
        v2Adapter?.isExecutionBlocked?(profileID) ?? false
    }

    /// Routes one explicit rebind confirmation through the installed
    /// execution gate's verified production path. Kind mismatches, missing
    /// confirmation proofs, and persistence failures throw and leave the
    /// profile blocked; nothing here can fabricate a verified rebind.
    @discardableResult
    func confirmV2Rebind(
        profileID: UUID,
        confirmation: SharedSetupV2RebindConfirmation
    ) throws -> Bool {
        guard let confirmRebind = v2Adapter?.confirmRebind else {
            throw SharedSetupV2CoordinatorError.transactionUnavailable
        }
        do {
            let didRebind = try confirmRebind(profileID, confirmation)
            if didRebind {
                v2ReboundProfileIDs.insert(profileID)
                errorMessage = nil
                accessibilityAnnouncer(
                    String(localized: "Imported profile destination rebound")
                )
            }
            return didRebind
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func finish() {
        importTask?.cancel()
        importTask = nil
        importRequestID &+= 1
        loadedPreview = nil
        v2Result = nil
        v2ResultWasUndo = false
        v2ReboundProfileIDs = []
        v2InFlowEndpointRowIDs = []
        isFlowPresented = false
    }

    /// True only when the installed adapter exposes the complete in-flow API
    /// credential confirmation path (conservative identity match plus the
    /// verified rebind). Anything less stays honestly unavailable.
    var isV2APIEndpointRebindAvailable: Bool {
        guard let v2Adapter else { return false }
        return v2Adapter.localAPIEndpointID != nil && v2Adapter.confirmAPIEndpointRebind != nil
    }

    /// True only when the installed adapter also exposes the in-flow
    /// endpoint-row creation path for a user-confirmed imported URL. Anything
    /// less keeps the no-match review row's honest dead-end copy — the flow
    /// never falls back to creating a row through any other path.
    var isV2ImportedAPIEndpointAddAvailable: Bool {
        v2Adapter?.upsertAPIEndpointForImportedURL != nil
    }

    /// Imported API endpoint identity for one review row, read from the
    /// still-loaded v2 plan. Nil keeps the row fail-closed — the flow never
    /// guesses an endpoint identity that is not retained.
    func importedV2APIEndpoint(
        for review: SharedSetupV2ImportedProfileReview
    ) -> SharedSetupV2ImportedEndpointIdentity? {
        guard case .v2(let plan) = loadedPreview,
              let profile = plan.document.profiles.first(where: {
                  $0.bundleID == review.sourceBundleID
              }),
              let endpoint = profile.destination.apiEndpoint,
              let validatedURLString = endpoint.validatedURLString else {
            return nil
        }
        return SharedSetupV2ImportedEndpointIdentity(
            displayHint: "\(endpoint.host)\(endpoint.path)",
            validatedURLString: validatedURLString
        )
    }

    /// The local endpoint row conservatively matching an imported endpoint
    /// identity, or nil when no honest match exists (fail closed).
    func matchingV2LocalAPIEndpointID(forImportedURLString url: String) -> UUID? {
        v2Adapter?.localAPIEndpointID?(url)
    }

    /// Read-only native connected-Mac pairing facts for the review rows,
    /// when the installed adapter supplies them.
    var v2ConnectedMacState: SharedSetupV2ConnectedMacState? {
        v2Adapter?.connectedMacState?()
    }

    /// Creates the local endpoint row for a blocked imported API-endpoint
    /// profile from the EXACT validated URL the still-loaded plan retains —
    /// reachable only after the user explicitly confirmed that URL in the
    /// flow, never from a typed or guessed one. A genuinely new row is named
    /// honestly from the imported identity's display hint; when the profile
    /// editor's upsert path would REUSE an existing row (its exact
    /// case-insensitive raw-URL rule), that row's existing name is preserved
    /// — the flow never renames a row it did not create. The row goes
    /// through the profile editor's exact upsert path, and no credential is
    /// stored here. Identity discipline: the upsert resolves rows
    /// case-insensitively by raw URL string while review matching is
    /// conservative, so the resulting row is re-resolved through the
    /// identity matcher; any mismatch fails closed and the blocked identity
    /// stays intact. On success the caller routes into the existing
    /// credential-confirmation flow against the row — which alone, through
    /// the verified rebind, can clear the block.
    @discardableResult
    func confirmV2ImportedAPIEndpointURL(
        for review: SharedSetupV2ImportedProfileReview
    ) throws -> UUID {
        guard let upsert = v2Adapter?.upsertAPIEndpointForImportedURL else {
            throw SharedSetupV2CoordinatorError.transactionUnavailable
        }
        guard let identity = importedV2APIEndpoint(for: review) else {
            let error = SharedSetupV2CoordinatorError.importedEndpointUnavailable
            errorMessage = error.localizedDescription
            throw error
        }
        do {
            // The editor's upsert path resolves rows case-insensitively by
            // raw URL string and renames the reused row to whatever name it
            // is handed — so hand it the reused row's own name and preserve
            // it; the identity-derived display hint names only a genuinely
            // new row. This lookup is naming advice only: the post-upsert
            // conservative identity re-verification below stays the sole
            // authority on which row is trustworthy.
            let rowID = try upsert(
                resolvedInFlowRowName(for: identity),
                identity.validatedURLString
            )
            // Prove the upserted row is the resolved conservative match
            // before routing the credential confirmation on. A mismatch —
            // for example a pre-existing row the upsert reused under its
            // case-insensitive URL rule while the conservative matcher
            // rejects its identity — fails closed and keeps the block.
            guard let resolvedID = matchingV2LocalAPIEndpointID(
                forImportedURLString: identity.validatedURLString
            ), resolvedID == rowID else {
                throw SharedSetupV2ExecutionGateError.persistenceVerificationFailed
            }
            v2InFlowEndpointRowIDs.insert(rowID)
            errorMessage = nil
            accessibilityAnnouncer(
                String(localized: "API endpoint added from the shared setup")
            )
            return rowID
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// The name the in-flow endpoint upsert receives: the existing name of
    /// the row the profile editor's exact case-insensitive raw-URL rule
    /// would reuse — preserved, so the flow never renames a row it did not
    /// create — or the identity-derived display hint when the upsert creates
    /// a genuinely new row. A blank reused name cannot be preserved (the
    /// editor itself would not keep it), so it also falls back to the hint;
    /// an unavailable reuse lookup keeps the historical hint naming.
    private func resolvedInFlowRowName(
        for identity: SharedSetupV2ImportedEndpointIdentity
    ) -> String {
        guard let reusedName = v2Adapter?.reusedAPIEndpointNameForImportedURL?(
            identity.validatedURLString
        ), !reusedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return identity.displayHint
        }
        return reusedName
    }

    /// Routes one explicit API-endpoint rebind through the installed verified
    /// production path. The credential is validated with the same bounds as
    /// every local credential entry (non-empty after trimming, at most 8,192
    /// characters, no newlines or control characters) and is only ever handed
    /// to the injected closure — this coordinator never stores it. Failures
    /// throw, publish an error, and leave the blocked identity intact.
    @discardableResult
    func confirmV2APIEndpointRebind(
        profileID: UUID,
        endpointID: UUID,
        credential: String
    ) throws -> Bool {
        guard let confirmAPIEndpointRebind = v2Adapter?.confirmAPIEndpointRebind else {
            throw SharedSetupV2CoordinatorError.transactionUnavailable
        }
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 8_192,
              !trimmed.contains(where: {
                  $0.isNewline || $0.asciiValue.map { $0 < 32 } == true
              }) else {
            let error = SharedSetupV2CoordinatorError.invalidCredential
            errorMessage = error.localizedDescription
            throw error
        }
        do {
            let didRebind = try confirmAPIEndpointRebind(profileID, endpointID, trimmed)
            if didRebind {
                v2ReboundProfileIDs.insert(profileID)
                errorMessage = nil
                accessibilityAnnouncer(String(localized: "API endpoint confirmed locally"))
            }
            return didRebind
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// THE production Shared Setup writer. It resolves the export context
    /// from the injected production owner — the single export-profile
    /// coordinator plus the v2 sidecar's preserved extensions — and encodes
    /// canonical `schema_version: 2` bytes exclusively. A missing resolver
    /// or owner fails closed; there is no other writer to fall back to.
    func exportData(appVersion: String, calendar: Calendar = .current) throws -> Data {
        guard let context = v2ExportContextResolver?() else {
            throw SharedSetupV2CoordinatorError.v2ExportContextUnavailable
        }
        return try exportV2Data(
            context: context,
            appVersion: appVersion,
            calendar: calendar
        )
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

    func makeShareArtifact(appVersion: String, calendar: Calendar = .current) throws -> URL {
        guard let context = v2ExportContextResolver?() else {
            throw SharedSetupV2CoordinatorError.v2ExportContextUnavailable
        }
        return try makeValidatedShareArtifact(
            exportV2Data(context: context, appVersion: appVersion, calendar: calendar)
        )
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
    @State private var v2SelectedBundleIDs: Set<String> = []
    @State private var v2ApplyMode: SharedSetupV2CoordinatorApplyMode = .add
    @State private var v2RebindTarget: SharedSetupV2ImportedProfileReview?

    var body: some View {
        NavigationStack {
            Group {
                if let result = coordinator.v2Result {
                    v2Success(result)
                } else if let loadedPreview = coordinator.loadedPreview {
                    switch loadedPreview {
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
                coordinator.v2Result == nil
                    ? "Review Shared Setup"
                    : (coordinator.v2ResultWasUndo ? "Import Undone" : "Setup Applied")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { coordinator.finish(); dismiss() } } }
            .onAppear(perform: seedV2SelectionFromPreview)
            .onChange(of: coordinator.loadedPreview) { _, _ in seedV2SelectionFromPreview() }
        }
    }

    /// Selection is view-local state: choosing profiles, changing the apply
    /// mode, and re-reviewing a document never write anything.
    private func seedV2SelectionFromPreview() {
        guard case .v2(let plan) = coordinator.loadedPreview else { return }
        v2SelectedBundleIDs = Set(plan.defaultSelectedBundleIDs)
        v2ApplyMode = .add
    }

    private func v2Review(_ preview: SharedSetupV2ImportPlan) -> some View {
        let selectionAvailable = coordinator.isV2TransactionAvailable && !preview.hasInvalidItems
        return List {
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
                    if selectionAvailable {
                        v2ProfileSelectionRow(profile: profile, plan: preview)
                    }
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

            Section(selectionAvailable ? "Apply" : "Apply unavailable") {
                if preview.hasInvalidItems {
                    Text("This plan contains invalid items and cannot be applied.")
                } else if coordinator.isV2TransactionAvailable {
                    Picker("Apply mode", selection: $v2ApplyMode) {
                        Text("Add").tag(SharedSetupV2CoordinatorApplyMode.add)
                        Text("Replace").tag(SharedSetupV2CoordinatorApplyMode.replace)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Apply mode")
                    if v2ApplyMode == .add {
                        Text("Add keeps every existing profile and appends the selected setups as new profiles. Profile names are adjusted to stay unique when needed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Replace removes every existing profile and keeps only the selected setups. Existing folders, endpoints, and credentials are never deleted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Apply Shared Setup v2") {
                        do {
                            _ = try coordinator.applyV2(
                                selectedBundleIDs: orderedV2Selection(in: preview),
                                mode: v2ApplyMode
                            )
                        } catch {
                            // The coordinator publishes errorMessage for the alert.
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(!coordinator.canApplyV2(
                        selectedBundleIDs: orderedV2Selection(in: preview)
                    ))
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.apply)
                    .accessibilityHint("Imports the selected profiles. Every imported destination stays unbound and every imported schedule stays disabled.")
                    Text("Imported profiles are blocked until you rebind each destination on this device. One Undo is available immediately after applying.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No verified Shared Setup v2 Add/Replace/Undo adapter is installed.")
                }
                if !selectionAvailable {
                    Button("Apply Shared Setup v2") {}
                        .disabled(true)
                }
            }
        }
    }

    /// Explicit per-profile selection control. Invalid profiles stay
    /// review-only and can never be selected for apply.
    @ViewBuilder
    private func v2ProfileSelectionRow(
        profile: SharedSetupV2.Profile,
        plan: SharedSetupV2ImportPlan
    ) -> some View {
        let profilePlan = plan.profiles.first { $0.bundleID == profile.bundleID }
        let isSelectable = profilePlan.map { !$0.hasInvalidItems } ?? false
        Toggle(isOn: v2SelectionBinding(profile.bundleID, isSelectable: isSelectable)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isSelectable ? "Import \(profile.name)" : "\(profile.name) cannot be applied")
                    .font(.headline)
                Text(isSelectable
                     ? "Include this profile when the shared setup is applied."
                     : "This profile contains invalid items and stays review-only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .disabled(!isSelectable)
        .accessibilityHint("Double tap to include or exclude this profile from the import.")
    }

    private func v2SelectionBinding(_ bundleID: String, isSelectable: Bool) -> Binding<Bool> {
        Binding(
            get: { v2SelectedBundleIDs.contains(bundleID) },
            set: { include in
                guard isSelectable else { return }
                if include {
                    v2SelectedBundleIDs.insert(bundleID)
                } else {
                    v2SelectedBundleIDs.remove(bundleID)
                }
            }
        )
    }

    /// Persisted order follows source-document order; tap order never decides.
    private func orderedV2Selection(in plan: SharedSetupV2ImportPlan) -> [String] {
        plan.document.profiles.map(\.bundleID).filter { v2SelectedBundleIDs.contains($0) }
    }

    private func v2Success(_ result: SharedSetupV2CoordinatorResult) -> some View {
        List {
            Section(coordinator.v2ResultWasUndo ? "Undone" : "Applied items") {
                if result.appliedItems.isEmpty {
                    Text("None reported")
                } else {
                    ForEach(result.appliedItems, id: \.self) {
                        Label(
                            $0,
                            systemImage: coordinator.v2ResultWasUndo
                                ? "arrow.uturn.backward.circle.fill"
                                : "checkmark.circle.fill"
                        )
                        .foregroundStyle(coordinator.v2ResultWasUndo ? Color.secondary : .green)
                    }
                }
            }
            if !coordinator.v2ResultWasUndo {
                Section("Items requiring attention") {
                    if result.attentionItems.isEmpty { Text("None") }
                    else { ForEach(result.attentionItems, id: \.self) { Text($0) } }
                }
                if !result.importedProfiles.isEmpty {
                    Section("Imported profiles") {
                        Text("Every imported destination is unbound and every imported schedule is disabled. Profiles stay blocked until their destination is explicitly rebound on this device.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(result.importedProfiles) { importedProfileReviewRow($0) }
                    }
                }
            }
            Section {
                Button("Undo") {
                    do { _ = try coordinator.undoV2() } catch { /* Published by coordinator. */ }
                }
                .disabled(!coordinator.canUndoV2)
                .accessibilityIdentifier(AccessibilityID.SharedSetup.undo)
                if coordinator.v2ResultWasUndo && !coordinator.canUndoV2 {
                    Text("Undo is one-shot. The previous state was restored, so this import can no longer be undone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Finish Setup") { coordinator.finish(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityID.SharedSetup.finish)
            }
        }
        .confirmationDialog(
            "Confirm Mac Pairing",
            isPresented: Binding(
                get: { v2RebindTarget != nil },
                set: { if !$0 { v2RebindTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Mac Is Paired — Rebind") {
                if let target = v2RebindTarget {
                    do {
                        _ = try coordinator.confirmV2Rebind(
                            profileID: target.id,
                            confirmation: .connectedMac(pairingConfirmed: true)
                        )
                    } catch {
                        // The coordinator publishes errorMessage; the profile
                        // stays blocked until a verified rebind succeeds.
                    }
                }
                v2RebindTarget = nil
            }
            Button("Cancel", role: .cancel) { v2RebindTarget = nil }
        } message: {
            Text(
                v2RebindTarget.map { target in
                    "\(target.sourceName) will use your local Mac pairing state. Pairing is never imported; confirm only if this device is paired with your Mac and its export folder is ready. Health.md verifies and persists the rebind before this profile can run."
                } ?? ""
            )
        }
    }

    /// Live blocked-state presentation for one imported profile, plus the
    /// honest rebind affordance for its destination kind. Only explicit local
    /// confirmation types the execution gate accepts are offered; folder and
    /// API rebinding require concrete bindings this review cannot fabricate.
    @ViewBuilder
    private func importedProfileReviewRow(_ review: SharedSetupV2ImportedProfileReview) -> some View {
        let isBlocked = coordinator.isV2ProfileExecutionBlocked(profileID: review.id)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isBlocked ? "lock.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isBlocked ? Color.orange : .green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.sourceName).font(.headline)
                    Text("\(review.sourceBundleID) · \(v2DestinationKindTitle(review.destinationKind))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if review.unsupportedSemanticIDCount > 0 {
                        Text("\(review.unsupportedSemanticIDCount) unsupported " +
                             "\(review.unsupportedSemanticIDCount == 1 ? "meaning is" : "meanings are") preserved for review only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if isBlocked {
                Text(SharedSetupV2ExecutionGate.blockedExecutionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch review.destinationKind {
                case .deviceFolder:
                    Text("To rebind: open this profile's export settings and choose a concrete folder on this device. Rebinding is confirmed automatically once the folder is bound.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .apiEndpoint:
                    v2APIEndpointRebindAffordance(for: review)
                case .connectedMac:
                    // Reading the revision here subscribes these rows to the
                    // adapter's connected-Mac change signal, so the captions
                    // re-render while the review sheet stays presented; the
                    // captions themselves always re-read the live closure
                    // snapshot at render time.
                    let _ = coordinator.v2ConnectedMacStateRevision
                    Text("Pairing is never imported. Rebind only after this device is paired with your Mac and its export folder is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Honest, read-only native pairing facts. Health.md tracks
                    // no durable multipeer pairing record; the saved Manual IP
                    // connection is the only persistent pairing evidence
                    // in-repo, and the live connection state is ephemeral
                    // transport state. Informational only — the explicit
                    // attestation below remains the only path that can clear
                    // this block.
                    if let macState = coordinator.v2ConnectedMacState {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(macState.savedPairingCaption)
                            Text(macState.liveConnectionCaption)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    if coordinator.isV2RebindAvailable {
                        Button("Confirm Paired Mac and Rebind…") {
                            v2RebindTarget = review
                        }
                        .accessibilityHint("Clears this profile's blocked state after Health.md verifies and persists the rebind.")
                    } else {
                        Text("Explicit rebind confirmation is not available in this flow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .cloud:
                    Text("Cloud destinations are not supported on Apple. This profile remains blocked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(
                    "Destination rebound locally — this profile can be activated and exported.",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
        }
    }

    /// In-flow API-credential confirmation affordance for one blocked
    /// imported API-endpoint profile. The imported identity is displayed
    /// exactly as the loaded plan retains it; a credential entry is offered
    /// ONLY against a local endpoint row that conservatively matches that
    /// identity. Without the injected verified path — or without a matching
    /// local row — the row stays fail-closed and points at export settings.
    @ViewBuilder
    private func v2APIEndpointRebindAffordance(
        for review: SharedSetupV2ImportedProfileReview
    ) -> some View {
        if coordinator.isV2APIEndpointRebindAvailable {
            if let identity = coordinator.importedV2APIEndpoint(for: review) {
                if let endpointID = coordinator.matchingV2LocalAPIEndpointID(
                    forImportedURLString: identity.validatedURLString
                ) {
                    SharedSetupV2EndpointCredentialConfirmation(
                        coordinator: coordinator,
                        profileID: review.id,
                        endpointID: endpointID,
                        identityHint: identity.displayHint
                    )
                } else if coordinator.isV2ImportedAPIEndpointAddAvailable {
                    SharedSetupV2ImportedEndpointURLConfirmation(
                        coordinator: coordinator,
                        review: review,
                        identity: identity
                    )
                } else {
                    Text("No saved API endpoint on this device matches \(identity.displayHint). Add this endpoint in the profile's export settings — this flow adds one only from the exact URL the shared setup retains after you confirm it, never a guess.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("The imported endpoint identity is no longer available. Configure the endpoint in this profile's export settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("To rebind: configure the endpoint and enter a new credential in this profile's export settings. Credentials are never imported and this review cannot confirm them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Explicit endpoint confirmation is not available in this flow.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func v2DestinationKindTitle(_ kind: SharedSetupV2.DestinationKind) -> String {
        switch kind {
        case .deviceFolder: "Device folder"
        case .connectedMac: "Connected Mac"
        case .apiEndpoint: "API endpoint"
        case .cloud: "Cloud"
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
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Label("Share My Setup", systemImage: "person.2.badge.gearshape")
                .font(.headline)
                .accessibilityIdentifier(AccessibilityID.SharedSetup.configurationCard)
            Text("Share export preferences—not health data, permissions, credentials, purchases, or device access. Custom Markdown, frontmatter values, and endpoint host/path are copied verbatim, so review them for personal, tenant, routing, or secret text before sending.").font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.s2) { setupActions }
                VStack(alignment: .leading, spacing: Spacing.s2) { setupActions }
            }
        }
        .sharedSetupFileImporter(
            isPresented: $isImporterPresented,
            coordinator: coordinator
        )
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

    @ViewBuilder
    private var setupActions: some View {
        SecondaryButton("Use a Shared Setup", icon: "doc.badge.gearshape") {
            coordinator.beginImport()
            isImporterPresented = true
        }
        .accessibilityIdentifier(AccessibilityID.SharedSetup.use)

        Menu {
            Button("Save to Files") { prepareExport() }
            Button("System Share") { prepareShare() }
        } label: {
            HStack(spacing: Spacing.s2) {
                Image(systemName: "square.and.arrow.up")
                    .accessibilityHidden(true)
                Text("Share")
                Image(systemName: "chevron.down")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityIdentifier(AccessibilityID.SharedSetup.share)
    }

    private func prepareExport() { do { exportDocument = try SharedSetupDocument(data: coordinator.exportData(appVersion: appVersion)); isExporterPresented = true } catch { coordinator.errorMessage = error.localizedDescription } }
    private func prepareShare() { do { shareURL = try coordinator.makeShareArtifact(appVersion: appVersion) } catch { coordinator.errorMessage = error.localizedDescription } }
    private struct ShareURL: Identifiable { let url: URL; var id: URL { url } }
}

/// View-local credential entry model for the v2 in-flow API endpoint
/// confirmation. It holds only the typed string; validation of the attempt
/// and every persistence decision live in the coordinator's verified path.
@MainActor
final class SharedSetupV2CredentialEntryModel: ObservableObject {
    /// `nonisolated deinit` keeps teardown off the MainActor back-deployed
    /// task-deinit path that aborts older simulator runtimes (see the
    /// matching annotations on the export stores and coordinators).
    nonisolated deinit {}

    @Published var authorization = ""

    var canConfirm: Bool {
        !authorization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The attempt is over after every confirm tap — success or failure —
    /// so the typed secret never lingers in the flow.
    func reset() {
        authorization = ""
    }
}

/// In-flow credential confirmation for one blocked imported API endpoint.
/// The typed
/// credential is handed only to the coordinator's injected verified rebind
/// path and is never stored by the flow; the field resets after every
/// attempt.
private struct SharedSetupV2EndpointCredentialConfirmation: View {
    @ObservedObject var coordinator: SharedSetupCoordinator
    let profileID: UUID
    let endpointID: UUID
    let identityHint: String
    @StateObject private var entry = SharedSetupV2CredentialEntryModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(identityHint).font(.caption.monospaced()).textSelection(.enabled)
            Text("Confirm this endpoint by entering a new local credential. Credentials are never imported and existing credentials are never inherited.")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Bearer token or Authorization value", text: $entry.authorization)
                .textContentType(.password)
                .privacySensitive()
                .accessibilityLabel("New local API endpoint credential")
            Button("Confirm Endpoint and Save Credential") {
                do {
                    _ = try coordinator.confirmV2APIEndpointRebind(
                        profileID: profileID,
                        endpointID: endpointID,
                        credential: entry.authorization
                    )
                } catch {
                    // The coordinator publishes errorMessage; the profile
                    // stays blocked until a verified rebind succeeds.
                }
                entry.reset()
            }
            .disabled(!entry.canConfirm)
        }
    }
}

/// In-flow URL confirmation for a blocked imported API-endpoint profile
/// with no conservatively matching local row. The exact validated URL the
/// loaded plan retains is displayed — the user reviews it, never types it:
/// this flow cannot invent a URL. Only the explicit confirm button creates
/// the local row, through the profile editor's upsert path re-verified
/// against the conservative identity matcher; the credential confirmation
/// that then renders against the new row — and its verified rebind — is the
/// only path that can clear the block.
private struct SharedSetupV2ImportedEndpointURLConfirmation: View {
    @ObservedObject var coordinator: SharedSetupCoordinator
    let review: SharedSetupV2ImportedProfileReview
    let identity: SharedSetupV2ImportedEndpointIdentity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(identity.validatedURLString)
                .font(.caption.monospaced())
                .textSelection(.enabled)
            Text("No saved API endpoint on this device matches this identity. You can add it here from the shared setup: the row is created only from the exact URL shown above — never a guess — and a new local credential is still required before this profile can export.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Add This Exact Endpoint From the Shared Setup") {
                do {
                    _ = try coordinator.confirmV2ImportedAPIEndpointURL(for: review)
                } catch {
                    // The coordinator publishes errorMessage; the profile
                    // stays blocked until a matching row exists and a
                    // verified credential rebind succeeds.
                }
            }
            .accessibilityHint("Creates a local endpoint row from the exact imported URL shown above. A new local credential is still required before this profile can export.")
        }
    }
}

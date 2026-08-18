#if DEBUG && os(iOS)
import Combine
import CryptoKit
import Foundation
import SwiftUI
import UIKit

@MainActor
final class IPhoneExportPerformanceLabCoordinator: ObservableObject {
    enum Scenario: String, CaseIterable, Sendable {
        case rawFull = "raw-full"
        case sleepSummary = "sleep-summary"
        case savedFull = "saved-full"
        case savedFullProviderEnabled = "saved-full-provider-enabled"
        case savedFullProviderDisabled = "saved-full-provider-disabled"
        case losslessDense = "lossless-dense"
        case multiDay = "multi-day"
        case thirtyDay = "thirty-day"
        case interruptResume = "interrupt-resume"
        case cancel = "cancel"
        case largeFileBackedBlob = "large-file-backed-blob"
    }

    struct Request: Identifiable, Equatable, Sendable {
        let runID: String
        let target: ExportPerformanceLabTarget
        let scenario: Scenario
        let binding: String
        let controlProof: String
        let proof: String?
        let expectedMacInstallationID: UUID?
        let isAutonomous: Bool

        var id: String { runID }
    }

    enum LinkAction: Equatable, Sendable {
        case run(Request)
        case end(runID: String)
        case cancel(runID: String)
        case setupAPI(binding: String)
        case setupLocal(binding: String)
        case cleanup(
            runID: String,
            target: ExportPerformanceLabTarget,
            binding: String
        )
    }

    enum LabState: Equatable {
        case idle
        case awaitingConfirmation
        case armed
        case running
        case completed
        case failed
        case cancelled
    }

    enum LabError: Error {
        case invalidLink
        case operationInProgress
        case protectedDataUnavailable
        case healthKitUnavailable
        case localDestinationUnavailable
        case apiDestinationUnavailable
        case connectedMacUnavailable
        case targetFailed
        case insufficientDisk
    }

    @Published private(set) var request: Request?
    @Published private(set) var state: LabState = .idle
    @Published private(set) var statusMessage = ""
    @Published var isConfirmationPresented = false
    @Published var isLocalSetupPresented = false
    @Published var isAPISetupConfirmationPresented = false

    private var operationTask: Task<Void, Never>?
    private var idleTimerRestorationTask: Task<Void, Never>?
    private var previousIdleTimerDisabled: Bool?
    private var pendingLocalSetupBinding: String?
    private var pendingAPISetup: (endpoint: URL, token: String, certificateSHA256: String)?

    var apiSetupSummary: String {
        guard let endpoint = pendingAPISetup?.endpoint else { return "Unknown private endpoint" }
        return "HTTPS sink on \(endpoint.host ?? "private host"):\(endpoint.port ?? 443)"
    }

    var canStart: Bool { state == .awaitingConfirmation && request != nil }
    var canAutonomouslyStart: Bool { canStart && request?.isAutonomous == true }
    var canCancel: Bool { state == .running }
    var destinationSummary: String {
        guard let request else { return "No destination" }
        switch request.target {
        case .localIPhone:
            return "Files folder: HealthMdPerformanceLab"
        case .apiEndpoint:
            return "HTTPS endpoint: \(APIExportSettings().redactedEndpointDescription)"
        case .connectedMac:
            return "Connected Mac destination: MacVault"
        case .directRaw:
            return "Direct CLI: strict raw output"
        case .directFiles:
            return "Direct CLI: generated files"
        }
    }

    func handle(url: URL) -> Bool {
        guard let action = Self.parse(url: url) else { return false }
        switch action {
        case .run(let request):
            guard verifyControlProof(request) else {
                statusMessage = "Rejected an unauthenticated export-lab request."
                return true
            }
            guard operationTask == nil,
                  state == .idle || state == .completed || state == .failed || state == .cancelled else {
                statusMessage = "Finish the current supervised export-lab run first."
                return true
            }
            self.request = request
            state = .awaitingConfirmation
            statusMessage = "Ready to run \(request.scenario.rawValue) against \(request.target.rawValue)."
            isConfirmationPresented = !request.isAutonomous
        case .end(let runID):
            if request?.runID == runID {
                operationTask?.cancel()
                operationTask = nil
                restoreIdleTimer()
                ExportPerformanceInstrumentation.endLabRun(runID: runID)
                request = nil
                state = .idle
                statusMessage = ""
                isConfirmationPresented = false
            }
        case .cancel(let runID):
            if request?.runID == runID, state == .running {
                cancel()
            }
        case .setupAPI(let binding):
            setupAPIFromStaging(binding: binding)
        case .setupLocal(let binding):
            pendingLocalSetupBinding = binding
            isLocalSetupPresented = true
        case .cleanup(let runID, let target, let binding):
            cleanupRun(runID: runID, target: target, binding: binding)
        }
        return true
    }

    func start(
        healthKitManager: HealthKitManager,
        syncService: SyncService,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) {
        guard let request, canStart else { return }
        guard UIApplication.shared.isProtectedDataAvailable else {
            failBeforeStart(.protectedDataUnavailable)
            return
        }
        guard healthKitManager.isAuthorized else {
            failBeforeStart(.healthKitUnavailable)
            return
        }
        guard !syncService.isSyncing,
              !IPhoneDirectExportCoordinator.shared.isExporting else {
            failBeforeStart(.operationInProgress)
            return
        }

        do {
            _ = try ExportPerformanceInstrumentation.beginLabRun(
                runID: request.runID,
                target: request.target
            )
        } catch {
            failBeforeStart(.operationInProgress)
            return
        }
        let armSpan = ExportPerformanceInstrumentation.beginSpan(
            pipeline: "export-lab",
            phase: "arm"
        )
        armSpan.finish(outcome: .success)
        let isDirect = request.target == .directRaw || request.target == .directFiles
        preventAutomaticLock(restoreAfter: isDirect ? .seconds(720) : nil)

        if isDirect {
            state = .armed
            statusMessage = "The export lab is armed. Start the matching CLI command on the Mac."
            isConfirmationPresented = false
            return
        }

        state = .running
        statusMessage = "Running supervised physical export…"
        operationTask = Task { [weak self] in
            guard let self else { return }
            syncService.isSyncing = true
            defer { syncService.isSyncing = false }
            let context = ExportPerformanceRunContext(
                runID: request.runID,
                target: request.target
            )
            await ExportPerformanceInstrumentation.withRunContext(context) {
                let runSpan = ExportPerformanceInstrumentation.beginSpan(
                    pipeline: "export-lab",
                    phase: "run"
                )
                do {
                    let result = try await self.execute(
                        request,
                        healthKitManager: healthKitManager,
                        syncService: syncService,
                        externalIntegrations: externalIntegrations
                    )
                    try Task.checkCancellation()
                    runSpan.finish(
                        outcome: .success,
                        itemCount: result.itemCount,
                        byteCount: result.byteCount
                    )
                    ExportPerformanceInstrumentation.endLabRun(runID: request.runID)
                    self.state = .completed
                    self.statusMessage = "The supervised physical export completed."
                } catch is CancellationError {
                    runSpan.finish(outcome: .cancelled)
                    ExportPerformanceInstrumentation.endLabRun(runID: request.runID)
                    self.state = .cancelled
                    self.statusMessage = "The supervised physical export was cancelled."
                } catch {
                    runSpan.finish(outcome: .failure)
                    ExportPerformanceInstrumentation.endLabRun(runID: request.runID)
                    self.state = .failed
                    self.statusMessage = "The supervised physical export failed. Review the health-free lab report on the Mac."
                }
                self.restoreIdleTimer()
                self.operationTask = nil
            }
        }
    }

    func cancel() {
        guard canCancel else { return }
        operationTask?.cancel()
    }

    func applicationDidEnterBackground() {
        guard let runID = request?.runID else { return }
        restoreIdleTimer()
        if state == .running {
            operationTask?.cancel()
            statusMessage = "Stopping because Health.md left the foreground…"
        } else if state == .armed {
            ExportPerformanceInstrumentation.beginSpan(
                pipeline: "export-lab",
                phase: "run"
            ).finish(outcome: .failure)
            ExportPerformanceInstrumentation.endLabRun(runID: runID)
            state = .failed
            statusMessage = "The supervised run stopped because Health.md left the foreground."
        }
    }

    func dismissCompletedRun() {
        guard state == .completed || state == .failed || state == .cancelled else { return }
        isConfirmationPresented = false
    }

    nonisolated static func parse(url: URL) -> LinkAction? {
        guard url.scheme?.lowercased() == "healthmd",
              url.host?.lowercased() == "export-lab",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard items.allSatisfy({ $0.value != nil }) else { return nil }
        let grouped = Dictionary(grouping: items, by: \.name)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else { return nil }
        let values = grouped.compactMapValues(\.first?.value)

        switch url.path {
        case "/run":
            guard let runID = values["run"],
                  ExportPerformanceLabTelemetryStore.isSafeRunID(runID),
                  let targetValue = values["target"],
                  let target = ExportPerformanceLabTarget(rawValue: targetValue),
                  let scenarioValue = values["scenario"],
                  let scenario = Scenario(rawValue: scenarioValue),
                  Self.supports(scenario: scenario, target: target),
                  let binding = values["binding"],
                  Self.isBinding(binding),
                  let controlProof = values["control"],
                  Self.isBinding(controlProof),
                  let mode = values["mode"],
                  mode == "confirm" || mode == "autonomous" else {
                return nil
            }
            let proof = values["proof"]
            let expectedMacInstallationID = values["peer"].flatMap(UUID.init(uuidString:))
            let baseKeys = Set(["run", "target", "scenario", "binding", "mode", "control"])
            if target == .apiEndpoint {
                guard Set(values.keys) == baseKeys.union(["proof"]),
                      let proof,
                      Self.isBinding(proof) else { return nil }
            } else if target == .connectedMac {
                guard Set(values.keys) == baseKeys.union(["peer"]),
                      expectedMacInstallationID != nil else { return nil }
            } else if Set(values.keys) != baseKeys {
                return nil
            }
            return .run(Request(
                runID: runID,
                target: target,
                scenario: scenario,
                binding: binding,
                controlProof: controlProof,
                proof: proof,
                expectedMacInstallationID: expectedMacInstallationID,
                isAutonomous: mode == "autonomous"
            ))
        case "/end":
            guard Set(values.keys) == Set(["run"]),
                  let runID = values["run"],
                  ExportPerformanceLabTelemetryStore.isSafeRunID(runID) else {
                return nil
            }
            return .end(runID: runID)
        case "/setup-api":
            guard Set(values.keys) == Set(["binding"]),
                  let binding = values["binding"],
                  Self.isBinding(binding) else { return nil }
            return .setupAPI(binding: binding)
        case "/setup-local":
            guard Set(values.keys) == Set(["binding"]),
                  let binding = values["binding"],
                  Self.isBinding(binding) else { return nil }
            return .setupLocal(binding: binding)
        case "/cancel":
            guard Set(values.keys) == Set(["run"]),
                  let runID = values["run"],
                  ExportPerformanceLabTelemetryStore.isSafeRunID(runID) else {
                return nil
            }
            return .cancel(runID: runID)
        case "/cleanup":
            guard Set(values.keys) == Set(["run", "target", "binding"]),
                  let runID = values["run"],
                  ExportPerformanceLabTelemetryStore.isSafeRunID(runID),
                  let targetValue = values["target"],
                  let target = ExportPerformanceLabTarget(rawValue: targetValue),
                  let binding = values["binding"],
                  Self.isBinding(binding) else {
                return nil
            }
            return .cleanup(runID: runID, target: target, binding: binding)
        default:
            return nil
        }
    }

    private nonisolated static func supports(
        scenario: Scenario,
        target: ExportPerformanceLabTarget
    ) -> Bool {
        switch target {
        case .directRaw:
            return scenario == .rawFull
        case .directFiles:
            return [
                .sleepSummary, .savedFull, .losslessDense, .multiDay,
                .thirtyDay, .interruptResume, .cancel,
            ].contains(scenario)
        case .localIPhone:
            return [
                .sleepSummary, .savedFull, .savedFullProviderEnabled,
                .savedFullProviderDisabled, .losslessDense, .multiDay,
                .cancel, .largeFileBackedBlob,
            ].contains(scenario)
        case .apiEndpoint, .connectedMac:
            return [
                .sleepSummary, .savedFull, .savedFullProviderEnabled,
                .savedFullProviderDisabled, .losslessDense, .multiDay, .cancel,
            ].contains(scenario)
        }
    }

    func completeLocalSetup(_ result: Result<[URL], Error>) {
        defer {
            pendingLocalSetupBinding = nil
            isLocalSetupPresented = false
        }
        guard let binding = pendingLocalSetupBinding,
              case .success(let urls) = result,
              let url = urls.first,
              url.lastPathComponent == "HealthMdPerformanceLab" else {
            statusMessage = "Select the dedicated HealthMdPerformanceLab folder."
            return
        }
        let vault = VaultManager()
        vault.setVaultFolder(url)
        vault.refreshVaultAccess()
        do {
            try verifyLocalDestination(vault: vault, binding: binding)
            statusMessage = "The dedicated Files destination is ready."
        } catch {
            statusMessage = "The selected Files destination could not be bound safely."
        }
    }

    private struct StagedAPISetup: Decodable {
        let endpoint: String
        let token: String
        let binding: String
        let proof: String
        let serverCertificateSHA256: String
    }

    private func setupAPIFromStaging(binding: String) {
        guard UIApplication.shared.isProtectedDataAvailable else {
            statusMessage = "Unlock iPhone before configuring the private API sink."
            return
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("HealthMdPerformanceLab", isDirectory: true)
        let stagingURL = root.appendingPathComponent("api-config.json")
        defer { try? FileManager.default.removeItem(at: stagingURL) }
        let values = try? stagingURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        )
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              (values?.fileSize ?? 0) <= 4_096,
              let data = try? Data(contentsOf: stagingURL),
              let staged = try? JSONDecoder().decode(StagedAPISetup.self, from: data),
              staged.binding == binding,
              Self.isBinding(staged.binding),
              Self.isBinding(staged.proof),
              Self.isBinding(staged.serverCertificateSHA256),
              (16...512).contains(staged.token.utf8.count),
              !staged.token.contains(where: \.isWhitespace),
              let endpoint = URL(string: staged.endpoint),
              endpoint.scheme?.lowercased() == "https",
              endpoint.port == 18_443,
              endpoint.path == "/export",
              endpoint.query == nil,
              endpoint.fragment == nil,
              let proofData = Self.hexData(staged.proof) else {
            statusMessage = "The staged API configuration was rejected."
            return
        }
        let message = [
            "setup-api",
            binding,
            endpoint.absoluteString,
            staged.serverCertificateSHA256,
        ]
            .joined(separator: "\n")
        let existingToken = APIExportSettings().bearerToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let authenticationToken = Self.apiSetupAuthenticationToken(
                existingToken: existingToken,
                stagedToken: staged.token
              ),
              HMAC<SHA256>.isValidAuthenticationCode(
                proofData,
                authenticating: Data(message.utf8),
                using: SymmetricKey(data: Data(authenticationToken.utf8))
              ) else {
            statusMessage = "The staged API configuration proof was rejected."
            return
        }
        if existingToken.isEmpty {
            pendingAPISetup = (
                endpoint,
                staged.token,
                staged.serverCertificateSHA256
            )
            isAPISetupConfirmationPresented = true
            statusMessage = "Confirm the initial private API sink setup."
            return
        }
        applyAPISetup(
            endpoint: endpoint,
            token: existingToken,
            certificateSHA256: staged.serverCertificateSHA256,
            root: root
        )
    }

    func completeInitialAPISetup(approved: Bool) {
        defer {
            pendingAPISetup = nil
            isAPISetupConfirmationPresented = false
        }
        guard approved, let pendingAPISetup else {
            statusMessage = "The private API sink setup was cancelled."
            return
        }
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("HealthMdPerformanceLab", isDirectory: true)
        applyAPISetup(
            endpoint: pendingAPISetup.endpoint,
            token: pendingAPISetup.token,
            certificateSHA256: pendingAPISetup.certificateSHA256,
            root: root
        )
    }

    private func applyAPISetup(
        endpoint: URL,
        token: String,
        certificateSHA256: String,
        root: URL
    ) {
        let settings = APIExportSettings()
        settings.endpointURLString = endpoint.absoluteString
        settings.bearerToken = token
        UserDefaults.standard.set(
            certificateSHA256,
            forKey: APIExportClient.debugPinnedCertificateSHA256Key
        )
        let receiptURL = root.appendingPathComponent("api-setup-complete")
        _ = FileManager.default.createFile(
            atPath: receiptURL.path,
            contents: Data("ready\n".utf8),
            attributes: [
                .posixPermissions: 0o600,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
            ]
        )
        statusMessage = "The private HTTPS export sink is configured."
    }

    nonisolated static func apiSetupAuthenticationToken(
        existingToken: String,
        stagedToken: String
    ) -> String? {
        existingToken.isEmpty || existingToken == stagedToken ? stagedToken : nil
    }

    nonisolated private static func isBinding(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
        }
    }

    private struct ExecutionResult: Sendable {
        let itemCount: Int
        let byteCount: Int64
    }

    private func execute(
        _ request: Request,
        healthKitManager: HealthKitManager,
        syncService: SyncService,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) async throws -> ExecutionResult {
        guard request.scenario != .rawFull else { throw LabError.invalidLink }
        if request.scenario == .largeFileBackedBlob {
            guard request.target == .localIPhone else { throw LabError.invalidLink }
            let vault = VaultManager()
            vault.refreshVaultAccess()
            try verifyLocalDestination(vault: vault, binding: request.binding)
            return try await runLargeFileBackedBlobStress()
        }

        let isolatedSettings = makeIsolatedSettings(runID: request.runID)
        defer { isolatedSettings.cleanup() }
        apply(request.scenario, to: isolatedSettings.settings)
        let dates = dates(for: request.scenario)
        let provider = usesProviderSidecars(request.scenario)
            ? externalIntegrations
            : nil

        switch request.target {
        case .localIPhone:
            let vault = VaultManager(
                defaults: SystemUserDefaults(defaults: isolatedSettings.defaults)
            )
            vault.healthSubfolder = "Runs/\(request.runID)"
            vault.refreshVaultAccess()
            try verifyLocalDestination(vault: vault, binding: request.binding)
            let result = await ExportOrchestrator.exportDates(
                dates,
                healthKitManager: healthKitManager,
                vaultManager: vault,
                settings: isolatedSettings.settings,
                externalIntegrations: provider
            )
            guard result.successCount > 0, !result.wasCancelled else {
                throw LabError.targetFailed
            }
            return ExecutionResult(itemCount: result.totalFilesWritten, byteCount: 0)

        case .apiEndpoint:
            let apiSettings = APIExportSettings()
            guard let destination = apiSettings.destinationSnapshot,
                  destination.endpointURL.scheme?.lowercased() == "https",
                  destination.endpointURL.port == 18_443,
                  destination.endpointURL.path == "/export",
                  destination.endpointURL.query == nil,
                  destination.authorizationHeaderValue != nil,
                  verifyAPIProof(
                    request: request,
                    endpointURL: destination.endpointURL,
                    token: apiSettings.bearerToken
                  ) else {
                throw LabError.apiDestinationUnavailable
            }
            let result = await APIEndpointExportRunner.export(
                dates: dates,
                healthKitManager: healthKitManager,
                settings: isolatedSettings.settings,
                destination: destination,
                externalIntegrations: provider
            )
            guard result.successCount > 0, !result.wasCancelled else {
                throw LabError.targetFailed
            }
            return ExecutionResult(itemCount: result.successCount, byteCount: 0)

        case .connectedMac:
            return try await runConnectedMac(
                runID: request.runID,
                expectedInstallationID: request.expectedMacInstallationID,
                dates: dates,
                settings: isolatedSettings.settings,
                healthKitManager: healthKitManager,
                syncService: syncService,
                externalIntegrations: provider
            )

        case .directRaw, .directFiles:
            throw LabError.invalidLink
        }
    }

    private func runConnectedMac(
        runID: String,
        expectedInstallationID: UUID?,
        dates: [Date],
        settings: AdvancedExportSettings,
        healthKitManager: HealthKitManager,
        syncService: SyncService,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) async throws -> ExecutionResult {
        guard syncService.canExportToConnectedMac(requiring: settings),
              syncService.macDestinationStatus?.destinationDisplayName == "MacVault",
              let remote = syncService.remoteCapabilities,
              remote.installationID == expectedInstallationID,
              let negotiation = SyncPeerCapabilities.current(platform: .iOS)
                .negotiateConnectedCorpusTransfer(with: remote),
              let first = dates.first,
              let last = dates.last else {
            throw LabError.connectedMacUnavailable
        }
        let jobID = UUID()
        let externalFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
        if let externalIntegrations,
           externalIntegrations.connectedProviderCount > 0 {
            externalFetcher = { date in
                await externalIntegrations.fetchDailyRecords(for: date)
            }
        } else {
            externalFetcher = nil
        }

        syncService.isSyncing = true
        defer { syncService.isSyncing = false }
        _ = try await IPhoneConnectedCorpusProducer.sendFileExport(
            jobID: jobID,
            startDate: first,
            endDate: last,
            requestedDates: dates,
            settings: settings,
            healthSubfolder: "Runs/\(runID)",
            destinationDisplayName: syncService.macDestinationStatus?.destinationDisplayName,
            negotiation: negotiation,
            healthKitManager: healthKitManager,
            externalRecordFetcher: externalFetcher,
            syncService: syncService,
            origin: .interactiveIPhone
        )

        let deadline = ContinuousClock.now.advanced(by: .seconds(600))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let message = syncService.latestMacExportMessage {
                switch message {
                case .macExportResult(let result) where result.jobID == jobID:
                    guard result.status == .success || result.status == .partialSuccess else {
                        throw LabError.targetFailed
                    }
                    return ExecutionResult(
                        itemCount: result.totalFilesWritten,
                        byteCount: 0
                    )
                case .macExportFailed(let failure) where failure.jobID == jobID:
                    throw LabError.targetFailed
                default:
                    break
                }
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw LabError.targetFailed
    }

    private func verifyLocalDestination(
        vault: VaultManager,
        binding: String
    ) throws {
        guard let root = vault.vaultURL,
              root.lastPathComponent == "HealthMdPerformanceLab",
              let accessLease = vault.beginVaultAccess() else {
            throw LabError.localDestinationUnavailable
        }
        defer { accessLease.stop() }
        let marker = root.appendingPathComponent(".healthmd-performance-lab")
        let attributes = try? FileManager.default.attributesOfItem(atPath: marker.path)
        if let fileType = attributes?[.type] as? FileAttributeType,
           fileType == .typeSymbolicLink {
            throw LabError.localDestinationUnavailable
        }
        if FileManager.default.fileExists(atPath: marker.path) {
            guard let data = try? Data(contentsOf: marker, options: .mappedIfSafe),
                  data.count <= 128,
                  String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines) == binding else {
                throw LabError.localDestinationUnavailable
            }
        } else {
            guard FileManager.default.createFile(
                atPath: marker.path,
                contents: Data("\(binding)\n".utf8),
                attributes: [
                    .posixPermissions: 0o600,
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication,
                ]
            ) else {
                throw LabError.localDestinationUnavailable
            }
        }
    }

    private func verifyControlProof(_ request: Request) -> Bool {
        let token = APIExportSettings().bearerToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let proofData = Self.hexData(request.controlProof) else { return false }
        let message = [
            request.runID,
            request.target.rawValue,
            request.scenario.rawValue,
            request.binding,
            request.expectedMacInstallationID?.uuidString.lowercased() ?? "-",
            request.isAutonomous ? "autonomous" : "confirm",
        ].joined(separator: "\n")
        return HMAC<SHA256>.isValidAuthenticationCode(
            proofData,
            authenticating: Data(message.utf8),
            using: SymmetricKey(data: Data(token.utf8))
        )
    }

    private func verifyAPIProof(
        request: Request,
        endpointURL: URL,
        token: String
    ) -> Bool {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              let proof = request.proof,
              let proofData = Self.hexData(proof) else { return false }
        let message = [
            request.runID,
            request.target.rawValue,
            request.scenario.rawValue,
            endpointURL.absoluteString,
        ].joined(separator: "\n")
        return HMAC<SHA256>.isValidAuthenticationCode(
            proofData,
            authenticating: Data(message.utf8),
            using: SymmetricKey(data: Data(token.utf8))
        )
    }

    nonisolated private static func hexData(_ value: String) -> Data? {
        guard isBinding(value) else { return nil }
        var data = Data(capacity: 32)
        var index = value.startIndex
        for _ in 0..<32 {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private func runLargeFileBackedBlobStress() async throws -> ExecutionResult {
        let requiredCapacity: Int64 = 700 * 1_024 * 1_024
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let values = try applicationSupport.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard (values.volumeAvailableCapacityForImportantUsage ?? 0) >= requiredCapacity else {
            throw LabError.insufficientDisk
        }

        let blobBytes = 256 * 1_024 * 1_024
        let sourceWorker = Task.detached(priority: .userInitiated) {
            let chunk = Data(repeating: 0xA5, count: 128 * 1_024)
            return try ExportArtifactIO.renderTemporary(
                prefix: "export-lab-blob",
                mediaType: "application/octet-stream"
            ) { sink in
                var remaining = blobBytes
                while remaining > 0 {
                    try Task.checkCancellation()
                    let count = min(remaining, chunk.count)
                    if count == chunk.count {
                        try sink.write(chunk)
                    } else {
                        try sink.write(Data(chunk.prefix(count)))
                    }
                    remaining -= count
                }
            }
        }
        let source = try await withTaskCancellationHandler {
            try await sourceWorker.value
        } onCancel: {
            sourceWorker.cancel()
        }
        let blob = HealthKitFileBackedBlob(artifact: source)
        let fixedDate = Date(timeIntervalSince1970: 0)
        let ownership = HealthKitDailyOwnershipMetadata(
            ownerDate: "1970-01-01",
            intervalStart: fixedDate,
            intervalEnd: fixedDate.addingTimeInterval(86_400),
            calendarTimeZoneIdentifier: "UTC"
        )
        let record = HealthKitRecord(
            originalUUID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            objectTypeIdentifier: "healthmd.export-lab.file-backed-blob",
            recordKind: .attachment,
            selectedMetricIDs: ["clinical_records"],
            includedBecause: .selectedMetric,
            startDate: fixedDate,
            endDate: fixedDate,
            sourceRevision: HealthKitSourceRevision(
                name: "Health.md Export Lab",
                bundleIdentifier: "com.codybontecou.obsidianhealth"
            ),
            metadata: ["payload": .fileBackedData(blob)],
            payload: .structured(kind: "attachment", fields: [:])
        )
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: ownership,
            records: [record]
        )
        let renderWorker = Task.detached(priority: .userInitiated) {
            try ExportArtifactIO.renderTemporary(
                prefix: "export-lab-rendered-blob",
                mediaType: "application/json"
            ) { sink in
                try HealthKitRecordArchiveSerializer.write(archive, to: sink)
            }
        }
        let output = try await withTaskCancellationHandler {
            try await renderWorker.value
        } onCancel: {
            renderWorker.cancel()
        }
        guard output.descriptor.byteCount > UInt64(blobBytes) else {
            throw LabError.targetFailed
        }
        return ExecutionResult(
            itemCount: 1,
            byteCount: Int64(output.descriptor.byteCount)
        )
    }

    private struct IsolatedSettings {
        let settings: AdvancedExportSettings
        let defaults: UserDefaults
        let suiteName: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeIsolatedSettings(runID: String) -> IsolatedSettings {
        let suiteName = "HealthMd.ExportPerformanceLab.\(runID)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            defaults.set(value, forKey: key)
        }
        return IsolatedSettings(
            settings: AdvancedExportSettings(userDefaults: defaults),
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func apply(_ scenario: Scenario, to settings: AdvancedExportSettings) {
        switch scenario {
        case .sleepSummary:
            settings.metricSelection.enabledCategories = [HealthMetricCategory.sleep.rawValue]
            settings.metricSelection.enabledMetrics = Set(
                (HealthMetrics.byCategory[.sleep] ?? []).map(\.id)
            )
            settings.includeGranularData = false
            settings.summaryOnlyExport = true
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        case .losslessDense:
            settings.metricSelection.enabledCategories = [HealthMetricCategory.heart.rawValue]
            settings.metricSelection.enabledMetrics = Set(
                (HealthMetrics.byCategory[.heart] ?? []).map(\.id)
            )
            settings.includeGranularData = true
            settings.summaryOnlyExport = false
        case .savedFullProviderDisabled:
            settings.metricSelection.enabledCategories = Set(
                HealthMetricCategory.availableCases
                    .filter { !$0.isPendingAppleApproval }
                    .map(\.rawValue)
            )
            settings.metricSelection.enabledMetrics = Set(
                HealthMetrics.availableInCurrentBuild
                    .filter {
                        !$0.isPendingAppleApproval
                            && $0.availability.isAvailableOnCurrentPlatform
                    }
                    .map(\.id)
            )
            settings.includeGranularData = true
            settings.summaryOnlyExport = false
        case .rawFull, .savedFull, .savedFullProviderEnabled, .multiDay,
             .thirtyDay, .interruptResume, .cancel, .largeFileBackedBlob:
            break
        }
    }

    private func dates(for scenario: Scenario) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch scenario {
        case .multiDay, .interruptResume, .cancel:
            return (1...7).reversed().compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }
        case .thirtyDay:
            return (1...30).reversed().compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }
        case .rawFull, .sleepSummary, .savedFull, .savedFullProviderEnabled,
             .savedFullProviderDisabled, .losslessDense:
            return [calendar.date(byAdding: .day, value: -1, to: today)!]
        case .largeFileBackedBlob:
            return []
        }
    }

    private func usesProviderSidecars(_ scenario: Scenario) -> Bool {
        scenario == .savedFull || scenario == .savedFullProviderEnabled
            || scenario == .multiDay || scenario == .thirtyDay
            || scenario == .interruptResume
            || scenario == .cancel
    }

    private func localMarkerMatches(root: URL, binding: String) -> Bool {
        let marker = root.appendingPathComponent(".healthmd-performance-lab")
        let values = try? marker.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true,
              let data = try? Data(contentsOf: marker, options: .mappedIfSafe),
              data.count <= 128 else { return false }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines) == binding
    }

    private func cleanupRun(
        runID: String,
        target: ExportPerformanceLabTarget,
        binding: String
    ) {
        guard ExportPerformanceLabTelemetryStore.isSafeRunID(runID),
              ExportPerformanceLabTelemetryStore.shared.activeContext?.runID != runID else {
            return
        }
        if target == .localIPhone {
            let vault = VaultManager()
            vault.refreshVaultAccess()
            if let root = vault.vaultURL,
               root.lastPathComponent == "HealthMdPerformanceLab",
               let accessLease = vault.beginVaultAccess() {
                defer { accessLease.stop() }
                if localMarkerMatches(root: root, binding: binding) {
                    let runsRoot = root.appendingPathComponent("Runs", isDirectory: true)
                        .standardizedFileURL
                    let destination = runsRoot.appendingPathComponent(runID, isDirectory: true)
                        .standardizedFileURL
                    if destination.deletingLastPathComponent() == runsRoot {
                        try? FileManager.default.removeItem(at: destination)
                    }
                }
            }
        }
        let telemetryRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("HealthMdPerformanceLab/Runs", isDirectory: true)
        .standardizedFileURL
        let telemetryRun = telemetryRoot.appendingPathComponent(runID, isDirectory: true)
            .standardizedFileURL
        if telemetryRun.deletingLastPathComponent() == telemetryRoot {
            try? FileManager.default.removeItem(at: telemetryRun)
        }
    }

    private func preventAutomaticLock(restoreAfter duration: Duration?) {
        if previousIdleTimerDisabled == nil {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = true
        idleTimerRestorationTask?.cancel()
        guard let duration, let runID = request?.runID else { return }
        idleTimerRestorationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled,
                  let self,
                  self.request?.runID == runID,
                  self.state == .armed else { return }
            self.restoreIdleTimer()
            ExportPerformanceInstrumentation.beginSpan(
                pipeline: "export-lab",
                phase: "run"
            ).finish(outcome: .failure)
            ExportPerformanceInstrumentation.endLabRun(runID: runID)
            self.state = .failed
            self.statusMessage = "The supervised run expired before the host completed it."
        }
    }

    private func restoreIdleTimer() {
        idleTimerRestorationTask?.cancel()
        idleTimerRestorationTask = nil
        guard let previousIdleTimerDisabled else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        self.previousIdleTimerDisabled = nil
    }

    private func failBeforeStart(_ error: LabError) {
        state = .failed
        statusMessage = "The export lab could not start. Resolve readiness on this iPhone and retry."
    }
}

struct IPhoneExportPerformanceLabConfirmationView: View {
    @ObservedObject var coordinator: IPhoneExportPerformanceLabCoordinator
    let start: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Physical Export Lab")
                    .font(.title2.bold())
                Text(coordinator.statusMessage)
                Text(coordinator.destinationSummary)
                    .font(.headline)
                Text("Verify that destination before starting. The local Files folder is privately bound on first confirmed use. This Debug-only run uses real HealthKit data and production export paths. Keep the iPhone unlocked, powered, and foregrounded. Payloads are not shown in lab reports.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if coordinator.state == .running {
                    ProgressView()
                    Button("Cancel Run", role: .destructive) {
                        coordinator.cancel()
                    }
                } else if coordinator.canStart {
                    Button("Start Supervised Run") { start() }
                        .buttonStyle(.borderedProminent)
                    Button("Not Now", role: .cancel) {
                        coordinator.isConfirmationPresented = false
                    }
                } else if coordinator.state == .completed
                            || coordinator.state == .failed
                            || coordinator.state == .cancelled {
                    Button("Done") { coordinator.dismissCompletedRun() }
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
            }
            .padding()
            .interactiveDismissDisabled(coordinator.state == .running)
        }
    }
}
#endif

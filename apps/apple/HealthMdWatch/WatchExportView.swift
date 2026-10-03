import SwiftUI

@MainActor
final class WatchExportViewModel: ObservableObject {
    @Published var endpoint = ""
    @Published var token = ""
    @Published var isConfigured = false
    @Published var hasPending = false
    @Published var isRunning = false
    @Published var message: String?
    @Published var errorMessage: String?
    // A navigation-away/reopen race must not create a second in-flight writer.
    private static let sharedService = WatchExportService(store: WatchExportKeychain(), transport: WatchExportHTTP())
    private var service: WatchExportService { Self.sharedService }
    private var task: Task<Void, Never>?

    func reload() {
        do {
            let state = try service.state()
            isConfigured = state.destination != nil
            hasPending = state.pending != nil
            endpoint = state.destination?.endpoint.absoluteString ?? ""
            // Never rehydrate the stored credential into an editable/displayable field.
            token = ""
        } catch { show(error) }
    }

    func save() {
        do {
            try service.configure(endpoint: endpoint, token: token)
            token = ""
            errorMessage = nil
            message = "Destination saved securely on this Watch. Sync Now sends local activity only."
            reload()
        } catch { show(error) }
    }

    func discard() {
        do {
            try service.discardPending()
            errorMessage = nil
            message = "Local pending snapshot discarded. This does not undo a possible backend delivery."
            reload()
        } catch { show(error) }
    }

    func forget() {
        do {
            try service.forgetDestination()
            errorMessage = nil
            message = "Destination and credential removed from this Watch."
            reload()
        } catch { show(error) }
    }

    func sync() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        task = Task {
            defer { isRunning = false; task = nil; reload() }
            do {
                try await service.sync(capture: { try await WatchExportCaptureProvider.capture() }) { message = $0 }
            } catch is CancellationError {
                message = "Interrupted. Any queued snapshot is retained; delivery may be uncertain. Retry when ready."
            } catch { show(error) }
        }
    }

    func cancel() { task?.cancel() }

    private func show(_ error: Error) {
        message = nil
        errorMessage = (error as? WatchExportError)?.localizedDescription ?? WatchExportError.storage.localizedDescription
    }
}

struct WatchExportView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = WatchExportViewModel()
    @State private var confirmDiscard = false
    @State private var confirmForget = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Send today's locally available steps, active energy, and Apple Exercise Time. No workouts, sleep, full history, or iPhone database. Missing values are unknown, not zero.")
                    .font(.footnote)
                Text("Use Connect Health on the dashboard first. Read permission can be denied without HealthKit revealing it.")
                    .font(.footnote)
                TextField("HTTPS endpoint", text: $model.endpoint)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isRunning || model.hasPending)
                SecureField("Backend bearer token", text: $model.token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isRunning || model.hasPending)
                Text("Only use a trusted backend that supports healthmd.watch_snapshot v1 and matching acknowledgements. Saving does not test or send data. A replacement token is required when saving changes.")
                    .font(.caption2)
                Button("Save Destination") { model.save() }
                    .disabled(model.isRunning || model.hasPending)
                Button(model.hasPending ? "Retry Pending Upload" : "Sync Now") { model.sync() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRunning || !model.isConfigured)
                if model.isRunning {
                    ProgressView("Syncing…")
                    Button("Cancel") { model.cancel() }
                }
                if let message = model.message { Text(message).font(.footnote) }
                if let error = model.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                if model.hasPending {
                    Text("Pending bytes stay bound to this destination and token, even after relaunch. Retry does not recapture. Keep the app open during upload.")
                        .font(.caption2)
                    Button("Discard Pending", role: .destructive) { confirmDiscard = true }
                        .disabled(model.isRunning)
                }
                if model.isConfigured {
                    Button("Forget Destination", role: .destructive) { confirmForget = true }
                        .disabled(model.isRunning || model.hasPending)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("API Sync")
        .task { model.reload() }
        .onDisappear { model.cancel() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } }
        .confirmationDialog("Delivery may already have occurred. Discard local pending bytes?", isPresented: $confirmDiscard) {
            Button("Discard Pending", role: .destructive) { model.discard() }
        }
        .confirmationDialog("Remove this Watch's API endpoint and credential?", isPresented: $confirmForget) {
            Button("Forget Destination", role: .destructive) { model.forget() }
        }
    }
}

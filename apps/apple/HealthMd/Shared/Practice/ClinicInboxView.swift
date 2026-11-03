#if canImport(SwiftUI)
import SwiftUI

/// Standalone entry for a future qualified app route. The default model has no configured transport.
@MainActor
struct ClinicInboxView: View {
    @Bindable var model: ClinicInboxModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var revoking: ClinicInboxRefresh?

    var body: some View {
        List {
            Section {
                Text("Review each clinic setup before saving it. Fresh exports run while Health.md is open and Health data is available.")
            }
            if model.snapshot.synthetic { Section { Text("Synthetic demo · No Health data is read or sent.") } }
            if model.busy { Section { ProgressView("Updating clinic request") } }
            if model.loading { Section { ProgressView("Loading clinic requests") } }
            if model.unavailable {
                Section { Text("Clinic connection is not available yet.") }
            } else if model.error {
                Section { Text("The clinic request could not be completed. Check your connection and export history before trying again.")
                    Button("Reload inbox") { Task { await model.load() } }.disabled(model.busy)
                }
            }
            Section("Setups to review") {
                if model.snapshot.reviews.isEmpty && !model.loading { Text("No clinic setups to review") }
                ForEach(model.snapshot.reviews) { item in
                    Button { model.openReview(item.id) } label: {
                        VStack(alignment: .leading) { Text(item.clinic).font(.headline); Text(item.profile).foregroundStyle(.secondary) }
                    }
                    .disabled(model.busy)
                    .accessibilityLabel("Review setup from \(item.clinic)")
                }
            }
            Section("Refresh requests") {
                if model.snapshot.refreshes.isEmpty && !model.loading { Text("No refresh requests") }
                ForEach(model.snapshot.refreshes) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.clinic).font(.headline)
                        Text(item.profile)
                        Text(item.destination).textSelection(.enabled)
                        Text(item.scope)
                        Text(item.metrics.joined(separator: ", "))
                        status(item.status).font(.subheadline)
                        if item.receiptPending {
                            Text("Upload saved on this phone. Clinic status confirmation is pending.").foregroundStyle(.secondary)
                            Button("Retry status report") { Task { await model.reportReceipt(item.id) } }
                        }
                        if item.status == .requested && item.sharingActive {
                            Button("Export now") { Task { await model.export(item.id) } }
                        }
                        if [.requested, .running].contains(item.status) {
                            Button("Cancel remaining work", role: .destructive) { Task { await model.cancel(item.id) } }
                        }
                        if !item.sharingActive && item.status != .revoked { Text("Sharing stopped") }
                        if item.sharingActive {
                            Button("Stop sharing with this clinic", role: .destructive) { revoking = item }
                        }
                    }
                    .disabled(model.busy || model.error)
                }
            }
        }
        .navigationTitle("Clinic sharing")
        .toolbar { Button("Reload inbox", systemImage: "arrow.clockwise") { Task { await model.load() } }.disabled(model.busy) }
        .task { await model.load() }
        .sheet(item: Binding(get: { model.review }, set: { _ in model.dismissReview() })) { review in
            ClinicSetupReviewSheet(model: model, review: review)
        }
        .confirmationDialog("Stop future sharing?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } })) {
            Button("Stop sharing", role: .destructive) {
                if let selected = revoking { Task { await model.revoke(selected.connectionID) } }
                revoking = nil
            }
        } message: { Text("This stops future clinic requests. Already uploaded files remain at their destination.") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.load() } } else { revoking = nil; model.clear() } }
        .onDisappear { model.clear() }
    }
    @ViewBuilder private func status(_ value: ClinicInboxStatus) -> some View {
        switch value {
        case .requested: Text("Requested · Waiting for you")
        case .running: Text("Running · Keep Health.md open")
        case .uploaded: Text("Uploaded · Awaiting clinic processing")
        case .processed: Text("Clinic processed")
        case .failed: Text("Stopped · Check export history before requesting another export")
        case .cancelled: Text("Cancelled · Existing uploads are retained")
        case .expired: Text("Expired · Request a new export from the clinic")
        case .revoked: Text("Sharing stopped")
        }
    }
}

@MainActor
private struct ClinicSetupReviewSheet: View {
    @Bindable var model: ClinicInboxModel
    let review: ClinicInboxReview
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Clinic and destination") {
                    LabeledContent("Clinic", value: review.clinic)
                    LabeledContent("Profile", value: review.profile)
                    Text(review.destination).textSelection(.enabled)
                }
                Section("Metrics to share") { ForEach(review.metrics, id: \.self) { Text($0) } }
                Section("Export options") {
                    ForEach(review.options) { fact in LabeledContent(fact.label, value: fact.value) }
                }
                Section("Schedule") {
                    Text(review.schedule)
                    Text("Schedules start paused. Enable scheduling separately after setup.").foregroundStyle(.secondary)
                }
                Section("Access and permissions") {
                    switch review.access {
                    case .clinicCovered: Text("Covered by your clinic")
                    case .consumer: Text("Using your existing access")
                    case .unavailable: Text("Clinic access is not ready. You can save this setup; export stays unavailable.")
                    }
                    Text("Saving this setup does not grant Health access. Health permissions and your sharing consent remain separate.")
                    LabeledContent("Review expires", value: review.expiresAt.formatted())
                }
                Section {
                    Toggle("I agree to share these metrics with this clinic", isOn: $model.consent).disabled(model.busy)
                    Button("Save approved setup") { Task { if await model.apply() { dismiss() } } }
                        .disabled(!model.canApply)
                    if model.error {
                        Text("Setup was not confirmed. Reload the inbox before retrying.")
                        Button("Reload inbox") { Task { await model.load(); dismiss() } }
                    }
                }
            }
            .navigationTitle("Review clinic setup")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.dismissReview(); dismiss() } } }
            .onDisappear { model.dismissReview() }
        }
    }
}

#Preview("Synthetic clinic inbox") {
    NavigationStack {
        ClinicInboxView(model: ClinicInboxModel(transport: SyntheticClinicInboxTransport(), enabled: { true }))
    }
}
#endif

#if os(iOS)
  import SwiftUI

  struct HostedAccountView: View {
    @ObservedObject var manager: HostedAccountManager
    @Environment(\.dismiss) private var dismiss
    @State private var metricIDs: Set<String>
    @State private var detail: HostedConsentDetail
    @State private var retentionDays: Int
    @State private var syncDayCount = 30
    @State private var draftOwnerBinding: String?
    @State private var draftRevision: UInt64?
    @State private var draftWasEdited = false
    @State private var showMetrics = false
    @State private var confirmRevocation = false
    @State private var confirmDeletion = false

    init(manager: HostedAccountManager) {
      self.manager = manager
      let existing = manager.consent
      let retentionDays = Int(existing?.retentionDays ?? 365)
      _metricIDs = State(initialValue: existing?.metricIDs ?? Self.defaultMetricIDs)
      _detail = State(initialValue: existing?.maximumDetail ?? .summary)
      _retentionDays = State(initialValue: retentionDays)
      _syncDayCount = State(initialValue: min(30, retentionDays))
      _draftOwnerBinding = State(initialValue: existing?.ownerBinding)
      _draftRevision = State(initialValue: existing?.revision)
    }

    var body: some View {
      NavigationStack {
        Form {
          statusSection
          if manager.isConfigured, manager.isConnected {
            consentSection
            synchronizationSection
            deletionSection
          }
          if let message = manager.statusMessage {
            Section("Latest result") {
              Text(message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("hosted-account-status-message")
            }
          }
        }
        .navigationTitle("Hosted Health.md")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
          }
        }
        .disabled(manager.isBusy)
        .onChange(of: retentionDays) { _, updatedValue in
          syncDayCount = min(syncDayCount, updatedValue)
        }
        .onChange(of: manager.consent) { _, updatedConsent in
          reconcileDraft(with: updatedConsent)
        }
        .onChange(of: manager.remoteStatus) { _, _ in
          reconcileDraft(with: manager.consent)
        }
        .overlay {
          if manager.isBusy {
            ProgressView()
              .padding()
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
          }
        }
        .alert("Revoke hosted synchronization?", isPresented: $confirmRevocation) {
          Button("Cancel", role: .cancel) {}
          Button("Revoke and Delete Data", role: .destructive) {
            Task { await manager.revokeConsent() }
          }
        } message: {
          Text(
            "This revokes synchronization consent and crypto-erases the synchronized hosted corpus. Local Apple Health data is unchanged."
          )
        }
        .alert("Delete hosted account data?", isPresented: $confirmDeletion) {
          Button("Cancel", role: .cancel) {}
          Button("Delete Account Data", role: .destructive) {
            Task { await manager.deleteAccount() }
          }
        } message: {
          Text(
            "This deletes hosted consent, encrypted synchronized days, and hosted account key material. Local Apple Health data is unchanged."
          )
        }
      }
    }

    @ViewBuilder
    private var statusSection: some View {
      Section("Account") {
        if !manager.isConfigured {
          Label(
            "Hosted synchronization is not configured for this build.",
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.secondary)
        } else if !manager.isProtectedStateAvailable {
          Label(
            "Unlock this device so Health.md can verify protected account state.",
            systemImage: "lock.fill"
          )
          .foregroundStyle(.secondary)
          Button("Retry Protected State") {
            _ = manager.reloadProtectedState()
          }
        } else if manager.hasCorruptProtectedState {
          Label(
            manager.hasPendingMutation
              ? "A protected privacy-recovery record is invalid. Reauthorize the original account before deleting its hosted data."
              : "The local hosted account record is invalid. You can reset only this iPhone's connection, then reconnect.",
            systemImage: "exclamationmark.shield.fill"
          )
          .foregroundStyle(.secondary)
          if manager.hasPendingMutation {
            Button("Reauthorize Original Account and Delete Hosted Data", role: .destructive) {
              Task { await manager.connect() }
            }
          } else {
            Button("Reset Invalid Local Connection", role: .destructive) {
              Task { await manager.resetInvalidLocalState() }
            }
          }
        } else if !manager.isConnected {
          Text(
            manager.hasPendingMutation
              ? "Reauthorize the original account to finish the pending privacy operation. A different account will be rejected."
              : "Connect through the configured OAuth provider. Health.md requests only synchronization-write and account-management scopes; read-only MCP access is authorized separately."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          Button(
            manager.hasPendingMutation
              ? "Reauthorize Original Account"
              : "Connect Hosted Account"
          ) {
            Task { await manager.connect() }
          }
          .accessibilityIdentifier("hosted-account-connect")
        } else {
          LabeledContent("Connection", value: "Connected")
          LabeledContent(
            "Consent",
            value: manager.hasPendingMutation
              ? "Recovery required"
              : (manager.consent == nil ? "Review required" : "Active")
          )
          if manager.hasPendingMutation {
            Text(
              "A previous consent, revocation, or deletion request has an unknown outcome. Refresh status to reconcile it before making another change."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
          }
          if let status = manager.remoteStatus {
            LabeledContent(
              "Remote consent",
              value: status.consentState.rawValue.capitalized
            )
          }
          Button("Refresh Status") {
            Task { await manager.refreshStatus() }
          }
        }
      }
    }

    private var consentSection: some View {
      Section {
        Picker(
          "Maximum detail",
          selection: Binding(
            get: { detail },
            set: {
              detail = $0
              draftWasEdited = true
            }
          )
        ) {
          Text("Summary").tag(HostedConsentDetail.summary)
          Text("Lossless evidence").tag(HostedConsentDetail.lossless)
        }
        Stepper(
          "Retention: \(retentionDays) days",
          value: Binding(
            get: { retentionDays },
            set: {
              retentionDays = $0
              draftWasEdited = true
            }
          ),
          in: 1...3_650
        )
        DisclosureGroup("Metrics (\(metricIDs.count))", isExpanded: $showMetrics) {
          ForEach(Self.availableMetrics) { (metric: HealthMetricDefinition) in
            Toggle(
              isOn: Binding(
                get: { metricIDs.contains(metric.id) },
                set: { enabled in
                  if enabled { metricIDs.insert(metric.id) } else { metricIDs.remove(metric.id) }
                  draftWasEdited = true
                }
              )
            ) {
              Text(metric.name)
            }
          }
        }
        Text(
          "Only the selected metrics and Apple Health/Health.md summary sources are allowed. Summary omits source values, notes, workout details, and sleep-stage intervals; Lossless includes those details when available. Reducing consent purges the synchronized corpus before narrower data can be uploaded."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        Button(manager.consent == nil ? "Activate Consent" : "Replace Consent") {
          Task {
            await manager.activateConsent(
              metricIDs: metricIDs,
              detail: detail,
              retentionDays: retentionDays
            )
          }
        }
        .disabled(metricIDs.isEmpty || manager.hasPendingMutation)
        .accessibilityIdentifier("hosted-account-activate-consent")
      } header: {
        Text("Explicit synchronization consent")
      }
    }

    private var synchronizationSection: some View {
      Section("Synchronization") {
        Toggle(
          "Refresh latest completed day when Health.md becomes active",
          isOn: Binding(
            get: { manager.automaticSyncEnabled },
            set: manager.setAutomaticSyncEnabled
          )
        )
        .disabled(manager.consent == nil || manager.hasPendingMutation)
        .accessibilityIdentifier("hosted-account-automatic-sync")
        Stepper(
          "Completed days: \(syncDayCount)",
          value: $syncDayCount,
          in: 1...min(365, retentionDays)
        )
        Button("Synchronize Now") {
          Task { await manager.synchronizeRecentDays(count: syncDayCount) }
        }
        .disabled(manager.consent == nil || manager.hasPendingMutation)
        .accessibilityIdentifier("hosted-account-sync-now")
        Text(
          "Compact context days are projected on this iPhone, digest-bound, sent in bounded idempotent batches, and never logged. Automatic refresh is opt-in, runs only after the app becomes active with protected data available, and sends only the latest completed day. A protected local journal records only successful owner-date digests."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }

    private var deletionSection: some View {
      Section("Privacy controls") {
        Button("Revoke Consent and Delete Synchronized Data", role: .destructive) {
          confirmRevocation = true
        }
        .disabled(manager.consent == nil || manager.hasPendingMutation)
        Button("Delete Hosted Account Data", role: .destructive) {
          confirmDeletion = true
        }
        .disabled(manager.hasPendingMutation)
      }
    }

    private func reconcileDraft(with consent: HostedLocalConsent?) {
      guard let consent else {
        guard let ownerBinding = manager.remoteStatus?.ownerBinding,
          ownerBinding != draftOwnerBinding
        else { return }
        metricIDs = Self.defaultMetricIDs
        detail = .summary
        retentionDays = 365
        syncDayCount = min(30, retentionDays)
        draftOwnerBinding = ownerBinding
        draftRevision = nil
        draftWasEdited = false
        return
      }
      let alreadyMatches =
        metricIDs == consent.metricIDs
        && detail == consent.maximumDetail
        && retentionDays == Int(consent.retentionDays)
      if alreadyMatches {
        draftOwnerBinding = consent.ownerBinding
        draftRevision = consent.revision
        draftWasEdited = false
        return
      }
      let principalChanged = draftOwnerBinding != consent.ownerBinding
      let revisionChanged = draftRevision != consent.revision
      guard principalChanged || (revisionChanged && !draftWasEdited) else { return }
      metricIDs = consent.metricIDs
      detail = consent.maximumDetail
      retentionDays = Int(consent.retentionDays)
      syncDayCount = min(syncDayCount, retentionDays)
      draftOwnerBinding = consent.ownerBinding
      draftRevision = consent.revision
      draftWasEdited = false
    }

    private static let availableMetrics: [HealthMetricDefinition] = HealthMetrics.all
      .filter {
        !$0.isPendingAppleApproval
          && $0.availability.isAvailableOnCurrentPlatform
      }
      .sorted(by: { (lhs: HealthMetricDefinition, rhs: HealthMetricDefinition) in
        if lhs.category.rawValue != rhs.category.rawValue {
          return lhs.category.rawValue < rhs.category.rawValue
        }
        return lhs.name < rhs.name
      })

    private static let defaultMetricIDs: Set<String> = Set(
      availableMetrics.filter { $0.isEnabledByDefault }.map { $0.id }
    )
  }
#endif

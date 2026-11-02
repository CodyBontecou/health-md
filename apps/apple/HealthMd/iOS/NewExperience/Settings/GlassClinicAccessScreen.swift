#if os(iOS)
import SwiftUI

/// ClinicAccessG. Reachable only while `PracticeFeaturePolicy.current.isEnabled`, which is
/// false in production. Everything here is local to this device: see `ClinicAccessStore`.
struct GlassClinicAccessScreen: View {
    let coordinator: ExportProfileCoordinator?

    @StateObject private var store = ClinicAccessStore()
    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager
    @State private var tokenDraft = ""
    @State private var errorMessage: String?
    @State private var confirmingDisconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                GlassPanel {
                    GlassRow(
                        title: store.clinicName ?? String(localized: "No clinic connected"),
                        subtitle: store.clinicName == nil
                            ? String(localized: "Your clinic sends an invitation when it offers access.")
                            : String(localized: "Sponsored access · invitation accepted")
                    ) {
                        GlassIconTile(systemImage: "cross.case", color: .settingsTileGreen)
                    } trailing: {
                        EmptyView()
                    }
                    .accessibilityElement(children: .combine)
                }

                GlassSectionLabel(title: String(localized: "Your sharing choice"))
                GlassPanel {
                    GlassToggleRow(
                        title: String(localized: "Share with this clinic"),
                        isOn: Binding(get: { store.isSharingEnabled }, set: { store.setSharingEnabled($0) })
                    )
                    .accessibilityIdentifier("glass.clinic.sharing")
                    NavigationLink {
                        GlassClinicDestinationProfilePicker(store: store, profiles: coordinator?.profileStore.profiles ?? [])
                    } label: {
                        GlassRow(title: String(localized: "Use clinic destination")) {
                            HStack(spacing: 8) {
                                Text(usesClinicDestination ? String(localized: "In profile") : String(localized: "Off"))
                                    .glassFont(.body)
                                    .foregroundStyle(palette.muted)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.muted)
                                    .accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .top) {
                            Rectangle().fill(palette.line).frame(height: 1)
                                .padding(.horizontal, GlassMetrics.panelPadding)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("glass.clinic.destination")
                }
                .configurationChangesProtected()
                note(String(localized: "Only metrics and dates you select are sent. Turning sharing off stops future uploads; it doesn’t delete what the clinic already has."))

                GlassPanel {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upload token").glassFont(.caption).foregroundStyle(palette.muted)
                            .accessibilityHidden(true)
                        SecureField(
                            store.hasUploadToken
                                ? String(localized: "Saved — enter a new token to replace it")
                                : String(localized: "Only if your clinic gave you one"),
                            text: $tokenDraft
                        )
                        .textFieldStyle(.plain)
                        .glassFont(.body)
                        .foregroundStyle(palette.text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .frame(minHeight: 28)
                        .accessibilityLabel(String(localized: "Upload token"))
                        .onSubmit(saveToken)
                        Text("Stored in Keychain, used only for this clinic’s endpoint.")
                            .font(.system(size: 12))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.horizontal, GlassMetrics.panelPadding)
                    .padding(.vertical, 10)
                    if !tokenDraft.isEmpty {
                        Button(String(localized: "Save"), action: saveToken)
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .padding(GlassMetrics.panelPadding)
                    }
                }
                .configurationChangesProtected()

                GlassPanel {
                    GlassSettingsRow(title: String(localized: "Refresh clinic access")) { store.refresh() }
                    Button(role: .destructive) {
                        configurationProtection.performConfigurationChange { confirmingDisconnect = true }
                    } label: {
                        Text("Disconnect clinic")
                            .glassFont(.body)
                            .foregroundStyle(palette.coral)
                            .frame(maxWidth: .infinity, minHeight: GlassMetrics.rowMinHeight, alignment: .leading)
                            .padding(.horizontal, GlassMetrics.panelPadding)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) {
                        Rectangle().fill(palette.line).frame(height: 1)
                            .padding(.horizontal, GlassMetrics.panelPadding)
                    }
                }
                note(String(localized: "Your own purchased access and local data stay available."))

                if let errorMessage {
                    GlassBanner(title: errorMessage, systemImage: "exclamationmark.triangle", tone: .warning)
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Clinic access"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("glass.clinicAccess")
        .confirmationDialog(
            String(localized: "Disconnect clinic"),
            isPresented: $confirmingDisconnect,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Disconnect clinic"), role: .destructive) {
                do {
                    try store.disconnect()
                    tokenDraft = ""
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("Your own purchased access and local data stay available.")
        }
    }

    /// Only an automation that still exists counts.
    private var usesClinicDestination: Bool {
        guard let id = store.clinicDestinationProfileID else { return false }
        return coordinator?.profileStore.profiles.contains { $0.id == id } ?? false
    }

    private func saveToken() {
        configurationProtection.performConfigurationChange {
            do {
                try store.saveUploadToken(tokenDraft)
                tokenDraft = ""
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .glassFont(.rowSubtitle)
            .foregroundStyle(palette.muted)
            .padding(.horizontal, 4)
    }
}
#endif

#if os(iOS)
/// "Use clinic destination": which automation sends to the clinic, or none. Local only,
/// like the rest of `ClinicAccessStore`.
private struct GlassClinicDestinationProfilePicker: View {
    @ObservedObject var store: ClinicAccessStore
    let profiles: [ExportProfile]

    @Environment(\.glassPalette) private var palette
    @EnvironmentObject private var configurationProtection: ConfigurationProtectionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                GlassPanel {
                    option(String(localized: "Off"), id: nil, showsDivider: false)
                    ForEach(profiles) { profile in
                        option(profile.name, id: profile.id, showsDivider: true)
                    }
                }
            }
            .padding(.horizontal, GlassMetrics.screenMargin)
            .padding(.top, 12)
            .padding(.bottom, GlassMetrics.scrollBottomInset)
        }
        .background(palette.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Use clinic destination"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ title: String, id: UUID?, showsDivider: Bool) -> some View {
        let selected = store.clinicDestinationProfileID == id
            || (id == nil && !profiles.contains { $0.id == store.clinicDestinationProfileID })
        return Button {
            configurationProtection.performConfigurationChange { store.setClinicDestinationProfile(id) }
        } label: {
            GlassRow(title: title) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .top) {
                if showsDivider {
                    Rectangle().fill(palette.line).frame(height: 1)
                        .padding(.horizontal, GlassMetrics.panelPadding)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif

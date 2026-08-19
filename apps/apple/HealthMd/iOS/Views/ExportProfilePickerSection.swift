import SwiftUI

/// Compact profile switcher rendered at the top of the Export tab.
///
/// Phase 2 surface for export profiles (see
/// `docs/features/export-profiles.md`): switching profiles loads the frozen
/// snapshot into the shared export settings and adopts the profile's
/// destinations; adding duplicates the active profile; deleting is refused
/// for the last remaining profile.
struct ExportProfilePickerSection: View {
    @ObservedObject var coordinator: ExportProfileCoordinator
    @State private var showRenameAlert = false
    @State private var showDeleteConfirmation = false
    @State private var showManageProfiles = false
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.accent)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Export Profile")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)

                    Text(profileSummary)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Menu {
                    ForEach(coordinator.profileStore.profiles) { profile in
                        Button {
                            coordinator.activate(profileID: profile.id)
                        } label: {
                            if profile.id == coordinator.profileStore.activeProfileID {
                                Label(profile.name, systemImage: "checkmark")
                            } else {
                                Text(profile.name)
                            }
                        }
                    }

                    Divider()

                    Button {
                        coordinator.addProfileDuplicatingActive()
                    } label: {
                        Label(
                            String(localized: "New Profile From Current", comment: "Action: duplicate the active export profile"),
                            systemImage: "plus.square.on.square"
                        )
                    }

                    Button {
                        renameText = coordinator.activeProfileName ?? ""
                        showRenameAlert = true
                    } label: {
                        Label(
                            String(localized: "Rename…", comment: "Action: rename the active export profile"),
                            systemImage: "pencil"
                        )
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label(
                            String(localized: "Delete Profile…", comment: "Action: delete the active export profile"),
                            systemImage: "trash"
                        )
                    }
                    .disabled(coordinator.profileStore.profiles.count <= 1)

                    #if os(iOS)
                    Divider()

                    Button {
                        showManageProfiles = true
                    } label: {
                        Label(
                            String(localized: "Manage Profiles…", comment: "Action: open the export profiles management view"),
                            systemImage: "list.bullet"
                        )
                    }
                    #endif
                } label: {
                    HStack(spacing: Spacing.s2) {
                        Text(coordinator.activeProfileName ?? String(localized: "Profile", comment: "Fallback export profile label"))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accent)
                    .padding(.horizontal, Spacing.s3)
                    .padding(.vertical, Spacing.s2)
                    .background(
                        Capsule().fill(Color.accent.opacity(0.12))
                    )
                }
                .accessibilityLabel(String(localized: "Export profile picker", comment: "Accessibility label for the profile menu"))
            }

            Text(profileNotice)
                .font(.caption)
                .foregroundStyle(Color.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 40)
        }
        .padding(.vertical, Spacing.s3)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.bgSecondary)
        )
        #if os(iOS)
        .navigationDestination(isPresented: $showManageProfiles) {
            ExportProfilesView(coordinator: coordinator)
        }
        #endif
        .alert(
            String(localized: "Rename Profile", comment: "Alert title: rename export profile"),
            isPresented: $showRenameAlert
        ) {
            TextField(
                String(localized: "Profile name", comment: "Placeholder for export profile name"),
                text: $renameText
            )
            Button(String(localized: "Save", comment: "Confirm rename")) {
                _ = coordinator.renameProfile(
                    id: coordinator.profileStore.activeProfileID ?? UUID(),
                    to: renameText
                )
            }
            Button(String(localized: "Cancel", comment: "Dismiss rename"), role: .cancel) { }
        }
        .confirmationDialog(
            String(localized: "Delete this profile?", comment: "Confirm deleting the active export profile"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                String(
                    localized: "Delete “%@”",
                    comment: "Destructive action deleting the named export profile"
                ),
                role: .destructive
            ) {
                if let id = coordinator.profileStore.activeProfileID {
                    _ = coordinator.deleteProfile(id: id)
                }
            }
            Button(String(localized: "Cancel", comment: "Dismiss delete"), role: .cancel) { }
        } message: {
            Text(String(
                localized: "Its saved settings and destination bindings are removed. Scheduled exports for other profiles are not affected.",
                comment: "Explanation shown when deleting an export profile"
            ))
        }
    }

    private var profileSummary: String {
        let target: String
        switch coordinator.activeTarget {
        case .localIPhoneFolder:
            target = String(localized: "Local iPhone Folder", comment: "Export target name")
        case .connectedMac:
            target = String(localized: "Connected Mac", comment: "Export target name")
        case .apiEndpoint:
            target = String(localized: "API Endpoint", comment: "Export target name")
        case nil:
            target = ""
        }
        return String(
            localized: "Editing: \(target)",
            comment: "Summary line under the profile name showing the bound export target"
        )
    }

    private var profileNotice: String {
        String(
            localized: "Switching profiles loads its metrics, formats, and destination. The last remaining profile can't be deleted.",
            comment: "Caption explaining profile switching behavior"
        )
    }
}

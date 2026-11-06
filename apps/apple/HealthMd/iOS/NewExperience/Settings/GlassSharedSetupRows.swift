#if os(iOS)
import SwiftUI
import UIKit

/// SettingsMoreG's Share setup and Import setup rows. Same coordinator calls, file types
/// and accessibility identifiers as `SharedSetupConfigurationCard`.
struct GlassSharedSetupRows: View {
    @ObservedObject var coordinator: SharedSetupCoordinator

    @Environment(\.glassPalette) private var palette
    @State private var isImporterPresented = false
    @State private var exportDocument: SharedSetupDocument?
    @State private var isExporterPresented = false
    @State private var shareURL: URL?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassPanel {
                Menu {
                    Button("Save to Files") { prepareExport() }
                    Button("System Share") { prepareShare() }
                } label: {
                    GlassRow(
                        title: String(localized: "Share setup"),
                        subtitle: String(localized: "Export a portable setup — no health data or credentials")
                    ) {
                        GlassIconTile(systemImage: "square.and.arrow.up", color: .settingsTileViolet)
                    } trailing: {
                        chevron
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.SharedSetup.share)

                Button {
                    coordinator.beginImport()
                    isImporterPresented = true
                } label: {
                    GlassRow(
                        title: String(localized: "Import setup"),
                        subtitle: String(localized: "Review changes before applying · undo available")
                    ) {
                        GlassIconTile(systemImage: "square.and.arrow.down", color: .settingsTileBlue)
                    } trailing: {
                        chevron
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(palette.line).frame(height: 1)
                            .padding(.horizontal, GlassMetrics.panelPadding)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(AccessibilityID.SharedSetup.use)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.SharedSetup.configurationCard)

            // Kept verbatim from the classic card: the user must know what a setup file copies.
            Text("Share export preferences—not health data, permissions, credentials, purchases, or device access. Custom Markdown, frontmatter values, and endpoint host/path are copied verbatim, so review them for personal, tenant, routing, or secret text before sending.")
                .glassFont(.rowSubtitle)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, 4)
        }
        .sharedSetupFileImporter(isPresented: $isImporterPresented, coordinator: coordinator)
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .healthMdConfiguration,
            defaultFilename: "Health-md-Setup.healthmdconfig"
        ) { result in
            if case .failure(let error) = result { coordinator.errorMessage = error.localizedDescription }
        }
        .sheet(item: Binding(
            get: { shareURL.map(ShareItem.init) },
            set: { value in
                if value == nil {
                    coordinator.removeShareArtifact(shareURL)
                    shareURL = nil
                }
            }
        )) { item in
            ActivitySheet(url: item.url)
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.muted)
            .accessibilityHidden(true)
    }

    private func prepareExport() {
        do {
            exportDocument = try SharedSetupDocument(data: coordinator.exportData(appVersion: appVersion))
            isExporterPresented = true
        } catch {
            coordinator.errorMessage = error.localizedDescription
        }
    }

    private func prepareShare() {
        do {
            shareURL = try coordinator.makeShareArtifact(appVersion: appVersion)
        } catch {
            coordinator.errorMessage = error.localizedDescription
        }
    }

    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    private struct ActivitySheet: UIViewControllerRepresentable {
        let url: URL
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: [url], applicationActivities: nil)
        }
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }
}
#endif

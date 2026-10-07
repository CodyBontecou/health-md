import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

private struct DiagnosticTextPreview: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

/// Release-available, native review/share flow; technical events are the primary
/// content, not localized replacement error summaries.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = DiagnosticRecorder.shared.settings
    @State private var events: [DiagnosticEvent] = []
    @State private var includePrivate = false
    @State private var hours = 24
    @State private var subsystem = "all"
    @State private var operationID = ""
    @State private var search = ""
    @State private var attachments: [URL] = []
    @State private var prepared: PreparedDiagnosticBundle?
    @State private var preview: DiagnosticTextPreview?
    @State private var choosingFiles = false
    @State private var reviewed = false
    @State private var busy = false
    @State private var error: String?
    @State private var summary = ""
    @State private var confirmShare = false
    @State private var reloadGeneration = UUID()
    @State private var confirmClear = false
    #if os(iOS)
    @State private var sharedURL: URL?
    @State private var showShare = false
    #else
    @State private var sharingPicker: NSSharingServicePicker?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Local Recording") {
                    Text("Diagnostics stay on this device until you save or share them. Operational events contain no health values, health record IDs, requested health dates, paths, endpoints, or credentials. They are not anonymous.")
                        .foregroundStyle(Color.textSecondary)
                    Toggle("Record Operational Events", isOn: $settings.enabled)
                        .accessibilityIdentifier("diagnostics.enabled")
                    Picker("Verbosity", selection: $settings.verbosity) {
                        ForEach(DiagnosticVerbosity.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Text("Info, Debug, and Trace change detail—not permission to collect health content. Retention: up to 7 days / 20 MiB. No automatic uploads.")
                        .font(Typography.caption()).foregroundStyle(Color.textSecondary)
                    if settings.privateContextUntil > Date().timeIntervalSince1970 {
                        Text("Private context recording expires at \(Date(timeIntervalSince1970: settings.privateContextUntil).formatted(date: .omitted, time: .shortened)).")
                        Button("Stop Private Recording") {
                            DiagnosticRecorder.shared.stopPrivateContextRecording()
                            settings = DiagnosticRecorder.shared.settings
                        }
                    } else {
                        Button("Record Private Context for 15 Minutes") {
                            DiagnosticRecorder.shared.startPrivateContextRecording()
                            settings = DiagnosticRecorder.shared.settings
                        }.disabled(!settings.enabled)
                    }
                    Text("V1 private context records peer names. It does not capture health payloads, credentials, or arbitrary error text. Private segments expire within 24 hours on the next app access.")
                        .font(Typography.caption()).foregroundStyle(Color.textSecondary)
                    Button("Clear All Diagnostics", role: .destructive) { confirmClear = true }
                        .accessibilityIdentifier("diagnostics.clear")
                }
                Section("Select Events") {
                    Picker("Time Range", selection: $hours) {
                        Text("Last Hour").tag(1); Text("Last 24 Hours").tag(24); Text("Last 7 Days").tag(168)
                    }
                    Picker("Subsystem", selection: $subsystem) {
                        ForEach(["all", "connection", "schedule", "notification", "export", "lifecycle", "diagnostics"], id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    TextField("Operation UUID (Optional)", text: $operationID)
                        .font(Typography.mono())
                    Toggle("Include Recorded Private Context", isOn: $includePrivate)
                    TextField("Search Event IDs or Fields", text: $search)
                    Button("Refresh Events", action: reload)
                    Text(summary).font(Typography.caption()).foregroundStyle(Color.textSecondary)
                    ForEach(events.filter { search.isEmpty || $0.jsonLine.localizedCaseInsensitiveContains(search) }.suffix(100).reversed()) { event in
                        Button {
                            preview = DiagnosticTextPreview(title: event.event_id.rawValue, text: event.jsonLine)
                        } label: {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(event.event_id.rawValue).font(Typography.mono()).foregroundStyle(Color.textPrimary)
                                Text("\(event.timestamp) · \(event.severity) · \(event.source)")
                                    .font(Typography.caption()).foregroundStyle(Color.textSecondary)
                            }
                        }.buttonStyle(.plain)
                    }
                    Text("Showing the newest 100 matching events. The bundle includes the selected snapshot, up to 10,000 events; any truncation is disclosed.")
                        .font(Typography.caption()).foregroundStyle(Color.textSecondary)
                }
                Section("Optional Attachments") {
                    Text("Add any existing files, including health exports or screenshots. Original bytes are copied unchanged and are NOT scrubbed. Source filenames are included. No new health reads are made. Limit: 50 files / 100 MiB.")
                        .font(Typography.caption()).foregroundStyle(Color.textSecondary)
                    Button("Choose Files…") { choosingFiles = true }
                        .accessibilityIdentifier("diagnostics.attach")
                    ForEach(Array(attachments.enumerated()), id: \.offset) { index, url in
                        HStack {
                            Text(url.lastPathComponent).font(Typography.mono()).textSelection(.enabled)
                            Spacer()
                            Button("Remove") { attachments.remove(at: index); invalidate() }
                        }
                    }
                }
                Section("Prepare and Review") {
                    Button(busy ? "Preparing…" : "Prepare Bundle") { prepare() }
                        .accessibilityIdentifier("diagnostics.prepare")
                    if let prepared {
                        Text("Frozen snapshot: \(prepared.manifest.event_count) events. Health content: \(prepared.manifest.health_content). ZIP is not encrypted.")
                            .foregroundStyle(Color.textSecondary)
                        ForEach(["manifest.json"] + prepared.manifest.files.map(\.path), id: \.self) { path in
                            Button(path) { showFile(path, in: prepared) }.font(Typography.mono())
                        }
                        Toggle("I Reviewed the Files I Want to Share", isOn: $reviewed)
                            .accessibilityIdentifier("diagnostics.reviewed")
                        Button("Share Reviewed ZIP") { confirmShare = true }
                            .disabled(!reviewed)
                            .accessibilityIdentifier("diagnostics.share")
                        #if os(macOS)
                        Button("Save Reviewed ZIP…") { save() }
                            .disabled(!reviewed)
                            .accessibilityIdentifier("diagnostics.save")
                        #endif
                        Text("Public posts can expose these files to anyone. Email and other destinations control their own copies; Health.md cannot recall them. Local bundles expire within 24 hours on the next app access, and only the newest 3 are retained.")
                            .font(Typography.caption()).foregroundStyle(Color.textSecondary)
                    }
                    if let error { Text(error).foregroundStyle(Color.error).textSelection(.enabled) }
                }
            }
            .disabled(busy)
            .navigationTitle("Diagnostics")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { reload() }
            .onChange(of: settings.enabled) { _, _ in configure() }
            .onChange(of: settings.verbosity) { _, _ in configure() }
            .onChange(of: hours) { _, _ in invalidate(); reload() }
            .onChange(of: subsystem) { _, _ in invalidate(); reload() }
            .onChange(of: operationID) { _, _ in invalidate(); reload() }
            .onChange(of: includePrivate) { _, _ in invalidate(); reload() }
            .fileImporter(isPresented: $choosingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                do { attachments.append(contentsOf: try result.get()); invalidate() }
                catch { self.error = "File selection failed. Select the files again." }
            }
            .sheet(item: $preview) { item in
                NavigationStack {
                    ScrollView {
                        Text(item.text).font(Typography.mono()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(Spacing.s4)
                    }.navigationTitle(item.title)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { preview = nil } } }
                }
                #if os(macOS)
                .frame(minWidth: 600, minHeight: 450)
                #endif
            }
            .confirmationDialog("Clear All Local Diagnostics?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear Diagnostics", role: .destructive) {
                    invalidate()
                    let cleared = DiagnosticRecorder.shared.clear()
                    if !cleared { error = "Some diagnostic files could not be deleted. Check storage access and try again." }
                    settings = DiagnosticRecorder.shared.settings
                    attachments = []
                    reload()
                }
            } message: { Text("Delete diagnostic events and prepared bundles, and stop private recording. Recording of new operational events keeps its current setting. Original files and copies already saved or shared are not deleted.") }
            .confirmationDialog("Share This Diagnostic Bundle?", isPresented: $confirmShare, titleVisibility: .visible) {
                Button("Share This Bundle") { share() }
            } message: {
                Text("The ZIP is not encrypted. Included private context and attachments may expose health data or secrets. The destination controls its own copies.")
            }
            #if os(iOS)
            .sheet(isPresented: $showShare) { if let sharedURL { DiagnosticShareSheet(url: sharedURL) } }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 660, minHeight: 600)
        #endif
    }

    private func configure() {
        DiagnosticRecorder.shared.configure(enabled: settings.enabled, verbosity: settings.verbosity)
        invalidate(); reload()
    }
    private func invalidate() { prepared?.delete(); prepared = nil; reviewed = false; error = nil }
    private func selection() -> (Date, String?, String?) {
        (Date().addingTimeInterval(-Double(hours) * 3600), subsystem == "all" ? nil : subsystem, operationID.isEmpty ? nil : operationID.lowercased())
    }
    private func reload() {
        let (since, subsystem, operationID) = selection()
        let include = includePrivate
        let generation = UUID(); reloadGeneration = generation; events = []
        Task {
            let snapshot = await Task.detached { DiagnosticRecorder.shared.snapshot(includePrivate: include, since: since, subsystem: subsystem, operationID: operationID) }.value
            guard generation == reloadGeneration else { return }
            events = snapshot.events
            summary = "\(snapshot.events.count) events · \(snapshot.droppedEventCount) session drops · \(snapshot.invalidEventCount) invalid · truncated=\(snapshot.truncated)"
        }
    }
    private func prepare() {
        guard operationID.isEmpty || UUID(uuidString: operationID) != nil else { error = "Operation ID must be a UUID."; return }
        invalidate(); busy = true
        let (since, subsystem, operationID) = selection()
        let include = includePrivate; let files = attachments
        Task {
            do {
                prepared = try await Task.detached { try DiagnosticBundleBuilder.prepare(includePrivate: include, since: since, subsystem: subsystem, operationID: operationID, attachments: files) }.value
            } catch { self.error = (error as? DiagnosticBundleError)?.rawValue ?? "Bundle preparation failed. Check file access and local storage, then prepare again." }
            busy = false
        }
    }
    private func showFile(_ path: String, in bundle: PreparedDiagnosticBundle) {
        Task {
            do {
                let (text, truncated) = try await Task.detached { try bundle.preview(path) }.value
                preview = DiagnosticTextPreview(title: path, text: text + (truncated ? "\n\n[Preview truncated at 128 KiB. Full original file remains in the ZIP.]" : ""))
            } catch { self.error = "The file is unavailable. Prepare and review the bundle again." }
        }
    }
    #if os(macOS)
    private func save() {
        guard let prepared, reviewed else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "healthmd-diagnostics.zip"
        panel.message = "This ZIP is not encrypted. Private context and attachments may contain health data or secrets. Saved copies cannot be recalled by Health.md."
        busy = true
        panel.begin { result in
            guard result == .OK, let destination = panel.url else { busy = false; return }
            Task {
                do {
                    try await Task.detached {
                        let source = try prepared.verifiedURL()
                        // Atomic replacement leaves an existing destination intact on failure.
                        try Data(contentsOf: source, options: .mappedIfSafe).write(to: destination, options: .atomic)
                    }.value
                } catch { self.error = "Saving failed or the reviewed bundle changed. Prepare and review it again." }
                busy = false
            }
        }
    }
    #endif
    private func share() {
        guard let prepared, reviewed else { return }
        busy = true
        Task {
            do {
                let url = try await Task.detached { try prepared.verifiedURL() }.value
                #if os(iOS)
                sharedURL = url; showShare = true
                #else
                if let view = NSApp.keyWindow?.contentView {
                    let picker = NSSharingServicePicker(items: [url]); sharingPicker = picker
                    picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1), of: view, preferredEdge: .minY)
                }
                #endif
            } catch { self.error = "The reviewed bundle changed or was deleted. Prepare and review it again." }
            busy = false
        }
    }
}

#if os(iOS)
private struct DiagnosticShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

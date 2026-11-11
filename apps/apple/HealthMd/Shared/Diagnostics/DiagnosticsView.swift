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
    @State private var showFilters = false
    #if os(iOS)
    @State private var sharedURL: URL?
    @State private var showShare = false
    #else
    @State private var sharingPicker: NSSharingServicePicker?
    #endif

    var body: some View {
        #if os(iOS)
        // DiagnosticsG is a pushed page on iPhone and iPad: Back, no Done.
        page.navigationBarTitleDisplayMode(.inline)
        #else
        NavigationStack {
            page.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 660, minHeight: 600)
        #endif
    }

    private var page: some View {
            content
            .disabled(busy)
            .navigationTitle("Diagnostics")
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

    #if os(iOS)
    /// DiagnosticsG. Same recorder, filters, prepare → review → share sequence as the
    /// macOS form; the review step appears inline once a bundle is frozen.
    private var content: some View {
        DiagnosticsGlassChrome { palette in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: GlassMetrics.sectionGap) {
                        privacyBanner(palette)
                        recordingSection(palette)
                        eventsSection(palette)
                        attachmentsSection(palette)
                        if let prepared { reviewSection(prepared, palette).id("diagnostics.review") }
                        if let error {
                            Text(error).glassFont(.caption).foregroundStyle(palette.coral).textSelection(.enabled)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.horizontal, GlassMetrics.screenMargin)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .onChange(of: prepared?.manifest.event_count) { _, count in
                    guard count != nil else { return }
                    withAnimation { proxy.scrollTo("diagnostics.review", anchor: .top) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar(palette) }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func privacyBanner(_ palette: GlassPalette) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle").foregroundStyle(palette.accent).accessibilityHidden(true)
            Text("Stays on this iPhone until you share it. No health values, record IDs, paths, endpoints or credentials. Not anonymous.")
                .font(.system(size: 14)).foregroundStyle(palette.sec)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: GlassMetrics.panelSmallRadius)
        .overlay(RoundedRectangle(cornerRadius: GlassMetrics.panelSmallRadius, style: .continuous).strokeBorder(palette.accent, lineWidth: 1))
    }

    private func sectionHeader(_ title: String, _ palette: GlassPalette) -> some View {
        Text(title).glassFont(.caption).foregroundStyle(palette.muted).padding(.horizontal, 20)
    }

    private func footnote(_ text: String, _ palette: GlassPalette) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
    }

    private func divider(_ palette: GlassPalette) -> some View {
        Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, GlassMetrics.panelPadding)
    }

    private func pillGroup<Value: Hashable>(_ title: String, _ options: [(Value, String)], _ selection: Binding<Value>, _ palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).glassFont(.body).foregroundStyle(palette.text).accessibilityHidden(true)
            // A label on the bare control would replace every segment's own name, so
            // VoiceOver could not tell which option is selected.
            GlassSegmentedControl(segments: options.map { GlassSegmentedControl<Value>.Segment(value: $0.0, title: $0.1) }, selection: selection)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, GlassMetrics.panelPadding).padding(.vertical, 12)
    }

    private func recordingSection(_ palette: GlassPalette) -> some View {
        let privateActive = settings.privateContextUntil > Date().timeIntervalSince1970
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader(String(localized: "Recording"), palette)
            GlassPanel {
                GlassToggleRow(title: String(localized: "Record Operational Events"), isOn: $settings.enabled)
                    .accessibilityIdentifier("diagnostics.enabled")
                divider(palette)
                pillGroup(String(localized: "Detail"), DiagnosticVerbosity.allCases.map { ($0, verbosityTitle($0)) }, $settings.verbosity, palette)
                divider(palette)
                Button {
                    if privateActive { DiagnosticRecorder.shared.stopPrivateContextRecording() }
                    else { DiagnosticRecorder.shared.startPrivateContextRecording() }
                    settings = DiagnosticRecorder.shared.settings
                } label: {
                    GlassRow(
                        title: privateActive ? String(localized: "Stop Private Recording") : String(localized: "Record private context"),
                        subtitle: String(localized: "Adds peer names · expires within 24 h")
                    ) {
                        Text(privateActive
                             ? String(localized: "Until \(Date(timeIntervalSince1970: settings.privateContextUntil).formatted(date: .omitted, time: .shortened))")
                             : String(localized: "15 min"))
                            .font(.system(size: 15)).foregroundStyle(palette.muted)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.muted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!settings.enabled && !privateActive)
            }
            footnote(String(localized: "Kept up to 7 days or 20 MiB. Never uploaded automatically."), palette)
        }
    }

    private func eventsSection(_ palette: GlassPalette) -> some View {
        let visible = Array(events.filter { search.isEmpty || $0.jsonLine.localizedCaseInsensitiveContains(search) }.suffix(100).reversed())
        return VStack(alignment: .leading, spacing: 6) {
            sectionHeader(String(localized: "Events"), palette)
            GlassPanel {
                pillGroup(String(localized: "Window"), [(1, String(localized: "1 hour")), (24, String(localized: "24 hours")), (168, String(localized: "7 days"))], $hours, palette)
                divider(palette)
                DisclosureGroup(isExpanded: $showFilters) {
                    VStack(spacing: 0) {
                        GlassMenuRow(title: String(localized: "Subsystem"), selection: $subsystem,
                                     options: ["all", "connection", "schedule", "notification", "export", "lifecycle", "diagnostics"],
                                     label: { $0.capitalized })
                        GlassToggleRow(title: String(localized: "Include Recorded Private Context"), isOn: $includePrivate)
                        filterField(String(localized: "Operation UUID (Optional)"), text: $operationID, mono: true, palette)
                        filterField(String(localized: "Search Event IDs or Fields"), text: $search, mono: false, palette)
                    }
                } label: {
                    Text("Filters").glassFont(.body).foregroundStyle(palette.text)
                }
                .tint(palette.muted)
                .padding(.horizontal, GlassMetrics.panelPadding)
                .frame(minHeight: GlassMetrics.rowMinHeight)
                divider(palette)
                if visible.isEmpty {
                    Text("No events in this window.").glassFont(.rowSubtitle).foregroundStyle(palette.muted)
                        .padding(GlassMetrics.panelPadding)
                } else {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, event in
                        if index > 0 { divider(palette) }
                        eventRow(event, palette)
                    }
                }
            }
            footnote(summary, palette)
            footnote(String(localized: "Showing the newest 100 matching events. The bundle includes the selected snapshot, up to 10,000 events; any truncation is disclosed."), palette)
        }
    }

    private func filterField(_ title: String, text: Binding<String>, mono: Bool, _ palette: GlassPalette) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .glassFont(mono ? .monoBody : .body)
            .foregroundStyle(palette.text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .padding(.horizontal, GlassMetrics.panelPadding)
            .frame(minHeight: GlassMetrics.touchTarget)
    }

    private func eventRow(_ event: DiagnosticEvent, _ palette: GlassPalette) -> some View {
        Button {
            preview = DiagnosticTextPreview(title: event.event_id.rawValue, text: event.jsonLine)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // 12-hour times ("11:26 AM") are wider than DiagnosticsG's 24-hour ones.
                Text(verbatim: DiagnosticEventDisplay.timeLabel(event.timestamp))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(palette.muted).frame(width: 64, alignment: .leading)
                Text(verbatim: DiagnosticEventDisplay.severityLabel(event.severity))
                    .foregroundStyle(DiagnosticEventDisplay.needsAttention(event.severity) ? palette.coral : palette.sec)
                    .frame(width: 46, alignment: .leading)
                Text(verbatim: DiagnosticEventDisplay.summary(eventID: event.event_id.rawValue, fields: event.fields))
                    .foregroundStyle(palette.text).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, GlassMetrics.panelPadding).padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func attachmentsSection(_ palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(String(localized: "Attachments"), palette)
            GlassPanel {
                Button { choosingFiles = true } label: {
                    GlassRow(title: String(localized: "Add files"),
                             subtitle: String(localized: "Copied unchanged — not scrubbed · up to 50 files / 100 MiB")) {
                        Text(attachments.isEmpty ? String(localized: "None") : String(localized: "\(attachments.count) files"))
                            .font(.system(size: 15)).foregroundStyle(palette.muted)
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("diagnostics.attach")
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, url in
                    divider(palette)
                    HStack {
                        Text(verbatim: url.lastPathComponent).glassFont(.monoBody).foregroundStyle(palette.text).lineLimit(1)
                        Spacer()
                        Button(String(localized: "Remove")) { attachments.remove(at: index); invalidate() }
                            .foregroundStyle(palette.coral)
                    }
                    .padding(.horizontal, GlassMetrics.panelPadding)
                    .frame(minHeight: GlassMetrics.touchTarget)
                }
            }
        }
    }

    private func reviewSection(_ prepared: PreparedDiagnosticBundle, _ palette: GlassPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(String(localized: "Review"), palette)
            GlassPanel {
                Text("Frozen snapshot: \(prepared.manifest.event_count) events. Health content: \(prepared.manifest.health_content). ZIP is not encrypted.")
                    .glassFont(.rowSubtitle).foregroundStyle(palette.sec)
                    .padding(GlassMetrics.panelPadding)
                ForEach(["manifest.json"] + prepared.manifest.files.map(\.path), id: \.self) { path in
                    divider(palette)
                    Button { showFile(path, in: prepared) } label: {
                        GlassRow(title: path) {
                            Image(systemName: "doc.text.magnifyingglass").foregroundStyle(palette.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
                divider(palette)
                GlassToggleRow(title: String(localized: "I Reviewed the Files I Want to Share"), isOn: $reviewed)
                    .accessibilityIdentifier("diagnostics.reviewed")
            }
            footnote(String(localized: "Public posts can expose these files to anyone. Email and other destinations control their own copies; Health.md cannot recall them. Local bundles expire within 24 hours on the next app access, and only the newest 3 are retained."), palette)
        }
    }

    private func actionBar(_ palette: GlassPalette) -> some View {
        VStack(spacing: 8) {
            if prepared != nil {
                Button(String(localized: "Share Reviewed ZIP")) { confirmShare = true }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(!reviewed)
                    .accessibilityIdentifier("diagnostics.share")
            } else {
                Button(busy ? String(localized: "Preparing…") : String(localized: "Review & prepare ZIP")) { prepare() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .accessibilityIdentifier("diagnostics.prepare")
            }
            Button(String(localized: "Clear diagnostics")) { confirmClear = true }
                .font(.system(size: 15))
                .foregroundStyle(palette.coral)
                .frame(minHeight: 40)
                .accessibilityIdentifier("diagnostics.clear")
        }
        .padding(.horizontal, GlassMetrics.screenMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background { Color.clear.glassSurface(in: Rectangle()).ignoresSafeArea(edges: .bottom) }
    }

    private func verbosityTitle(_ verbosity: DiagnosticVerbosity) -> String {
        switch verbosity {
        case .info: return String(localized: "Info")
        case .debug: return String(localized: "Debug")
        case .trace: return String(localized: "Trace")
        }
    }
    #endif

    #if os(macOS)
    private var content: some View {
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
                .glassFormRows()
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
                .glassFormRows()
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
                .glassFormRows()
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
                .glassFormRows()
            }
            .glassFormChrome()
    }
    #endif

    private func configure() {
        DiagnosticRecorder.shared.configure(enabled: settings.enabled, verbosity: settings.verbosity)
        // Disabling operational recording also revokes private recording consent.
        // Reflect that canonical state rather than retaining the editor's old deadline.
        settings = DiagnosticRecorder.shared.settings
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

#if os(iOS)
/// Resolves the glass palette for a sheet-presented screen and paints its background.
private struct DiagnosticsGlassChrome<Content: View>: View {
    @ViewBuilder let content: (GlassPalette) -> Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = GlassPalette.resolved(colorScheme: colorScheme, reduceTransparency: reduceTransparency)
        content(palette)
            .background(palette.bg.ignoresSafeArea())
            .tint(palette.accent)
            .glassTheme()
    }
}
#endif

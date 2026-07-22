#if os(macOS)
import SwiftUI

/// Local user-controlled editor. Saving always creates a new profile or bumps
/// the exact existing revision; agents cannot mutate their own authorization.
struct MacHealthContextProfileEditor: View {
    private enum DateMode: String, CaseIterable, Identifiable {
        case allHistory, fixedRange, callerProvided, relativeDays
        var id: Self { self }
        var label: String {
            switch self {
            case .allHistory: return "All history"
            case .fixedRange: return "Fixed range"
            case .callerProvided: return "Caller-provided range"
            case .relativeDays: return "Relative days"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileManager: HealthContextProfileManager

    private let existing: HealthContextProfile?
    @State private var name: String
    @State private var allMetrics: Bool
    @State private var selectedMetricIDs: Set<String>
    @State private var metricSearch = ""
    @State private var allSources: Bool
    @State private var selectedSourceIDs: Set<String>
    @State private var detailLevel: HealthContextDetailLevel
    @State private var dateMode: DateMode
    @State private var fixedStart: Date
    @State private var fixedEnd: Date
    @State private var relativeDays: String
    @State private var allowedSurfaces: Set<HealthContextSurface>
    @State private var requiresConfirmation: Bool
    @State private var bindsDestination: Bool
    @State private var destinationID: String
    @State private var expires: Bool
    @State private var expiration: Date
    @State private var saveError: String?
    @State private var isSaving = false

    private static let agentSurfaces: [(HealthContextSurface, String)] = [
        (.localControlAPI, "Local agent API"),
        (.commandLine, "healthmd CLI"),
        (.mcpStdio, "healthmd-mcp stdio")
    ]
    private static let sourceOptions: [(String, String)] = [
        ("apple_health", "Apple Health")
    ] + ExternalIntegrationProvider.allCases.map { ($0.id, $0.displayName) }

    init(existing: HealthContextProfile? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        switch existing?.metricScope {
        case .selected(let ids):
            _allMetrics = State(initialValue: false)
            _selectedMetricIDs = State(initialValue: Set(ids))
        default:
            _allMetrics = State(initialValue: true)
            _selectedMetricIDs = State(initialValue: [])
        }
        switch existing?.dataSourceScope {
        case .selected(let ids):
            _allSources = State(initialValue: false)
            _selectedSourceIDs = State(initialValue: Set(ids))
        default:
            _allSources = State(initialValue: true)
            _selectedSourceIDs = State(initialValue: [])
        }
        _detailLevel = State(initialValue: existing?.detailLevel ?? .lossless)
        let now = Date()
        switch existing?.datePolicy {
        case .explicit(let range):
            _dateMode = State(initialValue: .fixedRange)
            _fixedStart = State(initialValue: range.start)
            _fixedEnd = State(initialValue: range.end)
            _relativeDays = State(initialValue: "30")
        case .callerProvided:
            _dateMode = State(initialValue: .callerProvided)
            _fixedStart = State(initialValue: now)
            _fixedEnd = State(initialValue: now)
            _relativeDays = State(initialValue: "30")
        case .relative(let duration):
            _dateMode = State(initialValue: .relativeDays)
            _fixedStart = State(initialValue: now)
            _fixedEnd = State(initialValue: now)
            _relativeDays = State(initialValue: String(max(1, Int(duration / 86_400))))
        default:
            _dateMode = State(initialValue: .allHistory)
            _fixedStart = State(initialValue: now)
            _fixedEnd = State(initialValue: now)
            _relativeDays = State(initialValue: "30")
        }
        _allowedSurfaces = State(initialValue: Set(existing?.allowedSurfaces ?? [
            .localControlAPI, .commandLine, .mcpStdio
        ]))
        _requiresConfirmation = State(
            initialValue: existing?.confirmationRequirement == .required
        )
        if case .exact(let id) = existing?.destinationBinding {
            _bindsDestination = State(initialValue: true)
            _destinationID = State(initialValue: id)
        } else {
            _bindsDestination = State(initialValue: false)
            _destinationID = State(initialValue: "")
        }
        _expires = State(initialValue: existing?.expiresAt != nil)
        _expiration = State(initialValue: existing?.expiresAt ?? now.addingTimeInterval(30 * 86_400))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Profile name", text: $name)
                    if let existing {
                        LabeledContent("Next revision", value: "\(existing.revision.rawValue + 1)")
                    }
                }

                Section("Metrics") {
                    Toggle("Dynamically include every current and future metric", isOn: $allMetrics)
                    if !allMetrics {
                        TextField("Filter metrics", text: $metricSearch)
                        metricSelectionList
                        Text("\(selectedMetricIDs.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Providers and source records") {
                    Toggle("Dynamically include every current and future provider", isOn: $allSources)
                    if !allSources {
                        ForEach(Self.sourceOptions, id: \.0) { id, label in
                            Toggle(label, isOn: selectionBinding(id, in: $selectedSourceIDs))
                        }
                    }
                }

                Section("Detail and dates") {
                    Picker("Detail", selection: $detailLevel) {
                        Text("Summary").tag(HealthContextDetailLevel.summary)
                        Text("Lossless source records").tag(HealthContextDetailLevel.lossless)
                    }
                    Picker("Dates", selection: $dateMode) {
                        ForEach(DateMode.allCases) { Text($0.label).tag($0) }
                    }
                    switch dateMode {
                    case .fixedRange:
                        DatePicker("Start", selection: $fixedStart, displayedComponents: .date)
                        DatePicker("End", selection: $fixedEnd, displayedComponents: .date)
                    case .relativeDays:
                        TextField("Days", text: $relativeDays)
                    case .allHistory, .callerProvided:
                        EmptyView()
                    }
                }

                Section("Agent surfaces") {
                    ForEach(Self.agentSurfaces, id: \.0) { surface, label in
                        Toggle(label, isOn: selectionBinding(surface, in: $allowedSurfaces))
                    }
                    Toggle("Require confirmation at execution", isOn: $requiresConfirmation)
                }

                Section("Destination and expiry") {
                    Toggle("Bind to one exact destination ID", isOn: $bindsDestination)
                    if bindsDestination {
                        TextField("Destination ID", text: $destinationID)
                    }
                    Toggle("Profile expires", isOn: $expires)
                    if expires {
                        DatePicker("Expiration", selection: $expiration)
                    }
                }

                if let saveError {
                    Section { Text(saveError).foregroundStyle(Color.error) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(existing == nil ? "New Health Context Profile" : "Edit Health Context Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 680)
    }

    private var filteredMetrics: [HealthMetricDefinition] {
        let query = metricSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return HealthMetrics.all }
        return HealthMetrics.all.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
                || $0.category.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private var metricSelectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(filteredMetrics) { metric in
                    Toggle(isOn: selectionBinding(metric.id, in: $selectedMetricIDs)) {
                        VStack(alignment: .leading) {
                            Text(metric.name)
                            Text(metric.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }

    private func selectionBinding<T: Hashable>(_ value: T, in selection: Binding<Set<T>>) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(value) },
            set: { enabled in
                if enabled { selection.wrappedValue.insert(value) }
                else { selection.wrappedValue.remove(value) }
            }
        )
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let now = Date()
            let datePolicy: HealthContextDatePolicy
            switch dateMode {
            case .allHistory: datePolicy = .allHistory
            case .callerProvided: datePolicy = .callerProvided
            case .fixedRange:
                datePolicy = .explicit(.init(
                    start: Calendar.current.startOfDay(for: fixedStart),
                    end: Calendar.current.startOfDay(for: fixedEnd)
                ))
            case .relativeDays:
                guard let days = Double(relativeDays), days.isFinite, days > 0 else {
                    throw HealthContextProfileValidationError.invalidDatePolicy
                }
                datePolicy = .relative(duration: days * 86_400)
            }
            let profile = HealthContextProfile(
                id: existing?.id ?? UUID(),
                revision: .init((existing?.revision.rawValue ?? 0) + 1),
                name: name,
                metricScope: allMetrics
                    ? .allAvailable : .selected(metricIDs: selectedMetricIDs.sorted()),
                dataSourceScope: allSources
                    ? .allAvailable : .selected(sourceIDs: selectedSourceIDs.sorted()),
                detailLevel: detailLevel,
                datePolicy: datePolicy,
                allowedCallers: [.registeredAgent, .commandLine],
                allowedSurfaces: allowedSurfaces.sorted { $0.rawValue < $1.rawValue },
                confirmationRequirement: requiresConfirmation ? .required : .notRequired,
                expiresAt: expires ? expiration : nil,
                destinationBinding: bindsDestination
                    ? .exact(destinationID: destinationID) : .any,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try profile.validate()
            try await profileManager.upsert(profile)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
#endif

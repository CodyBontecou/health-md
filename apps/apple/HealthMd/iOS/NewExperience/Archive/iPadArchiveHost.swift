#if os(iOS)
import SwiftUI

/// The Archive on iPad, where exports do not run through `ExportProfileCoordinator`.
/// Day actions lead to the Export section, which owns the iPad export path.
struct iPadArchiveHost: View {
    let onOpenExport: () -> Void

    @ObservedObject private var ledgerStore = CoverageLedgerStore.shared
    @StateObject private var profileStore = ExportProfileStore()
    @StateObject private var entryStore = ScheduledExportEntryStore()
    @State private var showHistory = false

    var body: some View {
        ArchiveScreen(
            model: ArchiveModel(
                profiles: profileStore.profiles.enumerated().map { index, profile in
                    ArchiveProfile(
                        id: profile.id,
                        name: profile.name,
                        destination: profile.target.title,
                        colorIndex: index,
                        entry: entryStore.entries.first { $0.profileID == profile.id }
                    )
                },
                ledger: ledgerStore.ledger,
                now: Date(),
                calendar: .current
            ),
            needsSetup: false,
            attentionCount: 0,
            onAction: { _, _, _ in onOpenExport() },
            onResume: { _ in onOpenExport() },
            onManageAutomations: { showHistory = true },
            onShowAttention: {},
            onSetUp: onOpenExport
        )
        .glassTheme()
        .sheet(isPresented: $showHistory) { iPadHistoryView() }
    }
}
#endif

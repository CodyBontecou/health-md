#if os(iOS)
import SwiftUI

/// Hosts a page whose board is a pushed screen (Back, no Done/Close) at a call site that
/// is genuinely modal — a notification, the export result, a document open. The page
/// keeps its own title and trailing actions; the leading Back dismisses the modal.
struct GlassModalBackStack<Content: View>: View {
    var backIdentifier = "glass.page.back"
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    GlassBackButton { dismiss() }
                        .accessibilityIdentifier(backIdentifier)
                }
            }
        }
    }
}

/// The navigation bar's Back affordance (chevron + "Back") for modal hosts.
struct GlassBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward")
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
                Text("Back")
            }
        }
        .accessibilityLabel(Text("Back"))
    }
}
#endif
